// ignore_for_file: avoid_print
import 'package:hyper_logger/hyper_logger.dart';

/// Example: using HyperLoggerMixin with scoped loggers.
///
/// Run: dart run example/mixin_example.dart
void main() {
  HyperLogger.init(printer: LogPrinterPresets.ide());

  final service = PaymentService();
  service.processPayment('order-123', 49.99);

  print('');

  final simple = SimpleService();
  simple.doWork();
}

/// A service that uses the mixin with a scoped logger for per-class
/// tag and configuration.
class PaymentService with HyperLoggerMixin<PaymentService> {
  @override
  final scopedLogger = HyperLogger.withOptions<PaymentService>(tag: 'payments');

  void processPayment(String orderId, double amount) {
    logInfo('Processing payment', data: {'orderId': orderId, 'amount': amount});
    logDebug('Connecting to payment gateway');

    // Simulate success
    logInfo('Payment completed');

    // Measure performance
    final sw = Stopwatch()..start();
    _simulateWork();
    sw.stop();
    logStopwatch('Gateway round-trip', sw);
  }

  void _simulateWork() {
    // Simulate some work
    var sum = 0;
    for (var i = 0; i < 100000; i++) {
      sum += i;
    }
    assert(sum >= 0); // prevent dead code elimination
  }
}

/// A simple service that uses the mixin without a scoped logger.
/// Falls back to HyperLogger static methods.
class SimpleService with HyperLoggerMixin<SimpleService> {
  void doWork() {
    logInfo('Starting work');
    logDebug('Processing step 1');
    logInfo('Work complete');
  }
}
