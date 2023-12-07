import 'dart:async';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'ffi.dart';
import 'lc0_state.dart';

final _logger = Logger('Lc0');

/// A wrapper for C++ engine.
class Lc0 {
  final Completer<Lc0>? completer;

  final _state = _Lc0State();
  final _stdoutController = StreamController<String>.broadcast();
  final _mainPort = ReceivePort();
  final _stdoutPort = ReceivePort();

  late StreamSubscription _mainSubscription;
  late StreamSubscription _stdoutSubscription;

  Lc0._({this.completer}) {
    _mainSubscription =
        _mainPort.listen((message) => _cleanUp(message is int ? message : 1));
    _stdoutSubscription = _stdoutPort.listen((message) {
      if (message is String) {
        _stdoutController.sink.add(message);
      } else {
        _logger.fine('The stdout isolate sent $message');
      }
    });
    compute(_spawnIsolates, [_mainPort.sendPort, _stdoutPort.sendPort]).then(
      (success) {
        final state = success ? Lc0State.ready : Lc0State.error;
        _state._setValue(state);
        if (state == Lc0State.ready) {
          completer?.complete(this);
        }
      },
      onError: (error) {
        _logger.severe('The init isolate encountered an error $error');
        _cleanUp(1);
      },
    );
  }

  static Lc0? _instance;

  /// Creates a C++ engine.
  ///
  /// This may throws a [StateError] if an active instance is being used.
  /// Owner must [dispose] it before a new instance can be created.
  factory Lc0() {
    if (_instance != null) {
      throw new StateError('Multiple instances are not supported, yet.');
    }

    _instance = Lc0._();
    return _instance!;
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

    final pointer = '$line\n'.toNativeUtf8();
    nativeStdinWrite(pointer);
    calloc.free(pointer);
  }

  /// Stops the C++ engine.
  void dispose() {
    stdin = 'quit';
  }

  void _cleanUp(int exitCode) {
    _stdoutController.close();

    _mainSubscription.cancel();
    _stdoutSubscription.cancel();

    _state._setValue(exitCode == 0 ? Lc0State.disposed : Lc0State.error);

    _instance = null;
  }
}

/// Creates a C++ engine asynchronously.
///
/// This method is different from the factory method [Lc0.new] that
/// it will wait for the engine to be ready before returning the instance.
Future<Lc0> lc0Async() {
  if (Lc0._instance != null) {
    return Future.error(StateError('Only one instance can be used at a time'));
  }

  final completer = Completer<Lc0>();
  Lc0._instance = Lc0._(completer: completer);
  return completer.future;
}

class _Lc0State extends ChangeNotifier implements ValueListenable<Lc0State> {
  Lc0State _value = Lc0State.starting;

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

Future<bool> _spawnIsolates(List<SendPort> mainAndStdout) async {
  try {
    await Isolate.spawn(_isolateStdout, mainAndStdout[1]);
  } catch (error) {
    _logger.severe('Failed to spawn stdout isolate: $error');
    return false;
  }

  try {
    await Isolate.spawn(_isolateMain, mainAndStdout[0]);
  } catch (error) {
    _logger.severe('Failed to spawn main isolate: $error');
    return false;
  }

  return true;
}
