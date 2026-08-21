import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../extraction/caller_extractor.dart';
import '../extraction/stack_trace_parser.dart';
import '../model/log_entry.dart';
import '../model/log_level.dart';
import '../model/log_message.dart';
import '../rendering/style_resolver.dart';
import 'log_printer.dart';
import 'logger_name_filter.dart';

// ── Custom @JS bindings ────────────────────────────────────────────────────
// The standard `package:web` Console bindings only accept a single argument.
// These expose the variadic overloads needed for `%c` CSS styling.

/// `console.groupCollapsed` with two args for `%c` CSS styling.
@JS('console.groupCollapsed')
external void _styledGroupCollapsed(JSString format, JSString css);

/// `console.log` with two args for `%c` CSS styling.
@JS('console.log')
external void _styledLog(JSString format, JSString css);

/// Chrome DevTools-native log printer for web platforms.
///
/// Uses `%c` CSS styling on `console.groupCollapsed` (via custom `@JS`
/// bindings) to give group headers severity-appropriate colors derived
/// from [StyleResolver.defaultLevelColors]. Body content uses:
///
/// - `console.log` for message text (no auto-appended Chrome call stack)
/// - `console.dir` for structured data (native expandable object tree)
/// - `%c`-styled `console.log` for exceptions (red text)
/// - [StackTraceParser]-formatted text for stack traces (aligned columns,
///   internal frames filtered)
///
/// This printer is the default on web platforms (see `printer_factory_web.dart`).
/// On native platforms, [ComposablePrinter] with environment-detected presets
/// is used instead.
class WebConsolePrinter implements LogPrinter {
  /// Maximum stack frames to display.
  final int methodCount;

  /// Maximum stack frames for error/fatal entries (falls back to
  /// [methodCount] when null).
  final int? errorMethodCount;

  /// When `true`, suppresses `LogEntry.loggerName` from the label header.
  /// `dart compile js` minifies type names in release builds while
  /// leaving `dart.vm.product` as `false` — set this explicitly to
  /// `true` in production web bundles to avoid `[c8.fn]`-style noise.
  final bool suppressTypeNames;

  late final StackTraceParser _stackParser;
  late final CallerExtractor _callerExtractor;

  WebConsolePrinter({
    this.methodCount = 8,
    this.errorMethodCount,
    this.suppressTypeNames = false,
  }) {
    _stackParser = StackTraceParser(
      methodCount: methodCount,
      errorMethodCount: errorMethodCount,
      excludePaths: const [],
      showAsyncGaps: false,
    );
    _callerExtractor = CallerExtractor();
  }

  // ── Styling ──────────────────────────────────────────────────────────────

  /// Web brightness multiplier for [StyleResolver.defaultLevelColors].
  ///
  /// The terminal palette uses very dark tints (e.g. `rgb(50,0,0)` for
  /// error). This factor lifts them to readable CSS badge backgrounds
  /// while preserving the same hue relationships.
  static const double _webBrightness = 1.5;

  /// CSS for the `%c`-styled group header badge.
  static String _headerCss(LogLevel level) {
    final color = StyleResolver.defaultLevelColors[level]!.withBrightness(
      _webBrightness,
    );
    return 'color: #fff; background: ${color.hex};'
        ' padding: 1px 5px; border-radius: 3px';
  }

  /// CSS for `%c`-styled exception text — same palette as the header
  /// badge but used inline for the error message.
  static String get _errorCss {
    final color = StyleResolver.defaultLevelColors[LogLevel.error]!
        .withBrightness(_webBrightness);
    return 'color: #fff; background: ${color.hex};'
        ' padding: 1px 4px; border-radius: 2px; font-weight: bold';
  }

  // ── Logging ──────────────────────────────────────────────────────────────

  /// Maps [LogLevel] to the appropriate `console.*` method.
  ///
  /// Used only for non-[LogMessage] entries (plain strings) where no
  /// group is needed.
  void _logAtLevel(LogLevel level, String message) {
    final js = message.toJS;
    switch (level) {
      case LogLevel.error || LogLevel.fatal:
        web.console.error(js);
      case LogLevel.warning:
        web.console.warn(js);
      case LogLevel.info:
        web.console.log(js);
      case LogLevel.trace || LogLevel.debug:
        web.console.debug(js);
    }
  }

  @override
  void log(LogEntry entry) {
    final message = entry.object;

    if (message is LogMessage) {
      _logStructured(entry, message);
    } else {
      _logAtLevel(entry.level, entry.message);
    }
  }

