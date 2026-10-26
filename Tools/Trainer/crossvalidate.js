'use strict';

// K-fold cross-validation over authors.
//
// A single held-out split of 7 people carries roughly +-3 points of noise, so comparing two
// configurations against it says more about which people landed where than about the models.
// Every author takes a turn in the held-out fold here, and the spread across folds is reported
// next to the mean — a difference smaller than that spread is not a difference.
//
// Usage: node crossvalidate.js [--folds 5] [--per-author 120] [--per-class 1200]

const fs = require('fs');
const path = require('path');
const { decodeGrayscale } = require('./png');
const { extract } = require('./features');
const { augment } = require('./augment');
const { createRandom } = require('./random');
const network = require('./network');
const dataset = require('./dataset');

const CLASSES = dataset.CLASSES;

function parseArguments(argv) {
  const options = { folds: 5, perAuthor: 120, perClass: 1200 };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--folds') options.folds = Number(argv[i += 1]);
    else if (argv[i] === '--per-author') options.perAuthor = Number(argv[i += 1]);
    else if (argv[i] === '--per-class') options.perClass = Number(argv[i += 1]);
  }
  return options;
}

function toPair(features, classIndex, source, augmented) {
  return {
    input: features,
    output: dataset.oneHot(classIndex),
    label: classIndex,
    source,
    augmented
  };
}

// Features are extracted once; folds only regroup what is already in memory.
function collect({ perAuthor, perClass, random }) {
  const drawn = dataset.SOURCES.drawn;
  const filled = dataset.SOURCES.filled;

  const byAuthor = new Map();
  for (const author of fs.readdirSync(drawn.directory)) {
    const samples = [];
    CLASSES.forEach((className, classIndex) => {
      const directory = path.join(drawn.directory, author, drawn.folders[className]);
      if (!fs.existsSync(directory)) return;

      for (const file of random.shuffle(fs.readdirSync(directory)).slice(0, perAuthor)) {
        const image = decodeGrayscale(path.join(directory, file));
        const clean = extract(image.gray, image.width, image.height);
        if (clean) samples.push(toPair(Array.from(clean.features), classIndex, 'drawn', false));

        const variant = augment(image, random, 'drawn');
        const augmented = extract(variant.gray, variant.width, variant.height);
        if (augmented) samples.push(toPair(Array.from(augmented.features), classIndex, 'drawn', true));
      }
    });
    byAuthor.set(author, samples);
  }

  const generated = [];
  CLASSES.forEach((className, classIndex) => {
    const directory = path.join(filled.directory, filled.folders[className]);
    for (const file of random.shuffle(fs.readdirSync(directory)).slice(0, perClass)) {
      const image = decodeGrayscale(path.join(directory, file));
      const clean = extract(image.gray, image.width, image.height);
      if (clean) generated.push(toPair(Array.from(clean.features), classIndex, 'filled', false));

      const variant = augment(image, random, 'filled');
      const augmented = extract(variant.gray, variant.width, variant.height);
      if (augmented) generated.push(toPair(Array.from(augmented.features), classIndex, 'filled', true));
    }
  });

  return { byAuthor, generated };
}

function statistics(values) {
  const mean = values.reduce((sum, value) => sum + value, 0) / values.length;
  const deviation = Math.sqrt(values.reduce((sum, value) => sum + (value - mean) ** 2, 0) / values.length);
  return { mean, deviation, min: Math.min(...values), max: Math.max(...values) };
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  const random = createRandom(20261004);

  console.log(`cross-validation: ${options.folds} folds over authors\n`);
  const started = Date.now();
  const { byAuthor, generated } = collect({ perAuthor: options.perAuthor, perClass: options.perClass, random });
  const authors = random.shuffle([...byAuthor.keys()]);
  const drawnCount = [...byAuthor.values()].reduce((sum, list) => sum + list.length, 0);
  console.log(`features: ${drawnCount} hand-drawn from ${authors.length} authors, ${generated.length} generated — ${((Date.now() - started) / 1000).toFixed(1)}s\n`);

  // Generated images are split by file inside each fold, the drawn ones by author.
  const generatedFolds = [];
  const shuffledGenerated = random.shuffle([...generated]);
  for (let fold = 0; fold < options.folds; fold += 1) {
    generatedFolds.push(shuffledGenerated.filter((_, index) => index % options.folds === fold));
  }

  const candidates = {
    'hidden 16, fixed 600 iterations': { hiddenLayers: [16], earlyStopping: false, iterations: 600 },
    'hidden 8, early stopping': { hiddenLayers: [8], earlyStopping: true, iterations: 1200 },
    'hidden 16, early stopping': { hiddenLayers: [16], earlyStopping: true, iterations: 1200 },
    'hidden 4, early stopping': { hiddenLayers: [4], earlyStopping: true, iterations: 1200 }
  };

  const results = {};

  for (const [name, settings] of Object.entries(candidates)) {
    const overall = [];
    const drawnOnly = [];
    const gaps = [];

    for (let fold = 0; fold < options.folds; fold += 1) {
      const heldOutAuthors = authors.filter((_, index) => index % options.folds === fold);
      const heldOut = heldOutAuthors.flatMap((author) => byAuthor.get(author)).concat(generatedFolds[fold]);
      const training = authors
        .filter((author) => !heldOutAuthors.includes(author))
        .flatMap((author) => byAuthor.get(author))
        .concat(generatedFolds.filter((_, index) => index !== fold).flat());
      random.shuffle(training);

      const { net, config } = network.create({ hiddenLayers: settings.hiddenLayers, iterations: settings.iterations });
      if (settings.earlyStopping) {
        // The stopping point needs data the weights are not fitted on; a slice of the
        // training folds is used, never the held-out one.
        const monitorSize = Math.floor(training.length * 0.15);
        const monitor = training.slice(0, monitorSize);
        network.trainWithEarlyStopping(net, training.slice(monitorSize), monitor, config, { verbose: false });
      } else {
        network.train(net, training, config, { verbose: false });
      }

      const scores = network.evaluate(net, heldOut);
      const trainScores = network.evaluate(net, training);
      overall.push(scores.accuracy);
      drawnOnly.push(scores.drawnAccuracy);
      gaps.push(trainScores.accuracy - scores.accuracy);
    }

    results[name] = { overall: statistics(overall), drawn: statistics(drawnOnly), gap: statistics(gaps) };
    const r = results[name];
    console.log(name.padEnd(32),
      `held-out ${(100 * r.overall.mean).toFixed(2)}% ± ${(100 * r.overall.deviation).toFixed(2)}`,
      ` drawn ${(100 * r.drawn.mean).toFixed(2)}% ± ${(100 * r.drawn.deviation).toFixed(2)}`,
      ` gap ${(100 * r.gap.mean).toFixed(1)}`);
  }

  const ranked = Object.entries(results).sort((a, b) => b[1].overall.mean - a[1].overall.mean);
  const [bestName, best] = ranked[0];
  const [runnerName, runner] = ranked[1];
  const difference = 100 * (best.overall.mean - runner.overall.mean);
  const noise = 100 * Math.max(best.overall.deviation, runner.overall.deviation);

  console.log(`\nbest mean: ${bestName}`);
  console.log(difference < noise
    ? `but it leads "${runnerName}" by ${difference.toFixed(2)} points while folds vary by ±${noise.toFixed(2)} — not a real difference`
    : `leads "${runnerName}" by ${difference.toFixed(2)} points against a fold spread of ±${noise.toFixed(2)}`);
}

main();
