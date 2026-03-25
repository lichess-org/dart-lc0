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

# Fetch Lc0 (v0.32.1) and Eigen (3.4.0) source files (required before native builds)
bash fetchSources.sh
```

```bash
# Run tests
flutter test
```

## Architecture

The project has three layers:

### 1. Dart/Flutter Layer (`lib/`)
- `lib/src/lc0.dart` — Core `Lc0` class. Singleton (`Lc0.instance`). `start()` spawns two Dart isolates: one runs `nativeMain()` (blocks until engine exits), the other polls `nativeStdoutRead()` in a loop. `quit()` sends the UCI `quit` command and waits for the engine to exit. Exposes `stdin` setter (sends UCI commands), `stdout` getter (`Stream<String>`), and `state` (`ValueListenable<Lc0State>`).
- `lib/src/ffi.dart` — FFI bindings. On Android, opens `liblc0.so`; on iOS, uses `DynamicLibrary.process()`.
- `lib/src/lc0_state.dart` — Lifecycle enum: `initial`, `starting`, `ready`, `error`.

### 2. C++ Bridge Layer (`ios/src/ffi.cpp`)
Implements the three functions exported to Dart FFI:
- `lc0_main()` — Sets up stdin/stdout pipes via `dup2`, then calls `main()`. Sends `"quitok"` sentinel when done.
- `lc0_stdin_write(char*)` — Writes a UCI command to the engine's stdin pipe.
- `lc0_stdout_read()` — Reads a line from the engine's stdout pipe; returns `NULL` on `"quitok"` or error.

### 3. Lc0 Engine Layer (`ios/lc0/`, `android/lc0/`)
Lc0 v0.32.1 source, patched via `lc0.patch` to remove `selfplay`, `leela2onnx`, `onnx2leela`, and `describenet` modes—only `uci` and `benchmark` are kept. Eigen 3.4.0 is used for linear algebra.

## Native Build Details

### iOS (`ios/lc0.podspec`)
- Pre-build script: `bash ../fetchSources.sh`
- C++20, flags: `-DUSE_PTHREADS -DEIGEN_NO_CPUID -DNDEBUG -O3 -DIS_64BIT -DNO_PEXT`
- Links `libz`

### Android (`android/CMakeLists.txt` + `android/build.gradle`)
- Gradle `runBeforeCMake` task runs `fetchSources.sh` before CMake
- ABIs: `arm64-v8a`, `armeabi-v7a`, `x86_64`
- Produces `liblc0.so`; links `libz.so`

## Key Usage Pattern

`Lc0` is a singleton — always access it via `Lc0.instance`. The engine is not started automatically; call `start()` explicitly and `quit()` to stop it (it can be restarted after quitting).

```dart
// Start engine (returns Future that completes when ready)
await Lc0.instance.start();

// Listen to engine output
Lc0.instance.stdout.listen((line) => print(line));

// Load weights (required before analysis)
Lc0.instance.stdin = 'setoption name WeightsFile value /path/to/weights.pb.gz';

// Send UCI commands
Lc0.instance.stdin = 'position startpos moves e2e4';
Lc0.instance.stdin = 'go movetime 3000';

// Stop engine (returns Future; engine can be restarted with start())
await Lc0.instance.quit();
```

The example app (`example/`) bundles `maia1500.pb.gz` weights in assets and copies them to the app's documents directory on first launch before loading.
