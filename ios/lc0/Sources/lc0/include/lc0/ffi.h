#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// ---------------------------------------------------------------------------
// Phases reported by lc0_phase().
//
// These numbers are part of the FFI contract and are mirrored by Lc0Phase on
// the Dart side; keep the two in step. They follow dart-multistockfish's
// SF_PHASE_* numbering, so that an app hosting both engines can report their
// failures the same way.
// ---------------------------------------------------------------------------
#define LC0_PHASE_IDLE 0           // library loaded, init() not called yet
#define LC0_PHASE_INITIALIZING 1   // creating the pipes
#define LC0_PHASE_INITIALIZED 2    // pipes ready, waiting for main()
#define LC0_PHASE_REDIRECTING 3    // inside main(), attaching the engine I/O to its pipes
#define LC0_PHASE_ENGINE_BOOTING 4 // engine start-up: options, backend, weights
#define LC0_PHASE_UCI_LOOP 5       // inside the UCI loop, accepting commands
#define LC0_PHASE_SHUTTING_DOWN 6  // loop returned, tearing the engine down
#define LC0_PHASE_EXITED 7         // main() returned cleanly
#define LC0_PHASE_FAILED 8         // init or main failed

// Error codes returned by lc0_init().
#define LC0_INIT_PIPE_FAILED (-1)
#define LC0_INIT_ALREADY_RUNNING (-2)
#define LC0_INIT_FCNTL_FAILED (-3)

// Error codes returned by lc0_main(). Non-negative values are the engine's own
// exit code.
#define LC0_MAIN_ALREADY_RUNNING (-1)
#define LC0_MAIN_NOT_INITIALIZED (-2)
#define LC0_MAIN_BIND_FAILED (-3)  // the engine I/O could not be attached to its pipes
#define LC0_MAIN_ENGINE_THREW (-4)

// Error codes returned by lc0_stdin_write(). Non-negative values are the number
// of bytes written.
#define LC0_WRITE_NOT_INITIALIZED (-1)
#define LC0_WRITE_FAILED (-2)
#define LC0_WRITE_PIPE_FULL (-3)
#define LC0_WRITE_PARTIAL (-4)

// `weak` is what keeps these entry points reachable from Dart on iOS.
//
// Under Swift Package Manager this library is linked statically into the app
// binary rather than shipped as its own framework, so Dart resolves the symbols
// with dlsym(RTLD_DEFAULT, ...) against the app itself. Xcode's install/archive
// step runs `strip` over that binary with its default "All Symbols" style,
// which deletes ordinary global symbols from both the symbol table and the
// exports trie -- after which the lookup fails with "symbol not found", but
// only in an archived build. Weak definitions are the exception: dyld has to be
// able to coalesce them across images, so `strip` leaves them in the exports
// trie. `visibility("default")` and `used` survive compilation and
// dead-stripping; `weak` is what survives `strip`.
#define LC0_ATTRS \
  __attribute__((visibility("default"))) __attribute__((used)) __attribute__((weak))

#ifdef __cplusplus
#define LC0_EXPORT extern "C" LC0_ATTRS
#else
#define LC0_EXPORT LC0_ATTRS
#endif

/// Creates the engine's pipes, or reuses and drains the ones a previous run
/// left. Must succeed before any other call.
LC0_EXPORT int lc0_init();

/// Runs the engine. Returns when it has exited, which is why it is called on an
/// isolate of its own.
LC0_EXPORT int lc0_main();

/// Sends a command to the engine.
LC0_EXPORT ssize_t lc0_stdin_write(char *data);

/// Reads whatever the engine has written, blocking until there is something.
/// Returns NULL when the engine is gone.
LC0_EXPORT char *lc0_stdout_read();

/// The engine's current lifecycle phase, as one of the LC0_PHASE_* values.
LC0_EXPORT int lc0_phase();

/// A short name for the step within the current phase, e.g. "engine_boot".
/// Always a string literal, never NULL.
LC0_EXPORT const char *lc0_phase_step();

/// Milliseconds spent in the current step. A large value while the engine is
/// booting or shutting down is the signature of a wedged engine.
LC0_EXPORT long long lc0_phase_elapsed_ms();

/// Reports where the engine has got to.
///
/// Called from lc0's own sources, which the plugin patches at the few points
/// worth naming: entering the UCI loop, and leaving it for teardown. Everything
/// before the first of those is engine boot, which is where a start that never
/// completes usually is.
LC0_EXPORT void lc0_set_phase(int phase, const char *step);

/// Copies the most recent error message into `buffer`, truncating it to fit and
/// always NUL terminating. Returns the number of bytes written, or 0 if nothing
/// has failed yet.
///
/// The caller supplies the destination on purpose: handing back a pointer to a
/// shared buffer would let one reader overwrite it while another was still
/// copying out of it.
LC0_EXPORT int lc0_last_error(char *buffer, int size);
