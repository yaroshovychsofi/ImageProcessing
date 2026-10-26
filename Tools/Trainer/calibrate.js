'use strict';

// Temperature scaling (Guo et al., 2017).
//
// Brain.js ends in independent sigmoids trained towards 0 and 1, so after training almost
// every output is saturated: 98% of predictions come out above 99.9% "confidence", including
// the wrong ones. The ranking is fine — the argmax does not move — but the number shown to
// the user is meaningless.
//
// The fix is one parameter. Each sigmoid activation is turned back into the score that
// produced it (z = ln(a / (1 - a))), the scores are divided by a temperature T and passed
// through a softmax. T > 1 softens the distribution. It is fitted on the validation split by
// minimising negative log-likelihood, never on test, and it cannot change which class wins.
//
// Usage: node calibrate.js

const fs = require('fs');
const path = require('path');
const brain = require('brain.js');
const dataset = require('./dataset');
const network = require('./network');

const MODEL_DIR = path.resolve(__dirname, '../../Figure/Resources/Model');
const EPSILON = 1e-12;

function logits(activations) {
  return activations.map((value) => {
    const clamped = Math.min(1 - 1e-9, Math.max(1e-9, value));
    return Math.log(clamped / (1 - clamped));
  });
}

function softmax(scores, temperature) {
  const scaled = scores.map((value) => value / temperature);
  const highest = Math.max(...scaled);
  const exponentials = scaled.map((value) => Math.exp(value - highest));
  const total = exponentials.reduce((sum, value) => sum + value, 0);
  return exponentials.map((value) => value / total);
}

function negativeLogLikelihood(samples, temperature) {
  let total = 0;
  samples.forEach(({ scores, label }) => {
    const probabilities = softmax(scores, temperature);
    total -= Math.log(Math.max(probabilities[label], EPSILON));
  });
  return total / samples.length;
}

function reliability(samples, temperature) {
  const bands = [[0, 0.5], [0.5, 0.7], [0.7, 0.9], [0.9, 0.99], [0.99, 0.999], [0.999, 1.0001]];
  const rows = bands.map(() => ({ count: 0, correct: 0, sum: 0 }));

  samples.forEach(({ scores, label }) => {
    const probabilities = softmax(scores, temperature);
    let best = 0;
    probabilities.forEach((value, index) => {
      if (value > probabilities[best]) best = index;
    });
    const confidence = probabilities[best];
    const index = bands.findIndex(([from, to]) => confidence >= from && confidence < to);
    if (index < 0) return;
    rows[index].count += 1;
    rows[index].sum += confidence;
    if (best === label) rows[index].correct += 1;
  });

  let error = 0;
  let total = 0;
  const lines = rows.map((row, index) => {
    if (!row.count) return null;
    const confidence = row.sum / row.count;
    const accuracy = row.correct / row.count;
    error += row.count * Math.abs(confidence - accuracy);
    total += row.count;
    return `  ${`${bands[index][0]}–${bands[index][1]}`.padEnd(14)}${String(row.count).padStart(6)}  ${(100 * confidence).toFixed(1).padStart(8)}%  ${(100 * accuracy).toFixed(1).padStart(10)}%`;
  }).filter(Boolean);

  return { lines, error: total ? error / total : 0 };
}

function prepare(net, data) {
  return data.map((sample) => ({
    scores: logits(Array.from(net.run(sample.input))),
    label: sample.label
  }));
}

function main() {
  const net = new brain.NeuralNetwork();
  net.fromJSON(JSON.parse(fs.readFileSync(path.join(MODEL_DIR, 'model.json'), 'utf8')));

  const { validation, test } = dataset.load({ verbose: false });
  const validationScores = prepare(net, validation);
  const testScores = prepare(net, test);

  // Golden-section search over a range wide enough for a saturated sigmoid network.
  let low = 0.5;
  let high = 40;
  const phi = (Math.sqrt(5) - 1) / 2;
  for (let step = 0; step < 60; step += 1) {
    const a = high - phi * (high - low);
    const b = low + phi * (high - low);
    if (negativeLogLikelihood(validationScores, a) < negativeLogLikelihood(validationScores, b)) high = b;
    else low = a;
  }
  const temperature = (low + high) / 2;

  const before = reliability(validationScores, 1);
  const after = reliability(validationScores, temperature);
  const testBefore = reliability(testScores, 1);
  const testAfter = reliability(testScores, temperature);

  console.log(`temperature fitted on validation: T = ${temperature.toFixed(3)}`);
  console.log(`  negative log-likelihood ${negativeLogLikelihood(validationScores, 1).toFixed(4)} -> ${negativeLogLikelihood(validationScores, temperature).toFixed(4)}\n`);

  console.log('validation reliability after scaling');
  console.log('  band            n   mean conf   actual acc');
  after.lines.forEach((line) => console.log(line));
  console.log(`  calibration error: ${(100 * before.error).toFixed(2)} -> ${(100 * after.error).toFixed(2)} points\n`);

  console.log('test reliability after scaling');
  console.log('  band            n   mean conf   actual acc');
  testAfter.lines.forEach((line) => console.log(line));
  console.log(`  calibration error: ${(100 * testBefore.error).toFixed(2)} -> ${(100 * testAfter.error).toFixed(2)} points`);

  const payload = {
    method: 'temperature scaling of sigmoid logits, softmax output',
    temperature,
    fittedOn: 'validation split',
    calibrationError: { validation: after.error, test: testAfter.error },
    calibrationErrorBefore: { validation: before.error, test: testBefore.error },
    generatedAt: new Date().toISOString()
  };
  fs.writeFileSync(path.join(MODEL_DIR, 'calibration.json'), JSON.stringify(payload, null, 2));
  console.log(`\nwritten: Figure/Resources/Model/calibration.json (T = ${temperature.toFixed(3)})`);
}

main();
