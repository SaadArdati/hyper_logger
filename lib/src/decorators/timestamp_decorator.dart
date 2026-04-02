import 'log_decorator.dart';
import '../model/log_style.dart';

/// Enables a timestamp section in each log entry.
///
/// Owns [LogStyle.timestamp] and [LogStyle.dateTimeFormatter].
class TimestampDecorator extends LogDecorator {
  /// Custom formatter for the timestamp. When `null`, [_defaultFormat] is used.
  final DateTimeFormatter? formatter;

  const TimestampDecorator({this.formatter});

  @override
  void apply(LogStyle style) {
    style.timestamp = true;
    style.dateTimeFormatter = formatter ?? _defaultFormat;
  }

  static String _defaultFormat(DateTime dt) => dt.toIso8601String();
}
