/// Fires a delegate call, catching and swallowing any error so that
/// logging never crashes the app. The returned [Future] (if any) is
/// awaited with an error handler that also swallows.
void fireDelegateSafely(Future<void>? Function() fn) {
  try {
    fn()?.catchError((_) {});
  } catch (_) {
    // Synchronous throw from the delegate — swallow.
  }
}
