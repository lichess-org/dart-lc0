import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:lc0/lc0.dart';

/// Mock controller for simulating engine behavior in tests.
class MockEngineController {
  final List<String> stdinCalls = [];

  /// Set to true to make the next [spawnIsolates] call fail.
  bool failNextSpawn = false;

  SendPort? _mainPort;
  SendPort? _stdoutPort;

  /// Simulates the engine outputting a line to stdout.
  void emitStdout(String line) {
    _stdoutPort?.send(line);
  }

  /// Simulates the engine exiting with the given exit code.
  void exit(int code) {
    _mainPort?.send(code);
  }

  /// The spawn isolates override for zone injection.
  ///
  /// Always captures [mainPort] so that [exit] can reset engine state
  /// even when spawn fails.
  Future<bool> spawnIsolates(SendPort mainPort, SendPort stdoutPort) async {
    _mainPort = mainPort;
    _stdoutPort = stdoutPort;
    if (failNextSpawn) {
      failNextSpawn = false;
      return false;
    }
    return true;
  }

  /// The stdin write override for zone injection.
  void stdinWrite(String data) {
    stdinCalls.add(data);
  }
}

/// Runs [body] with mocked engine internals.
///
/// Injects [controller] for isolate spawning and stdin writes.
/// Always resets the engine to [Lc0State.initial] on exit.
Future<T> runWithMockLc0<T>(
  MockEngineController controller,
  FutureOr<T> Function() body,
) {
  return runZoned(
    () async {
      try {
        return await body();
      } finally {
        controller.exit(0);
        await Future.delayed(Duration.zero);
      }
    },
    zoneValues: {
      lc0SpawnIsolatesKey: controller.spawnIsolates,
      lc0StdinWriteKey: controller.stdinWrite,
    },
  );
}

