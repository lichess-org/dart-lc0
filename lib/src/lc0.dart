import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'bindings.dart';
import 'lc0_diagnostics.dart';
import 'lc0_state.dart';

final _logger = Logger('Lc0');

/// Zone key for overriding bindings in tests.
@visibleForTesting
const lc0BindingsKey = #_lc0Bindings;

/// Zone key for overriding isolate spawning in tests.
@visibleForTesting
const lc0SpawnIsolatesKey = #_lc0SpawnIsolates;

/// How long the engine is given to answer `uciok`.
///
/// Generous compared to a Stockfish start, because this is where the network is
/// read off disk and the backend is built.
const kStartTimeout = Duration(seconds: 30);

/// How long an engine is given to exit after being asked to quit, before it is
/// abandoned.
const kQuitTimeout = Duration(seconds: 5);

/// How long an exited engine's reader is given to let go of the pipe.
///
/// Short, because the marker it is waiting for is already in the pipe by then:
/// this is a thread wake-up, not work.
const kReaderStopTimeout = Duration(seconds: 1);

/// A live Lc0 engine.
///
/// Obtain one with [Lc0.create], which starts the engine and completes once it
/// has answered `uciok`, and release it with [dispose].
///
/// **One engine at a time.** lc0 keeps its command line, its option registry and
/// its backend factories in process globals, so [create] throws a [StateError]
/// while another engine holds the slot, and [dispose] frees it. Engines from
/// *other* plugins are unaffected: since this plugin stopped hijacking the
/// process's stdin and stdout, an lc0 engine and a Stockfish engine can be
/// resident at the same time, each with its own [stdin], [stdout], [state] and
/// [diagnostics].
///
/// A handle is single-use. Once [dispose] has been called, or the engine has
/// exited on its own, that handle stays dead; call [create] again for a fresh
/// one.
class Lc0 {
  Lc0._();

  /// The engine currently holding the slot, if any.
  static Lc0? _live;

  /// The engine currently live.
  ///
  /// The slot is process-wide, so a test that leaves one claimed leaks it into
  /// the next test.
  @visibleForTesting
  static Lc0? get debugLiveEngine => _live;

  /// Starts an engine and completes when it has answered `uciok`.
  ///
  /// Throws a [StateError] if an engine is already live — call [dispose] on it
  /// first — and a [TimeoutException] if the engine does not become ready
  /// within [kStartTimeout]. A failed create frees the slot again, but an engine
  /// that also refused to quit keeps its native state, and the next create may
  /// be refused by the native library until the process restarts.
  ///
  /// Pass [onStdout] to see the engine's start-up output. This future does not
  /// complete until the engine is ready, so a listener attached to [stdout]
  /// afterwards has already missed the UCI handshake; [onStdout] is attached
  /// before the engine is spawned and receives every line for its whole life.
  static Future<Lc0> create({void Function(String line)? onStdout}) async {
    // Claiming the slot before the first await is what makes two concurrent
    // create() calls resolve to a refusal rather than to two engines racing
    // each other into the same native globals.
    final engine = Lc0._().._claimSlot();
    if (onStdout != null) engine._stdoutController.stream.listen(onStdout);

    try {
      await engine._doStart();
    } catch (_) {
      engine._release(Lc0State.error, closeStdout: true);
      rethrow;
    }

    return engine;
  }

  Lc0Bindings get _bindings => _resolveBindings();

  final _state = _Lc0State();
  final _stdoutController = StreamController<String>.broadcast();

  /// The engine currently owning the state, or null when none is running.
  _RunningEngine? _engine;

  Future<void>? _disposal;

  /// Whether [dispose] has been called, recorded before anything it does can
  /// make the engine exit, so that [_onEngineExit] knows the exit was asked for.
  bool _disposing = false;

  /// The current state of the underlying C++ engine.
  ///
  /// A handle returned by [create] is [Lc0State.ready]. It ends as
  /// [Lc0State.disposed] — after [dispose], or after the engine exits cleanly on
  /// its own, as it does when sent `quit` over [stdin] — or as [Lc0State.error]
  /// if it died badly. None of those is recoverable on this handle: create
  /// another one.
  ValueListenable<Lc0State> get state => _state;

