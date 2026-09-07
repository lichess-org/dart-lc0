import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:lc0/lc0.dart';
import 'package:lc0/src/bindings.dart';
// The zone keys are test-only seams, so they live beside the implementation
// rather than in the public entrypoint.
// ignore: unnecessary_import
import 'package:lc0/src/lc0.dart' show lc0BindingsKey, lc0SpawnIsolatesKey;

/// A stand-in for the native library.
class MockLc0Bindings implements Lc0Bindings {
  final List<String> stdinCalls = [];

  int initReturnValue = 0;
  int mainReturnValue = 0;
  void Function(String input)? onStdin;

  /// The value [stdinWrite] reports. Negative values simulate a native write
  /// failure, e.g. an input pipe that stayed full.
  int stdinWriteReturnValue = 0;

  /// The phase, step and error the mocked native library reports.
  int phaseReturnValue = Lc0Phase.uciLoop.code;
  String phaseStepReturnValue = 'uci_loop';
  int phaseElapsedMsReturnValue = 0;
  String? lastErrorReturnValue;

  @override
  int init() => initReturnValue;

  @override
  int main() => mainReturnValue;

  @override
  int stdinWrite(String input) {
    stdinCalls.add(input);
    onStdin?.call(input);
    return stdinWriteReturnValue;
  }

  @override
  String? stdoutRead() => null;

  @override
  int phase() => phaseReturnValue;

  @override
  String phaseStep() => phaseStepReturnValue;

  @override
  int phaseElapsedMs() => phaseElapsedMsReturnValue;

  @override
  String? lastError() => lastErrorReturnValue;
}

/// A single simulated engine, holding the ports it was spawned with.
class MockEngine {
  MockEngine(this._mainPort, this._stdoutPort);

  final SendPort _mainPort;
  final SendPort _stdoutPort;

  bool _exited = false;

  /// Whether this engine is still running.
  bool get isAlive => !_exited;

  /// Simulates the engine writing a line.
  void emitStdout(String line) => _stdoutPort.send(line);

  /// Answers the handshake, as a healthy engine does.
  void answerHandshake() {
    emitStdout('id name Lc0 v0.32.1');
    emitStdout('uciok');
  }

  /// Simulates the engine exiting. Exiting twice is a no-op, as it is for a
  /// real process.
  ///
  /// The reader stops too: a real engine writes the quit marker on its way out,
  /// and the isolate reading its pipe returns as soon as it sees it. The handle
  /// waits for both, so a mock that reported only the exit would leave every
  /// teardown sitting on the reader timeout.
  void exit(int code) {
    if (_exited) return;
    _exited = true;
    _mainPort.send(code);
    _stdoutPort.send(null);
  }

  /// Simulates an engine that exits without its reader ever letting go — one
  /// wedged somewhere that never writes the quit marker.
  void exitWithoutStoppingReader(int code) {
    if (_exited) return;
    _exited = true;
    _mainPort.send(code);
  }

  /// Simulates the reader isolate seeing the quit marker and returning.
  void stopReader() => _stdoutPort.send(null);

  /// Simulates the reader isolate dying on an error instead of finishing.
  void failReader(String error) {
    _stdoutPort.send({'error': error, 'stackTrace': '<no stack>'});
    _stdoutPort.send(null);
  }
}

/// Drives the engine from the test.
class MockEngineController {
  final bindings = MockLc0Bindings();

  /// Every engine spawned so far, in spawn order.
  final List<MockEngine> engines = [];

  /// Set to true to make the next spawn fail.
  bool failNextSpawn = false;

  /// Whether an engine should answer `uci` with `uciok` by itself. Turned off
  /// by tests that want to watch a start hang.
  bool autoHandshake = true;

  /// Whether an engine's exit also stops its reader, as a real one's does by
  /// writing the quit marker. Turned off by tests that want to drive the two
  /// apart.
  bool readerStopsOnExit = true;

  MockEngine get engine => engines.last;

  MockEngineController() {
    bindings.onStdin = (input) {
      if (!autoHandshake || engines.isEmpty) return;
      if (input.trim() == 'uci') engines.last.answerHandshake();
      if (input.trim() == 'quit') {
        if (readerStopsOnExit) {
          engines.last.exit(0);
        } else {
          engines.last.exitWithoutStoppingReader(0);
        }
      }
    };
  }

  Future<bool> spawnIsolates(SendPort mainPort, SendPort stdoutPort) async {
    if (failNextSpawn) {
      failNextSpawn = false;
      return false;
    }
    if (bindings.init() != 0) return false;
    engines.add(MockEngine(mainPort, stdoutPort));
    return true;
  }
}

