// ignore_for_file: avoid_print
import 'package:hyper_logger/hyper_logger.dart';
import 'package:hyper_logger/src/platform/environment_detector.dart';

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
  print('=' * 80);
  print('  $title');
  print('=' * 80);
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
    (LogLevel.debug, 'Debug message', 'MyService', 'fetchData'),
    (LogLevel.info, 'User logged in successfully', 'AuthBloc', 'onLogin'),
    (LogLevel.warning, 'Rate limit approaching', 'ApiClient', 'request'),
    (LogLevel.error, 'Connection failed', 'WebSocket', 'connect'),
  ];

  for (final (level, msg, cls, method) in levels) {
    final logMsg = LogMessage(msg, String, method: method);
    final entry = LogEntry(
      level: level,
      message: msg,
      object: logMsg,
      loggerName: cls,
      time: DateTime.now(),
    );
    final lines = printer.format(entry);
    for (final line in lines) {
      print(line);
    }
  }

  // One with data
  print('');
  print('  -- with structured data --');
  print('');
  final withData = LogMessage(
    'Fetched portfolio',
    String,
    method: 'load',
    data: {'positions': 12, 'totalValue': 45230.50, 'currency': 'USD'},
  );
  final dataEntry = LogEntry(
    level: LogLevel.info,
    message: 'Fetched portfolio',
    object: withData,
    loggerName: 'Portfolio',
    time: DateTime.now(),
  );
  for (final line in printer.format(dataEntry)) {
    print(line);
  }

  // One with error + stack trace
  print('');
  print('  -- with error --');
  print('');
  final errorEntry = LogEntry(
    level: LogLevel.error,
    message: 'Failed to parse response',
    object: LogMessage('Failed to parse response', String, method: 'parseJson'),
    loggerName: 'ApiClient',
    time: DateTime.now(),
    error: FormatException('Unexpected character at position 42'),
    stackTrace: StackTrace.current,
  );
  for (final line in printer.format(errorEntry)) {
    print(line);
  }
}

void _jsonDemo(JsonPrinter printer) {
  final levels = [
    (LogLevel.debug, 'Debug message', 'MyService', 'fetchData'),
    (LogLevel.info, 'User logged in successfully', 'AuthBloc', 'onLogin'),
    (LogLevel.warning, 'Rate limit approaching', 'ApiClient', 'request'),
    (LogLevel.error, 'Connection failed', 'WebSocket', 'connect'),
  ];

  for (final (level, msg, cls, method) in levels) {
    final logMsg = LogMessage(msg, String, method: method);
    final entry = LogEntry(
      level: level,
      message: msg,
      object: logMsg,
      loggerName: cls,
      time: DateTime.now(),
    );
    final lines = printer.format(entry);
    for (final line in lines) {
      print(line);
    }
  }
}
