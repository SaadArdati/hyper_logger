import '../model/log_style.dart';

/// Base class for all log decorators.
///
/// Each decorator is a stateless strategy that writes a coherent, non-overlapping
/// subset of [LogStyle] fields. Applying decorators in any order to the same
/// [LogStyle] instance produces the same final state.
abstract class LogDecorator {
  const LogDecorator();

  /// Writes this decorator's configuration into [style].
  void apply(LogStyle style);
}
