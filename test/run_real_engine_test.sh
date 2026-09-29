#!/usr/bin/env bash
#
# Builds lc0 itself and boots it through the plugin's shim, on the host.
#
# Slower than test/run_shim_test.sh -- it compiles the whole engine -- but it is
# the only test that exercises the patch to lc0's own sources. Use the shim test
# while working on the shim, and this one before trusting the patch.
#
# Usage: test/run_real_engine_test.sh

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$here/.."

if [ ! -d "$root/ios/lc0/Sources/lc0/engine/src" ]; then
  echo "The vendored engine is missing. Run tools/update_engine.sh." >&2
  exit 1
fi

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

CXX="${CXX:-clang++}"
flags=(-std=c++20 -w -O0 -DEIGEN_NO_CPUID -DUSE_PTHREADS -DNDEBUG -DIS_64BIT -DNO_PEXT -DUSE_POPCNT
       -I"$root/ios/lc0/Sources/lc0" -I"$root/ios/lc0/Sources/lc0/include/lc0"
       -I"$root/ios/lc0/Sources/lc0/engine"
       -I"$root/ios/lc0/Sources/lc0/engine/src" -I"$root/ios/lc0/Sources/lc0/eigen")

# The engine's sources are whatever the Android build compiles, so the two cannot
# drift apart.
sources=()
while IFS= read -r line; do
  sources+=("$line")
done < <(grep -oE '\.\./ios/[^ )]*\.(cc|cpp)' "$root/android/CMakeLists.txt")

echo "Building ${#sources[@]} sources (this takes a couple of minutes)..."

# Compiled through xargs rather than by backgrounding jobs in this shell: a
# backgrounded command runs in a subshell that inherits this script's EXIT trap,
# and would delete the output directory out from under the other compilers.
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -e' 'src="$1"'
  printf 'obj=%q/$(echo "${src#../}" | tr / _).o\n' "$out"
  printf 'exec %q' "$CXX"
  printf ' %q' "${flags[@]}"
  printf ' -c %q/android/"$src" -o "$obj"\n' "$root"
} > "$out/compile.sh"
chmod +x "$out/compile.sh"

printf '%s\n' "${sources[@]}" |
  xargs -P "$(getconf _NPROCESSORS_ONLN)" -n 1 "$out/compile.sh"

echo "Linking..."
"$CXX" -std=c++20 -shared -o "$out/liblc0.dylib" "$out"/*.o -lz
"$CXX" -std=c++20 -w -o "$out/real_engine_test" "$here/real_engine_test.cpp"

echo "Running..."
# stdout is captured rather than shown: checking that the engine left it to the
# host is half of what this test is for.
"$out/real_engine_test" "$out/liblc0.dylib" > "$out/stdout.txt"
status=$?

expected="host stdout line"
if [ "$(cat "$out/stdout.txt")" != "$expected" ]; then
  echo "FAIL the process's stdout was not left to the host. It contains:" >&2
  cat "$out/stdout.txt" >&2
  exit 1
fi
echo "  ok   the host keeps its own stdout" >&2

exit $status
