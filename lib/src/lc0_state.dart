/// C++ engine state.
enum Lc0State {
  /// Engine has been stopped.
  disposed,

  /// An error occured (engine could not start).
  error,

  /// Engine is running.
  ready,

  /// Engine is starting.
  starting,
}
