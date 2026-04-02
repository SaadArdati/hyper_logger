import 'package:logging/logging.dart' as logging;

import 'log_decorator.dart';
import '../model/log_style.dart';

/// Enables emoji prefixes on log sections.
///
/// Owns [LogStyle.emoji] and [LogStyle.levelEmojis].
class EmojiDecorator extends LogDecorator {
  /// Per-level emoji overrides. When `null`, the resolver uses its defaults.
  final Map<logging.Level, String>? customEmojis;

  const EmojiDecorator({this.customEmojis});

  @override
  void apply(LogStyle style) {
    style.emoji = true;
    if (customEmojis != null) style.levelEmojis = customEmojis;
  }
}
