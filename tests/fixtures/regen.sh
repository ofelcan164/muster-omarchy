#!/bin/bash
# Rebuilds snapshot.json from a Muster checkout's own model.Snapshot, so the
# fixture keeps the shape musterd really writes. Run it whenever Muster's
# internal/model/model.go changes:
#
#   tests/fixtures/regen.sh ~/src/muster
#
# model is internal to Muster, so it is copied next to gen/main.go in a
# throwaway module rather than imported.
set -euo pipefail

muster="${1:?usage: regen.sh <path to a muster checkout>}"
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/model"
cp "$muster/internal/model/model.go" "$work/model/"
cp "$here/gen/main.go" "$work/"
printf 'module fixturegen\n\ngo 1.21\n' > "$work/go.mod"

(cd "$work" && go run .) > "$here/snapshot.json"
echo "wrote $here/snapshot.json"
