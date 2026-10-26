'use strict';

// Thin wrapper around Brain.js: the lab requires the network itself to come from Brain.js,
// so everything here only configures, trains and serialises brain.NeuralNetwork.

const brain = require('brain.js');
const { FEATURE_COUNT } = require('./features');
const { CLASSES } = require('./dataset');

const DEFAULTS = {
  hiddenLayers: [8],
  activation: 'sigmoid',
  learningRate: 0.1,
  momentum: 0.9,
  iterations: 1200,
  errorThresh: 0.0005,
  logPeriod: 25,
  evaluateEvery: 25,
  patience: 6
};

function create(options = {}) {
  const config = { ...DEFAULTS, ...options };
  return {
    config,
    net: new brain.NeuralNetwork({
      inputSize: FEATURE_COUNT,
      hiddenLayers: config.hiddenLayers,
      outputSize: CLASSES.length,
      activation: config.activation
    })
  };
}

// Brain.js has no dropout or weight decay, so the only regularisation available is to stop
// before the network starts memorising. Training runs in chunks; after each chunk the network
// is scored on data it is not training on, and the best-scoring weights are kept. Without
// this the run simply ends at the iteration budget, which is always past the optimum.
function trainWithEarlyStopping(net, data, validation, config, { verbose = true } = {}) {
  const started = Date.now();
  const history = [];
  const chunk = config.evaluateEvery ?? 25;

  let bestAccuracy = -1;
  let bestSnapshot = net.toJSON();
  let bestIteration = 0;
  let sinceBest = 0;
  let iterations = 0;
  let error = 1;

  while (iterations < config.iterations) {
    const status = net.train(data, {
      iterations: Math.min(chunk, config.iterations - iterations),
      errorThresh: 1e-8, // never satisfied: the stopping decision belongs to validation, not training error
      learningRate: config.learningRate,
      momentum: config.momentum,
      log: false,
      keepNetworkIntact: iterations > 0
    });

    iterations += Math.min(chunk, config.iterations - iterations);
    error = status.error;
    const accuracy = evaluate(net, validation).accuracy;
    history.push({ iterations, error, validationAccuracy: accuracy });

    if (accuracy > bestAccuracy) {
      bestAccuracy = accuracy;
      bestSnapshot = net.toJSON();
      bestIteration = iterations;
      sinceBest = 0;
    } else {
      sinceBest += 1;
    }

    if (verbose) {
      console.log(`  iteration ${String(iterations).padStart(4)}  error ${error.toFixed(6)}  validation ${(accuracy * 100).toFixed(2)}%${accuracy === bestAccuracy ? '  *' : ''}`);
    }

    if (sinceBest >= (config.patience ?? 6)) break;
  }

  net.fromJSON(bestSnapshot);
  return { iterations, bestIteration, bestAccuracy, error, history, seconds: (Date.now() - started) / 1000 };
}

function train(net, data, config, { verbose = true } = {}) {
  const started = Date.now();
  const history = [];

  const status = net.train(data, {
    iterations: config.iterations,
    errorThresh: config.errorThresh,
    learningRate: config.learningRate,
    momentum: config.momentum,
    log: verbose
      ? (detail) => {
          history.push({ iterations: detail.iterations, error: detail.error });
          console.log(`  iteration ${String(detail.iterations).padStart(4)}  error ${detail.error.toFixed(6)}`);
        }
      : false,
    logPeriod: config.logPeriod
  });

  return { ...status, history, seconds: (Date.now() - started) / 1000 };
}

function calibratedProbabilities(raw, temperature) {
  const safeTemperature = Number.isFinite(temperature) && temperature > 0 ? temperature : 1;
  const logits = raw.map((value) => {
    const probability = Math.min(1 - 1e-12, Math.max(1e-12, value));
    return Math.log(probability / (1 - probability)) / safeTemperature;
  });
  const largest = Math.max(...logits);
  const exponentials = logits.map((value) => Math.exp(value - largest));
  const total = exponentials.reduce((sum, value) => sum + value, 0);
  return exponentials.map((value) => value / total);
}

function calibrationLoss(prepared, temperature) {
  let loss = 0;
  prepared.forEach(({ raw, label }) => {
    const probabilities = calibratedProbabilities(raw, temperature);
    loss -= Math.log(Math.max(probabilities[label], 1e-15));
  });
  return loss / prepared.length;
}

// Temperature scaling is fitted only on validation data. It does not alter the selected class;
// it turns saturated sigmoid outputs into probabilities whose average confidence matches the
// observed validation accuracy.
function fitTemperature(net, validation) {
  const prepared = validation.map((sample) => ({
    raw: Array.from(net.run(sample.input)),
    label: sample.label
  }));

  let lower = 0.25;
  let upper = 10;
  for (let iteration = 0; iteration < 80; iteration += 1) {
    const first = lower + (upper - lower) / 3;
    const second = upper - (upper - lower) / 3;
    if (calibrationLoss(prepared, first) < calibrationLoss(prepared, second)) upper = second;
    else lower = first;
  }

  const temperature = (lower + upper) / 2;
  return {
    method: 'temperature scaling on validation logits',
    temperature,
    validationNllBefore: calibrationLoss(prepared, 1),
    validationNllAfter: calibrationLoss(prepared, temperature)
  };
}

// Brain.js returns one independent sigmoid activation per output neuron. Temperature-scaled
// softmax is used only for display; the predicted class remains the arg max of the raw outputs.
function predict(net, input, temperature = 1) {
  const raw = Array.from(net.run(input));
  const normalised = calibratedProbabilities(raw, temperature);

  let best = 0;
  for (let i = 1; i < raw.length; i += 1) if (raw[i] > raw[best]) best = i;

  return { raw, normalised, index: best, label: CLASSES[best], confidence: normalised[best] };
}

function evaluate(net, data) {
  const matrix = CLASSES.map(() => CLASSES.map(() => 0));
  let correct = 0;

  data.forEach((sample) => {
    const { index } = predict(net, sample.input);
    matrix[sample.label][index] += 1;
    if (index === sample.label) correct += 1;
  });

  const subset = (filter) => {
    const items = data.filter(filter);
    if (!items.length) return null;
    const hits = items.filter((sample) => predict(net, sample.input).index === sample.label).length;
    return hits / items.length;
  };

  return {
    accuracy: data.length ? correct / data.length : 0,
    cleanAccuracy: subset((sample) => !sample.augmented),
    augmentedAccuracy: subset((sample) => sample.augmented),
    filledAccuracy: subset((sample) => sample.source === 'filled'),
    drawnAccuracy: subset((sample) => sample.source === 'drawn'),
    matrix,
    total: data.length
  };
}

function formatMatrix(matrix) {
  const header = ['true \\ pred', ...CLASSES].map((cell) => cell.padEnd(12)).join('');
  const rows = matrix.map((row, i) => [CLASSES[i], ...row.map(String)].map((cell) => cell.padEnd(12)).join(''));
  return [header, ...rows].join('\n');
}

module.exports = { DEFAULTS, create, train, trainWithEarlyStopping, calibratedProbabilities, fitTemperature, predict, evaluate, formatMatrix };
