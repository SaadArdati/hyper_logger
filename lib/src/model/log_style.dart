import 'package:logging/logging.dart';

import 'ansi_color.dart';

/// Formats a [DateTime] to a display string.
typedef DateTimeFormatter = String Function(DateTime);

/// Mutable property bag that decorators write formatting preferences into.
///
/// All fields have sensible defaults. Decorators accumulate changes onto the
/// same instance; the [StyleResolver] reads the final state to produce
/// [ResolvedSectionStyle] / [ResolvedBorderStyle].
class LogStyle {
  /// Whether to draw a box border around the entire log entry.
  bool box = false;

  /// Whether to prepend an emoji to each section.
  bool emoji = false;

  /// Whether to apply ANSI color codes to the output.
  bool ansiColors = false;

  /// Whether to include a timestamp section.
  bool timestamp = false;

  /// Whether to prepend a `[Type]` bracket prefix to the message section.
  bool prefix = true;

  /// Maximum width of a rendered line before wrapping (characters).
  int lineLength = 120;

  /// Number of stack-trace frames to include. `null` means use the logger
  /// default (typically the full trace).
  int? stackTraceMethodCount;

  /// Override emojis per [Level]. When `null`, the resolver uses its defaults.
  Map<Level, String>? levelEmojis;

  /// Override ANSI colors per [Level]. When `null`, the resolver uses its
  /// defaults.
  Map<Level, AnsiColor>? levelColors;

  /// Custom formatter for the timestamp section. When `null`, the resolver
  /// uses its default ISO-8601 representation.
  DateTimeFormatter? dateTimeFormatter;
}
