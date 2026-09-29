/// The lifecycle phase of the native engine.
///
/// The engine runs on a thread Dart does not own, and the interesting failures
/// happen where Dart cannot see them: a boot that stalls loading a network, a
/// shutdown that never finishes joining the search threads. The native shim
/// publishes its phase so that an [Lc0] that never becomes ready can say *where*
/// it got stuck rather than just *that* it did.
///
/// The numeric codes are part of the FFI contract and mirror the `LC0_PHASE_*`
/// constants in `ios/src/ffi.h`. They deliberately match dart-multistockfish's
/// `StockfishPhase`, so that an app hosting both engines reports their failures
/// the same way.
enum Lc0Phase {
  /// The library is loaded but the engine has never been initialized.
  idle(0),

  /// The communication pipes are being created.
  initializing(1),

  /// The pipes are ready and the engine is waiting to be run.
  initialized(2),

  /// The engine is attaching its input and output to its pipes.
  redirecting(3),

  /// The engine is starting up: parsing options, building its backend, loading
  /// its network. A start that hangs here is usually reading the weights on a
  /// slow device.
  engineBooting(4),

  /// The engine is in its UCI loop and accepting commands. This is the normal
  /// resting phase of a healthy engine.
  uciLoop(5),

  /// The UCI loop has returned and the engine is tearing itself down, which
  /// means stopping the search and joining its threads. A start that hangs here
  /// is the wedge.
  shuttingDown(6),

  /// The engine returned cleanly.
  exited(7),

  /// Initialization or the engine itself failed.
  failed(8),

  /// The native library did not report a phase.
  unknown(-1);

  const Lc0Phase(this.code);

  /// The numeric code exchanged with the native library.
  final int code;

  /// The phase for [code], or [Lc0Phase.unknown] if it is not recognized.
  static Lc0Phase fromCode(int code) {
    for (final phase in values) {
      if (phase.code == code) return phase;
    }
    return Lc0Phase.unknown;
  }

  /// Whether an engine sitting in this phase is stuck rather than merely busy.
  ///
  /// The UCI loop is where a healthy engine spends its life, and the terminal
  /// phases are terminal; everything else is a transition that should be quick —
  /// with the honest exception of [engineBooting], which really does take
  /// seconds while a network is read off disk.
  bool get isTransient => switch (this) {
        Lc0Phase.initializing ||
        Lc0Phase.redirecting ||
        Lc0Phase.engineBooting ||
        Lc0Phase.shuttingDown =>
          true,
        _ => false,
      };
}

/// A snapshot of what the native engine is doing, for logging and bug reports.
///
/// Obtained from [Lc0.diagnostics]. Attach it to any report of an engine that
/// failed to start or failed to quit — [phase], [step] and [elapsed] together
/// identify which of the known wedges was hit.
class Lc0Diagnostics {
  const Lc0Diagnostics({
    required this.phase,
    required this.step,
    required this.elapsed,
    required this.lastError,
  });

  /// The engine's lifecycle phase.
  final Lc0Phase phase;

  /// The step within [phase], e.g. `engine_construct` or `engine_teardown`.
  ///
  /// Empty when the native library does not report one.
  final String step;

  /// How long the engine has been on this [step].
  final Duration elapsed;

  /// The most recent error reported by the native library, if any.
  final String? lastError;

  /// Whether the engine looks wedged: it is in a transitional phase and has
  /// been there far longer than that transition should take.
  ///
  /// Booting is given longer than the rest, because loading a network is real
  /// work rather than a handover.
  bool get looksStuck =>
      phase.isTransient &&
      elapsed >
          (phase == Lc0Phase.engineBooting
              ? const Duration(seconds: 30)
              : const Duration(seconds: 5));

  @override
  String toString() {
    final buffer = StringBuffer(
      'phase=${phase.name}'
      '${step.isEmpty ? '' : ' step=$step'}'
      ' for ${elapsed.inMilliseconds}ms',
    );
    if (looksStuck) buffer.write(' (STUCK)');
    if (lastError != null) buffer.write('; native error: $lastError');
    return buffer.toString();
  }
}

/// Describes a value returned by the native `lc0_init` function.
String describeInitCode(int code) => switch (code) {
      0 => 'ok',
      -1 => 'pipe() failed',
      -2 =>
        'refused: the previous engine never exited, so this process cannot host another one',
      -3 => 'fcntl() failed making the input pipe non-blocking',
      _ => 'unknown init error ($code)',
    };

/// Describes a value returned by the native `lc0_main` function.
///
/// Non-negative values are the engine's own exit code.
String describeMainExitCode(int code) => switch (code) {
      0 => 'clean exit',
      -1 => 'refused: an engine is already running',
      -2 => 'called before a successful init',
      -3 => "the engine's input and output could not be attached to its pipes",
      -4 => 'the engine threw an exception',
      _ when code > 0 => 'engine exit code $code',
      _ => 'unknown exit code ($code)',
    };

/// Result codes returned by the native `lc0_stdin_write` function.
///
/// Mirrors the `LC0_WRITE_*` constants in `ios/src/ffi.h`. Non-negative results
/// are the number of bytes written.
abstract final class Lc0WriteResult {
  /// The engine was not initialized.
  static const notInitialized = -1;

  /// `write()` failed outright, so the channel to the engine is broken.
  static const failed = -2;

  /// The input pipe stayed full and nothing was written. The engine has stopped
  /// reading, but the byte stream it will read is still coherent.
  static const pipeFull = -3;

  /// The input pipe filled part-way through a command. Half a line is now
  /// queued, and anything sent afterwards concatenates onto that fragment.
  static const partial = -4;

  /// Whether [code] leaves the session unusable.
  ///
  /// [pipeFull] does not: nothing was written, so the command was simply not
  /// delivered and can be retried. [partial] and [failed] do — one has corrupted
  /// the command stream, the other has broken the channel carrying it — and
  /// neither can be recovered from without restarting the engine.
  static bool isFatal(int code) => code == partial || code == failed;
}

/// Describes a value returned by the native `lc0_stdin_write` function.
///
/// Non-negative values are the number of bytes written.
String describeWriteCode(int code) => switch (code) {
      Lc0WriteResult.notInitialized => 'called before a successful init',
      Lc0WriteResult.failed => 'write() failed',
      Lc0WriteResult.pipeFull =>
        'the input pipe is full; the engine has stopped reading',
      Lc0WriteResult.partial =>
        'the input pipe filled mid-command; the command stream is now corrupt and '
            'the engine must be restarted',
      _ when code >= 0 => '$code bytes written',
      _ => 'unknown write error ($code)',
    };
