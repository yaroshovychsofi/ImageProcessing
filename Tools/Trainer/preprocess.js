'use strict';

// Shape-independent normalisation of an input image.
// Every step here is mirrored 1:1 by ImagePreprocessor.swift in the iOS app,
// so the features the network is trained on are the features it later receives.

const GRID_SIDE = 32;

// Otsu's method: picks the threshold that maximises between-class variance
// of the 256-bin intensity histogram. Returns a level in [0, 1].
function otsuThreshold(gray) {
  const histogram = new Float64Array(256);
  for (let i = 0; i < gray.length; i += 1) {
    let level = Math.round(gray[i] * 255);
    if (level < 0) level = 0;
    if (level > 255) level = 255;
    histogram[level] += 1;
  }

  const total = gray.length;
  let sum = 0;
  for (let level = 0; level < 256; level += 1) sum += level * histogram[level];

  let backgroundWeight = 0;
  let backgroundSum = 0;
  let bestVariance = -1;
  let bestLevel = 127;

  for (let level = 0; level < 256; level += 1) {
    backgroundWeight += histogram[level];
    if (backgroundWeight === 0) continue;
    const foregroundWeight = total - backgroundWeight;
    if (foregroundWeight === 0) break;

    backgroundSum += level * histogram[level];
    const backgroundMean = backgroundSum / backgroundWeight;
    const foregroundMean = (sum - backgroundSum) / foregroundWeight;
    const delta = backgroundMean - foregroundMean;
    const variance = backgroundWeight * foregroundWeight * delta * delta;

    if (variance > bestVariance) {
      bestVariance = variance;
      bestLevel = level;
    }
  }

  return bestLevel / 255;
}

// Convex hull of the thresholded blob, filled by scanlines.
//
// All three classes are convex, so the hull loses nothing that matters and gains a lot: a
// hand-drawn outline becomes the solid figure it depicts, and gaps in the stroke stop
// mattering. Morphological closing plus hole filling was tried first and left 15% of the
// hand-drawn set unusable, because a gap wider than the kernel lets the fill leak out; the
// hull brings that down to 1%. The price is that any blob now looks solid and convex, so
// this cannot be used to tell a figure from an arbitrary photograph.
function convexHull(mask, width, height) {
  const points = [];
  // Only boundary pixels can be hull vertices, which keeps the sort small on large images.
  for (let y = 0; y < height; y += 1) {
    let first = -1;
    let last = -1;
    for (let x = 0; x < width; x += 1) {
      if (!mask[y * width + x]) continue;
      if (first < 0) first = x;
      last = x;
    }
    if (first >= 0) {
      points.push([first, y]);
      if (last !== first) points.push([last, y]);
    }
  }
  if (points.length < 3) return null;

  points.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const cross = (o, a, b) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);

  const lower = [];
  for (const point of points) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], point) <= 0) lower.pop();
    lower.push(point);
  }
  const upper = [];
  for (let i = points.length - 1; i >= 0; i -= 1) {
    const point = points[i];
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], point) <= 0) upper.pop();
    upper.push(point);
  }

  return lower.slice(0, -1).concat(upper.slice(0, -1));
}

// Scanline fill of a convex polygon: per row the polygon covers one interval, so only its
// left and right edges have to be found. O(width * height) rather than a point-in-polygon
// test per pixel.
function fillHull(hull, width, height) {
  const out = new Uint8Array(width * height);

  for (let y = 0; y < height; y += 1) {
    let minX = Infinity;
    let maxX = -Infinity;

    for (let i = 0; i < hull.length; i += 1) {
      const [x1, y1] = hull[i];
      const [x2, y2] = hull[(i + 1) % hull.length];
      if (y1 === y2) {
        if (y1 !== y) continue;
        minX = Math.min(minX, x1, x2);
        maxX = Math.max(maxX, x1, x2);
        continue;
      }

      const top = Math.min(y1, y2);
      const bottom = Math.max(y1, y2);
      if (y < top || y > bottom) continue;

      const x = x1 + ((y - y1) * (x2 - x1)) / (y2 - y1);
      minX = Math.min(minX, x);
      maxX = Math.max(maxX, x);
    }

    if (minX > maxX) continue;
    const from = Math.max(0, Math.ceil(minX - 0.5));
    const to = Math.min(width - 1, Math.floor(maxX + 0.5));
    for (let x = from; x <= to; x += 1) out[y * width + x] = 1;
  }

  return out;
}

