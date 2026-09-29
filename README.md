# dart-lc0

A Flutter plugin that embeds the [Lc0](https://github.com/LeelaChessZero/lc0) (Leela Chess Zero) chess engine for iOS and Android. CPU-only — no GPU required.

## Features

- Runs Lc0 v0.32.1 in-process via Dart FFI
- Communicates with the engine using the [UCI protocol](https://www.chessprogramming.org/UCI)
- Non-blocking: engine runs in a Dart isolate
- Supports any `.pb.gz` neural network weights file (e.g. [Maia](https://maiachess.com/))

## Platform Support

| Android | iOS |
|---------|-----|
| ✓       | ✓   |

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  lc0:
    git:
      url: https://github.com/lichess-org/dart-lc0.git
```

## Usage

An engine is a handle: `Lc0.create()` starts one and completes once it has
answered `uciok`, and `dispose()` releases it.

```dart
import 'package:lc0/lc0.dart';

// Start the engine. Completes when it is ready for commands.
final engine = await Lc0.create();

// Listen to engine output. Pass `onStdout` to `create` instead if you need the
// lines it writes while starting.
engine.stdout.listen((line) => print(line));

// Load neural network weights (required before analysis)
engine.stdin = 'setoption name WeightsFile value /path/to/weights.pb.gz';

// Analyze a position
engine.stdin = 'position startpos moves e2e4 e7e5';
engine.stdin = 'go movetime 3000';

// Release it. The handle is single-use: call create() again for a fresh engine.
await engine.dispose();
```

**One engine at a time.** lc0 keeps its command line, its option registry and its
backend factories in process globals, so `create()` throws a `StateError` while
another engine is live. Engines from *other* plugins are unaffected: this plugin
no longer takes the process's stdin and stdout over, so an lc0 engine and a
Stockfish engine can be resident side by side.

### When something goes wrong

The engine runs on a thread Dart does not own, so `engine.diagnostics` reports
what the native side is doing — which phase it is in, which step of it, and for
how long. Attach it to any report of an engine that would not start or would not
quit; `Lc0Diagnostics.looksStuck` says when a transition has taken far longer
than it should.

```dart
final engine = await Lc0.create();
print(engine.diagnostics);  // phase=uciLoop step=uci_loop for 12ms
```

Check the [`example/`](example/) directory for a complete Flutter app that bundles and loads Maia weights.

## Building

The engine and Eigen are vendored under `ios/lc0/Sources/lc0/`, so a checkout builds without
fetching anything. The plugin ships both a Swift Package (`ios/lc0/Package.swift`) and a podspec;
Flutter picks the package when Swift Package Manager is enabled for the host app.

`tools/update_engine.sh` re-vendors the engine from upstream and re-applies `lc0.patch`. It is a
maintainer's tool — its output is committed.

## Weights

The engine requires a neural network weights file at runtime. You can use any Lc0-compatible `.pb.gz` weights file. The example app ships with `maia1500.pb.gz` from the [Maia Chess](https://maiachess.com/) project.

## License

GPL — see [LICENSE](LICENSE).
