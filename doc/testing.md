# Testing

## Suppressing output in tests

Use `LogMode.silent` (delegates still fire) or `LogMode.disabled` (total no-op):

```dart
void main() {
  setUp(() {
    HyperLogger.init(mode: LogMode.silent);
  });

  tearDown(() {
    HyperLogger.reset(); // Clean slate for each test
  });
}
```

## Capturing output for assertions

Use `DirectPrinter` with a list as the output sink:

```dart
test('logs the expected message', () {
  final captured = <String>[];
  HyperLogger.init(printer: DirectPrinter(output: captured.add));

  HyperLogger.info<MyClass>('hello');

  expect(captured.join(), contains('hello'));
});
```

## Mocking scoped loggers

`ScopedLoggerApi<T>` is an interface — mock it directly:

```dart
class MockLogger implements ScopedLoggerApi<MyService> {
  final infoCalls = <String>[];
  final errorCalls = <String>[];

  @override
  void info(String msg, {Object? data, String? method}) => infoCalls.add(msg);

  @override
  void error(String message, {Object? exception, StackTrace? stackTrace,
    Object? data, String? method, bool? skipCrashReporting}) =>
      errorCalls.add(message);

  // ... implement remaining methods
}
```

Inject via constructor or override `scopedLogger` in the mixin:

```dart
class MyService with HyperLoggerMixin<MyService> {
  @override
  final ScopedLoggerApi<MyService>? scopedLogger;

  MyService({this.scopedLogger});
}

// In test:
final mock = MockLogger();
final service = MyService(scopedLogger: mock);
service.doWork();
expect(mock.infoCalls, contains('work started'));
```

## Testing delegate behavior

Use recording test doubles:

```dart
class FakeCrashReporting extends CrashReportingDelegate {
  final logs = <String>[];
  final errors = <(Object, StackTrace?, bool, String?)>[];

  @override
  Future<void> log(String message) async => logs.add(message);

  @override
  Future<void> recordError(Object error, StackTrace? stackTrace,
      {bool fatal = false, String? reason}) async =>
      errors.add((error, stackTrace, fatal, reason));
}

test('warning fires crash delegate', () async {
  final crash = FakeCrashReporting();
  HyperLogger.init(printer: DirectPrinter(output: (_) {}));
  HyperLogger.attachServices(crashReporting: crash);

  HyperLogger.warning<MyClass>('uh oh');
  await Future<void>.delayed(Duration.zero);

  expect(crash.logs, contains('uh oh'));
});
```

## Important: always call `reset()` in tearDown

`HyperLogger` is static. Without `reset()`, state leaks between tests:

```dart
setUp(() => HyperLogger.reset());
tearDown(() => HyperLogger.reset());
```
