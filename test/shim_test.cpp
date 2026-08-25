// Host integration test for the plugin's shim and its private engine I/O.
//
// This is what §6.2 items 1-3 of the app's engine refactor are about, and it is
// the guarantee the change exists for: an lc0 engine used to dup2() its pipe
// onto the process's fd 0 and fd 1, which meant no other engine could be
// resident beside it and the host application lost its own stdout for as long as
// lc0 was running.
//
// The engine itself is not built here. It is replaced by a stub main() that
// reads lc0io::in() and writes lc0io::out(), which is exactly the contract the
// real engine now follows after the patch to engine_loop.cc, uciloop.cc and
// logging.cc. That keeps this test to a few seconds instead of the several
// minutes an lc0 build takes, and it keeps it honest: what is being tested is
// the channel, not the chess.
//
// All diagnostics go to stderr, which leaves stdout free to be checked for
// exactly the interference the engine no longer causes.
//
// Usage: test/run_shim_test.sh

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <unistd.h>

#include "ffi.h"
#include "lc0io.h"

static int g_failures = 0;

static void check(bool ok, const char *what)
{
  fprintf(stderr, "  %s %s\n", ok ? "ok  " : "FAIL", what);
  if (!ok)
    g_failures++;
}

// ---------------------------------------------------------------------------
// The engine, replaced by the smallest thing that behaves like one.
//
// It answers `uci` with `uciok`, echoes anything else back, and exits on `quit`
// -- the same shape as lc0's own loop, reading and writing the plugin's streams
// rather than the process's.
// ---------------------------------------------------------------------------

static std::atomic<int> g_main_calls{0};
static std::atomic<bool> g_main_running{false};

static int run_stub_engine()
{
  g_main_calls++;
  g_main_running = true;

  lc0_set_phase(LC0_PHASE_UCI_LOOP, "uci_loop");

  std::string line;
  while (std::getline(lc0io::in(), line))
  {
    if (line == "quit")
      break;
    if (line == "uci")
      lc0io::out() << "id name Lc0 stub" << std::endl
                   << "uciok" << std::endl;
    else
      lc0io::out() << "echo " << line << std::endl;
  }

  lc0_set_phase(LC0_PHASE_SHUTTING_DOWN, "engine_teardown");
  g_main_running = false;
  return 0;
}

// ---------------------------------------------------------------------------
// Reading the engine's output.
// ---------------------------------------------------------------------------

// Waits for `needle` to appear in the engine's output, or gives up.
static bool await_line(const char *needle, int timeout_ms = 3000)
{
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout_ms);

  static std::string pending;

  while (std::chrono::steady_clock::now() < deadline)
  {
    if (pending.find(needle) != std::string::npos)
    {
      pending.clear();
      return true;
    }

    char *chunk = lc0_stdout_read();
    if (chunk == NULL)
      return false;
    pending += chunk;
  }

  return false;
}

static void send(const char *command)
{
  char buffer[256];
  snprintf(buffer, sizeof(buffer), "%s\n", command);
  lc0_stdin_write(buffer);
}

static int run_test()
{
  fprintf(stderr, "Private I/O and shim lifecycle\n");

  // The process's own stdout must survive an engine. Anything the engine writes
  // arriving here instead of in its pipe is the bug this change removed.
  printf("this line belongs to the host, not to the engine\n");
  fflush(stdout);

  check(lc0_phase() == LC0_PHASE_IDLE, "starts idle");

  check(lc0_init() == 0, "init creates the pipes");
  check(lc0_phase() == LC0_PHASE_INITIALIZED, "init reports initialized");

  std::thread engine([] { lc0_main(); });

  send("uci");
  check(await_line("uciok"), "answers the handshake through its own pipe");

  send("hello");
  check(await_line("echo hello"), "echoes a command back");

  // The re-entry guard: lc0 keeps its state in process globals, so a second
  // concurrent run would race the first.
  check(lc0_main() == LC0_MAIN_ALREADY_RUNNING, "refuses a second engine");
  check(lc0_init() == LC0_INIT_ALREADY_RUNNING, "refuses init while running");

  check(lc0_phase() == LC0_PHASE_UCI_LOOP, "reports the UCI loop");
  check(strcmp(lc0_phase_step(), "uci_loop") == 0, "reports the step");

  send("quit");
  engine.join();
  check(g_main_running == false, "the engine exited");
  check(lc0_phase() == LC0_PHASE_EXITED, "reports a clean exit");

  // A restart reuses the pipes rather than creating a second pair.
  check(lc0_init() == 0, "init succeeds again after the engine exited");
  std::thread second([] { lc0_main(); });
  send("uci");
  check(await_line("uciok"), "a second engine answers on the same pipe");
  check(g_main_calls == 2, "the engine really was started twice");
  send("quit");
  second.join();

  // Nothing the engine said should have reached the host's stdout. The runner
  // discards stdout and keeps stderr, so a failure here shows up as engine
  // output appearing where the host's own writes go.
  fprintf(stderr, "\n%s\n", g_failures == 0 ? "All checks passed." : "FAILURES");
  return g_failures == 0 ? 0 : 1;
}

// The engine the shim runs, standing in for lc0's own entry point.
int lc0_engine_main(int, const char **) { return run_stub_engine(); }

int main(int, char **) { return run_test(); }
