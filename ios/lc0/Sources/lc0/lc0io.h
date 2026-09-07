/*
  Private engine I/O.

  The engine used to talk to the outside world through the process's own
  descriptors: the shim dup2()'d its pipe onto fd 0 and fd 1, and lc0 read
  std::cin and wrote std::cout. That had two consequences. This engine could not
  be resident alongside another one -- the last redirection won, and both
  engines' output arrived in one channel -- and the host application lost its own
  stdout for as long as the engine was running. Sharing a process with
  multistockfish, which is the whole point of this change, is impossible under
  those terms.

  These two streams replace std::cin and std::cout inside the engine. The shim
  binds them to its pipe with bind(), in place of the dup2 it used to do, so this
  engine's input and output reach this engine's pipe and nothing else's.

  Until bind() is called they read and write the process's standard descriptors,
  which keeps a plain command-line build of the engine working unchanged.

  Ported from dart-multistockfish's sfio.{h,cpp}, which solved the same problem
  for Stockfish; keep the two in step. The one structural difference is that lc0
  ships as a single native library, so there is no per-flavour namespace to
  configure.
*/

#ifndef LC0IO_H_INCLUDED
#define LC0IO_H_INCLUDED

#include <istream>
#include <ostream>

namespace lc0io {

// This engine's input. Every command it will ever execute is read from here.
std::istream& in();

// This engine's output. Every "info", "bestmove" and "id" line goes here.
std::ostream& out();

// Points the streams at `read_fd` and `write_fd`.
//
// Discards anything a previous engine left buffered on either side, so that a
// restart neither emits the tail of a dead engine's output nor executes commands
// queued for it, and clears the streams' error state so that it does not inherit
// a previous end-of-file.
//
// Returns false if either descriptor is not open, in which case the streams stay
// bound to whatever they were using before.
bool bind(int read_fd, int write_fd);

}  // namespace lc0io

#endif  // #ifndef LC0IO_H_INCLUDED
