import 'dart:convert';
import 'dart:js_interop';

import 'package:logging/logging.dart' as logging;
import 'package:web/web.dart' as web;

import '../model/log_message.dart';
import 'log_printer.dart';

/// Chrome DevTools-native log printer.
///
/// Routes log levels to the correct `console.*` methods so Chrome DevTools
/// can filter by Verbose / Info / Warning / Error. Uses
/// `console.groupCollapsed` for structured [LogMessage] entries instead of
/// box-drawing characters.
class WebConsolePrinter implements LogPrinter {
  /// Maps [logging.Level] to the appropriate `console.*` method.
  void _logAtLevel(logging.Level level, String message) {
    final js = message.toJS;
    if (level >= logging.Level.SEVERE) {
      web.console.error(js);
    } else if (level >= logging.Level.WARNING) {
      web.console.warn(js);
    } else if (level >= logging.Level.INFO) {
      web.console.log(js);
    } else {
      // FINE, FINER, FINEST → console.debug (Verbose in Chrome, hidden by default)
      web.console.debug(js);
    }
  }

  @override
  void log(logging.LogRecord record) {
    final message = record.object ?? record.message;

    // For LogMessage objects, use groupCollapsed for structured output.
    if (message is LogMessage) {
      final label = _buildLabel(record.level, message);
      web.console.groupCollapsed(label.toJS);

      // Message body
      _logAtLevel(record.level, message.message);

      // Structured data (if present)
      if (message.data != null) {
        try {
          final encoder = JsonEncoder.withIndent(
            '  ',
            (object) => object.toString(),
          );
          _logAtLevel(record.level, encoder.convert(message.data));
        } catch (_) {
          _logAtLevel(record.level, message.data.toString());
        }
      }

      // Stack trace (if error/fatal)
      if (record.stackTrace != null) {
        web.console.error(record.stackTrace.toString().toJS);
      }

      web.console.groupEnd();
    } else {
      // Simple string message — log directly at the appropriate level.
      _logAtLevel(record.level, message.toString());
    }
  }

  /// Builds a concise label for the collapsed group header.
  ///
  /// Format: `<emoji> [Type.method] message`
  String _buildLabel(logging.Level level, LogMessage message) {
    final emoji = _emojiForLevel(level);
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

  String _emojiForLevel(logging.Level level) {
    if (level >= logging.Level.SHOUT) return '👾';
    if (level >= logging.Level.SEVERE) return '⛔';
    if (level >= logging.Level.WARNING) return '⚠️';
    if (level >= logging.Level.INFO) return '💡';
    if (level >= logging.Level.FINE) return '🐛';
    return '';
  }
}