  /// The standard output stream.
  ///
  /// Closes when the engine is disposed.
  Stream<String> get stdout => _stdoutController.stream;

  /// A snapshot of what the native engine is doing.
  ///
  /// Cheap to read at any time, including while the engine is wedged — the
  /// values are atomics published by the native shim, not a round trip through
  /// the engine. Attach it to any report of an engine that would not start or
  /// would not quit.
  Lc0Diagnostics get diagnostics {
    final bindings = _bindings;
    return Lc0Diagnostics(
      phase: Lc0Phase.fromCode(bindings.phase()),
      step: bindings.phaseStep(),
      elapsed: Duration(milliseconds: bindings.phaseElapsedMs()),
      lastError: bindings.lastError(),
    );
  }

  /// The standard input sink.
  ///
  /// A failed write is logged at [Level.SEVERE] along with [diagnostics] rather
  /// than thrown, so that a broken engine does not turn every command site into
  /// a try/catch. The write never blocks: if the engine has stopped reading its
  /// input, this reports the failure instead of hanging the calling isolate.
  ///
  /// A failure that leaves the session unusable — see [Lc0WriteResult.isFatal] —
  /// additionally moves [state] to [Lc0State.error], so subsequent commands
  /// throw rather than pile onto a channel the engine can no longer read
  /// correctly.
  set stdin(String line) {
    final stateValue = _state.value;
    if (stateValue != Lc0State.ready) {
      throw StateError('Lc0 is not ready ($stateValue)');
    }

    _write(line);
  }

  /// Sends a line to the engine, returning the native write result.
  ///
  /// Negative values are failures described by [describeWriteCode]. They are
  /// logged here so that every caller reports them the same way, and returned so
  /// that callers who cannot simply carry on — [dispose] in particular — can act
  /// on them.
  int _write(String line) {
    _logger.finest('[stdin] $line');

    final written = _bindings.stdinWrite('$line\n');
    if (written < 0) {
      _logger.severe(
        'Failed to send "$line" to the engine: ${describeWriteCode(written)}. '
        '$diagnostics',
      );

      if (Lc0WriteResult.isFatal(written)) {
        // The engine can no longer be sent a coherent command stream, so this
        // session is over whatever the engine itself does next. Failing the
        // state here makes the rest of the API refuse work until the caller
        // starts another engine, instead of letting commands accumulate on a
        // broken channel and be answered with nonsense.
        _logger.severe(
          'The engine session is unrecoverable and has been marked failed. '
          'Dispose this engine and create another one.',
        );
        _state._setValue(Lc0State.error);
      }
    }
    return written;
  }

  /// Takes the slot, or throws if another engine still holds it.
  void _claimSlot() {
    if (_live != null) {
      throw StateError(
        'An lc0 engine is already live. Dispose it before creating another '
        'one. (Engines from other plugins are unaffected and can run alongside '
        'it.)',
      );
    }
    _live = this;
  }

  /// Gives the slot back, if this engine still holds it.
  void _releaseSlot() {
    if (identical(_live, this)) _live = null;
  }

  Future<void> _doStart() async {
    late final _RunningEngine engine;
    engine = _RunningEngine(
      onExit: (exitCode) {
        if (identical(_engine, engine)) _engine = null;
        _onEngineExit(exitCode);
        // When dispose() asked for the exit it detaches itself, once it has
        // waited for the reader to let go of the pipe. Every other way an engine
        // can end has nobody waiting, so the ports are closed here instead.
        if (!_disposing) engine.detach();
      },
      onStdout: (line) {
        if (!_stdoutController.isClosed) _stdoutController.add(line);
      },
      onReaderFailed: (error) {
        _logger.severe(
          'The reader for the engine died, so nothing is draining its output any more. '
          'The engine will stop answering as soon as its pipe fills, so this session is '
          'over. $diagnostics\n$error',
        );
        _state._setValue(Lc0State.error);
      },
    );
    _engine = engine;

    final success = await _spawnIsolates(
      engine.mainPort.sendPort,
      engine.stdoutPort.sendPort,
    );

    if (!success) {
      _logger.severe('Failed to spawn isolates');
      _engine = null;
      engine.detach();
      throw Exception('Failed to spawn isolates');
    }

    _state._setValue(Lc0State.starting);

    try {
      // Unlike Stockfish, lc0 writes nothing to its output before it is asked
      // to: its banner goes to the log, not to the UCI channel. So there is no
      // greeting to wait for, and the handshake itself is what says the engine
      // is up. The command sits in the pipe until the engine reaches its loop,
      // which is exactly the wait this is here to make.
      _state._setValue(Lc0State.ready);
      stdin = 'uci';
      await _awaitLine(engine, (line) => line.trim() == 'uciok');
    } on TimeoutException {
      // Read the diagnostics before asking the engine to quit: doing so moves it
      // on to another phase and would erase the evidence of where it stalled.
      final stalledAt = diagnostics;
      _logger.severe(
        'The engine did not become ready in time (${kStartTimeout.inSeconds}s). '
        '$stalledAt',
      );
      await _quitEngine(engine);
      throw TimeoutException(
        'Lc0 did not become ready in time. $stalledAt',
        kStartTimeout,
      );
    }
  }

