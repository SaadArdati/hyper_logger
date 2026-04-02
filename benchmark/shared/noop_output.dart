/// A no-op output sink that discards all strings.
///
/// Used in benchmarks to isolate formatting/resolution cost from I/O.
/// The [callCount] field prevents dead-code elimination by the compiler.
class NoopOutput {
  int callCount = 0;

  void call(String s) {
    callCount++;
  }
}
