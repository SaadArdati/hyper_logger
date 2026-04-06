import 'dart:convert';

import 'package:stack_trace/stack_trace.dart';

import '../model/log_entry.dart';
import '../model/log_level.dart';
import '../model/log_message.dart';
import '../model/log_section.dart';
import 'caller_extractor.dart';
import 'stack_trace_parser.dart';

/// The structured output of a single [ContentExtractor.extract] call.
class ExtractionResult {
  final List<LogSection> sections;
  final String? className;
  final String? methodName;
  final LogLevel level;

  /// The timestamp from the original [LogEntry].
  final DateTime time;

  const ExtractionResult({
    required this.sections,
    required this.level,
    required this.time,
    this.className,
    this.methodName,
  });
}

/// Performs a single-pass parse of a [LogEntry] into an
/// [ExtractionResult] with pre-split [LogSection]s.
///
/// All expensive work (JSON serialisation, stack-trace parsing, caller
/// extraction) happens here and only here. Everything downstream works
/// with pre-parsed data.
/// True in release/production mode where Type.toString() returns minified names.
const bool _isReleaseMode = bool.fromEnvironment('dart.vm.product');

class ContentExtractor {
  final StackTraceParser stackTraceParser;
  final CallerExtractor callerExtractor;

  const ContentExtractor({
    required this.stackTraceParser,
    required this.callerExtractor,
  });

  ExtractionResult extract(LogEntry entry) {
    final object = entry.object;
    final sections = <LogSection>[];
    String? className;
    String? methodName;

    if (object is LogMessage) {
      // ── message section ──────────────────────────────────────────────────
      sections.add(
        LogSection(SectionKind.message, _splitLines(object.message)),
      );

      // ── data section ─────────────────────────────────────────────────────
      final data = object.data;
      if (data != null) {
        sections.add(LogSection(SectionKind.data, _formatData(data)));
      }

      // ── className / methodName ────────────────────────────────────────────
      // In release mode (dart2js), Type.toString() returns minified names.
      // Skip type rendering to avoid garbled output.
      if (!_isReleaseMode) {
        final typeName = object.type.toString();
        if (typeName != 'dynamic' && typeName != 'Object') {
          className = typeName;
        }
      }

      methodName = object.method;
      if (methodName == null) {
        final callerStack = object.callerStackTrace;
        if (callerStack != null) {
          // Parse the chain once, reuse for caller extraction.
          final callerChain = callerStack is Chain
              ? callerStack
              : Chain.forTrace(callerStack);
          final info = callerExtractor.extract(
            callerStack,
            prebuiltChain: callerChain,
          );
          if (info != null) {
            className ??= info.className;
            methodName = info.methodName;
          }
        }
      }
    } else {
      // Plain string (or anything with a usable toString)
      sections.add(LogSection(SectionKind.message, _splitLines(entry.message)));
    }

    // ── error section ────────────────────────────────────────────────────────
    final error = entry.error;
    if (error != null) {
      sections.add(LogSection(SectionKind.error, [error.toString()]));
    }

    // ── stackTrace section ───────────────────────────────────────────────────
    final stackTrace = entry.stackTrace;
    if (stackTrace != null) {
      // Parse the chain once, share with parser.
      final chain = stackTrace is Chain
          ? stackTrace
          : Chain.forTrace(stackTrace);
      final stLines = stackTraceParser.parse(
        stackTrace,
        isError: error != null,
        prebuiltChain: chain,
      );
      if (stLines.isNotEmpty) {
        sections.add(LogSection(SectionKind.stackTrace, stLines));
      }
    }

    return ExtractionResult(
      sections: sections,
      level: entry.level,
      time: entry.time,
      className: className,
      methodName: methodName,
    );
  }

  /// Formats [data] for display.
  ///
  /// Maps and [Iterable]s are pretty-printed as JSON. Anything that cannot be
  /// encoded falls back to [Object.toString]. Other values use [toString]
  /// directly.
  List<String> _formatData(Object data) {
    if (data is Map || data is Iterable) {
      try {
        final encoder = JsonEncoder.withIndent(
          '  ',
          (o) => o.toString(), // fallback for non-encodable values
        );
        return _splitLines(encoder.convert(data));
      } catch (_) {
        return [data.toString()];
      }
    }
    return [data.toString()];
  }

  /// Splits [s] by newlines, with a fast path for the common single-line case.
  ///
  /// Avoids the List allocation overhead of [String.split] when the string
  /// contains no newlines (~90% case for log messages).
  static List<String> _splitLines(String s) {
    if (!s.contains('\n')) return [s];
    return s.split('\n');
  }
}
