#!/usr/bin/env bash
#
# Refreshes the vendored engine sources under ios/lc0/Sources/lc0/.
#
# The engine used to be cloned at build time by the podspec's prepare_command.
# It is vendored instead because Swift Package Manager has no equivalent hook:
# an SPM target's sources have to be inside the package when Xcode resolves it.
# So this is a maintainer's tool, run when bumping the engine, and its output is
# committed.
#
# Usage: tools/update_engine.sh [lc0-tag]

set -euo pipefail

tag="${1:-v0.32.1}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$here/.."
target="$root/ios/lc0/Sources/lc0"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Cloning lc0 $tag..."
git clone -q -b "$tag" --depth 1 https://github.com/LeelaChessZero/lc0 "$work/lc0"
cd "$work/lc0"
git submodule -q update --init --recursive
mkdir -p src/proto
python3 scripts/compile_proto.py libs/lczero-common/proto/net.proto \
  --proto_path=libs/lczero-common/proto --cpp_out=src/proto
echo "Applying lc0.patch..."
# -M so that the rename of src/main.cc is applied as one, rather than being
# rejected as a modification to a file that does not exist upstream.
git apply "$root/lc0.patch"

echo "Cloning eigen..."
git clone -q -b 3.4.0 --depth 1 https://gitlab.com/libeigen/eigen "$work/eigen"

echo "Vendoring..."
rm -rf "$target/engine" "$target/eigen"
mkdir -p "$target/engine" "$target/eigen"
cp -R "$work/lc0/src" "$target/engine/src"
cp "$work/lc0/COPYING" "$work/lc0/README.md" "$target/engine/"
# Only Eigen/Core is used, and eigen is header-only.
cp -R "$work/eigen/Eigen" "$target/eigen/Eigen"
cp "$work/eigen/COPYING.MPL2" "$work/eigen/COPYING.README" "$target/eigen/"

echo "Done. Review the diff, then keep ios/lc0/Package.swift and"
echo "android/CMakeLists.txt in step with any files upstream added or removed."