  /// Waits for [engine] to print a line matching [test].
  ///
  /// Throws a [TimeoutException] after [kStartTimeout], and gives up as soon as
  /// the engine exits instead: an engine the native library refused to run
  /// reports that in milliseconds, and waiting out the timeout would replace a
  /// precise answer with a vague one.
  Future<void> _awaitLine(
    _RunningEngine engine,
    bool Function(String line) test,
  ) {
    final completer = Completer<void>();

    final subscription = _stdoutController.stream.listen((line) {
      if (!completer.isCompleted && test(line)) completer.complete();
    });

    unawaited(
      engine.exited.future.then((exitCode) {
        if (completer.isCompleted) return;
        completer.completeError(
          Exception(
            'The engine exited while starting '
            '(code $exitCode: ${describeMainExitCode(exitCode)}) '
            'and will never become ready. $diagnostics',
          ),
        );
      }),
    );

    return completer.future
        .timeout(kStartTimeout)
        .whenComplete(subscription.cancel);
  }

  /// Quits the engine and frees the slot.
  ///
  /// Completes when the engine has exited. It is safe to call more than once and
  /// safe to call on an engine that has already died; later calls wait for the
  /// first.
  ///
  /// An engine that does exit is also waited on for [kReaderStopTimeout], so that
  /// its reader has let go of the output pipe before the next engine can drain
  /// it.
  ///
  /// An engine that does not exit within [kQuitTimeout] is abandoned: the slot is
  /// freed and everything the engine sends afterwards is dropped, but it keeps
  /// the native state it is stuck in, so a later [create] may be refused until
  /// the process restarts.
  Future<void> dispose() {
    _disposing = true;
    return _disposal ??= _doDispose();
  }

  Future<void> _doDispose() async {
    final engine = _engine;
    if (engine != null) await _quitEngine(engine);

    // A handle that already failed goes on saying so. Disposing it is not what
    // went wrong, and of the two facts the failure is the one worth keeping.
    _release(
      _state.value == Lc0State.error ? Lc0State.error : Lc0State.disposed,
      closeStdout: true,
    );
  }

  /// Asks [engine] to quit and waits for it to exit.
  ///
  /// Waiting matters even where the caller has stopped caring: another engine
  /// may be created as soon as this returns, and one still winding down would
  /// otherwise report its exit while its successor runs.
  Future<void> _quitEngine(_RunningEngine engine) async {
    if (!engine.exited.isCompleted) {
      if (_write('quit') < 0) {
        _logger.severe(
          'The engine could not be asked to quit and will never report an '
          'exit. Giving up on a clean shutdown. $diagnostics',
        );
      } else {
        try {
          await engine.exited.future.timeout(kQuitTimeout);
        } on TimeoutException {
          _logger.severe(
            'The engine did not exit in time (${kQuitTimeout.inSeconds}s). '
            '$diagnostics It is abandoned: nothing it sends from now on is '
            'delivered, but until this process is restarted a new engine may be '
            'refused by the native library, because lc0 keeps its state in '
            'process globals the stuck one still owns.',
          );
        }
      }
    }

    // The engine has gone, but its reader has not necessarily noticed: it learns
    // that from the quit marker in the pipe, and until it has read it the isolate
    // is still blocked on that pipe. The next create() drains the pipe before it
    // starts its engine, and a drain that beats the reader to the marker leaves
    // it blocked forever -- a second reader on the new engine's output, taking
    // lines at random from the isolate that is supposed to deliver them.
    //
    // Only worth waiting for when the engine actually exited: an abandoned one
    // never writes the marker, and its reader is never going to stop.
    if (engine.exited.isCompleted) {
      try {
        await engine.readerStopped.future.timeout(kReaderStopTimeout);
      } on TimeoutException {
        _logger.warning(
          'The engine exited but its reader did not let go of the pipe within '
          '${kReaderStopTimeout.inMilliseconds}ms. A new engine may lose output '
          'to it. $diagnostics',
        );
      }
    }

    if (identical(_engine, engine)) _engine = null;
    engine.detach();
  }

