'use strict';

// Classification by cell intensities (the second method from the Zavyalov article):
// the normalised figure is split into an 8x8 grid and every cell contributes its mean
// intensity. Three scale-invariant geometric descriptors are appended because an 8x8
// grid alone cannot separate a square rotated by 45 degrees from a triangle.
// Mirrored 1:1 by FeatureExtractor.swift.

const { GRID_SIDE, normalise } = require('./preprocess');

const CELLS = 8;                       // 8 x 8 cell grid
const POOL = GRID_SIDE / CELLS;        // 32 / 8 = 4 source cells per feature
const GRID_FEATURES = CELLS * CELLS;   // 64
const EXTRA_FEATURES = 5;              // fill, compactness, symmetry, corners, rectangularity
const FEATURE_COUNT = GRID_FEATURES + EXTRA_FEATURES; // 69
const MAX_CORNERS = 12;

// Mean intensity per cell: a 4x4 box average over the 32x32 normalised grid.
function poolGrid(grid) {
  const pooled = new Float64Array(GRID_FEATURES);

  for (let cy = 0; cy < CELLS; cy += 1) {
    for (let cx = 0; cx < CELLS; cx += 1) {
      let sum = 0;
      for (let y = 0; y < POOL; y += 1) {
        for (let x = 0; x < POOL; x += 1) {
          sum += grid[(cy * POOL + y) * GRID_SIDE + cx * POOL + x];
        }
      }
      pooled[cy * CELLS + cx] = sum / (POOL * POOL);
    }
  }

  return pooled;
}

// Count of 4-connected mask transitions — a discrete perimeter estimate.
function perimeter(crop, width, height) {
  let edges = 0;

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const value = crop[y * width + x];
      if (x + 1 < width && value !== crop[y * width + x + 1]) edges += 1;
      if (y + 1 < height && value !== crop[(y + 1) * width + x]) edges += 1;
    }
  }

  return edges;
}

// Ramer-Douglas-Peucker on the convex hull. The number of vertices that survive is the
// classic separator for convex shapes: 3 for a triangle, 4 for a square, many for a circle.
// Tolerance scales with the hull's size, so the count does not depend on resolution.
function cornerCount(hull) {
  if (!hull || hull.length < 3) return 0;

  let perimeter = 0;
  for (let i = 0; i < hull.length; i += 1) {
    const [x1, y1] = hull[i];
    const [x2, y2] = hull[(i + 1) % hull.length];
    perimeter += Math.hypot(x2 - x1, y2 - y1);
  }
  const tolerance = Math.max(1, 0.025 * perimeter);

  const distance = (point, from, to) => {
    const dx = to[0] - from[0];
    const dy = to[1] - from[1];
    const length = Math.hypot(dx, dy);
    if (length === 0) return Math.hypot(point[0] - from[0], point[1] - from[1]);
    return Math.abs(dy * point[0] - dx * point[1] + to[0] * from[1] - to[1] * from[0]) / length;
  };

  const simplify = (points) => {
    if (points.length < 3) return points;
    let worst = 0;
    let index = 0;
    for (let i = 1; i < points.length - 1; i += 1) {
      const d = distance(points[i], points[0], points[points.length - 1]);
      if (d > worst) {
        worst = d;
        index = i;
      }
    }
    if (worst <= tolerance) return [points[0], points[points.length - 1]];
    return simplify(points.slice(0, index + 1)).slice(0, -1).concat(simplify(points.slice(index)));
  };

  // Split the closed hull at its two most distant vertices so RDP sees two open chains.
  let a = 0;
  let b = 0;
  let best = -1;
  for (let i = 0; i < hull.length; i += 1) {
    for (let j = i + 1; j < hull.length; j += 1) {
      const d = Math.hypot(hull[i][0] - hull[j][0], hull[i][1] - hull[j][1]);
      if (d > best) {
        best = d;
        a = i;
        b = j;
      }
    }
  }
  const first = hull.slice(a, b + 1);
  const second = hull.slice(b).concat(hull.slice(0, a + 1));
  return simplify(first).length + simplify(second).length - 2;
}

// Rotating calipers: area of the hull over the area of its smallest enclosing rectangle.
// Unlike area / bounding box this does not change when the figure is rotated —
// ~1.0 for a square, ~0.785 for a circle, ~0.5 for a triangle at any angle.
function rectangularity(hull) {
  if (!hull || hull.length < 3) return 0;

  let area = 0;
  for (let i = 0; i < hull.length; i += 1) {
    const [x1, y1] = hull[i];
    const [x2, y2] = hull[(i + 1) % hull.length];
    area += x1 * y2 - x2 * y1;
  }
  area = Math.abs(area) / 2;
  if (area === 0) return 0;

  let smallest = Infinity;
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

    smallest = Math.min(smallest, (maxU - minU) * (maxV - minV));
  }

  return smallest === Infinity || smallest === 0 ? 0 : Math.min(area / smallest, 1);
}

function geometry(crop, width, height) {
  let area = 0;
  for (let i = 0; i < crop.length; i += 1) area += crop[i];

  // area / bounding box: ~0.785 for a circle, ~0.5 for a triangle, 0.5...1.0 for a square.
  const fill = area / (width * height);

  // Isoperimetric ratio, clamped because the discrete perimeter underestimates
  // diagonal borders and may otherwise push the ratio far above 1 and destabilise training.
  const edges = perimeter(crop, width, height);
  const compactness = Math.min((4 * Math.PI * area) / Math.max(edges * edges, 1), 1);

  // Top/bottom mass ratio: close to 1 for a circle or square, well below 1 for a triangle.
  const half = Math.floor(height / 2);
  let top = 0;
  let bottom = 0;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (!crop[y * width + x]) continue;
      if (y < half) top += 1; else bottom += 1;
    }
  }
  const topMean = half > 0 ? top / (half * width) : 0;
  const bottomMean = (height - half) > 0 ? bottom / ((height - half) * width) : 0;
  const symmetry = Math.min(topMean / Math.max(bottomMean, 1e-3), 2) / 2;

  return { fill, compactness, symmetry, area, perimeter: edges };
}

// gray: Float64Array in [0, 1]. Returns null when the image holds no isolable figure.
function extract(gray, width, height) {
  const normalised = normalise(gray, width, height);
  if (!normalised) return null;

  const cells = poolGrid(normalised.grid);
  const shape = geometry(normalised.crop, normalised.cropWidth, normalised.cropHeight);
  const corners = cornerCount(normalised.hull);
  const rectangular = rectangularity(normalised.hull);

  const features = new Float64Array(FEATURE_COUNT);
  features.set(cells, 0);
  features[GRID_FEATURES] = shape.fill;
  features[GRID_FEATURES + 1] = shape.compactness;
  features[GRID_FEATURES + 2] = shape.symmetry;
  features[GRID_FEATURES + 3] = Math.min(corners, MAX_CORNERS) / MAX_CORNERS;
  features[GRID_FEATURES + 4] = rectangular;

  return {
    features,
    cells,
    geometry: { ...shape, corners, rectangularity: rectangular },
    box: normalised.box
  };
}

module.exports = { CELLS, GRID_FEATURES, FEATURE_COUNT, MAX_CORNERS, extract, poolGrid, geometry, cornerCount, rectangularity };
