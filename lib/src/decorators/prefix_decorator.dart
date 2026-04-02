import 'log_decorator.dart';
import '../model/log_style.dart';

/// Enables the `[Type]` bracket prefix on the message section.
///
/// Owns [LogStyle.prefix].
class PrefixDecorator extends LogDecorator {
  const PrefixDecorator();

  @override
  void apply(LogStyle style) {
    style.prefix = true;
  }
}