  /// Logs a structured [LogMessage] entry using a collapsible group.
  void _logStructured(LogEntry entry, LogMessage message) {
    final label = _buildLabel(entry, message);

    // Colored collapsible header via %c.
    _styledGroupCollapsed('%c$label'.toJS, _headerCss(entry.level).toJS);

    // Message text.
    web.console.log(entry.message.toJS);

    // Structured data as a native expandable JS object.
    if (message.data != null) {
      _logData(message.data!);
    }

    // Render request-scoped context (`child(context: {...})`) alongside
    // `data` so Flutter Web users adopting the child API see
    // `requestId` etc. in DevTools — parity with the cloud printers
    // and `ComposablePrinter`.
    final context = message.context;
    if (context != null && context.isNotEmpty) {
      _logData(context);
    }

    // Exception in red via %c.
    if (entry.error != null) {
      _styledLog('%c${entry.error}'.toJS, _errorCss.toJS);
    }

    // Stack trace — aligned columns, internal frames filtered.
    if (entry.stackTrace != null) {
      final isError =
          entry.level == LogLevel.error || entry.level == LogLevel.fatal;
      final frames = _stackParser.parse(entry.stackTrace, isError: isError);
      if (frames.isNotEmpty) {
        web.console.log('\n${frames.join('\n')}'.toJS);
      }
    }

    web.console.groupEnd();
  }

  /// Logs structured data as a native expandable JS object via
  /// `console.dir`, or falls back to JSON text for non-Map data.
  /// Nested maps and iterables retain their tree shape so DevTools'
  /// object inspector can drill in.
  void _logData(Object data) {
    if (data is Map || data is Iterable) {
      web.console.dir(_jsify(data, <Object>{}));
    } else {
      try {
        web.console.log(_dataEncoder.convert(data).toJS);
      } catch (_) {
        web.console.log(data.toString().toJS);
      }
    }
  }

  static final JsonEncoder _dataEncoder = JsonEncoder.withIndent(
    '  ',
    (object) => object.toString(),
  );

  /// Recursively converts Dart values to JS-friendly forms preserving
  /// nesting: maps and iterables retain structure; primitives box via
  /// `.toJS`; everything else stringifies.
  ///
  /// `seen` tracks Map/Iterable instances on the current descent path.
  /// A back-reference renders as the literal string `"<cycle>"` so a
  /// self-referencing payload doesn't stack-overflow the tab.
  JSAny? _jsify(Object? value, Set<Object> seen) {
    if (value == null) return null;
    if (value is num) return value.toJS;
    if (value is bool) return value.toJS;
    if (value is String) return value.toJS;
    if (value is Map) {
      if (!seen.add(value)) return '<cycle>'.toJS;
      try {
        final out = <String, JSAny?>{};
        for (final e in value.entries) {
          out[e.key.toString()] = _jsify(e.value, seen);
        }
        return out.jsify();
      } finally {
        seen.remove(value);
      }
    }
    if (value is Iterable) {
      if (!seen.add(value)) return '<cycle>'.toJS;
      try {
        return value.map((v) => _jsify(v, seen)).toList().jsify();
      } finally {
        seen.remove(value);
      }
    }
    return value.toString().toJS;
  }

  // ── Label ────────────────────────────────────────────────────────────────

  /// Builds a concise label for the collapsed group header.
  ///
  /// Format: `<emoji> [Type.method] message`
  ///
  /// When `HyperLogger.<level>(...)` is called without a type argument,
  /// `loggerName` is the placeholder `'dynamic'` / `'Object'` / `'Null'`;
  /// the bracket is dropped (matching `PrefixDecorator`) and a caller
  /// is extracted from the captured stack trace via [CallerExtractor]
  /// so the "method extracted from stack trace" behavior is honored
  /// on web too.
  String _buildLabel(LogEntry entry, LogMessage message) {
    final emoji = entry.level.emoji;
    final buffer = StringBuffer();
    if (emoji.isNotEmpty) {
      buffer.write('$emoji ');
    }

    final hasUsefulType =
        !suppressTypeNames && !isGenericLoggerName(entry.loggerName);

    String? method = message.method;
    String? className = hasUsefulType ? entry.loggerName : null;

    // If the user didn't provide a method and we have a stack trace
    // captured by HyperLogger, try to extract the caller info.
    if (method == null) {
      final callerStack = message.callerStackTrace;
      if (callerStack != null) {
        final info = _callerExtractor.extract(callerStack);
        if (info != null) {
          className ??= info.className;
          method = info.methodName;
        }
      }
    }

    if (className != null && method != null) {
      buffer.write('[$className.$method] ');
    } else if (className != null) {
      buffer.write('[$className] ');
    } else if (method != null) {
      buffer.write('[$method] ');
    }

    buffer.write(entry.message);
    return buffer.toString();
  }

  @override
  void dispose() {
    /* stateless */
  }
}
