// Host integration test for the real engine over the plugin's private I/O.
//
// The shim test beside this one stands the engine in with a stub, which keeps it
// quick. This one builds lc0 itself and boots it, which is the only way to check
// the thing the patch to the engine's own sources is for: that lc0 reads
// lc0io::in() and writes lc0io::out() everywhere it used to read std::cin and
// write std::cout, so its UCI channel is the plugin's pipe and the host keeps
// its own stdout.
//
// No network is needed: `uci` and `isready` are answered before any weights are
// read. The engine's banner goes to stderr, where it always did.
//
// Usage: test/run_real_engine_test.sh

#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <unistd.h>

#include <dlfcn.h>

static int (*lc0_init)();
static int (*lc0_main)();
static ssize_t (*lc0_stdin_write)(char *);
static char *(*lc0_stdout_read)();
static int (*lc0_phase)();
static const char *(*lc0_phase_step)();

static std::string collected;

static bool await_line(const char *needle, int timeout_ms)
{
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout_ms);
  while (std::chrono::steady_clock::now() < deadline) {
    if (collected.find(needle) != std::string::npos) return true;
    char *chunk = lc0_stdout_read();
    if (chunk == NULL) return collected.find(needle) != std::string::npos;
    collected += chunk;
  }
  return false;
}

static void send(const char *cmd)
{
  char buf[256];
  snprintf(buf, sizeof(buf), "%s\n", cmd);
  lc0_stdin_write(buf);
}

int lc0_driver()
{
  int failures = 0;
  auto check = [&](bool ok, const char *what) {
    fprintf(stderr, "  %s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok) failures++;
  };

  printf("host stdout line\n");
  fflush(stdout);

  check(lc0_init() == 0, "init");
  std::thread engine([] { lc0_main(); });

  send("uci");
  check(await_line("uciok", 20000), "the real engine answers uciok on its own pipe");
  check(collected.find("id name Lc0") != std::string::npos, "reports its name");
  fprintf(stderr, "  phase=%d step=%s\n", lc0_phase(), lc0_phase_step());

  send("isready");
  check(await_line("readyok", 20000), "answers isready");

  // Whether the network can be swapped without restarting the engine decides
  // whether the app's Lc0Spec has to carry the weights path. Engine::SetPosition
  // calls UpdateBackendConfig(), which rebuilds the backend when the options it
  // was built from have changed -- so a WeightsFile set now should be picked up
  // on the next position, and a bad one should be complained about rather than
  // ignored.
  collected.clear();
  send("setoption name WeightsFile value /nonexistent/network.pb.gz");
  send("position startpos");
  send("go nodes 1");
  const bool complained = await_line("nonexistent", 20000) ||
                          collected.find("error") != std::string::npos;
  check(complained, "WeightsFile is applied at runtime, not only at start-up");
  fprintf(stderr, "  -- engine said: %s\n", collected.c_str());

  send("quit");
  engine.join();
  check(true, "the engine exited");

  fprintf(stderr, "\n%s\n", failures == 0 ? "All checks passed." : "FAILURES");
  return failures;
}

int main(int argc, char **argv)
{
  if (argc < 2) { fprintf(stderr, "usage: real_engine_test <library>\n"); return 1; }
  void *lib = dlopen(argv[1], RTLD_NOW);
  if (!lib) { fprintf(stderr, "dlopen failed: %s\n", dlerror()); return 1; }
  lc0_init = (int (*)())dlsym(lib, "lc0_init");
  lc0_main = (int (*)())dlsym(lib, "lc0_main");
  lc0_stdin_write = (ssize_t (*)(char *))dlsym(lib, "lc0_stdin_write");
  lc0_stdout_read = (char *(*)())dlsym(lib, "lc0_stdout_read");
  lc0_phase = (int (*)())dlsym(lib, "lc0_phase");
  lc0_phase_step = (const char *(*)())dlsym(lib, "lc0_phase_step");
  if (!lc0_init || !lc0_main) { fprintf(stderr, "missing symbols\n"); return 1; }
  return lc0_driver();
}
