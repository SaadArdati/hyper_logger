import '../decorators/log_decorator.dart';
import '../extraction/caller_extractor.dart';
import '../extraction/content_extractor.dart';
import '../extraction/stack_trace_parser.dart';
import '../model/log_entry.dart';
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
/// LogEntry
///   → ContentExtractor.extract()   (parse sections, className, methodName)
///   → StyleResolver.resolve*()     (map LogStyle flags → ResolvedStyle)
///   → LogRenderer.render()         (assemble lines)
/// ```
///
/// ### Output
/// [output] defaults to [print] and can be overridden for testing.
class ComposablePrinter implements LogPrinter {
  /// Default number of stack-trace frames rendered for a non-error log.
  ///
  /// Exposed so callers that wrap this constructor — `LogPrinterPresets`
  /// in particular — can mirror the default in their own signatures
  /// instead of hardcoding a second copy of the number.
  static const int defaultMethodCount = 10;

  /// The decorators applied at construction to build [style].
  final List<LogDecorator> decorators;

  /// The merged [LogStyle] produced by applying all [decorators].
  ///
  /// Frozen after construction; do not mutate.
  late final LogStyle style;

  /// Sink for formatted lines. Defaults to [print].
  final LogOutput output;

  late final ContentExtractor _extractor;
  late final StyleResolver _resolver;
  late final LogRenderer _renderer;

  /// Tuning for the extraction stage:
  ///
  /// - [methodCount] — stack frames rendered for a normal log. `0`
  ///   skips stack rendering entirely.
  /// - [errorMethodCount] — frames rendered when the entry carries an
  ///   error; falls back to [methodCount] when null, so normal logs can
  ///   stay terse while failures get a deep trace.
  /// - [excludePaths] — libraries whose frames are dropped, on top of
  ///   the always-excluded `package:logging/` and `package:hyper_logger/`.
  ///   An entry matches a library exactly or as a directory prefix, so
  ///   write `'package:noisy'`, not `'package:noisy/'`.
  /// - [showAsyncGaps] — separate the traces of a chain with an
  ///   `asynchronous gap` row instead of splicing them together.
  /// - [suppressTypeNames] — skip rendering `Type.toString()` into the
  ///   class-name section, for builds where type names are minified.
  ///   Defaults to [ContentExtractor.defaultSuppressTypeNames].
  ComposablePrinter(
    this.decorators, {
    int methodCount = defaultMethodCount,
    int? errorMethodCount,
    List<String> excludePaths = const [],
    bool showAsyncGaps = false,
    bool? suppressTypeNames,
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
      suppressTypeNames:
          suppressTypeNames ?? ContentExtractor.defaultSuppressTypeNames,
    );
    _resolver = StyleResolver();
    _renderer = LogRenderer(sectionRenderer: const SectionRenderer());
  }

  @override
  void log(LogEntry entry) {
    final lines = format(entry);
    for (int i = 0; i < lines.length; i++) {
      output(lines[i]);
    }
  }

  /// Formats [entry] into a flat list of output lines without emitting them.
  ///
  /// Useful for testing and for printers that buffer output.
  List<String> format(LogEntry entry) {
    final extraction = _extractor.extract(entry);
    return _renderer.render(extraction, style, _resolver);
  }

  @override
  void dispose() {
    /* stateless extraction/rendering */
  }
}