/// Runs [body] with the native library and the isolates mocked out.
///
/// The cleanup happens inside the zone too: the slot is process-wide, so an
/// engine left behind leaks into the next test — and disposing it outside the
/// zone would reach for the real native library.
Future<T> runWithMockLc0<T>(
  MockEngineController controller,
  Future<T> Function() body,
) {
  return runZoned(
    () async {
      try {
        return await body();
      } finally {
        // Exiting the engines first keeps the cleanup from waiting out a quit
        // timeout.
        for (final engine in controller.engines) {
          engine.exit(0);
        }
        await Future<void>.delayed(Duration.zero);
        await Lc0.debugLiveEngine?.dispose();
      }
    },
    zoneValues: {
      lc0BindingsKey: controller.bindings,
      lc0SpawnIsolatesKey: controller.spawnIsolates,
    },
  );
}

void main() {
  group('Lc0.create', () {
    test('returns an engine that has answered its handshake', () async {
      final controller = MockEngineController();

      await runWithMockLc0(controller, () async {
        final engine = await Lc0.create();

        expect(engine.state.value, Lc0State.ready);
        expect(controller.bindings.stdinCalls, contains('uci\n'));
      });
    });

    test('refuses a second engine while the first is live', () async {
      final controller = MockEngineController();

      await runWithMockLc0(controller, () async {
        await Lc0.create();

        await expectLater(Lc0.create(), throwsA(isA<StateError>()));
      });
    });

    test('refuses a second engine while the first is still starting', () async {
      final controller = MockEngineController()..autoHandshake = false;

      await runWithMockLc0(controller, () async {
        final starting = Lc0.create();
        await expectLater(Lc0.create(), throwsA(isA<StateError>()));

        // Let the first one finish, so the test does not leave it hanging.
        await pumpEventQueue();
        controller.engine.answerHandshake();
        await starting;
      });
    });

    test('throws and frees the slot when the native init fails', () async {
      final controller = MockEngineController();
      controller.bindings.initReturnValue = -1;

      await runWithMockLc0(controller, () async {
        await expectLater(Lc0.create(), throwsA(isA<Exception>()));
        expect(Lc0.debugLiveEngine, isNull);
      });
    });

    test(
        'reports an engine that exits while starting, without waiting out '
        'the timeout', () async {
      final controller = MockEngineController()..autoHandshake = false;

      await runWithMockLc0(controller, () async {
        final starting = Lc0.create();
        await pumpEventQueue();

        controller.engine.exit(1);

        await expectLater(starting, throwsA(isA<Exception>()));
        expect(Lc0.debugLiveEngine, isNull);
      });
    });

    test('the engine is asked for the handshake it is waited on', () async {
      // lc0 says nothing until it is spoken to -- its banner goes to the log,
      // not to the UCI channel -- so `uci` is both the first command and the
      // thing that proves the engine is up.
      final controller = MockEngineController();

      await runWithMockLc0(controller, () async {
        await Lc0.create();

        expect(controller.bindings.stdinCalls.first, 'uci\n');
      });
    });

    test('start-up output reaches onStdout, which stdout would have missed',
        () async {
      final controller = MockEngineController();
      final lines = <String>[];

      await runWithMockLc0(controller, () async {
        await Lc0.create(onStdout: lines.add);

        expect(lines, contains('id name Lc0 v0.32.1'));
        expect(lines, contains('uciok'));
      });
    });
  });

  group('Lc0.dispose', () {
    test('quits the engine, waits for it and frees the slot', () async {
      final controller = MockEngineController();

      await runWithMockLc0(controller, () async {
        final engine = await Lc0.create();

        await engine.dispose();

        expect(controller.bindings.stdinCalls, contains('quit\n'));
        expect(controller.engine.isAlive, isFalse);
        expect(engine.state.value, Lc0State.disposed);
        expect(Lc0.debugLiveEngine, isNull);
      });
    });

    test('closes the stdout stream and refuses further commands', () async {
      final controller = MockEngineController();

      await runWithMockLc0(controller, () async {
        final engine = await Lc0.create();
        final done = expectLater(engine.stdout, emitsDone);

        await engine.dispose();

        await done;
        expect(() => engine.stdin = 'go', throwsA(isA<StateError>()));
      });
    });

    test('concurrent calls share the first one', () async {
      final controller = MockEngineController();

      await runWithMockLc0(controller, () async {
        final engine = await Lc0.create();

        await Future.wait([engine.dispose(), engine.dispose()]);

        expect(
          controller.bindings.stdinCalls.where((c) => c == 'quit\n').length,
          1,
        );
      });
    });

    test('fails the engine when its reader dies', () async {
      final controller = MockEngineController();

      await runWithMockLc0(controller, () async {
        final engine = await Lc0.create();
        expect(engine.state.value, Lc0State.ready);

        // Nothing is draining the engine's output any more. It goes on running until its
        // pipe fills and then answers nothing, so the session is over whatever it does.
        controller.engine.failReader('Bad state: the reader blew up');
        await pumpEventQueue();

        expect(engine.state.value, Lc0State.error);
        expect(() => engine.stdin = 'isready', throwsStateError);
      });
    });

    test('waits for the reader to let go of the pipe before it returns',
        () async {
      final controller = MockEngineController();

      await runWithMockLc0(controller, () async {
        final engine = await Lc0.create();

        // The engine exits on `quit` as usual, but its reader stays blocked on
        // the pipe: it only learns of the exit from the quit marker, which it
        // has not read yet.
        controller.readerStopsOnExit = false;

        var disposed = false;
        unawaited(engine.dispose().then((_) => disposed = true));
        await pumpEventQueue();

        expect(
          disposed,
          isFalse,
          reason:
              'returning here would let the next create() drain the pipe out '
              'from under a reader that has not stopped',
        );

        // The reader wakes, sees the marker and returns.
        controller.engine.stopReader();
        await pumpEventQueue();
        expect(disposed, isTrue);
      });
    });

    test('does not wait forever for a reader that never stops', () async {
      final controller = MockEngineController();

      await runWithMockLc0(controller, () async {
        final engine = await Lc0.create();

        controller.readerStopsOnExit = false;

        final elapsed = Stopwatch()..start();
        final disposal = engine.dispose();

        await disposal.timeout(
          kReaderStopTimeout * 3,
          onTimeout: () =>
              fail('dispose() hung waiting for a reader that never stops'),
        );
        elapsed.stop();

        expect(
          elapsed.elapsed,
          greaterThanOrEqualTo(
            kReaderStopTimeout - const Duration(milliseconds: 100),
          ),
          reason: 'it should have given the reader its full window first',
        );
        expect(engine.state.value, Lc0State.disposed);
        expect(Lc0.debugLiveEngine, isNull);
      });
    });

    test('completes on an engine that has already died', () async {
      final controller = MockEngineController();

      await runWithMockLc0(controller, () async {
        final engine = await Lc0.create();
        controller.engine.exit(0);
        await pumpEventQueue();

        await engine.dispose();
        expect(engine.state.value, Lc0State.disposed);
      });
    });
  });

  group('Lc0.stdin', () {
    test('logs a failed write instead of throwing', () async {
      final controller = MockEngineController();
      controller.bindings.stdinWriteReturnValue = Lc0WriteResult.pipeFull;

      await runWithMockLc0(controller, () async {
        final engine = await Lc0.create();

        expect(() => engine.stdin = 'go', returnsNormally);
        // A full pipe delivered nothing, but the command stream is still
        // coherent, so the session survives.
        expect(engine.state.value, Lc0State.ready);
      });
    });

    test('a partial write fails the engine so later commands throw', () async {
      final controller = MockEngineController();

      await runWithMockLc0(controller, () async {
        final engine = await Lc0.create();

        controller.bindings.stdinWriteReturnValue = Lc0WriteResult.partial;
        engine.stdin = 'go';

        expect(engine.state.value, Lc0State.error);
        expect(() => engine.stdin = 'stop', throwsA(isA<StateError>()));
      });
    });
  });

  group('Lc0.state', () {
    test('a crash is an error the handle does not recover from', () async {
      final controller = MockEngineController();

      await runWithMockLc0(controller, () async {
        final engine = await Lc0.create();

        controller.engine.exit(139);
        await pumpEventQueue();

        expect(engine.state.value, Lc0State.error);
        expect(Lc0.debugLiveEngine, isNull, reason: 'the slot is free again');

        // Disposing a handle that already failed keeps the failure: that is the
        // fact worth reporting, not the disposal.
        await engine.dispose();
        expect(engine.state.value, Lc0State.error);
      });
    });
  });

  group('Lc0.diagnostics', () {
    test('reports what the native library says', () async {
      final controller = MockEngineController();
      controller.bindings
        ..phaseReturnValue = Lc0Phase.engineBooting.code
        ..phaseStepReturnValue = 'engine_construct'
        ..phaseElapsedMsReturnValue = 1200
        ..lastErrorReturnValue = 'could not read the network';

      await runWithMockLc0(controller, () async {
        final engine = await Lc0.create();

        final diagnostics = engine.diagnostics;
        expect(diagnostics.phase, Lc0Phase.engineBooting);
        expect(diagnostics.step, 'engine_construct');
        expect(diagnostics.elapsed, const Duration(milliseconds: 1200));
        expect(diagnostics.lastError, 'could not read the network');
        expect(diagnostics.looksStuck, isFalse, reason: 'booting takes time');
      });
    });

    test('a boot is only stuck once it has taken far too long', () async {
      // Loading a network is real work, unlike the other transitions, so it is
      // given much longer before it is called a wedge.
      const booting = Lc0Diagnostics(
        phase: Lc0Phase.engineBooting,
        step: 'engine_construct',
        elapsed: Duration(seconds: 20),
        lastError: null,
      );
      expect(booting.looksStuck, isFalse);

      const wedged = Lc0Diagnostics(
        phase: Lc0Phase.engineBooting,
        step: 'engine_construct',
        elapsed: Duration(seconds: 60),
        lastError: null,
      );
      expect(wedged.looksStuck, isTrue);

      const teardown = Lc0Diagnostics(
        phase: Lc0Phase.shuttingDown,
        step: 'engine_teardown',
        elapsed: Duration(seconds: 10),
        lastError: null,
      );
      expect(teardown.looksStuck, isTrue);
    });
  });
}
