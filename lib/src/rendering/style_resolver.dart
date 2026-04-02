import 'package:logging/logging.dart' as logging;

import '../model/ansi_color.dart';
import '../model/log_section.dart';
import '../model/log_style.dart';
import '../model/resolved_style.dart';

/// Reconciles all [LogStyle] flags into concrete [ResolvedSectionStyle] and
/// [ResolvedBorderStyle] values.
///
/// This is the **only** place where flag interactions live — every downstream
/// renderer receives already-resolved styles and applies them blindly.
///
/// Design: CSS-cascade model.
/// • box  → `linePrefix`
/// • emoji → `emojiPrefix` (message sections only)
/// • prefix → `bracketPrefix` (message sections only)
/// • ansiColors → `textColor` / `bgColor` (section-kind-specific palette)
class StyleResolver {
  // --------------------------------------------------------------------------
  // Default level → background-color mappings (muted backgrounds)
  // --------------------------------------------------------------------------

  // Exact colors from DebugLogger v4.2 — base color at 30% brightness.
  //
  //   warning : 0xFFCC8500 × 0.3 = RGB(61, 40, 0)
  //   error   : 0xFFA60000 × 0.3 = RGB(50, 0, 0)
  //   info    : 0xFF004BC3 × 0.3 = RGB(0, 23, 59)
  //   function: 0xFFA80097 × 0.3 = RGB(50, 0, 45)
  //   network : 0xFF00FFFF × 0.3 = RGB(0, 77, 77)
  static final Map<logging.Level, AnsiColor> _defaultLevelColors = {
    logging.Level.FINEST: AnsiColor.fromRGB(
      30,
      30,
      30,
    ), // trace: very dark gray
    logging.Level.FINER: AnsiColor.fromRGB(30, 30, 30),
    logging.Level.FINE: AnsiColor.fromRGB(
      50,
      0,
      45,
    ), // debug: muted purple (function)
    logging.Level.INFO: AnsiColor.fromRGB(0, 23, 59), // info: muted blue
    logging.Level.WARNING: AnsiColor.fromRGB(
      61,
      40,
      0,
    ), // warning: muted orange
    logging.Level.SEVERE: AnsiColor.fromRGB(50, 0, 0), // error: muted red
    logging.Level.SHOUT: AnsiColor.fromRGB(50, 0, 45), // fatal: muted magenta
  };

  // --------------------------------------------------------------------------
  // Default level → emoji mappings (with trailing space)
  // --------------------------------------------------------------------------

  static final Map<logging.Level, String> _defaultLevelEmojis = {
    logging.Level.FINEST: '',
    logging.Level.FINER: '',
    logging.Level.FINE: '🐛 ',
    logging.Level.INFO: '💡 ',
    logging.Level.WARNING: '⚠️ ',
    logging.Level.SEVERE: '⛔ ',
    logging.Level.SHOUT: '👾 ',
  };

  // --------------------------------------------------------------------------
  // Section-specific color palette
  // --------------------------------------------------------------------------

  static final AnsiColor _errorBgColor = AnsiColor.fromRGB(50, 0, 0);
  static final AnsiColor _whiteText = AnsiColor.white;

  // --------------------------------------------------------------------------
  // Public API
  // --------------------------------------------------------------------------

  /// Resolves style for a single [LogSection] described by [kind] at [level].
  ///
  /// [className] and [methodName] are used only when [style.prefix] is true and
  /// [kind] is [SectionKind.message].
  ResolvedSectionStyle resolve({
    required LogStyle style,
    required SectionKind kind,
    required logging.Level level,
    String? className,
    String? methodName,
  }) {
    return ResolvedSectionStyle(
      linePrefix: _resolveLinePrefix(style),
      emojiPrefix: _resolveEmojiPrefix(style, kind, level),
      bracketPrefix: _resolveBracketPrefix(style, kind, className, methodName),
      textColor: _resolveTextColor(style, kind),
      bgColor: _resolveBgColor(style, kind, level),
    );
  }

  /// Resolves the border strings for a box-framed log entry.
  ///
  /// Returns [ResolvedBorderStyle.none] when [style.box] is false.
  /// When [style.ansiColors] is also true the border strings are wrapped in the
  /// level-mapped background color + white foreground + ANSI reset.
  ResolvedBorderStyle resolveBorder(LogStyle style, logging.Level level) {
    if (!style.box) return const ResolvedBorderStyle.none();

    final len = style.lineLength;

    // Match original AppPrettyPrinter style: no right corners.
    final top = '┌${'─' * (len - 1)}';
    final bottom = '└${'─' * (len - 1)}';
    final divider = '├${'┄' * (len - 1)}';

    if (!style.ansiColors) {
      return ResolvedBorderStyle(
        topBorder: top,
        bottomBorder: bottom,
        divider: divider,
      );
    }

    // Wrap each border line in level-bg + white-fg + reset.
    final bg = _levelBg(style, level);
    final fg = _whiteText;

    String colorize(String s) => '${bg.bg}${fg.fg}$s${AnsiColor.reset}';

    return ResolvedBorderStyle(
      topBorder: colorize(top),
      bottomBorder: colorize(bottom),
      divider: colorize(divider),
    );
  }

  // --------------------------------------------------------------------------
  // Private helpers
  // --------------------------------------------------------------------------

  String _resolveLinePrefix(LogStyle style) => style.box ? '│ ' : '';

  String? _resolveEmojiPrefix(
    LogStyle style,
    SectionKind kind,
    logging.Level level,
  ) {
    if (!style.emoji) return null;
    if (kind != SectionKind.message) return null;

    // Custom emojis take precedence; fall back to built-in defaults.
    final emoji = style.levelEmojis?[level] ?? _defaultLevelEmojis[level] ?? '';
    // Treat empty string as "no emoji" (return null for clean no-op).
    return emoji.isEmpty ? null : emoji;
  }

  String? _resolveBracketPrefix(
    LogStyle style,
    SectionKind kind,
    String? className,
    String? methodName,
  ) {
    if (!style.prefix) return null;
    if (kind != SectionKind.message) return null;

    if (className == null && methodName == null) return null;

    if (className != null && methodName != null) {
      return '[$className.$methodName] ';
    }
    if (className != null) {
      return '[$className] ';
    }
    // methodName without className: use methodName alone.
    return '[$methodName] ';
  }

  AnsiColor? _resolveTextColor(LogStyle style, SectionKind kind) {
    if (!style.ansiColors) return null;
    return switch (kind) {
      SectionKind.message => _whiteText,
      SectionKind.timestamp => _whiteText,
      SectionKind.data => null,
      SectionKind.error => _whiteText,
      SectionKind.stackTrace => null,
    };
  }

  AnsiColor? _resolveBgColor(
    LogStyle style,
    SectionKind kind,
    logging.Level level,
  ) {
    if (!style.ansiColors) return null;
    return switch (kind) {
      SectionKind.message => _levelBg(style, level),
      SectionKind.timestamp => _levelBg(style, level),
      SectionKind.data => null,
      SectionKind.error => _errorBgColor,
      SectionKind.stackTrace => null,
    };
  }

  /// Returns the background [AnsiColor] for [level], respecting custom overrides.
  AnsiColor _levelBg(LogStyle style, logging.Level level) {
    return style.levelColors?[level] ??
        _defaultLevelColors[level] ??
        AnsiColor.fromRGB(60, 60, 60);
  }
}
