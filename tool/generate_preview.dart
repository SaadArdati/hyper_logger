// ignore_for_file: avoid_print
import 'package:hyper_logger/hyper_logger.dart';

// ── Stub classes for meaningful type names in previews ───────────────────────

class AuthService {}

class TokenManager {}

class ApiClient {}

class Database {}

class AppBootstrap {}

class PortfolioCubit {}

class OrderService {}

class TickHandler {}

class CacheManager {}

class CoffeeTracker {}

class PaymentService {}

class NoisyService {}

class Api {}

class ImageCache {}

/// Generates sample log output for README screenshots.
///
/// Usage:
///   dart run tool/generate_preview.dart `preset`
///
/// Presets: terminal, ide, ci, json, custom_colors, custom_box, data,
///          stacktrace, full, throttled, hero
void main(List<String> args) {
  final preset = args.isNotEmpty ? args.first : 'terminal';

  switch (preset) {
    case 'terminal':
      _demoComposable(LogPrinterPresets.terminal());

    case 'ide':
      // Renders the IDE Run Console shape: ANSI color but no box
      // (line widths unknown). Replaces the old `LogPrinterPresets.ide()`
      // preset with the equivalent capability-based composition.
      _demoComposable(
        LogPrinterPresets.human(
          const TerminalCapabilities(ansi: true, tty: false),
        ),
      );

    case 'ci':
      _demoComposable(LogPrinterPresets.ci());

    case 'json':
      _demoJson(GcpJsonPrinter());

    case 'custom_colors':
      _demoCustomColors();

    case 'custom_box':
      _demoComposable(
        ComposablePrinter(const [
          BoxDecorator(lineLength: 80),
          EmojiDecorator(),
          PrefixDecorator(),
        ]),
      );

    case 'data':
      _demoData(LogPrinterPresets.terminal());

    case 'stacktrace':
      _demoStacktrace(LogPrinterPresets.terminal());

    case 'full':
      _demoFull(LogPrinterPresets.terminal());

    case 'throttled':
      _demoThrottled();

    case 'hero':
      _demoHero();

    case 'doc_data':
      _demoDocData();

    case 'doc_scoped':
      _demoDocScoped();

    case 'doc_scoped_silent':
      _demoDocScopedSilent();

    case 'doc_minlevel':
      _demoDocMinLevel();

    case 'doc_mixin':
      _demoDocMixin();

    default:
      print('Unknown preset: $preset');
      print(
        'Available: terminal, ide, ci, json, custom_colors, custom_box, '
        'data, stacktrace, full, throttled, hero, '
        'doc_data, doc_scoped, doc_scoped_silent, doc_minlevel, doc_mixin',
      );
  }
}

// ── Demos ────────────────────────────────────────────────────────────────────

void _demoComposable(ComposablePrinter printer) {
  final entries = [
    _entry(LogLevel.info, 'User logged in successfully', AuthService, 'login'),
    _entry(LogLevel.debug, 'Token refreshed', TokenManager, 'refresh'),
    _entry(
      LogLevel.warning,
      'Rate limit approaching threshold',
      ApiClient,
      'request',
    ),
    _entry(
      LogLevel.error,
      'Query failed after 3 retries',
      Database,
      'executeQuery',
    ),
    _entry(
      LogLevel.fatal,
      'Required migration failed',
      AppBootstrap,
      'runMigrations',
    ),
  ];

  for (final entry in entries) {
    for (final line in printer.format(entry)) {
      print(line);
    }
  }
}

void _demoCustomColors() {
  final printer = ComposablePrinter(const [
    EmojiDecorator(),
    AnsiColorDecorator(),
    BoxDecorator(lineLength: 100),
    PrefixDecorator(),
  ]);

  final entries = [
    _entryWithData(
      LogLevel.info,
      'Positions loaded',
      PortfolioCubit,
      'load',
      {'count': 12, 'totalValue': 45230.50, 'currency': 'USD'},
    ),
    _entry(
      LogLevel.warning,
      'Rate limit approaching threshold',
      ApiClient,
      'request',
    ),
    LogEntry(
      level: LogLevel.error,
      message: 'Query failed after 3 retries',
      object: LogMessage(
        'Query failed after 3 retries',
        Database,
        method: 'executeQuery',
      ),
      loggerName: 'Database',
      time: DateTime(2026, 4, 6, 10, 30, 0),
      error: StateError('Connection timed out after 5000ms'),
      stackTrace: _fakeStackTrace,
    ),
  ];

  for (final entry in entries) {
    for (final line in printer.format(entry)) {
      print(line);
    }
  }
}

