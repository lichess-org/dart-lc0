import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'ffi.dart';
import 'lc0_state.dart';

final _logger = Logger('Lc0');

/// A wrapper for the Lc0 chess engine.
///
/// This is a singleton - use [Lc0.instance] to access it.
///
/// Call [start] to start the engine and [quit] to stop it.
/// The engine can be restarted after quitting.
class Lc0 {
  /// The singleton instance of Lc0.
  static final Lc0 instance = Lc0._();

  final _state = _Lc0State();
  final _stdoutController = StreamController<String>.broadcast();
  final _mainPort = ReceivePort('Lc0 main isolate port');
  final _stdoutPort = ReceivePort('Lc0 stdout isolate port');

  Future<void>? _pendingStart;
  Future<void>? _pendingQuit;

  Lc0._() {
    _mainPort.listen((message) {
      _logger.fine('The main isolate sent $message');
      _onEngineExit(message is int ? message : 1);
    });

    _stdoutPort.listen((message) {
      if (message is String) {
        _logger.finest('[stdout] $message');
        _stdoutController.sink.add(message);
      } else {
        _logger.fine('The stdout isolate sent $message');
      }
    });
  }

  /// The current state of the underlying C++ engine.
  ValueListenable<Lc0State> get state => _state;

  /// The standard output stream.
  Stream<String> get stdout => _stdoutController.stream;

  /// The standard input sink.
  set stdin(String line) {
    final stateValue = _state.value;
    if (stateValue != Lc0State.ready) {
      throw StateError('Lc0 is not ready ($stateValue)');
    }

    _logger.finest('[stdin] $line');

    final pointer = '$line\n'.toNativeUtf8();
    nativeStdinWrite(pointer);
    calloc.free(pointer);
  }

  /// Starts the C++ engine.
  ///
  /// Returns a [Future] that completes when the engine is ready to accept commands.
  ///
  /// It is safe to call [start] while a previous start is in progress;
  /// subsequent calls will wait for the first to complete.
  Future<void> start() {
    if (_pendingStart != null) {
      return _pendingStart!;
    }

    if (_state.value != Lc0State.initial && _state.value != Lc0State.error) {
      throw StateError(
        'Lc0 is already running. Call quit() before starting again.',
      );
    }

    return _pendingStart = _doStart().whenComplete(() => _pendingStart = null);
  }

  Future<void> _doStart() async {
    _state._setValue(Lc0State.starting);

    final success = await _spawnIsolates(_mainPort.sendPort, _stdoutPort.sendPort);

    if (!success) {
      _logger.severe('Failed to spawn isolates');
      _state._setValue(Lc0State.error);
      throw Exception('Failed to spawn isolates');
    }

    _state._setValue(Lc0State.ready);
  }

  /// Quits the C++ engine.
  ///
  /// Returns a [Future] that completes when the engine has exited.
  ///
  /// After quitting, the engine can be started again with [start].
  ///
  /// It is safe to call [quit] multiple times; subsequent calls will wait
  /// for the first to complete.
  Future<void> quit() {
    if (_pendingQuit != null) {
      return _pendingQuit!;
    }

    switch (_state.value) {
      case Lc0State.initial:
      case Lc0State.error:
        return Future.value();
      case Lc0State.starting:
      case Lc0State.ready:
        return _pendingQuit = _doQuit().whenComplete(() => _pendingQuit = null);
    }
  }

  Future<void> _doQuit() {
    final completer = Completer<void>();

    void onStateChange() {
      switch (_state.value) {
        case Lc0State.ready:
          stdin = 'quit';
        case Lc0State.initial:
        case Lc0State.error:
          _state.removeListener(onStateChange);
          completer.complete();
        default:
          break;
      }
    }

    _state.addListener(onStateChange);
    if (_state.value == Lc0State.ready) {
      stdin = 'quit';
    }
    return completer.future;
  }

  void _onEngineExit(int exitCode) {
    _state._setValue(exitCode == 0 ? Lc0State.initial : Lc0State.error);
  }
}

class _Lc0State extends ChangeNotifier implements ValueListenable<Lc0State> {
  Lc0State _value = Lc0State.initial;

  @override
  Lc0State get value => _value;

  _setValue(Lc0State v) {
    if (v == _value) return;
    _value = v;
    notifyListeners();
  }
}

void _isolateMain(SendPort mainPort) {
  final exitCode = nativeMain();
  mainPort.send(exitCode);
  _logger.fine('nativeMain returns $exitCode');
}

void _isolateStdout(SendPort stdoutPort) {
  String previous = '';

  while (true) {
    final pointer = nativeStdoutRead();

    if (pointer.address == 0) {
      _logger.fine('nativeStdoutRead returns NULL');
      return;
    }

    final data = previous + pointer.toDartString();
    final lines = data.split('\n');
    previous = lines.removeLast();
    for (final line in lines) {
      stdoutPort.send(line);
    }
  }
}

Future<bool> _spawnIsolates(SendPort mainPort, SendPort stdoutPort) async {
  try {
    await Isolate.spawn(_isolateStdout, stdoutPort,
        debugName: 'Lc0 stdout isolate');
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
