import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';

final _logger = Logger('Lc0');

/// The native functions the plugin exports.
///
/// An interface rather than a set of top-level functions so that tests can put
/// a fake engine behind it without a native library.
abstract class Lc0Bindings {
  /// Creates the engine's pipes, or drains the ones a previous run left.
  ///
  /// Returns 0 on success, or a negative code described by [describeInitCode].
  int init();

  /// Runs the engine, returning when it has exited.
  ///
  /// Returns the engine's exit code, or a negative code described by
  /// [describeMainExitCode].
  int main();

  /// Sends a command to the engine.
  ///
  /// Returns the number of bytes written, or a negative code described by
  /// [describeWriteCode]. Never blocks indefinitely: if the engine has stopped
  /// reading, it gives up and reports the failure instead.
  int stdinWrite(String input);

  /// Reads whatever the engine has written, blocking until there is something.
  /// Null when the engine is gone.
  String? stdoutRead();

  /// The engine's current lifecycle phase, as an `LC0_PHASE_*` code.
  int phase();

  /// A short name for the step within the current phase.
  String phaseStep();

  /// Milliseconds spent on the current step.
  int phaseElapsedMs();

  /// The most recent error reported by the native library, if any.
  String? lastError();
}

/// The library the plugin's symbols live in.
///
/// On Android the plugin is its own shared object. On iOS and macOS it may be
/// statically merged into the app binary instead, which `DynamicLibrary.open`
/// cannot reach — but `process()` resolves symbols from both, because a
/// dynamically linked framework is loaded at launch just as statically linked
/// code is.
ffi.DynamicLibrary _openLibrary() {
  if (Platform.isAndroid || Platform.isLinux) {
    return ffi.DynamicLibrary.open('liblc0.so');
  }
  return ffi.DynamicLibrary.process();
}

/// FFI implementation of [Lc0Bindings].
class Lc0BindingsFFI implements Lc0Bindings {
  Lc0BindingsFFI([ffi.DynamicLibrary? dynamicLibrary])
      : _lookup = (dynamicLibrary ?? _openLibrary()).lookup;

  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
      _lookup;

  @override
  int init() => _init();

  @override
  int main() => _main();

  @override
  int stdinWrite(String input) {
    final pointer = input.toNativeUtf8();
    try {
      return _stdinWrite(pointer);
    } finally {
      calloc.free(pointer);
    }
  }

  @override
  String? stdoutRead() {
    final pointer = _stdoutRead();
    if (pointer.address == 0) {
      _logger.fine('lc0_stdout_read returns NULL');
      return null;
    }
    return pointer.toDartString();
  }

  @override
  int phase() => _phase();

  @override
  String phaseStep() {
    final pointer = _phaseStep();
    if (pointer.address == 0) return '';
    return pointer.toDartString();
  }

  @override
  int phaseElapsedMs() => _phaseElapsedMs();

  /// Matches the `g_last_error` buffer in the native shim. A longer message is
  /// truncated natively, so this only ever costs one short-lived allocation.
  static const _lastErrorBufferSize = 512;

  @override
  String? lastError() {
    // The buffer belongs to this call. The native side fills it while holding
    // its lock, so no other caller can be writing these bytes while they are
    // read back — which a shared native buffer could not promise.
    final buffer = calloc<ffi.Uint8>(_lastErrorBufferSize);
    try {
      final length = _lastError(buffer.cast<Utf8>(), _lastErrorBufferSize);
      if (length <= 0) return null;
      return buffer.cast<Utf8>().toDartString(length: length);
    } finally {
      calloc.free(buffer);
    }
  }

  late final _init = _lookup<ffi.NativeFunction<ffi.Int32 Function()>>(
    'lc0_init',
  ).asFunction<int Function()>();

  late final _main = _lookup<ffi.NativeFunction<ffi.Int32 Function()>>(
    'lc0_main',
  ).asFunction<int Function()>();

  late final _stdinWrite =
      _lookup<ffi.NativeFunction<ffi.IntPtr Function(ffi.Pointer<Utf8>)>>(
    'lc0_stdin_write',
  ).asFunction<int Function(ffi.Pointer<Utf8>)>();

  late final _stdoutRead =
      _lookup<ffi.NativeFunction<ffi.Pointer<Utf8> Function()>>(
    'lc0_stdout_read',
  ).asFunction<ffi.Pointer<Utf8> Function()>();

  late final _phase = _lookup<ffi.NativeFunction<ffi.Int32 Function()>>(
    'lc0_phase',
  ).asFunction<int Function()>();

  late final _phaseStep =
      _lookup<ffi.NativeFunction<ffi.Pointer<Utf8> Function()>>(
    'lc0_phase_step',
  ).asFunction<ffi.Pointer<Utf8> Function()>();

  late final _phaseElapsedMs =
      _lookup<ffi.NativeFunction<ffi.Int64 Function()>>(
    'lc0_phase_elapsed_ms',
  ).asFunction<int Function()>();

  late final _lastError = _lookup<
          ffi.NativeFunction<
              ffi.Int32 Function(
                  ffi.Pointer<Utf8>, ffi.Int32)>>('lc0_last_error')
      .asFunction<int Function(ffi.Pointer<Utf8>, int)>();
}