void _demoJson(GcpJsonPrinter printer) {
  final entries = [
    _entry(LogLevel.info, 'User logged in successfully', AuthService, 'login'),
    _entry(LogLevel.warning, 'Rate limit approaching', ApiClient, 'request'),
    _entryWithData(
      LogLevel.info,
      'Positions loaded',
      PortfolioCubit,
      'load',
      {'count': 12, 'totalValue': 45230.50},
    ),
    _entryWithError(
      LogLevel.error,
      'Request failed',
      ApiClient,
      'fetch',
      'TimeoutException: 5000ms',
    ),
  ];

  for (final entry in entries) {
    for (final line in printer.format(entry)) {
      print(line);
    }
  }
}

void _demoData(ComposablePrinter printer) {
  final entry = _entryWithData(
    LogLevel.info,
    'Portfolio positions loaded',
    PortfolioCubit,
    'load',
    {
      'positions': 12,
      'totalValue': 45230.50,
      'currency': 'USD',
      'lastUpdated': '2026-04-06T10:30:00Z',
    },
  );
  for (final line in printer.format(entry)) {
    print(line);
  }

  final errorEntry = LogEntry(
    level: LogLevel.error,
    message: 'Failed to parse API response',
    object: LogMessage(
      'Failed to parse API response',
      ApiClient,
      method: 'parseJson',
    ),
    loggerName: 'ApiClient',
    time: DateTime(2026, 4, 6, 10, 30, 1),
    error: const FormatException('Unexpected character at position 42'),
  );
  for (final line in printer.format(errorEntry)) {
    print(line);
  }
}

void _demoStacktrace(ComposablePrinter printer) {
  final entry = LogEntry(
    level: LogLevel.error,
    message: 'Failed to parse API response',
    object: LogMessage(
      'Failed to parse API response',
      ApiClient,
      method: 'parseJson',
    ),
    loggerName: 'ApiClient',
    time: DateTime(2026, 4, 6, 10, 30, 0),
    error: const FormatException('Unexpected character at position 42'),
    stackTrace: _fakeStackTrace,
  );
  for (final line in printer.format(entry)) {
    print(line);
  }
}

void _demoFull(ComposablePrinter printer) {
  final entry = LogEntry(
    level: LogLevel.error,
    message: 'Order processing failed',
    object: LogMessage(
      'Order processing failed',
      OrderService,
      method: 'processOrder',
      data: {
        'orderId': 'ORD-2026-04-001',
        'userId': 'usr_abc123',
        'amount': 149.99,
        'currency': 'USD',
        'items': 3,
      },
    ),
    loggerName: 'OrderService',
    time: DateTime(2026, 4, 6, 10, 30, 0),
    error: StateError('Payment gateway timeout after 5000ms'),
    stackTrace: _fakeStackTrace,
  );
  for (final line in printer.format(entry)) {
    print(line);
  }
}

void _demoThrottled() {
  final inner = DirectPrinter();
  final throttled = ThrottledPrinter(inner, maxPerSecond: 3, maxQueueSize: 5);

  for (var i = 0; i < 20; i++) {
    throttled.log(
      _entry(
        LogLevel.info,
        'Tick $i | bid=1.${1000 + i}',
        TickHandler,
        'onTick',
      ),
    );
  }
  throttled.flush();
}

void _demoHero() {
  void header(String title) {
    print('');
    print('\x1B[1;37m  $title\x1B[0m');
    print('');
  }

  header('Terminal');
  final ComposablePrinter terminal = LogPrinterPresets.terminal();
  for (final e in _heroEntries()) {
    for (final line in terminal.format(e)) {
      print(line);
    }
  }

  header('IDE');
  final ComposablePrinter ide = LogPrinterPresets.human(
    const TerminalCapabilities(ansi: true, tty: false),
  );
  for (final e in _heroEntries()) {
    for (final line in ide.format(e)) {
      print(line);
    }
  }

  header('CI');
  final ComposablePrinter ci = LogPrinterPresets.ci();
  for (final e in _heroEntries()) {
    for (final line in ci.format(e)) {
      print(line);
    }
  }

  header('Cloud Run / JSON');
  final json = GcpJsonPrinter();
  for (final e in _heroEntries().take(3)) {
    for (final line in json.format(e)) {
      print(line);
    }
  }
}

// ── Doc-specific demos ──────────────────────────────────────────────────────

void _demoDocData() {
  final printer = LogPrinterPresets.terminal();
  final entry = _entryWithData(
    LogLevel.info,
    'Daily intake logged',
    CoffeeTracker,
    'track',
    {
      'cups': 4,
      'regret': false,
      'productivity': 'questionable',
    },
  );
  for (final line in printer.format(entry)) {
    print(line);
  }
}

