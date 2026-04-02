import 'ansi_color.dart';

/// The fully-resolved styling for a single [LogSection].
///
/// Produced by [StyleResolver] after all decorators have run.
/// Consumed by [SectionRenderer] to format each line of a section.
class ResolvedSectionStyle {
  /// A literal string prepended to every line (e.g. a box-drawing gutter
  /// character like `│ `). Sits *outside* any ANSI color block.
  final String linePrefix;

  /// An emoji prepended to the styled content (before the bracket prefix and
  /// text). `null` means no emoji.
  final String? emojiPrefix;

  /// A bracket-style type prefix (e.g. `[MyClass] `). `null` means no prefix.
  final String? bracketPrefix;

  /// The ANSI foreground color applied to the content. `null` means no color.
  final AnsiColor? textColor;

  /// The ANSI background color applied to the content. `null` means no color.
  final AnsiColor? bgColor;

  const ResolvedSectionStyle({
    required this.linePrefix,
    required this.emojiPrefix,
    required this.bracketPrefix,
    required this.textColor,
    required this.bgColor,
  });

  /// Applies resolved style to a single [line].
  ///
  /// Assembly order (left to right):
  /// 1. [linePrefix]   — always present, sits outside ANSI escapes
  /// 2. bg escape      — if [bgColor] is set and not none
  /// 3. fg escape      — if [textColor] is set and not none
  /// 4. [emojiPrefix]  — if set
  /// 5. [bracketPrefix]— if set
  /// 6. [line]         — the text content
  /// 7. ANSI reset     — only when any color was applied
  ///
  /// Uses a [StringBuffer] to avoid intermediate allocations.
  String apply(String line) {
    final bool hasColors =
        (bgColor != null && !bgColor!.isNone) ||
        (textColor != null && !textColor!.isNone);

    // Fast path: nothing to add.
    if (linePrefix.isEmpty &&
        emojiPrefix == null &&
        bracketPrefix == null &&
        !hasColors) {
      return line;
    }

    final buf = StringBuffer();

    // linePrefix sits outside ANSI so that terminal gutter characters are not
    // colored.
    if (linePrefix.isNotEmpty) {
      buf.write(linePrefix);
    }

    if (hasColors) {
      if (bgColor != null && !bgColor!.isNone) {
        buf.write(bgColor!.bg);
      }
      if (textColor != null && !textColor!.isNone) {
        buf.write(textColor!.fg);
      }
    }

    if (emojiPrefix != null) {
      buf.write(emojiPrefix);
    }

    if (bracketPrefix != null) {
      buf.write(bracketPrefix);
    }

    buf.write(line);

    if (hasColors) {
      buf.write(AnsiColor.reset);
    }

    return buf.toString();
  }
}

/// The fully-resolved border strings for a box-framed log entry.
///
/// All fields are `null` when boxing is disabled; use [ResolvedBorderStyle.none]
/// in that case.
class ResolvedBorderStyle {
  /// Top border line drawn before all sections.
  final String? topBorder;

  /// Bottom border line drawn after all sections.
  final String? bottomBorder;

  /// Divider line drawn between sections.
  final String? divider;

  const ResolvedBorderStyle({
    required this.topBorder,
    required this.bottomBorder,
    required this.divider,
  });

  /// Creates a [ResolvedBorderStyle] with all borders set to `null` (no box).
  const ResolvedBorderStyle.none()
    : topBorder = null,
      bottomBorder = null,
      divider = null;
}
