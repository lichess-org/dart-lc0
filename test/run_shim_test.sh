#!/usr/bin/env bash
#
# Builds and runs the native shim integration test on the host.
#
# The engine itself is not built: test/shim_test.cpp stands in for it with a stub
# that reads and writes the same streams lc0 does after the patch. That keeps
# this to a few seconds rather than the several minutes an lc0 build takes, and
# keeps the test about the channel rather than about the chess. For the engine
# itself, run the example app.
#
# Usage: test/run_shim_test.sh

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$here/../ios/src"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

echo "Building..."
"${CXX:-clang++}" \
  -std=c++20 -O1 \
  -o "$out/shim_test" \
  -I"$src" \
  "$src/ffi.cpp" \
  "$src/lc0io.cpp" \
  "$here/shim_test.cpp"

echo "Running..."
# The test reports on stderr and writes exactly one line to stdout, from the host
# rather than from the engine. Capturing stdout separately is what checks the
# thing this change is for: an engine that still dup2'd onto fd 1 would land its
# own output in here.
"$out/shim_test" > "$out/stdout.txt"
status=$?

expected="this line belongs to the host, not to the engine"
if [ "$(cat "$out/stdout.txt")" != "$expected" ]; then
  echo "FAIL the process's stdout was not left to the host. It contains:" >&2
  cat "$out/stdout.txt" >&2
  exit 1
fi
echo "  ok   the host keeps its own stdout" >&2

exit $status