// Angle of the longest edge of the hull's minimum-area rectangle. Rotating the figure by
// -angle puts every shape into the same canonical orientation before the cell grid is taken,
// which is what makes the 8x8 intensities comparable between a figure drawn upright and the
// same figure drawn at 40 degrees. Worth ~3 accuracy points on hand-drawn input.
function orientation(hull) {
  // A rectangle has 90-degree symmetry, so every candidate is folded into [0, 90). Without
  // that, a symmetric figure produces several edges with a bit-identical rectangle area and
  // the winner depends on where the hull happens to start — which made the Swift port pick a
  // different canonical rotation for the same circle.
  const fold = (value) => {
    const quarter = Math.PI / 2;
    let folded = value % quarter;
    if (folded < 0) folded += quarter;
    return folded;
  };

  let smallest = Infinity;
  let angle = 0;

  for (let i = 0; i < hull.length; i += 1) {
    const [x1, y1] = hull[i];
    const [x2, y2] = hull[(i + 1) % hull.length];
    const length = Math.hypot(x2 - x1, y2 - y1);
    if (length === 0) continue;

    const ux = (x2 - x1) / length;
    const uy = (y2 - y1) / length;
    let minU = Infinity;
    let maxU = -Infinity;
    let minV = Infinity;
    let maxV = -Infinity;

    for (const [x, y] of hull) {
      const u = x * ux + y * uy;
      const v = -x * uy + y * ux;
      if (u < minU) minU = u;
      if (u > maxU) maxU = u;
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }

    const area = (maxU - minU) * (maxV - minV);
    const candidate = fold(Math.atan2(uy, ux));
    if (area < smallest * (1 - 1e-9) || (area <= smallest * (1 + 1e-9) && candidate < angle)) {
      if (area < smallest) smallest = area;
      angle = candidate;
    }
  }

  return angle;
}

// Nearest-neighbour rotation of a binary mask onto an expanded canvas.
function rotateMask(mask, width, height, angle) {
  const cos = Math.cos(-angle);
  const sin = Math.sin(-angle);
  const outWidth = Math.ceil(Math.abs(width * cos) + Math.abs(height * sin));
  const outHeight = Math.ceil(Math.abs(width * sin) + Math.abs(height * cos));
  const out = new Uint8Array(outWidth * outHeight);

  const srcCx = (width - 1) / 2;
  const srcCy = (height - 1) / 2;
  const dstCx = (outWidth - 1) / 2;
  const dstCy = (outHeight - 1) / 2;

  for (let y = 0; y < outHeight; y += 1) {
    for (let x = 0; x < outWidth; x += 1) {
      const dx = x - dstCx;
      const dy = y - dstCy;
      const sx = Math.round(srcCx + dx * cos + dy * sin);
      const sy = Math.round(srcCy - dx * sin + dy * cos);
      if (sx >= 0 && sy >= 0 && sx < width && sy < height) out[y * outWidth + x] = mask[sy * width + sx];
    }
  }

  return { mask: out, width: outWidth, height: outHeight };
}

// Keeps every substantial 4-connected part of the drawing. A thin hand-drawn contour can
// contain small gaps (for example, where the user lifted the pencil), so keeping only the
// largest component may turn a square into an L-shaped fragment. Tiny JPEG artefacts and
// isolated dust are still rejected relative to the largest detected component.
function significantComponents(mask, width, height, minimumRelativeSize = 0.12) {
  const labels = new Int32Array(mask.length).fill(-1);
  const queue = new Int32Array(mask.length);
  const sizes = [];
  let label = 0;

  for (let start = 0; start < mask.length; start += 1) {
    if (!mask[start] || labels[start] !== -1) continue;

    let head = 0;
    let tail = 0;
    queue[tail] = start;
    tail += 1;
    labels[start] = label;
    let size = 0;

    while (head < tail) {
      const index = queue[head];
      head += 1;
      size += 1;
      const x = index % width;
      const y = (index - x) / width;

      if (x > 0) {
        const neighbour = index - 1;
        if (mask[neighbour] && labels[neighbour] === -1) {
          labels[neighbour] = label;
          queue[tail] = neighbour;
          tail += 1;
        }
      }
      if (x + 1 < width) {
        const neighbour = index + 1;
        if (mask[neighbour] && labels[neighbour] === -1) {
          labels[neighbour] = label;
          queue[tail] = neighbour;
          tail += 1;
        }
      }
      if (y > 0) {
        const neighbour = index - width;
        if (mask[neighbour] && labels[neighbour] === -1) {
          labels[neighbour] = label;
          queue[tail] = neighbour;
          tail += 1;
        }
      }
      if (y + 1 < height) {
        const neighbour = index + width;
        if (mask[neighbour] && labels[neighbour] === -1) {
          labels[neighbour] = label;
          queue[tail] = neighbour;
          tail += 1;
        }
      }
    }

    sizes.push(size);
    label += 1;
  }

  if (sizes.length === 0) return mask;
  let largest = 0;
  for (const size of sizes) if (size > largest) largest = size;
  const minimumSize = Math.max(2, Math.ceil(largest * minimumRelativeSize));
  const out = new Uint8Array(mask.length);
  for (let i = 0; i < mask.length; i += 1) {
    const component = labels[i];
    if (component >= 0 && sizes[component] >= minimumSize) out[i] = 1;
  }
  return out;
}

