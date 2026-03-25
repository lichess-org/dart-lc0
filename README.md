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

`Lc0` is a singleton — access it via `Lc0.instance`.

```dart
import 'package:lc0/lc0.dart';

// Start the engine
await Lc0.instance.start();

// Listen to engine output
Lc0.instance.stdout.listen((line) => print(line));

// Load neural network weights (required before analysis)
Lc0.instance.stdin = 'setoption name WeightsFile value /path/to/weights.pb.gz';

// Analyze a position
Lc0.instance.stdin = 'position startpos moves e2e4 e7e5';
Lc0.instance.stdin = 'go movetime 3000';

// Stop the engine (can be restarted later with start())
await Lc0.instance.quit();
```

Check the [`example/`](example/) directory for a complete Flutter app that bundles and loads Maia weights.

## Weights

The engine requires a neural network weights file at runtime. You can use any Lc0-compatible `.pb.gz` weights file. The example app ships with `maia1500.pb.gz` from the [Maia Chess](https://maiachess.com/) project.

## License

GPL — see [LICENSE](LICENSE).
