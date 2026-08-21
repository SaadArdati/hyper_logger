import 'package:hyper_logger/hyper_logger.dart';
import 'package:test/test.dart';

void main() {
  group('LogMessage.copyWith', () {
    test('preserves omitted fields and replaces supplied fields', () {
      final data = Object();
      final stackTrace = StackTrace.current;
      final context = <String, Object?>{'requestId': 'request-1'};
      final time = DateTime.utc(2026);
      final original = LogMessage(
        'before',
        String,
        data: data,
        method: 'method',
        callerStackTrace: stackTrace,
        context: context,
        time: time,
        scopeTag: 'scope',
        reportToCrashReporting: true,
      );

      final copy = original.copyWith(message: 'after', type: int);

      expect(copy.message, 'after');
      expect(copy.type, int);
      expect(copy.data, same(data));
      expect(copy.method, 'method');
      expect(copy.callerStackTrace, same(stackTrace));
      expect(copy.context, same(context));
      expect(copy.time, time);
      expect(copy.scopeTag, 'scope');
      expect(copy.reportToCrashReporting, isTrue);
    });

    test('nullable fields can be explicitly replaced or cleared', () {
      final replacement = Object();
      final original = LogMessage(
        'message',
        String,
        data: Object(),
        method: 'method',
        callerStackTrace: StackTrace.current,
        context: const {'requestId': 'request-1'},
        time: DateTime.utc(2026),
        scopeTag: 'scope',
      );

      final copy = original.copyWith(
        data: () => replacement,
        method: () => null,
        callerStackTrace: () => null,
        context: () => null,
        time: () => null,
        scopeTag: () => null,
        reportToCrashReporting: true,
      );

      expect(copy.data, same(replacement));
      expect(copy.method, isNull);
      expect(copy.callerStackTrace, isNull);
      expect(copy.context, isNull);
      expect(copy.time, isNull);
      expect(copy.scopeTag, isNull);
      expect(copy.reportToCrashReporting, isTrue);
    });

    test('routing metadata defaults to false and can be reset', () {
      const ordinary = LogMessage('ordinary', String);
      const routed = LogMessage('routed', String, reportToCrashReporting: true);

      expect(ordinary.reportToCrashReporting, isFalse);
      expect(
        routed.copyWith(reportToCrashReporting: false).reportToCrashReporting,
        isFalse,
      );
    });
  });
}
