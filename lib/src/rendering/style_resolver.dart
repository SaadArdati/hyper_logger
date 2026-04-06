import '../model/ansi_color.dart';
import '../model/log_level.dart';
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
/// - box  → `linePrefix`
/// - emoji → `emojiPrefix` (message sections only)
/// - prefix → `bracketPrefix` (message sections only)
/// - ansiColors → `textColor` / `bgColor` (section-kind-specific palette)
class StyleResolver {
  // --------------------------------------------------------------------------
  // Default level → background-color mappings (muted backgrounds)
  // --------------------------------------------------------------------------

  static final Map<LogLevel, AnsiColor> _defaultLevelColors = {
    LogLevel.trace: AnsiColor.fromRGB(30, 30, 30),
    LogLevel.debug: AnsiColor.fromRGB(50, 0, 45),
    LogLevel.info: AnsiColor.fromRGB(0, 23, 59),
    LogLevel.warning: AnsiColor.fromRGB(61, 40, 0),
    LogLevel.error: AnsiColor.fromRGB(50, 0, 0),
    LogLevel.fatal: AnsiColor.fromRGB(50, 0, 45),
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
    required LogLevel level,
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
  ResolvedBorderStyle resolveBorder(LogStyle style, LogLevel level) {
    if (!style.box) return const ResolvedBorderStyle.none();

    final len = style.lineLength;

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
    LogLevel level,
  ) {
    if (!style.emoji) return null;
    if (kind != SectionKind.message) return null;

    // Custom emojis take precedence and are used as-is.
    final custom = style.levelEmojis?[level];
    if (custom != null) return custom.isEmpty ? null : custom;
    // Default: derive from LogLevel, add trailing space for rendering.
    final emoji = level.emoji;
    if (emoji.isEmpty) return null;
    return '$emoji ';
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

  AnsiColor? _resolveBgColor(LogStyle style, SectionKind kind, LogLevel level) {
    if (!style.ansiColors) return null;
    return switch (kind) {
      SectionKind.message => _levelBg(style, level),
      SectionKind.timestamp => _levelBg(style, level),
      SectionKind.data => null,
      SectionKind.error => _errorBgColor,
      SectionKind.stackTrace => null,
    };
  }

  AnsiColor _levelBg(LogStyle style, LogLevel level) {
    return style.levelColors?[level] ??
        _defaultLevelColors[level] ??
        AnsiColor.fromRGB(60, 60, 60);
  }
}
