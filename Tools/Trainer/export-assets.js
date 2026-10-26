'use strict';

// Copies a balanced, reproducible subset of both datasets into the app bundle so that the
// in-app trainer has real images to learn from. Folders are grouped by source quality:
//   Assets/generated_200/<class>/  — Four Shapes, solid figures, 200×200
//   Assets/handdrawn_70/<class>/   — Hand-drawn Shapes, pen outlines, 70×70
// Usage: node export-assets.js [--per-class 100]

const fs = require('fs');
const path = require('path');
const { createRandom } = require('./random');

const root = path.resolve(__dirname, '../..');
const datasetDir = path.join(root, '.dataset');
const outDir = path.join(root, 'Figure/Resources/Assets');
const flag = process.argv.indexOf('--per-class');
const perClass = flag > 0 ? Number(process.argv[flag + 1]) : 100;
const random = createRandom(2025);

const classes = ['circle', 'square', 'triangle'];
const handdrawnFolder = { circle: 'ellipse', square: 'rectangle', triangle: 'triangle' };
const pngs = (dir) => !fs.existsSync(dir) ? [] : fs.readdirSync(dir).filter((name) => name.endsWith('.png')).map((name) => path.join(dir, name));

function copy(files, target, prefix) {
  fs.mkdirSync(target, { recursive: true });
  files.forEach((file, index) => fs.copyFileSync(file, path.join(target, `${prefix}-${String(index).padStart(3, '0')}.png`)));
}

fs.rmSync(outDir, { recursive: true, force: true });
const authors = fs.readdirSync(path.join(datasetDir, 'handdrawn')).filter((name) => !name.startsWith('.')).sort();

for (const figure of classes) {
  const generated = random.shuffle(pngs(path.join(datasetDir, 'shapes', figure)).sort()).slice(0, perClass);
  copy(generated, path.join(outDir, 'generated_200', figure), figure);

  // Round-robin over authors so the subset keeps the variety of handwriting.
  const byAuthor = authors.map((author) => random.shuffle(pngs(path.join(datasetDir, 'handdrawn', author, handdrawnFolder[figure])).sort()));
  const drawn = [];
  for (let round = 0; drawn.length < perClass; round += 1) {
    for (const files of byAuthor) if (files[round] && drawn.length < perClass) drawn.push(files[round]);
  }
  copy(drawn, path.join(outDir, 'handdrawn_70', figure), figure);
}

console.log(`exported ${perClass * classes.length * 2} images into ${path.relative(root, outDir)}`);
