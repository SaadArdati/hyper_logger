import '../model/log_section.dart';
import '../model/resolved_style.dart';

/// Renders a single [LogSection] into a list of styled output lines.
///
/// Emoji and bracket prefixes apply only to the first line of a multi-line
/// section. Subsequent lines inherit the same [linePrefix], text color, and
/// background color but drop the emoji and bracket prefix so they form a clean
/// continuation block.
class SectionRenderer {
  const SectionRenderer();

  /// Renders a section's lines with resolved style applied.
  /// Emoji and bracket prefixes apply only to the FIRST line.
  /// Uses direct for-loops, no .map().toList().
  List<String> render(LogSection section, ResolvedSectionStyle style) {
    final lines = section.lines;
    if (lines.isEmpty) return const [];

    final result = <String>[];

    // First line: full style (emoji + bracket + colors).
    result.add(style.apply(lines[0]));

    // Remaining lines: same style minus emoji and bracket prefix.
    if (lines.length > 1) {
      final continuationStyle = ResolvedSectionStyle(
        linePrefix: style.linePrefix,
        emojiPrefix: null,
        bracketPrefix: null,
        textColor: style.textColor,
        bgColor: style.bgColor,
      );
      for (int i = 1; i < lines.length; i++) {
        result.add(continuationStyle.apply(lines[i]));
      }
    }

    return result;
  }
}
