'use strict';

// Evaluates the trained model and runs a feature ablation: how well the network performs on
// the 8x8 cell grid alone, on the three geometric descriptors alone, and on both together.
//
// Usage: node evaluate.js

const fs = require('fs');
const path = require('path');
const dataset = require('./dataset');
const network = require('./network');
const { CELLS, GRID_FEATURES } = require('./features');

const MODEL_FILE = path.resolve(__dirname, '../../Figure/Resources/Model/model.json');
const FEATURE_NAMES = ['area / bbox', 'compactness', 'vertical symmetry'];

const percent = (value) => (value === null ? '   n/a' : `${(value * 100).toFixed(2)}%`.padStart(7));

function restrict(data, columns) {
  return data.map((sample) => ({ ...sample, input: columns.map((column) => sample.input[column]) }));
}

function retrain(trainingSet, validation, columns, label) {
  const { net, config } = network.create();
  network.train(net, restrict(trainingSet, columns), config, { verbose: false });
  const metrics = network.evaluate(net, restrict(validation, columns));
  console.log(`  ${label.padEnd(34)} ${percent(metrics.accuracy)}   clean ${percent(metrics.cleanAccuracy)}   augmented ${percent(metrics.augmentedAccuracy)}`);
  return metrics;
}

function main() {
  const { train: trainingSet, validation } = dataset.load();
  console.log(`samples: ${trainingSet.length} training, ${validation.length} validation\n`);

  if (fs.existsSync(MODEL_FILE)) {
    const stored = new (require('brain.js').NeuralNetwork)();
    stored.fromJSON(JSON.parse(fs.readFileSync(MODEL_FILE, 'utf8')));
    const metrics = network.evaluate(stored, validation);

    console.log('shipped model (Figure/Resources/Model/model.json)');
    console.log(`  accuracy ${percent(metrics.accuracy)}   clean ${percent(metrics.cleanAccuracy)}   augmented ${percent(metrics.augmentedAccuracy)}`);
    console.log(`\n${network.formatMatrix(metrics.matrix)}\n`);
  } else {
    console.log('no trained model found — run `npm run train` first\n');
  }

  const grid = Array.from({ length: GRID_FEATURES }, (_, i) => i);
  const geometry = Array.from({ length: dataset.FEATURE_COUNT - GRID_FEATURES }, (_, i) => GRID_FEATURES + i);

  console.log('feature ablation (each variant retrained from scratch)');
  retrain(trainingSet, validation, [...grid, ...geometry], 'all features');
  retrain(trainingSet, validation, grid, `${CELLS}x${CELLS} cell grid only`);
  retrain(trainingSet, validation, geometry, `geometry only (${FEATURE_NAMES.join(', ')})`);
}

main();