// 1 marks the figure, 0 the background. The minority class is assumed to be the
// figure, which makes the pipeline indifferent to dark-on-light vs light-on-dark input.
function makeMask(gray, width, height) {
  // The current path intentionally thresholds the original pixels. A 3x3 median filter is
  // excellent for photographs but erases one-pixel pencil strokes. Component filtering below
  // removes isolated noise without destroying the contour itself.
  const threshold = otsuThreshold(gray);
  const mask = new Uint8Array(gray.length);
  let darkCount = 0;

  for (let i = 0; i < gray.length; i += 1) {
    const isDark = gray[i] <= threshold ? 1 : 0;
    mask[i] = isDark;
    darkCount += isDark;
  }

  if (darkCount * 2 > gray.length) {
    for (let i = 0; i < mask.length; i += 1) mask[i] = mask[i] ? 0 : 1;
  }

  const blob = significantComponents(mask, width, height);
  const hull = convexHull(blob, width, height);
  return hull ? fillHull(hull, width, height) : blob;
}

function boundingBox(mask, width, height) {
  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (!mask[y * width + x]) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }

  if (maxX < 0) return null;
  return { x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1 };
}

function cropMask(mask, width, box) {
  const crop = new Uint8Array(box.width * box.height);
  for (let y = 0; y < box.height; y += 1) {
    for (let x = 0; x < box.width; x += 1) {
      crop[y * box.width + x] = mask[(box.y + y) * width + box.x + x];
    }
  }
  return crop;
}

// Area-weighted (box filter) resampling of the cropped mask into side x side cells.
// Exact fractional pixel coverage keeps the result identical in JS and Swift and
// avoids aliasing when the crop is smaller than the target grid.
function resample(crop, cropWidth, cropHeight, side = GRID_SIDE) {
  const out = new Float64Array(side * side);
  const scaleX = cropWidth / side;
  const scaleY = cropHeight / side;

  for (let gy = 0; gy < side; gy += 1) {
    const y0 = gy * scaleY;
    const y1 = y0 + scaleY;

    for (let gx = 0; gx < side; gx += 1) {
      const x0 = gx * scaleX;
      const x1 = x0 + scaleX;
      let accumulated = 0;

      for (let py = Math.floor(y0); py < Math.ceil(y1); py += 1) {
        const weightY = Math.min(py + 1, y1) - Math.max(py, y0);
        if (weightY <= 0) continue;

        for (let px = Math.floor(x0); px < Math.ceil(x1); px += 1) {
          const weightX = Math.min(px + 1, x1) - Math.max(px, x0);
          if (weightX <= 0) continue;
          accumulated += crop[py * cropWidth + px] * weightX * weightY;
        }
      }

      out[gy * side + gx] = accumulated / (scaleX * scaleY);
    }
  }

  return out;
}

// gray: Float64Array in [0, 1]. Returns null when no figure can be isolated.
function normalise(gray, width, height) {
  const mask = makeMask(gray, width, height);
  const box = boundingBox(mask, width, height);
  if (!box) return null;

  const firstCrop = cropMask(mask, width, box);
  const firstHull = convexHull(firstCrop, box.width, box.height);
  if (!firstHull) return null;

  // Canonical orientation, then crop again: rotating moves the figure inside its canvas.
  const rotated = rotateMask(firstCrop, box.width, box.height, orientation(firstHull));
  const rotatedBox = boundingBox(rotated.mask, rotated.width, rotated.height);
  if (!rotatedBox) return null;

  const crop = cropMask(rotated.mask, rotated.width, rotatedBox);
  return {
    box,
    crop,
    cropWidth: rotatedBox.width,
    cropHeight: rotatedBox.height,
    hull: convexHull(crop, rotatedBox.width, rotatedBox.height),
    grid: resample(crop, rotatedBox.width, rotatedBox.height, GRID_SIDE)
  };
}

module.exports = { GRID_SIDE, otsuThreshold, convexHull, fillHull, orientation, rotateMask, significantComponents, makeMask, boundingBox, cropMask, resample, normalise };
