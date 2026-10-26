'use strict';

// Two sources, one feature space:
//   filled - Kaggle smeschke/four-shapes (CC0): machine generated, solid figures.
//   drawn  - Kaggle frobert/handdrawn-shapes-hds-dataset (CC BY 4.0): real pen drawings,
//            37 authors, outlines rather than solid shapes.
// The drawn set is what keeps the network honest: a model trained only on generated images
// learns the generator, not the shape.
//
// Splitting differs per source and is done before any sample is generated. Files are split
// for the generated set; the drawn set is split by *author*, because the same person's
// handwriting in both halves would make validation measure memorisation of that hand.
//
// Three splits, not two. Validation is what every tuning decision was made against — the
// convex hull, the rotation step, the augmentation profiles, the hidden layer size — so by
// construction it reports an optimistic number. The test split is touched exactly once, at
// the end, and is the only honest estimate of how the model behaves on new input.
//
// Extracted features are cached in a flat binary file: extraction costs far more than
// training, and retraining with new hyperparameters is frequent.

const fs = require('fs');
const path = require('path');
const { decodeGrayscale } = require('./png');
const { extract, FEATURE_COUNT } = require('./features');
const { augment } = require('./augment');
const { createRandom } = require('./random');

const CLASSES = ['circle', 'square', 'triangle'];
const DATASET_ROOT = path.resolve(__dirname, '../../.dataset');
const CACHE_FILE = path.resolve(__dirname, 'cache/features.bin');
const CACHE_FORMAT_VERSION = 2;

const SOURCES = {
  filled: {
    name: 'Four Shapes (Kaggle smeschke/four-shapes, CC0)',
    directory: path.join(DATASET_ROOT, 'shapes'),
    folders: { circle: 'circle', square: 'square', triangle: 'triangle' },
    splitBy: 'file'
  },
  drawn: {
    name: 'Hand-drawn Shapes (Kaggle frobert/handdrawn-shapes-hds-dataset, CC BY 4.0)',
    directory: path.join(DATASET_ROOT, 'handdrawn'),
    folders: { circle: 'ellipse', square: 'rectangle', triangle: 'triangle' },
    splitBy: 'author'
  }
};

const SOURCE_KEYS = Object.keys(SOURCES);

function oneHot(index) {
  return CLASSES.map((_, i) => (i === index ? 1 : 0));
}

function listPNG(directory) {
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory).filter((name) => name.toLowerCase().endsWith('.png'));
}

const SPLITS = ['train', 'validation', 'test'];

// Returns { train: [paths], validation: [paths], test: [paths] } for one class of one source.
function splitFiles(source, className, { perClass, ratios, random, authors }) {
  const folder = source.folders[className];

  if (source.splitBy === 'author') {
    const result = {};
    SPLITS.forEach((split) => {
      const quota = Math.round(perClass * ratios[split]);
      const people = authors[split];
      if (!people.length) {
        result[split] = [];
        return;
      }

      // Equal quota per person. Pooling every file instead would let the most prolific
      // authors define the metric: in this dataset one author owns 1627 of the 2889 files in
      // the test group, and the three largest contributors are also the three hardest to
      // read, so an unbalanced pool reports their score as if it were everyone's.
      const perPerson = Math.ceil(quota / people.length);
      const files = [];
      people.forEach((author) => {
        const directory = path.join(source.directory, author, folder);
        const owned = listPNG(directory).map((file) => path.join(directory, file));
        random.shuffle(owned).slice(0, perPerson).forEach((file) => files.push(file));
      });

      result[split] = random.shuffle(files).slice(0, quota);
    });
    return result;
  }

  const directory = path.join(source.directory, folder);
  const files = random
    .shuffle(listPNG(directory).map((file) => path.join(directory, file)))
    .slice(0, perClass);

  const trainEdge = Math.max(1, Math.floor(files.length * ratios.train));
  const validationEdge = trainEdge + Math.max(1, Math.floor(files.length * ratios.validation));
  return {
    train: files.slice(0, trainEdge),
    validation: files.slice(trainEdge, validationEdge),
    test: files.slice(validationEdge)
  };
}

function sampleFrom({ file, classIndex, sourceKey, split, augmented, random }) {
  const image = decodeGrayscale(file);
  const source = augmented ? augment(image, random, sourceKey) : image;
  const result = extract(source.gray, source.width, source.height);
  if (!result) return null;

  return {
    label: classIndex,
    source: sourceKey,
    split,
    augmented,
    file,
    features: Array.from(result.features)
  };
}

function buildSamples({ perClass, augmentedRatio, ratios, seed, onProgress }) {
  const random = createRandom(seed);
  const samples = [];
  let produced = 0;

  // One author split shared by all classes, so no author appears in two splits.
  const allAuthors = random.shuffle(
    fs.existsSync(SOURCES.drawn.directory) ? fs.readdirSync(SOURCES.drawn.directory) : []
  );
  const trainAuthors = Math.max(1, Math.round(allAuthors.length * ratios.train));
  const validationAuthors = Math.max(1, Math.round(allAuthors.length * ratios.validation));
  const authors = {
    train: allAuthors.slice(0, trainAuthors),
    validation: allAuthors.slice(trainAuthors, trainAuthors + validationAuthors),
    test: allAuthors.slice(trainAuthors + validationAuthors)
  };

  SOURCE_KEYS.forEach((sourceKey) => {
    const source = SOURCES[sourceKey];
    if (!fs.existsSync(source.directory)) {
      console.warn(`skipping source "${sourceKey}": ${source.directory} not found`);
      return;
    }

    CLASSES.forEach((className, classIndex) => {
      const split = splitFiles(source, className, { perClass, ratios, random, authors });

      SPLITS.forEach((splitName) => {
        const files = split[splitName];

        files.forEach((file) => {
          const sample = sampleFrom({ file, classIndex, sourceKey, split: splitName, augmented: false, random });
          produced += 1;
          if (onProgress) onProgress(produced);
          if (sample) samples.push(sample);
        });

        // Augmented variants come only from this split's own files.
        const augmentedCount = Math.round(files.length * augmentedRatio);
        for (let i = 0; i < augmentedCount && files.length > 0; i += 1) {
          const file = files[random.int(files.length)];
          const sample = sampleFrom({ file, classIndex, sourceKey, split: splitName, augmented: true, random });
          produced += 1;
          if (onProgress) onProgress(produced);
          if (sample) samples.push(sample);
        }
      });
    });
  });

  return { samples: random.shuffle(samples), authors };
}

