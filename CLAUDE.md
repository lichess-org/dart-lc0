# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Flutter/Dart plugin that wraps the [Lc0 chess engine](https://github.com/LeelaChessZero/lc0) (Leela Chess Zero) for iOS and Android. It's a CPU-only ("no GPU") build. The plugin communicates with Lc0 via the UCI protocol over redirected stdin/stdout pipes.

## Common Commands

```bash
# Run example app on a connected device
cd example && flutter run

# Analyze Dart code
dart analyze lib/

# Format Dart code
dart format lib/

# Re-vendor the engine from upstream (maintainer's tool; its output is committed)
tools/update_engine.sh
```

```bash
# Dart tests (the handle API, against a mocked native library)
flutter test

# Native shim test: private I/O, the re-entry guard, pipe reuse, diagnostics.
# Builds in seconds -- the engine is replaced by a stub that reads and writes the
# same streams lc0 does.
test/run_shim_test.sh

# The real engine, booted through the shim. Compiles lc0 itself, so it is the
# only test that covers the patch to the engine's own sources.
test/run_real_engine_test.sh
```

## Architecture

The project has three layers:

### 1. Dart/Flutter Layer (`lib/`)
- `lib/src/lc0.dart` — Core `Lc0` class. An engine is a **handle**: `Lc0.create()` starts one and completes once it has answered `uciok`, `dispose()` releases it, and the handle is single-use. At most one engine is live at a time (lc0 keeps its state in process globals), which `create()` enforces by throwing a `StateError`. It spawns two Dart isolates: one runs `lc0_main()` (blocks until the engine exits), the other polls `lc0_stdout_read()` in a loop. Exposes `stdin` setter, `stdout` getter (`Stream<String>`), `state` (`ValueListenable<Lc0State>`) and `diagnostics`.
- `lib/src/bindings.dart` — `Lc0Bindings`, an interface over the native symbols, plus its FFI implementation. On Android it opens `liblc0.so`; elsewhere it uses `DynamicLibrary.process()`, which reaches symbols whether the plugin was linked as a framework or merged into the app binary. Tests put a fake behind the interface via the `lc0BindingsKey` zone value.
- `lib/src/lc0_state.dart` — Lifecycle enum: `initial`, `starting`, `ready`, `error`, `disposed`.
- `lib/src/lc0_diagnostics.dart` — `Lc0Phase` / `Lc0Diagnostics`, mirroring the `LC0_PHASE_*` codes the native shim publishes, and the `describe*Code` helpers for its return values. Deliberately the same shape as dart-multistockfish's, so an app hosting both reports their failures the same way.

### 2. C++ Bridge Layer (`ios/lc0/Sources/lc0/`)
- `ffi.cpp` / `ffi.h` — the shim. `lc0_init()` creates the pipes once and drains them on a restart; `lc0_main()` binds the engine's streams to them and runs it, refusing to run twice over the same process globals; `lc0_stdin_write()` never blocks (the write side is non-blocking, and a pipe that stays full is reported rather than waited on); `lc0_stdout_read()` blocks until there is output and returns `NULL` when the engine is gone. `lc0_phase()`, `lc0_phase_step()`, `lc0_phase_elapsed_ms()` and `lc0_last_error()` publish where the engine got to, which is the only way to see a wedge from Dart.
- `include/lc0/ffi.h` — the public header. In `include/` because SwiftPM requires a public headers directory per target.
- `lc0io.cpp` / `lc0io.h` — **private engine I/O**. Two streams that replace `std::cin` and `std::cout` inside the engine, bound straight to the shim's pipe. This replaces a `dup2` onto the process's fd 0 and fd 1, which meant no other engine could be resident beside lc0 and the host app lost its own stdout while it ran. Ported from dart-multistockfish's `sfio.{h,cpp}`; keep the two in step.

### 3. Lc0 Engine Layer (`ios/lc0/Sources/lc0/engine/`, `.../eigen/`)

Lc0 v0.32.1 and Eigen 3.4.0, **vendored** — committed to this repo rather than cloned at build
time. Swift Package Manager has no equivalent of CocoaPods' `prepare_command`: an SPM target's
sources have to be inside the package when Xcode resolves it. Only `Eigen/Core` is used, so only
`eigen/Eigen` is vendored.

`lc0.patch` is the diff from a pristine `v0.32.1`. It does three things:

1. removes the `selfplay`, `leela2onnx`, `onnx2leela` and `describenet` modes (only `uci` and
   `benchmark` are kept);
2. points the engine's UCI channel at `lc0io::in()` / `lc0io::out()` instead of `std::cin` /
   `std::cout` — three sites, in `engine_loop.cc`, `chess/uciloop.cc` and `utils/logging.cc` — plus
   the two `lc0_set_phase()` calls that let the shim say whether a start is still booting or
   already in the loop;
3. renames `src/main.cc`'s `main()` to `lc0_engine_main()`, and the file with it. Calling `main()`
   is not allowed in C++; a global `main()` would collide with the host application's own when the
   plugin is statically merged into it, which is what SwiftPM does; and SwiftPM decides a target is
   an executable rather than a library by looking for a file called `main.cc`.

To bump the engine, edit `lc0.patch` (or apply it to a fresh clone, change what you need, and
regenerate it with `git add -A && git diff --cached -M`), then re-vendor:

```bash
tools/update_engine.sh            # defaults to v0.32.1
tools/update_engine.sh v0.33.0    # or a different tag
```

Keep `ios/lc0/Package.swift` and `android/CMakeLists.txt` in step with any files upstream adds or
removes: both list the ~58 sources this build compiles, out of the 112 the engine ships.

## Native Build Details

### iOS — Swift Package (`ios/lc0/Package.swift`) and podspec (`ios/lc0.podspec`)
Both are kept: Flutter uses the package when Swift Package Manager is enabled for the host app and
the podspec otherwise, and the two must list the same sources and flags.
- C++20, flags: `-w -DUSE_PTHREADS -DEIGEN_NO_CPUID -DNDEBUG -O3 -DIS_64BIT -DNO_PEXT`
- Links `libz`
- Under SwiftPM the plugin's object code is merged into the host application's own binary, which is
  why the engine must not define a global `main()` and must not touch the process's descriptors.

### Android (`android/CMakeLists.txt` + `android/build.gradle`)
- ABIs: `arm64-v8a`, `armeabi-v7a`, `x86_64`
- Produces `liblc0.so` (~2.1 MB per ABI); links `libz.so`

This is an **FFI plugin** (`ffiPlugin: true`): everything Dart talks to is a C symbol, so there is
no plugin class to register on either platform.

## Key Usage Pattern

An engine is a handle rather than a singleton: `Lc0.create()` starts one and completes once it is ready, `dispose()` releases it, and a handle is never restarted.

```dart
// Start the engine. Completes when it has answered `uciok`.
final engine = await Lc0.create();

// Listen to engine output
engine.stdout.listen((line) => print(line));

// Load neural network weights (required before analysis)
engine.stdin = 'setoption name WeightsFile value /path/to/weights.pb.gz';

// Analyze a position
engine.stdin = 'position startpos moves e2e4';
engine.stdin = 'go movetime 3000';

// Release it
await engine.dispose();
```

The example app (`example/`) bundles `maia1500.pb.gz` weights in assets and copies them to the app's documents directory on first launch before loading.
