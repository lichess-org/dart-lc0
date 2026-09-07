## 0.1.0

Initial release.

- Embeds Lc0 v0.32.1 (CPU-only, BLAS/Eigen backend) for iOS and Android, driven
  over UCI through Dart FFI.
- An engine is a handle: `Lc0.create()` starts one and completes once it has
  answered `uciok`, `dispose()` releases it, and the handle is single-use. Only
  one engine may be live at a time -- lc0 keeps its state in process globals --
  which `create()` enforces by throwing a `StateError`.
- The engine reads and writes its own private streams instead of the process's
  stdin and stdout, so the host app keeps its output and another engine can be
  resident alongside lc0.
- `state` and `diagnostics` report where a start got to (`Lc0Phase`, the step
  within it, how long it has been there and the last native error), which is the
  only way to see a wedged engine from Dart.
- Ships as a Swift package and a podspec on iOS, so it builds whether or not the
  host app has Swift Package Manager enabled; the engine's sources are vendored
  rather than fetched at build time, and `lc0.patch` is the diff from a pristine
  v0.32.1.