const FLAG_AUGMENTED = 0x80;
const FLAG_VALIDATION = 0x40;
const FLAG_DRAWN = 0x20;
const FLAG_TEST = 0x10;

function writeCache(samples) {
  fs.mkdirSync(path.dirname(CACHE_FILE), { recursive: true });
  const buffer = Buffer.alloc(12 + samples.length * (1 + FEATURE_COUNT * 8));
  buffer.writeUInt32LE(samples.length, 0);
  buffer.writeUInt32LE(FEATURE_COUNT, 4);
  buffer.writeUInt32LE(CACHE_FORMAT_VERSION, 8);

  let offset = 12;
  samples.forEach((sample) => {
    const flags = sample.label
      | (sample.augmented ? FLAG_AUGMENTED : 0)
      | (sample.split === 'validation' ? FLAG_VALIDATION : 0)
      | (sample.split === 'test' ? FLAG_TEST : 0)
      | (sample.source === 'drawn' ? FLAG_DRAWN : 0);
    buffer.writeUInt8(flags, offset);
    offset += 1;
    sample.features.forEach((value) => {
      buffer.writeDoubleLE(value, offset);
      offset += 8;
    });
  });

  fs.writeFileSync(CACHE_FILE, buffer);
}

function readCache() {
  if (!fs.existsSync(CACHE_FILE)) return null;
  const buffer = fs.readFileSync(CACHE_FILE);
  if (buffer.length < 12) return null;
  const count = buffer.readUInt32LE(0);
  const featureCount = buffer.readUInt32LE(4);
  const cacheVersion = buffer.readUInt32LE(8);
  if (featureCount !== FEATURE_COUNT || cacheVersion !== CACHE_FORMAT_VERSION) return null;

  const samples = [];
  let offset = 12;
  for (let i = 0; i < count; i += 1) {
    const flags = buffer.readUInt8(offset);
    offset += 1;
    const features = new Array(featureCount);
    for (let f = 0; f < featureCount; f += 1) {
      features[f] = buffer.readDoubleLE(offset);
      offset += 8;
    }
    samples.push({
      label: flags & 0x0f,
      augmented: Boolean(flags & FLAG_AUGMENTED),
      split: flags & FLAG_VALIDATION ? 'validation' : (flags & FLAG_TEST ? 'test' : 'train'),
      source: flags & FLAG_DRAWN ? 'drawn' : 'filled',
      features
    });
  }
  return samples;
}

function toPair(sample) {
  return {
    input: sample.features,
    output: oneHot(sample.label),
    label: sample.label,
    augmented: sample.augmented,
    source: sample.source
  };
}

function group(samples) {
  return {
    train: samples.filter((sample) => sample.split === 'train').map(toPair),
    validation: samples.filter((sample) => sample.split === 'validation').map(toPair),
    test: samples.filter((sample) => sample.split === 'test').map(toPair)
  };
}

function describe(samples) {
  const counts = {};
  samples.forEach((sample) => {
    const key = `${sample.source}/${sample.split}${sample.augmented ? '+aug' : ''}`;
    counts[key] = (counts[key] ?? 0) + 1;
  });
  return counts;
}

function load({
  perClass = 1200,
  augmentedRatio = 1,
  ratios = { train: 0.65, validation: 0.17, test: 0.18 },
  seed = 20261004,
  useCache = true,
  verbose = true
} = {}) {
  if (useCache) {
    const cached = readCache();
    if (cached) {
      if (verbose) console.log(`cache: ${cached.length} samples from ${path.relative(process.cwd(), CACHE_FILE)}`);
      return { samples: cached, ...group(cached) };
    }
  }

  const expected = SOURCE_KEYS.length * CLASSES.length * Math.round(perClass * (1 + augmentedRatio));
  const started = Date.now();
  let lastLogged = 0;

  const { samples, authors } = buildSamples({
    perClass,
    augmentedRatio,
    ratios,
    seed,
    onProgress: (done) => {
      if (!verbose || done - lastLogged < 500) return;
      lastLogged = done;
      process.stdout.write(`\rextracting features: ${done}/~${expected}`);
    }
  });

  if (verbose) {
    const seconds = (Date.now() - started) / 1000;
    process.stdout.write(`\rextracting features: ${samples.length} samples in ${seconds.toFixed(1)}s (${((1000 * seconds) / samples.length).toFixed(2)} ms/image)\n`);
    console.log(`authors: ${authors.train.length} training, ${authors.validation.length} validation, ${authors.test.length} test (hand-drawn source)`);
    console.log(`composition: ${JSON.stringify(describe(samples))}`);
  }

  writeCache(samples);
  return { samples, ...group(samples) };
}

module.exports = { CLASSES, SOURCES, SOURCE_KEYS, SPLITS, DATASET_ROOT, FEATURE_COUNT, load, buildSamples, group, describe, oneHot };
