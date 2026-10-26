#!/usr/bin/env bash
# Downloads both datasets into .dataset/ at the repository root.
#
# They are not in git — together they are 122 MB of images that the app never ships, only the
# trainer reads. Both are public on Kaggle and their download endpoints redirect to a signed
# storage URL, so no account or API token is needed.
#
# Usage: ./download-datasets.sh [--force]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DATASET_DIR="$ROOT/.dataset"
FORCE="${1:-}"

download() {
  local slug="$1" target="$2" archive
  if [ -d "$target" ] && [ "$FORCE" != "--force" ]; then
    echo "already present: ${target#"$ROOT"/} (pass --force to re-download)"
    return
  fi

  archive="$(mktemp -t dataset).zip"
  echo "downloading $slug …"
  curl -sSL -o "$archive" "https://www.kaggle.com/api/v1/datasets/download/$slug"
  echo "  $(du -h "$archive" | cut -f1) downloaded, unpacking"
  rm -rf "$target.tmp"
  mkdir -p "$target.tmp"
  unzip -q -o "$archive" -d "$target.tmp"
  rm -f "$archive"
}

mkdir -p "$DATASET_DIR"

# Four Shapes (CC0): star is ignored, the task has three classes.
download "smeschke/four-shapes" "$DATASET_DIR/shapes"
if [ -d "$DATASET_DIR/shapes.tmp" ]; then
  rm -rf "$DATASET_DIR/shapes"
  mkdir -p "$DATASET_DIR/shapes"
  for class in circle square triangle; do
    mv "$DATASET_DIR/shapes.tmp/shapes/$class" "$DATASET_DIR/shapes/$class"
  done
  rm -rf "$DATASET_DIR/shapes.tmp"
fi

# Hand-drawn Shapes (CC BY 4.0): flattened from data/<author>/images/<class> to <author>/<class>.
download "frobert/handdrawn-shapes-hds-dataset" "$DATASET_DIR/handdrawn"
if [ -d "$DATASET_DIR/handdrawn.tmp" ]; then
  rm -rf "$DATASET_DIR/handdrawn"
  mkdir -p "$DATASET_DIR/handdrawn"
  for author in "$DATASET_DIR/handdrawn.tmp/data"/*/; do
    name="$(basename "$author")"
    for class in ellipse rectangle triangle; do
      [ -d "$author/images/$class" ] || continue
      mkdir -p "$DATASET_DIR/handdrawn/$name/$class"
      mv "$author/images/$class"/*.png "$DATASET_DIR/handdrawn/$name/$class/"
    done
  done
  rm -rf "$DATASET_DIR/handdrawn.tmp"
fi

echo
echo "ready:"
for class in circle square triangle; do
  printf '  shapes/%-9s %s files\n' "$class" "$(find "$DATASET_DIR/shapes/$class" -name '*.png' | wc -l | tr -d ' ')"
done
printf '  handdrawn      %s authors, %s files\n' \
  "$(find "$DATASET_DIR/handdrawn" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')" \
  "$(find "$DATASET_DIR/handdrawn" -name '*.png' | wc -l | tr -d ' ')"
