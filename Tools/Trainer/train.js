'use strict';

// Trains the Brain.js network and writes everything the iOS app needs:
//   model.json    - brain.NeuralNetwork#toJSON(), loaded and evaluated by the app
//   metrics.json  - accuracy / confusion matrix / hyperparameters of this run
//   fixtures.json - reference feature vectors and outputs that pin the Swift port
//
// Usage: node train.js [--per-class 1200] [--augmented 1200] [--iterations 400] [--rebuild]

const fs = require('fs');
const path = require('path');
const dataset = require('./dataset');
const network = require('./network');
const { decodeGrayscale } = require('./png');
const { extract } = require('./features');

const OUTPUT_DIR = path.resolve(__dirname, '../../Figure/Resources/Model');
const SAMPLE_DIR = path.resolve(__dirname, '../../Figure/Resources/Samples');
const FIXTURES_PER_SOURCE = 5; // per class, per source

function parseArguments(argv) {
  const options = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--rebuild') options.useCache = false;
    else if (token === '--per-class') options.perClass = Number(argv[i += 1]);
    else if (token === '--augmented-ratio') options.augmentedRatio = Number(argv[i += 1]);
    else if (token === '--iterations') options.iterations = Number(argv[i += 1]);
    else if (token === '--hidden') options.hiddenLayers = argv[i += 1].split(',').map(Number);
    else if (token === '--learning-rate') options.learningRate = Number(argv[i += 1]);
    else if (token === '--error-thresh') options.errorThresh = Number(argv[i += 1]);
  }
  return options;
}

