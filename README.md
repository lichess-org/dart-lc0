# dart-lc0

A Flutter plugin that embeds the [Lc0](https://github.com/LeelaChessZero/lc0) (Leela Chess Zero) chess engine for iOS and Android. CPU-only — no GPU required.

## Features

- Runs Lc0 v0.29.0 in-process via Dart FFI
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

```dart
import 'package:lc0/lc0.dart';

// Initialize the engine
final lc0 = await Lc0.lc0Async();

// Listen to engine output
lc0.stdout.listen((line) => print(line));

// Load neural network weights (required before analysis)
lc0.stdin = 'setoption name WeightsFile value /path/to/weights.pb.gz';
lc0.stdin = 'isready'; // waits for "readyok"

// Analyze a position
lc0.stdin = 'position startpos moves e2e4 e7e5';
lc0.stdin = 'go movetime 3000';

// Stop and clean up
lc0.stdin = 'quit';
lc0.dispose();
```

Check the [`example/`](example/) directory for a complete Flutter app that bundles and loads Maia weights.

## Weights

The engine requires a neural network weights file at runtime. You can use any Lc0-compatible `.pb.gz` weights file. The example app ships with `maia1500.pb.gz` from the [Maia Chess](https://maiachess.com/) project.

## License

GPL — see [LICENSE](LICENSE).
