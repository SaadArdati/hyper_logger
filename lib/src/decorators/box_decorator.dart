import 'log_decorator.dart';
import '../model/log_style.dart';

/// Enables box-border rendering around the entire log entry.
///
/// Owns [LogStyle.box] and [LogStyle.lineLength].
class BoxDecorator extends LogDecorator {
  /// The maximum line width in characters. Defaults to 120.
  final int lineLength;

  const BoxDecorator({this.lineLength = 120});

  @override
  void apply(LogStyle style) {
    style.box = true;
    style.lineLength = lineLength;
  }
}
