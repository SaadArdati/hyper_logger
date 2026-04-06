import '../extraction/content_extractor.dart';
import '../model/log_level.dart';
import '../model/log_section.dart';
import '../model/log_style.dart';
import 'section_renderer.dart';
import 'style_resolver.dart';

/// Orchestrates the rendering of a complete log entry.
///
/// [LogRenderer] iterates over all [ExtractionResult.sections], delegates
/// per-line formatting to [SectionRenderer], and wraps the output with any
/// borders produced by [StyleResolver].
class LogRenderer {
  final SectionRenderer sectionRenderer;

  const LogRenderer({required this.sectionRenderer});

  /// Renders [extraction] into a flat list of output lines.
  List<String> render(
    ExtractionResult extraction,
    LogStyle style,
    StyleResolver resolver,
  ) {
    final buffer = <String>[];
    final borderStyle = resolver.resolveBorder(style, extraction.level);

    final String? timestampStr = style.timestamp
        ? _formatTimestamp(extraction.time, extraction.level, style)
        : null;

    final sections = <LogSection>[
      if (timestampStr != null && style.box)
        LogSection(SectionKind.timestamp, [timestampStr]),
      ...extraction.sections,
    ];

    final bool inlineTimestamp = timestampStr != null && !style.box;

    if (borderStyle.topBorder != null) buffer.add(borderStyle.topBorder!);

    for (int i = 0; i < sections.length; i++) {
      final section = sections[i];
      final resolved = resolver.resolve(
        style: style,
        kind: section.kind,
        level: extraction.level,
        className: extraction.className,
        methodName: extraction.methodName,
      );
      final renderedLines = sectionRenderer.render(section, resolved);
      buffer.addAll(renderedLines);

      if (borderStyle.divider != null && i < sections.length - 1) {
        buffer.add(borderStyle.divider!);
      }
    }

    if (borderStyle.bottomBorder != null) buffer.add(borderStyle.bottomBorder!);

    if (inlineTimestamp && buffer.isNotEmpty) {
      buffer[0] = '$timestampStr ${buffer[0]}';
    }

    return buffer;
  }

  String _formatTimestamp(DateTime time, LogLevel level, LogStyle style) {
    final formatter =
        style.dateTimeFormatter ?? (DateTime dt) => dt.toIso8601String();
    return '${formatter(time)} [${level.label}]';
  }
}
