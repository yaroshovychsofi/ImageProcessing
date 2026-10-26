# Trainer

Trains the figure recognition network with **Brain.js** and exports everything the iOS app
loads at runtime. The app never trains: it only evaluates `model.json`.

The currently shipped `model.json` is the 69-input thin-stroke-safe model. The iOS runtime
also remains able to load a 67-input model if one is supplied, but only the current production
model is kept in the clean project.

## Datasets

Two sources, both kept out of git under `.dataset/`:

| Source | Content | Layout |
| --- | --- | --- |
| [Four Shapes](https://www.kaggle.com/datasets/smeschke/four-shapes) (CC0) | 11 205 generated solid figures, 200×200 | `.dataset/shapes/<class>/*.png` |
| [Hand-drawn Shapes](https://www.kaggle.com/datasets/frobert/handdrawn-shapes-hds-dataset) (CC BY 4.0) | 20 005 pen drawings by 37 people, 70×70 | `.dataset/handdrawn/<author>/<class>/*.png` |

Class folders map as `ellipse → circle`, `rectangle → square`, `triangle → triangle`.

Neither dataset is in git — together they are 122 MB that only the trainer reads. Fetch them
with `npm run datasets` (or `./download-datasets.sh`). Both download without a Kaggle account:
the API endpoint redirects to a signed storage URL. The script also rearranges the hand-drawn
archive from `data/<author>/images/<class>` into `<author>/<class>` and drops the fourth
`star` class from Four Shapes.

The generated set is split by file; the hand-drawn set is split **by author**, so validation
measures recognition of a hand the network has never seen rather than memorisation of one.

## Commands

```
npm install
npm run datasets        # download Four Shapes and Hand-drawn Shapes into .dataset/
npm run train           # extract features, train, export model + metrics + fixtures
npm run evaluate        # accuracy of the shipped model and a feature ablation
npm run cross-validate  # k-fold over authors: compares configurations without burning the test split
```

`train.js` flags: `--per-class`, `--augmented-ratio`, `--iterations`, `--hidden`, `--learning-rate`,
`--error-thresh`, `--rebuild` (ignore the feature cache).

## Pipeline

1. `png.js` — PNG decoding on Node's built-in `zlib`, no image libraries.
2. `preprocess.js` — Otsu threshold on the original pixels → significant connected components
   (at least 12% of the largest) → convex hull → canonical rotation → area-weighted resampling
   to 32×32. Thresholding the original preserves one-pixel pencil strokes; retaining multiple
   substantial components lets the hull reconnect an interrupted hand-drawn contour.
   The hull turns a drawn outline into the solid figure it depicts (all three classes are
   convex); the rotation puts every figure into one orientation so the cell grid is comparable.
3. `features.js` — 8×8 cell intensities (64) + area/bbox, compactness, vertical symmetry,
   corner count after RDP simplification, and rectangularity (5).
4. `augment.js` — rotation, rescaling, blur and noise, with a gentler profile for the drawn
   source: the aggressive profile erases 2-pixel pen strokes and costs ~15 accuracy points.
5. `network.js` / `train.js` — `brain.NeuralNetwork`, 69 → 8 → 3, sigmoid.

After training, temperature scaling is fitted on the validation split and written to
`metrics.json`. The app applies it only to the displayed class distribution: it does not alter
the winning class, but prevents saturated sigmoid outputs from being shown as false certainty.

## Outputs (`Figure/Resources/`)

| File | Purpose |
| --- | --- |
| `Model/model.json` | `net.toJSON()`, parsed by `BrainNetwork.swift` |
| `Model/metrics.json` | accuracy, confusion matrix, hyperparameters of the run |
| `Model/fixtures.json` | reference vectors that pin the Swift port to this pipeline |
| `Samples/*.png` | the images those fixtures refer to |

## Current 69-feature model

Three splits. Validation is what every design decision was tuned against, so only the test
column is an unbiased estimate. Network: 69 → 8 → 3, early stopping at iteration 350 of a
1200 budget.

| Split | Overall | Generated | Hand-drawn |
| --- | --- | --- | --- |
| Training | 99.72% | — | — |
| Validation | 98.01% | 100% | 95.55% |
| **Test (held out)** | **96.99%** | 100% | **93.98%** |

Cross-validation over authors (`npm run cross-validate`, every author held out once) agrees:
96.6% ± 2.0 across five folds, which is where the single test figure lands.

Reading these honestly:

- The train→test gap is 3.2 points. It was 6-7 points before the sampling fix below, and
  regularisation had nothing to do with closing it.
- 100% on the generated source everywhere means little. Those images come from one script and
  are near-duplicates of each other, so that column measures reproduction, not generalisation.
- Per-author accuracy ranges from 79% to 100%, σ ≈ 6-8 points. With seven people in the test
  split that is ±3 points of standard error, so a two-point difference between configurations
  is noise. Cross-validation showed four architectures (4, 8 and 16 hidden units, with and
  without early stopping) within 0.2 points of each other — none is meaningfully better.
- Accuracy depends on where a drawing sits in its author's sequence: 96.9% on each author's
  first 20 drawings, 87.9% on their last 20. All numbers sample files at random.

### Confidence calibration

The network ends in sigmoids trained towards 0 and 1, so its raw outputs saturate: 5076 of
5184 held-out predictions came out above 99.9% "confidence" — including 113 wrong ones. The
argmax was fine, the number next to it was not.

`train.js` fits a single temperature on the validation split by minimising negative
log-likelihood and stores it with the training metrics. The app reads that value from
`metrics.json`. Each sigmoid activation is turned back into the score that produced it, the
scores are divided by T and passed through a softmax. It cannot change which class wins.

| | Before | After (T = 3.56) |
| --- | --- | --- |
| Calibration error, validation | 1.85 points | 0.13 points |
| Calibration error, test | 2.85 points | 0.98 points |

Reliability on the test split after scaling: predictions claiming 97.4% are right 96.4% of
the time, those claiming 99.5% are right 99.0%, and the 0.5-0.7 band is right 60.0%. The app
also rounds percentages down, because a displayed "100%" is always a rounding artefact.

### Why the sampling is balanced per author

Taking files from a pooled list made the metric belong to whoever drew the most. One author
owns 1627 of the 2889 files in the test group — 56% — and the three largest contributors are
also the three hardest to read (85.8%, 80.8%, 83.3%) while people with 90 files each score
near 100%. Pooled, the test set reported 83.3% on hand-drawn input; that was three people's
score presented as everyone's. With an equal quota per person it reports 92.1%, and the
difference is in what is being measured, not in the model.

Steps 2 and 3 exist twice — here and in `Figure/ML` — because the trainer runs on Node and
the app on iOS. `FixtureValidator.swift` recomputes the fixtures on device and reports any
divergence, so the duplication cannot drift unnoticed.
