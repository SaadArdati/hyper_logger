# Testing

`HyperLogger` is static. If you don't clean up between tests, state
leaks: printers carry over, delegates fire unexpectedly, cached scoped
loggers from one test affect another. This page covers how to keep your
tests clean and how to verify logging behavior.

## Always call `reset()` in setUp/tearDown

```dart
void main() {
  setUp(() => HyperLogger.reset());
  tearDown(() => HyperLogger.reset());
}
```

`reset()` clears everything: the printer, mode, log filter, crash
reporting delegate, stream subscription, and both internal caches
(per-type loggers and scoped logger instances). After `reset()`, the
next log call will re-initialize with platform defaults.

## Suppressing output in tests

If you just want logging to be quiet during tests, you have two options:

**`LogMode.silent`**: Suppresses printer output, but delegates still
fire. Use this if you need to test crash reporting behavior:

```dart
setUp(() {
  HyperLogger.init(mode: LogMode.silent);
});
```

**`LogMode.disabled`**: Total no-op. No output, no delegates, no work.
Use this when you don't care about logging at all and just want it out
of the way:

```dart
setUp(() {
  HyperLogger.init(mode: LogMode.disabled);
});
```

## Capturing output for assertions

Use `DirectPrinter` with a list as the output sink. Every log call
appends the raw message to the list:

```dart
test('logs the expected message', () {
  final captured = <String>[];
  HyperLogger.init(printer: DirectPrinter(output: captured.add));

  HyperLogger.info<MyClass>('hello');

  expect(captured, hasLength(1));
  expect(captured.first, contains('hello'));
});
```

A helper function keeps this clean across many tests:

```dart
List<String> initCapturing({LogMode mode = LogMode.enabled}) {
  final captured = <String>[];
  HyperLogger.init(
    printer: DirectPrinter(output: captured.add),
    mode: mode,
  );
  return captured;
}

test('example', () {
  final captured = initCapturing();
  HyperLogger.info<String>('test');
  expect(captured, isNotEmpty);
});
```

## Inspecting LogEntry details

`DirectPrinter` only gives you the message string. If you need to
inspect the full `LogEntry` (level, logger name, timestamp, error,
stack trace), use a recording printer:

```dart
class RecordingPrinter implements LogPrinter {
  final List<LogEntry> entries = [];

  @override
  void log(LogEntry entry) => entries.add(entry);
}

test('logs at the correct level', () {
  final printer = RecordingPrinter();
  HyperLogger.init(printer: printer);

  HyperLogger.warning<AuthService>('Token expired');

  expect(printer.entries, hasLength(1));
  expect(printer.entries.first.level, equals(LogLevel.warning));
  expect(printer.entries.first.loggerName, equals('AuthService'));
});
```

To access structured data, cast the `object` field:

```dart
test('captures structured data', () {
  final printer = RecordingPrinter();
  HyperLogger.init(printer: printer);

  HyperLogger.info<String>('event', data: {'count': 42});

  final logMsg = printer.entries.first.object as LogMessage;
  expect(logMsg.data, equals({'count': 42}));
});
```

## Testing crash reporting delegates

Use a recording test double:

```dart
class FakeCrashReporting implements CrashReportingDelegate {
  final logs = <String>[];
  final errors = <(Object, StackTrace?, bool, String?)>[];

  @override
  Future<void> log(String message) async => logs.add(message);

  @override
  Future<void> recordError(Object error, StackTrace? stackTrace,
      {bool fatal = false, String? reason}) async =>
      errors.add((error, stackTrace, fatal, reason));
}
```

Attach it and verify:

```dart
test('warning fires crash delegate', () async {
  final crash = FakeCrashReporting();
  HyperLogger.init(printer: DirectPrinter(output: (_) {}));
  HyperLogger.attachServices(crashReporting: crash);

  HyperLogger.warning<MyClass>('uh oh');
  await Future<void>.delayed(Duration.zero);

  expect(crash.logs, contains('uh oh'));
});

test('error fires recordError', () async {
  final crash = FakeCrashReporting();
  HyperLogger.init(printer: DirectPrinter(output: (_) {}));
  HyperLogger.attachServices(crashReporting: crash);

  final exception = Exception('broken');
  HyperLogger.error<MyClass>('failed', exception: exception);
  await Future<void>.delayed(Duration.zero);

  expect(crash.errors, hasLength(1));
  expect(crash.errors.first.$1, equals(exception));
  expect(crash.errors.first.$3, isFalse); // not fatal
});
```

The `await Future<void>.delayed(Duration.zero)` is important. Delegate
calls are fire-and-forget async operations. The microtask delay gives
them a chance to complete before you assert.

## Testing log filters

```dart
test('filter suppresses matching entries', () {
  final printer = RecordingPrinter();
  HyperLogger.init(
    printer: printer,
    logFilter: (entry) => entry.level.index >= LogLevel.warning.index,
  );

  HyperLogger.info<String>('filtered out');
  HyperLogger.warning<String>('passed through');

  expect(printer.entries, hasLength(1));
  expect(printer.entries.first.message, contains('passed through'));
});
```

## Mocking scoped loggers

`ScopedLoggerApi<T>` is an interface. Mock it directly, no mocking
library required:

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

test('logs work event', () {
  final mock = MockLogger();
  final service = MyService(scopedLogger: mock);
  service.doWork();
  expect(mock.infoCalls, contains('work started'));
});
```

## Testing scoped logger mode toggling

```dart
test('runtime mode change affects output', () {
  final printer = RecordingPrinter();
  HyperLogger.init(printer: printer);

  final log = HyperLogger.withOptions<String>(tag: 'test');

  log.info('before');
  expect(printer.entries, hasLength(1));

  log.mode = LogMode.disabled;
  log.info('during');
  expect(printer.entries, hasLength(1)); // unchanged

  log.mode = LogMode.enabled;
  log.info('after');
  expect(printer.entries, hasLength(2));
});
```
