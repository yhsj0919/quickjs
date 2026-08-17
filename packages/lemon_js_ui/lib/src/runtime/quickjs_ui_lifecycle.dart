/// Lifecycle hooks supported by a JavaScript UI page.
enum JsUiLifecycle {
  /// The page has created its initial state.
  mount,

  /// The page became visible.
  show,

  /// The page became hidden.
  hide,

  /// The host application paused.
  pause,

  /// The host application resumed.
  resume,

  /// A route became active.
  routeEnter,

  /// A route is preparing to become inactive.
  routeLeave,

  /// A child route returned a result.
  routeResult,

  /// The page is being permanently released.
  dispose,
}
