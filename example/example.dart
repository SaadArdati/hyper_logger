// ignore_for_file: avoid_print
import 'package:hyper_logger/hyper_logger.dart';
import 'package:logging/logging.dart' as logging;

/// Run: dart run example/demo.dart
/// Or from repo root: dart run packages/hyper_logger/example/demo.dart
void main() {
  _section('AUTOMATIC PRESET (best-effort environment detection)');
  print('  Detected environment: ${const EnvironmentDetector().detect().name}');
  print('');
  _demoPrinter(LogPrinterPresets.automatic());

  _section('TERMINAL PRESET (emoji + box + bg colors + prefix)');
  _demo(LogPrinterPresets.terminal());

  _section('IDE PRESET (emoji + prefix, no ANSI)');
  _demo(LogPrinterPresets.ide());

  _section('CI PRESET (timestamp + prefix, no formatting)');
  _demo(LogPrinterPresets.ci());

  _section('CLOUD RUN PRESET (JSON structured logging)');
  _jsonDemo(LogPrinterPresets.cloudRun());

  _section('CUSTOM: emoji + colors, no box');
  _demo(
    ComposablePrinter([
      const EmojiDecorator(),
      const AnsiColorDecorator(),
      const PrefixDecorator(),
    ]),
  );

  _section('CUSTOM: box + emoji, no colors');
  _demo(
    ComposablePrinter([
      const BoxDecorator(lineLength: 80),
      const EmojiDecorator(),
      const PrefixDecorator(),
    ]),
  );

  _section('CUSTOM: colors only, no emoji, no box');
  _demo(
    ComposablePrinter([const AnsiColorDecorator(), const PrefixDecorator()]),
  );

  _section('CUSTOM: everything + timestamp');
  _demo(
    ComposablePrinter([
      const EmojiDecorator(),
      const BoxDecorator(lineLength: 100),
      const AnsiColorDecorator(),
      const PrefixDecorator(),
      const TimestampDecorator(),
    ]),
  );

  _section('BARE: no decorators at all');
  _demo(ComposablePrinter([]));
}

void _section(String title) {
  print('');
  print('═' * 80);
  print('  $title');
  print('═' * 80);
  print('');
}

void _demoPrinter(LogPrinter printer) {
  if (printer is ComposablePrinter) {
    _demo(printer);
  } else if (printer is JsonPrinter) {
    _jsonDemo(printer);
  }
}

void _demo(ComposablePrinter printer) {
  final levels = [
    (logging.Level.FINE, 'Debug message', 'MyService', 'fetchData'),
    (logging.Level.INFO, 'User logged in successfully', 'AuthBloc', 'onLogin'),
    (logging.Level.WARNING, 'Rate limit approaching', 'ApiClient', 'request'),
    (logging.Level.SEVERE, 'Connection failed', 'WebSocket', 'connect'),
  ];

  for (final (level, msg, cls, method) in levels) {
    final logMsg = LogMessage(msg, String, method: method);
    // Fake the className by putting it in the message prefix
    final record = logging.LogRecord(level, msg, cls, null, null, null, logMsg);
    final lines = printer.format(record);
    for (final line in lines) {
      print(line);
    }
  }

  // One with data
  print('');
  print('  ── with structured data ──');
  print('');
  final withData = LogMessage(
    'Fetched portfolio',
    String,
    method: 'load',
    data: {'positions': 12, 'totalValue': 45230.50, 'currency': 'USD'},
  );
  final dataRecord = logging.LogRecord(
    logging.Level.INFO,
    'Fetched portfolio',
    'Portfolio',
    null,
    null,
    null,
    withData,
  );
  for (final line in printer.format(dataRecord)) {
    print(line);
  }

  // One with error + stack trace
  print('');
  print('  ── with error ──');
  print('');
  final errorRecord = logging.LogRecord(
    logging.Level.SEVERE,
    'Failed to parse response',
    'ApiClient',
    FormatException('Unexpected character at position 42'),
    StackTrace.current,
    null,
    LogMessage('Failed to parse response', String, method: 'parseJson'),
  );
  for (final line in printer.format(errorRecord)) {
    print(line);
  }
}

void _jsonDemo(JsonPrinter printer) {
  final levels = [
    (logging.Level.FINE, 'Debug message', 'MyService', 'fetchData'),
    (logging.Level.INFO, 'User logged in successfully', 'AuthBloc', 'onLogin'),
    (logging.Level.WARNING, 'Rate limit approaching', 'ApiClient', 'request'),
    (logging.Level.SEVERE, 'Connection failed', 'WebSocket', 'connect'),
  ];

  for (final (level, msg, cls, method) in levels) {
    final logMsg = LogMessage(msg, String, method: method);
    final record = logging.LogRecord(level, msg, cls, null, null, null, logMsg);
    final lines = printer.format(record);
    for (final line in lines) {
      print(line);
    }
  }
}
