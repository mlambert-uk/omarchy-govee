#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_dir"

omarchy plugin validate .
jq empty manifest.json
git diff --check

qml_root=$(mktemp -d)
trap 'rm -rf -- "$qml_root"' EXIT
ln -s /usr/share/omarchy/shell "$qml_root/qs"

/usr/lib/qt6/bin/qmllint \
  -I "$qml_root" \
  --unqualified disable \
  --missing-property disable \
  --unused-imports disable \
  --signal-handler-parameters disable \
  --property-override error \
  --inheritance-cycle error \
  --import error \
  --unresolved-type error \
  --incompatible-type error \
  ./*.qml

node tests/govee-api.test.js

printf '%s\n' "All plugin verification checks passed"
