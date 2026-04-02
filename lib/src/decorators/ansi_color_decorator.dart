import 'package:logging/logging.dart' as logging;

import 'log_decorator.dart';
import '../model/ansi_color.dart';
import '../model/log_style.dart';

/// Enables ANSI 24-bit color output for terminal rendering.
///
/// Owns [LogStyle.ansiColors] and [LogStyle.levelColors].
class AnsiColorDecorator extends LogDecorator {
  /// Per-level color overrides. When `null`, the resolver uses its defaults.
  final Map<logging.Level, AnsiColor>? customLevelColors;

  const AnsiColorDecorator({this.customLevelColors});

  @override
  void apply(LogStyle style) {
    style.ansiColors = true;
    if (customLevelColors != null) style.levelColors = customLevelColors;
  }
}