  /// Ends this engine's session: slot returned, ports closed, state published.
  void _release(Lc0State finalState, {required bool closeStdout}) {
    _releaseSlot();
    _engine?.detach();
    _engine = null;
    _state._setValue(finalState);
    if (closeStdout && !_stdoutController.isClosed) _stdoutController.close();
  }

  void _onEngineExit(int exitCode) {
    if (exitCode == 0) {
      _logger.fine('The engine exited cleanly.');
    } else {
      _logger.severe(
        'The engine exited with code $exitCode: '
        '${describeMainExitCode(exitCode)}. $diagnostics',
      );
    }

    // When dispose() asked for the exit, it publishes the final state itself.
    if (_disposing) return;

    // The handle is finished either way, but only a bad exit is a failure: an
    // engine told `quit` over [stdin] exits cleanly and nothing went wrong.
    //
    // The slot is free whatever the code, because the engine is provably gone —
    // that is exactly what the native library's re-entry guard keys off.
    // Holding it until dispose() would only make the caller ask permission to
    // replace an engine that no longer exists.
    _release(
      exitCode == 0 ? Lc0State.disposed : Lc0State.error,
      closeStdout: true,
    );
  }
}

/// The ports of a single engine, and its lifetime.
///
/// Each engine gets its own ports so that closing them is enough to make an
/// abandoned engine invisible to the [Lc0] handle that started it.
class _RunningEngine {
  _RunningEngine({
    required void Function(int exitCode) onExit,
    required void Function(String line) onStdout,
    required void Function(String error) onReaderFailed,
  }) {
    mainPort.listen((message) {
      _logger.fine('The main isolate sent $message');
      final code = message is int ? message : 1;
      // The only thing that completes [exited]; see its doc comment.
      if (!exited.isCompleted) exited.complete(code);
      onExit(code);
    });

    stdoutPort.listen((message) {
      // The reader's own end of stream, not engine output.
      if (message == null) {
        _logger.fine('The stdout isolate has let go of the pipe');
        if (!readerStopped.isCompleted) readerStopped.complete();
        return;
      }

      // The reader reporting that it died rather than finished.
      if (message is Map) {
        onReaderFailed('${message['error']}\n${message['stackTrace']}');
        return;
      }

      // A batch of lines from the reader, or a single line from a test's fake.
      final lines = switch (message) {
        final List<Object?> batch => batch,
        final String line => [line],
        _ => const <Object?>[],
      };

      if (lines.isEmpty) {
        _logger.fine('The stdout isolate sent $message');
        return;
      }

      // Checked once rather than per line: this runs for every line the engine
      // writes, and the interpolation below is not free when nobody is
      // listening.
      final trace = _logger.isLoggable(Level.FINEST);

      for (final line in lines) {
        if (line is! String) continue;
        if (trace) _logger.finest('[stdout] $line');
        onStdout(line);
      }
    });
  }

  final mainPort = ReceivePort('Lc0 main isolate port');
  final stdoutPort = ReceivePort('Lc0 stdout isolate port');

  /// Completes with the engine's exit code when it has actually exited.
  ///
  /// Completed only by the main isolate reporting that the engine's main()
  /// returned, and never by [detach]: a handle that has stopped listening says
  /// nothing about whether the engine is still running. [Lc0._quitEngine] skips
  /// the `quit` write for an engine that has already exited, so anything else
  /// completing this would abandon a live engine still holding the native slot.
  final exited = Completer<int>();

