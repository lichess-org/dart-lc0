/// C++ engine state.
enum Lc0State {
  /// Engine is not running.
  initial,

  /// Engine is starting.
  starting,

  /// Engine is running, ready to receive commands.
  ready,

  /// An error occurred: the engine could not start, or died on its own.
  error,

  /// The engine has been disposed and its slot freed.
  disposed,
}