// Reference vectors computed here in JavaScript; FixtureValidator.swift recomputes them
// from the same PNG files and fails loudly if the two preprocessing paths ever diverge.
// The referenced images are copied into the app bundle so the check can run on device.
function buildFixtures(net) {
  const fixtures = [];
  fs.rmSync(SAMPLE_DIR, { recursive: true, force: true });
  fs.mkdirSync(SAMPLE_DIR, { recursive: true });

  const collect = (sourceKey, className) => {
    const source = dataset.SOURCES[sourceKey];
    const folder = source.folders[className];

    if (source.splitBy === 'author') {
      const author = fs.readdirSync(source.directory).sort()[0];
      const directory = path.join(source.directory, author, folder);
      return fs.readdirSync(directory).sort().slice(0, FIXTURES_PER_SOURCE).map((file) => path.join(directory, file));
    }

    const directory = path.join(source.directory, folder);
    return fs
      .readdirSync(directory)
      .filter((name) => name.toLowerCase().endsWith('.png'))
      .sort((a, b) => parseInt(a, 10) - parseInt(b, 10))
      .slice(0, FIXTURES_PER_SOURCE)
      .map((file) => path.join(directory, file));
  };

  dataset.CLASSES.forEach((className, classIndex) => {
    dataset.SOURCE_KEYS.forEach((sourceKey) => {
      collect(sourceKey, className).forEach((file, index) => {
        const image = decodeGrayscale(file);
        const result = extract(image.gray, image.width, image.height);
        if (!result) return;
        const prediction = network.predict(net, Array.from(result.features));

        const bundleName = `${className}-${sourceKey}-${index}.png`;
        fs.copyFileSync(file, path.join(SAMPLE_DIR, bundleName));

        fixtures.push({
          file: path.relative(dataset.DATASET_ROOT, file),
          bundleName,
          source: sourceKey,
          label: className,
          labelIndex: classIndex,
          features: Array.from(result.features),
          output: prediction.raw,
          predicted: prediction.label
        });
      });
    });
  });

  return fixtures;
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  console.log('Figure recognition trainer — Brain.js\n');

  const { train: trainingSet, validation, test } = dataset.load({
    perClass: options.perClass ?? 1200,
    augmentedRatio: options.augmentedRatio ?? 1,
    useCache: options.useCache ?? true
  });
  console.log(`samples: ${trainingSet.length} training, ${validation.length} validation, ${dataset.FEATURE_COUNT} inputs\n`);

  const { net, config } = network.create(options);
  console.log(`network: ${dataset.FEATURE_COUNT} -> ${config.hiddenLayers.join(' -> ')} -> ${dataset.CLASSES.length}  (${config.activation}, lr ${config.learningRate}, momentum ${config.momentum})`);

  // Early stopping: the iteration budget is an upper bound, validation decides where to stop.
  const status = network.trainWithEarlyStopping(net, trainingSet, validation, config);
  console.log(`\ntrained in ${status.seconds.toFixed(1)}s — stopped at iteration ${status.bestIteration} of ${status.iterations} run, final error ${status.error.toFixed(6)}\n`);

  const trainingMetrics = network.evaluate(net, trainingSet);
  const validationMetrics = network.evaluate(net, validation);
  const testMetrics = network.evaluate(net, test);
  const calibration = network.fitTemperature(net, validation);

  const percent = (value) => (value === null ? 'n/a' : `${(value * 100).toFixed(2)}%`);
  console.log(`training accuracy   : ${percent(trainingMetrics.accuracy)}`);
  console.log(`validation accuracy : ${percent(validationMetrics.accuracy)}`);
  console.log(`  on clean images   : ${percent(validationMetrics.cleanAccuracy)}`);
  console.log(`  on augmented      : ${percent(validationMetrics.augmentedAccuracy)}`);
  console.log(`  on generated set  : ${percent(validationMetrics.filledAccuracy)}`);
  console.log(`  on hand-drawn set : ${percent(validationMetrics.drawnAccuracy)}  <- unseen authors`);
  console.log(`\ntest accuracy       : ${percent(testMetrics.accuracy)}  <- held out, never used for tuning`);
  console.log(`  on generated set  : ${percent(testMetrics.filledAccuracy)}`);
  console.log(`  on hand-drawn set : ${percent(testMetrics.drawnAccuracy)}`);
  console.log(`\ntest confusion matrix:\n${network.formatMatrix(testMetrics.matrix)}\n`);
  console.log(`confidence calibration: temperature ${calibration.temperature.toFixed(4)}, validation NLL ${calibration.validationNllBefore.toFixed(4)} -> ${calibration.validationNllAfter.toFixed(4)}\n`);

  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  const model = net.toJSON();
  fs.writeFileSync(path.join(OUTPUT_DIR, 'model.json'), JSON.stringify(model));

  const metrics = {
    generatedAt: new Date().toISOString(),
    dataset: {
      sources: dataset.SOURCE_KEYS.map((key) => dataset.SOURCES[key].name),
      classes: dataset.CLASSES,
      perClassPerSource: options.perClass ?? 1200,
      augmentedRatio: options.augmentedRatio ?? 1,
      training: trainingSet.length,
      validation: validation.length,
      test: test.length,
      note: 'the hand-drawn source is split by author, so validation authors are unseen'
    },
    network: { inputs: dataset.FEATURE_COUNT, ...config, library: `brain.js ${require('brain.js/package.json').version}` },
    calibration,
    training: {
      iterations: status.iterations,
      bestIteration: status.bestIteration,
      earlyStopping: 'weights taken from the best validation score, not the last iteration',
      error: status.error,
      seconds: status.seconds,
      history: status.history
    },
    accuracy: {
      training: trainingMetrics.accuracy,
      validation: validationMetrics.accuracy,
      validationClean: validationMetrics.cleanAccuracy,
      validationAugmented: validationMetrics.augmentedAccuracy,
      validationGenerated: validationMetrics.filledAccuracy,
      validationHandDrawn: validationMetrics.drawnAccuracy,
      test: testMetrics.accuracy,
      testGenerated: testMetrics.filledAccuracy,
      testHandDrawn: testMetrics.drawnAccuracy
    },
    confusion: { labels: dataset.CLASSES, validation: validationMetrics.matrix, training: trainingMetrics.matrix }
  };
  fs.writeFileSync(path.join(OUTPUT_DIR, 'metrics.json'), JSON.stringify(metrics, null, 2));

  const fixtures = buildFixtures(net);
  fs.writeFileSync(path.join(OUTPUT_DIR, 'fixtures.json'), JSON.stringify({ featureCount: dataset.FEATURE_COUNT, classes: dataset.CLASSES, fixtures }, null, 2));

  const relative = (name) => path.relative(path.resolve(__dirname, '../..'), path.join(OUTPUT_DIR, name));
  console.log(`written:\n  ${relative('model.json')} (${(JSON.stringify(model).length / 1024).toFixed(1)} KB)\n  ${relative('metrics.json')}\n  ${relative('fixtures.json')} (${fixtures.length} vectors)\n  ${path.relative(path.resolve(__dirname, '../..'), SAMPLE_DIR)}/ (${fixtures.length} images)`);
}

main();