void main() {
  group('Lc0.instance', () {
    test('is a singleton', () {
      expect(Lc0.instance, same(Lc0.instance));
    });

    test('starts in initial state', () async {
      final controller = MockEngineController();
      await runWithMockLc0(controller, () {
        expect(Lc0.instance.state.value, Lc0State.initial);
      });
    });
  });

  group('Lc0.start', () {
    test('transitions through starting to ready on success', () async {
      final controller = MockEngineController();
      await runWithMockLc0(controller, () async {
        final lc0 = Lc0.instance;
        final startFuture = lc0.start();

        expect(lc0.state.value, Lc0State.starting);

        await startFuture;
        expect(lc0.state.value, Lc0State.ready);
      });
    });

    test('throws StateError when already running', () async {
      final controller = MockEngineController();
      await runWithMockLc0(controller, () async {
        final lc0 = Lc0.instance;
        await lc0.start();

        expect(() => lc0.start(), throwsStateError);
      });
    });

    test('returns same Future when start is already in progress', () async {
      final controller = MockEngineController();
      await runWithMockLc0(controller, () async {
        final lc0 = Lc0.instance;

        final startFuture1 = lc0.start();
        expect(lc0.state.value, Lc0State.starting);

        final startFuture2 = lc0.start();
        expect(startFuture2, same(startFuture1));

        await Future.wait([startFuture1, startFuture2]);
        expect(lc0.state.value, Lc0State.ready);
      });
    });

    test('throws and sets error state when spawn fails', () async {
      final controller = MockEngineController();
      controller.failNextSpawn = true;

      await runWithMockLc0(controller, () async {
        await expectLater(Lc0.instance.start(), throwsException);
        expect(Lc0.instance.state.value, Lc0State.error);
      });
    });

    test('can restart after error', () async {
      final controller = MockEngineController();
      controller.failNextSpawn = true;

      await runWithMockLc0(controller, () async {
        final lc0 = Lc0.instance;

        await expectLater(lc0.start(), throwsException);
        expect(lc0.state.value, Lc0State.error);

        await lc0.start();
        expect(lc0.state.value, Lc0State.ready);
      });
    });

    test('can restart after quit', () async {
      final controller = MockEngineController();
      await runWithMockLc0(controller, () async {
        final lc0 = Lc0.instance;

        await lc0.start();
        expect(lc0.state.value, Lc0State.ready);

        final quitFuture = lc0.quit();
        controller.exit(0);
        await quitFuture;
        expect(lc0.state.value, Lc0State.initial);

        await lc0.start();
        expect(lc0.state.value, Lc0State.ready);
      });
    });
  });

  group('Lc0.quit', () {
    test('completes immediately when already in initial state', () async {
      final controller = MockEngineController();
      await runWithMockLc0(controller, () async {
        final lc0 = Lc0.instance;
        expect(lc0.state.value, Lc0State.initial);

        await lc0.quit();
        expect(lc0.state.value, Lc0State.initial);
      });
    });

    test('sends quit command and transitions to initial state', () async {
      final controller = MockEngineController();
      await runWithMockLc0(controller, () async {
        final lc0 = Lc0.instance;
        await lc0.start();

        final quitFuture = lc0.quit();
        controller.exit(0);
        await quitFuture;

        expect(controller.stdinCalls, contains('quit\n'));
        expect(lc0.state.value, Lc0State.initial);
      });
    });

    test('waits for ready state before sending quit when starting', () async {
      final controller = MockEngineController();
      await runWithMockLc0(controller, () async {
        final lc0 = Lc0.instance;
        lc0.start(); // don't await — engine is starting

        expect(lc0.state.value, Lc0State.starting);

        final quitFuture = lc0.quit();

        // quit not yet sent while still starting
        expect(controller.stdinCalls, isNot(contains('quit\n')));

        // let start() complete: state → ready → onStateChange sends quit
        await Future.delayed(Duration.zero);
        expect(controller.stdinCalls, contains('quit\n'));

        controller.exit(0);
        await quitFuture;
        expect(lc0.state.value, Lc0State.initial);
      });
    });

    test('returns same Future when quit is already in progress', () async {
      final controller = MockEngineController();
      await runWithMockLc0(controller, () async {
        final lc0 = Lc0.instance;
        await lc0.start();

        final quitFuture1 = lc0.quit();
        final quitFuture2 = lc0.quit();
        final quitFuture3 = lc0.quit();

        expect(quitFuture2, same(quitFuture1));
        expect(quitFuture3, same(quitFuture1));

        expect(
          controller.stdinCalls.where((c) => c == 'quit\n').length,
          equals(1),
        );

        controller.exit(0);
        await Future.wait([quitFuture1, quitFuture2, quitFuture3]);
        expect(lc0.state.value, Lc0State.initial);
      });
    });
  });

  group('Lc0.stdin', () {
    test('throws StateError when engine is not ready', () async {
      final controller = MockEngineController();
      await runWithMockLc0(controller, () {
        expect(() => Lc0.instance.stdin = 'isready', throwsStateError);
      });
    });

    test('writes command with newline to engine when ready', () async {
      final controller = MockEngineController();
      await runWithMockLc0(controller, () async {
        final lc0 = Lc0.instance;
        await lc0.start();

        lc0.stdin = 'isready';
        lc0.stdin = 'go movetime 1000';

        expect(controller.stdinCalls, contains('isready\n'));
        expect(controller.stdinCalls, contains('go movetime 1000\n'));
      });
    });
  });

  group('Lc0.stdout', () {
    test('emits lines from engine', () async {
      final controller = MockEngineController();
      await runWithMockLc0(controller, () async {
        final lc0 = Lc0.instance;
        final lines = <String>[];
        lc0.stdout.listen(lines.add);

        await lc0.start();

        controller.emitStdout('id name Lc0');
        controller.emitStdout('uciok');
        await Future.delayed(Duration.zero);

        expect(lines, containsAll(['id name Lc0', 'uciok']));
      });
    });

    test('stream persists across restarts', () async {
      final controller = MockEngineController();
      await runWithMockLc0(controller, () async {
        final lc0 = Lc0.instance;
        final lines = <String>[];
        lc0.stdout.listen(lines.add);

        await lc0.start();
        controller.emitStdout('session 1');

        final quitFuture = lc0.quit();
        controller.exit(0);
        await quitFuture;

        await lc0.start();
        controller.emitStdout('session 2');
        await Future.delayed(Duration.zero);

        expect(lines, containsAll(['session 1', 'session 2']));
      });
    });
  });

  group('Lc0.state', () {
    test('notifies listeners on state changes', () async {
      final controller = MockEngineController();
      await runWithMockLc0(controller, () async {
        final lc0 = Lc0.instance;
        final states = <Lc0State>[];
        lc0.state.addListener(() => states.add(lc0.state.value));

        await lc0.start();

        final quitFuture = lc0.quit();
        controller.exit(0);
        await quitFuture;

        expect(states, [
          Lc0State.starting,
          Lc0State.ready,
          Lc0State.initial,
        ]);
      });
    });

    test('transitions to error state on engine crash', () async {
      final controller = MockEngineController();
      await runWithMockLc0(controller, () async {
        final lc0 = Lc0.instance;
        await lc0.start();

        controller.exit(1); // non-zero = crash
        await Future.delayed(Duration.zero);

        expect(lc0.state.value, Lc0State.error);
      });
    });

    test('can restart after engine crash', () async {
      final controller = MockEngineController();
      await runWithMockLc0(controller, () async {
        final lc0 = Lc0.instance;
        await lc0.start();

        controller.exit(1);
        await Future.delayed(Duration.zero);
        expect(lc0.state.value, Lc0State.error);

        await lc0.start();
        expect(lc0.state.value, Lc0State.ready);
      });
    });
  });
}
