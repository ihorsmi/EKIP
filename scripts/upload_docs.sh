#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:8000}"
DOC_DIR="${DOC_DIR:-./data/sample_docs}"

echo "Uploading docs from: ${DOC_DIR} -> ${API_BASE}/upload"
for f in "${DOC_DIR}"/*; do
  echo " - $(basename "$f")"
  curl -sS -F "file=@${f}" "${API_BASE}/upload"
  echo
done
echo "Done."
