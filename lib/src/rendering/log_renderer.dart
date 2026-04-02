import 'package:logging/logging.dart' as logging;

import '../extraction/content_extractor.dart';
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
  ///
  /// Layout:
  /// 1. Top border (when box is enabled)
  /// 2. Timestamp section (when [LogStyle.timestamp] is true) — always first
  /// 3. Per-section rendered lines, each separated by a divider (when boxed)
  /// 4. Bottom border (when box is enabled)
  List<String> render(
    ExtractionResult extraction,
    LogStyle style,
    StyleResolver resolver,
  ) {
    final buffer = <String>[];
    final borderStyle = resolver.resolveBorder(style, extraction.level);

    // When timestamp is enabled AND box is off, prefix the timestamp onto
    // the first message line so CI log aggregators see one event per line.
    // When boxed, render timestamp as its own section (visually separated).
    final String? timestampStr = style.timestamp
        ? _formatTimestamp(extraction.time, extraction.level, style)
        : null;

    final sections = <LogSection>[
      if (timestampStr != null && style.box)
        LogSection(SectionKind.timestamp, [timestampStr]),
      ...extraction.sections,
    ];

    // For non-boxed timestamps, we prepend the timestamp to the first
    // message line after rendering (see below).
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

    // Inline timestamp: prepend to first line so CI sees one event per line.
    if (inlineTimestamp && buffer.isNotEmpty) {
      buffer[0] = '$timestampStr ${buffer[0]}';
    }

    return buffer;
  }

  /// Formats the timestamp string including the severity tag.
  ///
  /// Uses [LogStyle.dateTimeFormatter] when available, otherwise ISO 8601.
  /// Always appends `[LEVEL]` for machine-parseable output.
  String _formatTimestamp(DateTime time, logging.Level level, LogStyle style) {
    final formatter =
        style.dateTimeFormatter ?? (DateTime dt) => dt.toIso8601String();
    return '${formatter(time)} [${_levelName(level)}]';
  }

  /// Maps a [logging.Level] to a short, human-readable severity name.
  static String _levelName(logging.Level level) {
    if (level >= logging.Level.SHOUT) return 'FATAL';
    if (level >= logging.Level.SEVERE) return 'ERROR';
    if (level >= logging.Level.WARNING) return 'WARN';
    if (level >= logging.Level.INFO) return 'INFO';
    if (level >= logging.Level.FINE) return 'DEBUG';
    return 'TRACE';
  }
}
