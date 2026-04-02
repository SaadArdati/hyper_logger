import 'package:logging/logging.dart' as logging;

import '../decorators/log_decorator.dart';
import '../extraction/caller_extractor.dart';
import '../extraction/content_extractor.dart';
import '../extraction/stack_trace_parser.dart';
import '../model/log_style.dart';
import '../rendering/log_renderer.dart';
import '../rendering/section_renderer.dart';
import '../rendering/style_resolver.dart';
import 'log_printer.dart';

/// A [LogPrinter] that formats records through a composable decorator pipeline.
///
/// ### Construction
/// [decorators] are applied to a fresh [LogStyle] at construction time.  The
/// resulting [style] is immutable for the lifetime of the printer — mutation
/// after construction is not supported.
///
/// ### Pipeline
/// ```
/// LogRecord
///   → ContentExtractor.extract()   (parse sections, className, methodName)
///   → StyleResolver.resolve*()     (map LogStyle flags → ResolvedStyle)
///   → LogRenderer.render()         (assemble lines)
/// ```
///
/// ### Output
/// [output] defaults to [print] and can be overridden for testing.
class ComposablePrinter implements LogPrinter {
  /// The decorators applied at construction to build [style].
  final List<LogDecorator> decorators;

  /// The merged [LogStyle] produced by applying all [decorators].
  ///
  /// Frozen after construction; do not mutate.
  late final LogStyle style;

  /// Sink for formatted lines. Defaults to [print].
  final void Function(String) output;

  late final ContentExtractor _extractor;
  late final StyleResolver _resolver;
  late final LogRenderer _renderer;

  ComposablePrinter(
    this.decorators, {
    int methodCount = 10,
    int? errorMethodCount,
    List<String> excludePaths = const [],
    bool showAsyncGaps = false,
    this.output = print,
  }) {
    style = LogStyle();
    for (int i = 0; i < decorators.length; i++) {
      decorators[i].apply(style);
    }
    _extractor = ContentExtractor(
      stackTraceParser: StackTraceParser(
        methodCount: methodCount,
        errorMethodCount: errorMethodCount,
        excludePaths: excludePaths,
        showAsyncGaps: showAsyncGaps,
      ),
      callerExtractor: CallerExtractor(),
    );
    _resolver = StyleResolver();
    _renderer = LogRenderer(sectionRenderer: const SectionRenderer());
  }

  @override
  void log(logging.LogRecord record) {
    final lines = format(record);
    for (int i = 0; i < lines.length; i++) {
      output(lines[i]);
    }
  }

  /// Formats [record] into a flat list of output lines without emitting them.
  ///
  /// Useful for testing and for printers that buffer output.
  List<String> format(logging.LogRecord record) {
    final extraction = _extractor.extract(record);
    return _renderer.render(extraction, style, _resolver);
  }
}