void _demoDocScoped() {
  final printer = LogPrinterPresets.terminal();
  // PaymentService with tag
  final entry1 = LogEntry(
    level: LogLevel.info,
    message: '[payments] Payment processed',
    object: LogMessage(
      '[payments] Payment processed',
      PaymentService,
      method: 'process',
    ),
    loggerName: 'PaymentService',
    time: DateTime(2026, 4, 6, 10, 30, 0),
  );
  // Api with stripe tag
  final entry2 = LogEntry(
    level: LogLevel.info,
    message: '[stripe] Webhook received',
    object: LogMessage(
      '[stripe] Webhook received',
      Api,
      method: 'handleWebhook',
    ),
    loggerName: 'Api',
    time: DateTime(2026, 4, 6, 10, 30, 1),
  );
  // Api with sendgrid tag
  final entry3 = LogEntry(
    level: LogLevel.info,
    message: '[sendgrid] Email queued',
    object: LogMessage(
      '[sendgrid] Email queued',
      Api,
      method: 'sendEmail',
    ),
    loggerName: 'Api',
    time: DateTime(2026, 4, 6, 10, 30, 2),
  );
  for (final e in [entry1, entry2, entry3]) {
    for (final line in printer.format(e)) {
      print(line);
    }
  }
}

void _demoDocScopedSilent() {
  // Show what the crash reporting service receives (text-only, no ANSI)
  print('Console: (nothing)');
  print('');
  print('Crash reporting receives:');
  print('  [stripe] rate limited');
}

void _demoDocMinLevel() {
  final printer = LogPrinterPresets.terminal();
  // Only the error gets through (warning is below minLevel: error)
  final entry = _entry(
    LogLevel.error,
    'connection lost',
    NoisyService,
    'connect',
  );
  print('// minLevel: LogLevel.error');
  print('// log.warning(\'rate limited\')  → filtered out');
  print('// log.error(\'connection lost\') → output + delegate:');
  print('');
  for (final line in printer.format(entry)) {
    print(line);
  }
}

void _demoDocMixin() {
  final printer = LogPrinterPresets.terminal();
  final entry = LogEntry(
    level: LogLevel.info,
    message: 'Login attempt',
    object: LogMessage(
      'Login attempt',
      AuthService,
      method: 'login',
      data: {'email': 'user@example.com'},
    ),
    loggerName: 'AuthService',
    time: DateTime(2026, 4, 6, 10, 30, 0),
  );
  for (final line in printer.format(entry)) {
    print(line);
  }
}

// ── Shared entries ───────────────────────────────────────────────────────────

List<LogEntry> _heroEntries() => [
  _entry(LogLevel.info, 'User logged in', AuthService, 'login'),
  _entry(LogLevel.warning, 'Rate limit approaching', ApiClient, 'request'),
  _entry(LogLevel.error, 'Query failed', Database, 'execute'),
];

// ── Fake stack trace for demos (avoids showing generate_preview.dart frames) ─

final _fakeStackTrace = StackTrace.fromString(
  '#0      Database.executeQuery (package:myapp/src/database.dart:142:11)\n'
  '#1      UserRepository.findById (package:myapp/src/repositories/user_repo.dart:58:23)\n'
  '#2      AuthService.login (package:myapp/src/services/auth_service.dart:31:17)\n'
  '#3      LoginController.handleSubmit (package:myapp/src/controllers/login.dart:22:9)',
);

// ── Entry factories ──────────────────────────────────────────────────────────

LogEntry _entry(LogLevel level, String message, Type type, String method) {
  return LogEntry(
    level: level,
    message: message,
    object: LogMessage(message, type, method: method),
    loggerName: type.toString(),
    time: DateTime(2026, 4, 6, 10, 30, 0),
  );
}

LogEntry _entryWithData(
  LogLevel level,
  String message,
  Type type,
  String method,
  Map<String, Object> data,
) {
  return LogEntry(
    level: level,
    message: message,
    object: LogMessage(message, type, method: method, data: data),
    loggerName: type.toString(),
    time: DateTime(2026, 4, 6, 10, 30, 0),
  );
}

LogEntry _entryWithError(
  LogLevel level,
  String message,
  Type type,
  String method,
  String error,
) {
  return LogEntry(
    level: level,
    message: message,
    object: LogMessage(message, type, method: method),
    loggerName: type.toString(),
    time: DateTime(2026, 4, 6, 10, 30, 0),
    error: error,
  );
}
