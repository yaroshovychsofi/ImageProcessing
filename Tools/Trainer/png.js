'use strict';

// Minimal PNG decoder built on Node's built-in zlib — no third-party image libraries.
// Returns a grayscale image as Float64Array in [0, 1] (1 = white).
// Supports 8-bit color types 0 (gray), 2 (RGB), 4 (gray+alpha) and 6 (RGBA).

const fs = require('fs');
const zlib = require('zlib');

const SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const CHANNELS = { 0: 1, 2: 3, 4: 2, 6: 4 };
// Rec. 601 luma weights, matching the grayscale conversion used on the iOS side.
const LUMA = [0.299, 0.587, 0.114];

function readChunks(buffer) {
  if (!buffer.subarray(0, 8).equals(SIGNATURE)) throw new Error('not a PNG file');

  const chunks = [];
  let offset = 8;
  while (offset + 8 <= buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString('ascii', offset + 4, offset + 8);
    chunks.push({ type, data: buffer.subarray(offset + 8, offset + 8 + length) });
    offset += 12 + length; // length + type + data + crc
    if (type === 'IEND') break;
  }
  return chunks;
}

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

// Reverses the per-scanline filters defined by the PNG spec (filter types 0-4).
function unfilter(raw, width, height, bytesPerPixel) {
  const stride = width * bytesPerPixel;
  const out = Buffer.alloc(height * stride);

  for (let y = 0; y < height; y += 1) {
    const filter = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, y * (stride + 1) + 1 + stride);
    const target = y * stride;
    const previous = target - stride;

    for (let x = 0; x < stride; x += 1) {
      const left = x >= bytesPerPixel ? out[target + x - bytesPerPixel] : 0;
      const up = y > 0 ? out[previous + x] : 0;
      const upLeft = y > 0 && x >= bytesPerPixel ? out[previous + x - bytesPerPixel] : 0;

      let value = line[x];
      switch (filter) {
        case 0: break;
        case 1: value += left; break;
        case 2: value += up; break;
        case 3: value += (left + up) >> 1; break;
        case 4: value += paeth(left, up, upLeft); break;
        default: throw new Error(`unsupported PNG filter type ${filter}`);
      }
      out[target + x] = value & 0xff;
    }
  }
  return out;
}

function decodeGrayscale(filePath) {
  const chunks = readChunks(fs.readFileSync(filePath));

  const header = chunks.find((chunk) => chunk.type === 'IHDR');
  if (!header) throw new Error('missing IHDR chunk');

  const width = header.data.readUInt32BE(0);
  const height = header.data.readUInt32BE(4);
  const bitDepth = header.data[8];
  const colorType = header.data[9];
  const interlace = header.data[12];

  if (bitDepth !== 8) throw new Error(`unsupported bit depth ${bitDepth}`);
  if (interlace !== 0) throw new Error('interlaced PNG is not supported');
  const channels = CHANNELS[colorType];
  if (!channels) throw new Error(`unsupported color type ${colorType}`);

  const compressed = Buffer.concat(chunks.filter((chunk) => chunk.type === 'IDAT').map((chunk) => chunk.data));
  const pixels = unfilter(zlib.inflateSync(compressed), width, height, channels);

  const gray = new Float64Array(width * height);
  for (let i = 0; i < width * height; i += 1) {
    const base = i * channels;
    let value;
    let alpha = 1;

    if (colorType === 0) {
      value = pixels[base] / 255;
    } else if (colorType === 4) {
      value = pixels[base] / 255;
      alpha = pixels[base + 1] / 255;
    } else {
      value = (LUMA[0] * pixels[base] + LUMA[1] * pixels[base + 1] + LUMA[2] * pixels[base + 2]) / 255;
      if (colorType === 6) alpha = pixels[base + 3] / 255;
    }

    // Transparent areas count as white paper, the same way the iOS app renders them.
    gray[i] = alpha * value + (1 - alpha);
  }

  return { width, height, gray };
}

module.exports = { decodeGrayscale };
