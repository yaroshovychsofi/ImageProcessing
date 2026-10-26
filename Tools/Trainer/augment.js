'use strict';

// Training-time augmentation. The source dataset is machine generated: every figure is
// centred, noise-free and drawn by the same script, so a network trained on it alone
// collapses on real photographs. Rotation, rescaling, blur and additive noise are applied
// to the grayscale image *before* normalisation, i.e. exactly where real-world variation
// enters. Augmentation lives in the trainer only — the app never needs it.

const WHITE = 1;

function sample(gray, width, height, x, y) {
  if (x < 0 || y < 0 || x > width - 1 || y > height - 1) return WHITE;

  const x0 = Math.floor(x);
  const y0 = Math.floor(y);
  const x1 = Math.min(x0 + 1, width - 1);
  const y1 = Math.min(y0 + 1, height - 1);
  const fx = x - x0;
  const fy = y - y0;

  const top = gray[y0 * width + x0] * (1 - fx) + gray[y0 * width + x1] * fx;
  const bottom = gray[y1 * width + x0] * (1 - fx) + gray[y1 * width + x1] * fx;
  return top * (1 - fy) + bottom * fy;
}

function rotate(image, radians) {
  const { width, height, gray } = image;
  const cos = Math.cos(radians);
  const sin = Math.sin(radians);

  // Expand the canvas so the rotated figure is never clipped.
  const outWidth = Math.ceil(Math.abs(width * cos) + Math.abs(height * sin));
  const outHeight = Math.ceil(Math.abs(width * sin) + Math.abs(height * cos));
  const out = new Float64Array(outWidth * outHeight);

  const srcCx = (width - 1) / 2;
  const srcCy = (height - 1) / 2;
  const dstCx = (outWidth - 1) / 2;
  const dstCy = (outHeight - 1) / 2;

  for (let y = 0; y < outHeight; y += 1) {
    for (let x = 0; x < outWidth; x += 1) {
      const dx = x - dstCx;
      const dy = y - dstCy;
      // Inverse mapping: look up where this destination pixel came from.
      out[y * outWidth + x] = sample(gray, width, height, srcCx + dx * cos + dy * sin, srcCy - dx * sin + dy * cos);
    }
  }

  return { width: outWidth, height: outHeight, gray: out };
}

function scale(image, factor) {
  const outWidth = Math.max(16, Math.round(image.width * factor));
  const outHeight = Math.max(16, Math.round(image.height * factor));
  const out = new Float64Array(outWidth * outHeight);
  const stepX = image.width / outWidth;
  const stepY = image.height / outHeight;

  for (let y = 0; y < outHeight; y += 1) {
    for (let x = 0; x < outWidth; x += 1) {
      out[y * outWidth + x] = sample(image.gray, image.width, image.height, (x + 0.5) * stepX - 0.5, (y + 0.5) * stepY - 0.5);
    }
  }

  return { width: outWidth, height: outHeight, gray: out };
}

// Repeated 3x3 box blur approximates a Gaussian and imitates an out-of-focus camera.
function blur(image, passes) {
  const { width, height } = image;
  let source = image.gray;

  for (let pass = 0; pass < passes; pass += 1) {
    const out = new Float64Array(width * height);
    for (let y = 0; y < height; y += 1) {
      for (let x = 0; x < width; x += 1) {
        let sum = 0;
        let count = 0;
        for (let dy = -1; dy <= 1; dy += 1) {
          for (let dx = -1; dx <= 1; dx += 1) {
            const nx = x + dx;
            const ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
            sum += source[ny * width + nx];
            count += 1;
          }
        }
        out[y * width + x] = sum / count;
      }
    }
    source = out;
  }

  return { width, height, gray: source };
}

function noise(image, sigma, random) {
  const out = new Float64Array(image.gray.length);
  for (let i = 0; i < out.length; i += 1) {
    out[i] = Math.min(1, Math.max(0, image.gray[i] + random.normal() * sigma));
  }
  return { width: image.width, height: image.height, gray: out };
}

// Augmentation has to match what the source can survive. The generated set is 200x200 solid
// shapes and tolerates anything. The hand-drawn set is 70x70 pen strokes a couple of pixels
// wide: shrinking it by half or blurring it twice erases the stroke, and the result is a
// mislabelled sample that costs more accuracy than the extra variety buys. Measured: the
// aggressive profile applied to the drawn set dropped its clean accuracy from ~95% to ~80%.
const PROFILES = {
  filled: { scale: [0.4, 1.2], blurChance: 0.5, blurPasses: 2, noiseChance: 0.8, noise: [0.04, 0.14] },
  drawn: { scale: [0.8, 1.15], blurChance: 0, blurPasses: 0, noiseChance: 0.5, noise: [0.02, 0.06] }
};

function augment(image, random, profileName = 'filled') {
  const profile = PROFILES[profileName] ?? PROFILES.filled;

  let result = rotate(image, random.between(0, 2 * Math.PI));
  result = scale(result, random.between(profile.scale[0], profile.scale[1]));
  if (profile.blurChance > 0 && random.next() < profile.blurChance) {
    result = blur(result, 1 + random.int(profile.blurPasses));
  }
  if (random.next() < profile.noiseChance) {
    result = noise(result, random.between(profile.noise[0], profile.noise[1]), random);
  }
  return result;
}

module.exports = { augment, rotate, scale, blur, noise, PROFILES };
