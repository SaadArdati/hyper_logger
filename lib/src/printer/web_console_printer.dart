import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../extraction/stack_trace_parser.dart';
import '../model/log_entry.dart';
import '../model/log_level.dart';
import '../model/log_message.dart';
import '../rendering/style_resolver.dart';
import 'log_printer.dart';

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

  late final StackTraceParser _stackParser;

  WebConsolePrinter({this.methodCount = 8, this.errorMethodCount}) {
    _stackParser = StackTraceParser(
      methodCount: methodCount,
      errorMethodCount: errorMethodCount,
      excludePaths: const [],
      showAsyncGaps: false,
    );
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
    final message = entry.object ?? entry.message;

    if (message is LogMessage) {
      _logStructured(entry, message);
    } else {
      _logAtLevel(entry.level, message.toString());
    }
  }

  /// Logs a structured [LogMessage] entry using a collapsible group.
  void _logStructured(LogEntry entry, LogMessage message) {
    final label = _buildLabel(entry.level, message);

    // Colored collapsible header via %c.
    _styledGroupCollapsed('%c$label'.toJS, _headerCss(entry.level).toJS);

    // Message text.
    web.console.log(message.message.toJS);

    // Structured data as a native expandable JS object.
    if (message.data != null) {
      _logData(message.data!);
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
  void _logData(Object data) {
    if (data is Map) {
      final jsObj = <String, JSAny?>{};
      for (final entry in data.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        jsObj[key] = switch (value) {
          num v => v.toJS,
          bool v => v.toJS,
          String v => v.toJS,
          _ => value.toString().toJS,
        };
      }
      web.console.dir(jsObj.jsify());
    } else {
      try {
        final encoder = JsonEncoder.withIndent(
          '  ',
          (object) => object.toString(),
        );
        web.console.log(encoder.convert(data).toJS);
      } catch (_) {
        web.console.log(data.toString().toJS);
      }
    }
  }

  // ── Label ────────────────────────────────────────────────────────────────

  /// Builds a concise label for the collapsed group header.
  ///
  /// Format: `<emoji> [Type.method] message`
  String _buildLabel(LogLevel level, LogMessage message) {
    final emoji = level.emoji;
    final buffer = StringBuffer();
    if (emoji.isNotEmpty) {
      buffer.write('$emoji ');
    }

    final runtimeType = message.type.toString();
    if (runtimeType != 'dynamic' && runtimeType != 'Object') {
      buffer.write('[$runtimeType');
      if (message.method != null) {
        buffer.write('.${message.method}');
      }
      buffer.write('] ');
    } else if (message.method != null) {
      buffer.write('[${message.method}] ');
    }

    buffer.write(message.message);
    return buffer.toString();
  }
}
