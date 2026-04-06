import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../model/log_entry.dart';
import '../model/log_level.dart';
import '../model/log_message.dart';
import 'log_printer.dart';

/// Chrome DevTools-native log printer.
///
/// Routes log levels to the correct `console.*` methods so Chrome DevTools
/// can filter by Verbose / Info / Warning / Error. Uses
/// `console.groupCollapsed` for structured [LogMessage] entries instead of
/// box-drawing characters.
class WebConsolePrinter implements LogPrinter {
  /// Maps [LogLevel] to the appropriate `console.*` method.
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
      final label = _buildLabel(entry.level, message);
      web.console.groupCollapsed(label.toJS);

      _logAtLevel(entry.level, message.message);

      if (message.data != null) {
        try {
          final encoder = JsonEncoder.withIndent(
            '  ',
            (object) => object.toString(),
          );
          _logAtLevel(entry.level, encoder.convert(message.data));
        } catch (_) {
          _logAtLevel(entry.level, message.data.toString());
        }
      }

      if (entry.stackTrace != null) {
        web.console.error(entry.stackTrace.toString().toJS);
      }

      web.console.groupEnd();
    } else {
      _logAtLevel(entry.level, message.toString());
    }
  }

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