  /// Completes when the reader isolate has finished with the output pipe.
  ///
  /// Not the same event as the engine exiting: the reader learns of that from
  /// the quit marker in the pipe, which it may not have read yet.
  final readerStopped = Completer<void>();

  bool _detached = false;

  /// Stops listening to this engine's isolates.
  ///
  /// Says nothing about the engine, which may still be running: this is the
  /// handle letting go, not the engine ending.
  void detach() {
    if (_detached) return;
    _detached = true;
    mainPort.close();
    stdoutPort.close();
  }
}

class _Lc0State extends ChangeNotifier implements ValueListenable<Lc0State> {
  Lc0State _value = Lc0State.initial;

  @override
  Lc0State get value => _value;

  // ignore: use_setters_to_change_properties
  _setValue(Lc0State v) {
    if (v == _value) return;
    _value = v;
    notifyListeners();
  }
}

Lc0Bindings? _cachedBindings;

Lc0Bindings _resolveBindings() {
  final override = Zone.current[lc0BindingsKey];
  if (override != null) return override as Lc0Bindings;
  return _cachedBindings ??= Lc0BindingsFFI();
}

void _isolateMain(SendPort mainPort) {
  final exitCode = _resolveBindings().main();
  mainPort.send(exitCode);

  // Logging from a spawned isolate does not reach the root logger's listeners,
  // so the exit code is reported by _onEngineExit on the main isolate instead.
  _logger.fine('lc0_main returns $exitCode');
}

void _isolateStdout(SendPort stdoutPort) {
  try {
    _readStdout(stdoutPort);
  } catch (error, stackTrace) {
    // This isolate is the only thing draining the engine's pipe. If it stops
    // without saying so the pipe fills, the engine blocks in write() inside its
    // UCI loop and answers nothing from then on -- a wedge with no visible
    // cause. Reporting the failure lets the handle fail the engine instead.
    stdoutPort.send({'error': '$error', 'stackTrace': '$stackTrace'});
  }

  // Tells the handle the pipe is free. Until this arrives the isolate is
  // still blocked reading it, and a create() that drained the pipe in the
  // meantime would leave it blocked forever -- a second reader stealing the
  // next engine's output.
  stdoutPort.send(null);
}

void _readStdout(SendPort stdoutPort) {
  final bindings = _resolveBindings();
  String previous = '';

  while (true) {
    final stdout = bindings.stdoutRead();

    if (stdout == null) {
      _logger.fine('lc0_stdout_read returns NULL');
      return;
    }

    final data = previous + stdout;
    final lines = data.split('\n');
    previous = lines.removeLast();

    // One message for the whole chunk rather than one per line. A page of engine
    // output holds many lines, and every port message is an event the main
    // isolate has to turn its loop for -- the isolate also running the UI.
    if (lines.isNotEmpty) stdoutPort.send(lines);
  }
}

Future<bool> _spawnIsolates(SendPort mainPort, SendPort stdoutPort) async {
  final override = Zone.current[lc0SpawnIsolatesKey];
  if (override != null) {
    return await (override as Future<bool> Function(SendPort, SendPort))(
      mainPort,
      stdoutPort,
    );
  }

  final bindings = _resolveBindings();

  final initResult = bindings.init();
  if (initResult != 0) {
    _logger.severe(
      'Failed to initialize the engine (init returned $initResult): '
      '${describeInitCode(initResult)}. '
      'phase=${Lc0Phase.fromCode(bindings.phase()).name} '
      'step=${bindings.phaseStep()} '
      'for ${bindings.phaseElapsedMs()}ms'
      '${bindings.lastError() == null ? '' : '; native error: ${bindings.lastError()}'}',
    );
    return false;
  }

  try {
    await Isolate.spawn(
      _isolateStdout,
      stdoutPort,
      debugName: 'Lc0 stdout isolate',
    );
  } catch (error) {
    _logger.severe('Failed to spawn stdout isolate: $error');
    return false;
  }

  try {
    await Isolate.spawn(_isolateMain, mainPort, debugName: 'Lc0 main isolate');
  } catch (error) {
    _logger.severe('Failed to spawn main isolate: $error');
    return false;
  }

  return true;
}
