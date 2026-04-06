/// hyper_logger — quick start example.
///
/// Run: dart run example/example.dart
library;

import 'package:hyper_logger/hyper_logger.dart';

// ── Simple usage ─────────────────────────────────────────────────────────────

/// The type parameter is always optional. Without it you still get the
/// method name extracted from the stack trace.
void simplestUsage() {
  HyperLogger.info('Server started on port 8080');
  HyperLogger.debug('Cache warmed', data: {'entries': 42});
}

/// Add a type parameter to include the class name in the prefix.
void withTypeParameter() {
  HyperLogger.info<AuthService>('User logged in');
  HyperLogger.warning<AuthService>('Token expires in 5 minutes');
  HyperLogger.error<AuthService>(
    'Login failed',
    exception: Exception('Invalid credentials'),
  );
}

// ── Scoped loggers ───────────────────────────────────────────────────────────

/// Scoped loggers add tags, level filters, and runtime mode toggling.
void scopedLoggerExample() {
  final log = HyperLogger.withOptions<NoisyService>(
    minLevel: LogLevel.warning,
    tag: 'noisy',
  );

  log.info('This is filtered out'); // no-op (below minLevel)
  log.warning('This gets through'); // only warnings and above

  // Toggle at runtime (e.g. from a feature flag or debug menu)
  log.mode = LogMode.disabled;
  log.error('This is completely suppressed');
}

// ── Mixin ────────────────────────────────────────────────────────────────────

/// Mix into any class for instance-method logging.
class AuthService with HyperLoggerMixin<AuthService> {
  void login(String user) {
    logInfo('User $user logged in');
    // Output: 💡 [AuthService.login] User alice logged in
  }

  void failedAttempt(String user) {
    logWarning('Failed login attempt for $user');
  }
}

/// Override scopedLogger for per-class config.
class PaymentService with HyperLoggerMixin<PaymentService> {
  @override
  final scopedLogger = HyperLogger.withOptions<PaymentService>(
    tag: 'payments',
    minLevel: LogLevel.info,
  );

  void process(String orderId) {
    logInfo('Processing order $orderId');
    // Output: 💡 [PaymentService.process] [payments] Processing order ORD-001
  }
}

// ── Structured data ──────────────────────────────────────────────────────────

void structuredDataExample() {
  HyperLogger.info<PortfolioService>(
    'Positions loaded',
    data: {'count': 12, 'totalValue': 45230.50, 'currency': 'USD'},
  );

  HyperLogger.error<ApiClient>(
    'Request failed',
    exception: Exception('Connection timeout after 5000ms'),
    stackTrace: StackTrace.current,
    data: {'endpoint': '/api/v1/positions', 'retries': 3},
  );
}

// ── Custom printer ───────────────────────────────────────────────────────────

/// Compose your own printer from decorators. Order doesn't matter.
void customPrinterExample() {
  HyperLogger.init(
    printer: ComposablePrinter([
      const EmojiDecorator(),
      const AnsiColorDecorator(),
      const BoxDecorator(lineLength: 100),
      const TimestampDecorator(),
      const PrefixDecorator(),
    ]),
  );

  HyperLogger.info<CustomPrinterDemo>('Using a custom decorator stack');
  HyperLogger.error<CustomPrinterDemo>('Errors get full box treatment');
}

// ── Rate limiting ────────────────────────────────────────────────────────────

void throttledExample() {
  HyperLogger.init(
    printer: ThrottledPrinter(LogPrinterPresets.terminal(), maxPerSecond: 30),
  );

  // Hot loop — only 30 entries/sec reach the console, rest are queued.
  for (var i = 0; i < 100; i++) {
    HyperLogger.info<TickHandler>('Tick $i');
  }
}

// ── Main ─────────────────────────────────────────────────────────────────────

void main() {
  // Zero config — just start logging.
  simplestUsage();

  withTypeParameter();

  scopedLoggerExample();

  final auth = AuthService();
  auth.login('alice');
  auth.failedAttempt('bob');

  final payments = PaymentService();
  payments.process('ORD-001');

  structuredDataExample();

  // Re-init with custom printer to show decorator composition.
  customPrinterExample();

  // Re-init with throttling to show rate limiting.
  throttledExample();
}

// ── Dummy types for the examples ─────────────────────────────────────────────

class NoisyService {}

class PortfolioService {}

class ApiClient {}

class CustomPrinterDemo {}

class TickHandler {}
