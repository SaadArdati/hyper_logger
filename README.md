# hyper_logger

Composable, beautiful logging for Dart. Zero config. Every environment.

![hyper_logger output across environments](assets/preview_hero.png)

## Start logging in one line

```dart
import 'package:hyper_logger/hyper_logger.dart';

HyperLogger.info('Server started on port 8080');
```

No init call. No setup. It auto-detects your environment and picks
the right output format. The method name is extracted from the stack
trace automatically.

### Add a type parameter for richer output

```dart
HyperLogger.info<AuthService>('User logged in');
HyperLogger.error<Database>('Query failed', exception: e, stackTrace: st);
```

The `<T>` type parameter adds the class name to the log prefix, turning
`[main] Server started` into `[AuthService.login] User logged in`. It's
always optional: omit it when you don't need it, add it when you do.

## Every environment, one API

`LogPrinterPresets.automatic()` detects GCP, AWS, CI, and human
and selects the best format:

**Terminal** (emoji + box + ANSI colors)
![Terminal](assets/preview_terminal.png)

**IDE Run Console** (emoji + ANSI color + prefix, no box)
![IDE](assets/preview_ide.png)

**CI** (timestamp + prefix, machine-parseable)
![CI](assets/preview_ci.png)

**Cloud Run / JSON** (structured, Cloud Logging compatible)
![JSON](assets/preview_json.png)

**Web** (DevTools groups with `%c` CSS styling, `console.dir` for data)
![Web Console](assets/preview_web_console.png)

Works on native, web, Flutter, and pure Dart.

## Compose your own

Decorators are order-independent. Just pick what you want:

```dart
ComposablePrinter([
  const EmojiDecorator(),
  const AnsiColorDecorator(),
  const BoxDecorator(lineLength: 100),
  const PrefixDecorator(),
]);
```

![Custom colors](assets/preview_custom_colors.png)

## Add logging to any class

```dart
class MyService with HyperLoggerMixin<MyService> {
  void doWork() => logInfo('working');
}
```

That's it. `logInfo`, `logError`, `logDebug`, etc. are available
immediately. The type parameter provides the class name in the prefix.

Want per-class config? Override `scopedLogger`:

```dart
class PaymentService with HyperLoggerMixin<PaymentService> {
  @override
  final scopedLogger = HyperLogger.withOptions<PaymentService>(
    tag: 'payments',
    minLevel: LogLevel.warning,
  );

  void process() {
    logInfo('Processing payment');
    // Output: 💡 [PaymentService.process] [payments] Processing payment
  }
}
```

## Structured data and errors

Pass `data:` for pretty-printed JSON. Errors and stack traces render
in-box with level-appropriate colors:

```dart
HyperLogger.info<Portfolio>('Positions loaded', data: {
  'count': 12,
  'totalValue': 45230.50,
  'currency': 'USD',
});
```

![Data and errors](assets/preview_data.png)

Full error with data + exception + stack trace:

![Full error](assets/preview_full.png)

## Scoped loggers

Per-feature tags, level filters, and runtime mode toggling. Cached and
mockable via `ScopedLoggerApi<T>`:

```dart
final log = HyperLogger.withOptions<NoisyService>(
  minLevel: LogLevel.warning,
  tag: 'noisy',
);
log.info('filtered out');     // no-op
log.warning('gets through');  // only warnings and above

log.mode = LogMode.disabled;  // toggle at runtime
```

## Crash reporting

Attach a delegate for Crashlytics or Sentry. It fires automatically on
`warning`, `error`, and `fatal` calls:

```dart
HyperLogger.attachServices(
  crashReporting: MyCrashReporter(),
);
```

The delegate fires even in `LogMode.silent` (output suppressed, reporting
active). See [example/crash_reporting_example.dart](example/crash_reporting_example.dart).

## Rate limiting

Put a log line in a `build()` method that triggers hundreds of times per
second, and your Dart process will freeze while the console tries to
catch up. `ThrottledPrinter` prevents this by rate-limiting any printer:

```dart
HyperLogger.init(
  printer: ThrottledPrinter(LogPrinterPresets.terminal(), maxPerSecond: 30),
);
```

## Request-scoped child loggers

Attach key-value context to every log call inside a unit of work
(request, transaction, job) without restating the data per call:

```dart
void handleRequest(Request req) {
  final log = HyperLogger.child<Handler>(context: {'requestId': req.id});
  log.info('Received');
  log.info('Authenticated', data: {'userId': req.user.id});
  // Both lines carry requestId; the second carries userId too.
}
```

`child(...)` is uncached — each call returns a fresh logger so per-request
state doesn't leak across unrelated requests. From inside a class, the
mixin shortcut works the same way:

```dart
class UserService with HyperLoggerMixin<UserService> {
  void handleRequest(Request req) {
    final log = child(context: {'requestId': req.id});
    log.info('Processing');
  }
}
```

Cloud-shaped printers (`GcpJsonPrinter`, `AwsJsonPrinter`) merge the
context into the JSON root so log aggregators can correlate by it.

## Interceptors: filter, redact, enrich, sample

`HyperLogger.init(interceptors: [...])` runs each entry through a chain
of `LogEntry? Function(LogEntry)` — return the entry to pass it through,
return `null` to drop it. A throwing interceptor is isolated and skipped
so one bad hook can't black-hole the pipeline.

```dart
HyperLogger.init(
  printer: LogPrinterPresets.automatic(),
  interceptors: [
    // 1. Drop noisy third-party logs entirely.
    (e) => e.loggerName.contains('GoTrue') ? null : e,
    // 2. Redact secrets from messages before they reach the printer.
    (e) => LogEntry(
      level: e.level,
      message: e.message.replaceAll(RegExp(r'token=\S+'), 'token=***'),
      object: e.object,
      loggerName: e.loggerName,
      time: e.time,
      error: e.error,
      stackTrace: e.stackTrace,
    ),
  ],
);
```

## File output with rotation

`RotatingFilePrinter` appends entries to a file with optional rotation
(by size or interval), gzip compression, and retention. Async path
providers are supported for Flutter (`path_provider`):

> Flutter snippet: depend on
> [`path_provider`](https://pub.dev/packages/path_provider) and add
> `import 'package:path_provider/path_provider.dart';`. The
> `RotatingFilePrinter` constructor itself does not transitively expose
> it.

```dart
final filePrinter = RotatingFilePrinter(
  baseFilePathProvider: () async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/logs/app.log';
  },
  rotationConfig: FileRotationConfig.size(
    maxBytes: 10 * 1024 * 1024,  // 10 MB
    maxFiles: 5,
    compress: true,
  ),
  onError: (error, stack) {
    // surface IO failures to your monitoring; default is stderr
  },
);

HyperLogger.init(printer: filePrinter);
// ... at shutdown:
await filePrinter.close();  // flushes pending writes + in-flight gzip
```

File output requires `dart:io`; on web the constructor throws
`UnsupportedError`.

## Fan-out to multiple sinks

`MultiPrinter` dispatches every entry to a list of child printers — use
it when you want, say, a pretty terminal view *and* a rotating file
archive at the same time:

```dart
HyperLogger.init(
  printer: MultiPrinter([
    LogPrinterPresets.terminal(),
    RotatingFilePrinter(
      baseFilePathProvider: () => '/var/log/app.log',
      rotationConfig: FileRotationConfig.size(
        maxBytes: 10 * 1024 * 1024,
        maxFiles: 5,
        compress: true,
      ),
    ),
  ]),
);
```

Children are isolated — a throwing child doesn't stop the others from
receiving the entry. After the fan-out, if anything threw, `MultiPrinter`
raises a `MultiPrinterError` that the package's pipeline-error hook
catches (`HyperLogger.setPipelineErrorHandler`), so a broken sink
surfaces instead of disappearing silently. `MultiPrinter` is itself a
`LogPrinter`, so it composes: wrap it in `ThrottledPrinter` to throttle
the whole fan-out, or throttle just one child and leave the others alone.

## Cloud platforms

Google Cloud Logging (`GcpJsonPrinter`), AWS CloudWatch (`AwsJsonPrinter`),
and Azure Application Insights (`AzureJsonPrinter`) are all first-class.
`LogPrinterPresets.automatic()` detects the runtime (GCP / AWS / Azure / CI)
and picks the right printer for you. To pin one explicitly:

```dart
HyperLogger.init(printer: LogPrinterPresets.aws());
// or .gcp(), or .azure()
```

For severity ≥ ERROR with both error and stack trace, the trace is
embedded into the cloud printer's `message` field so Cloud Error
Reporting (GCP), CloudWatch Logs Insights (AWS), and Application
Insights' search (Azure) auto-surface the exception. Azure's
printer additionally nests user `context` under `customDimensions`
to match the AppInsights `traces` table conventions.

## Install

```yaml
dependencies:
  hyper_logger: ^0.2.0
```

## Documentation

| Guide | |
|---|---|
| [Configuration](doc/configuration.md) | Log levels, log modes, printer presets, filtering, ANSI colors |
| [Custom printers](doc/custom_printers.md) | Printer interface, decorators, `ThrottledPrinter`, custom sinks |
| [Scoped loggers](doc/scoped_loggers.md) | Tags, level filters, mode toggling, caching |
| [HyperLoggerMixin](doc/mixin.md) | Mixin usage, delegation chain, scoped injection |
| [Delegates](doc/delegates.md) | Crash reporting, error safety, mode interaction |
| [Testing](doc/testing.md) | Suppressing output, capturing logs, mocking, test patterns |
| [Flutter integration](doc/flutter.md) | Error handling, `debugPrint`, build modes |
| [Firebase Crashlytics](doc/firebase.md) | Crashlytics delegate, init ordering, production main.dart |
| [Architecture](doc/architecture.md) | Pipeline design, internals, performance |

Examples: [quick start](example/example.dart) | [all presets](example/preset_showcase_example.dart) | [mixin](example/mixin_example.dart) | [crash reporting](example/crash_reporting_example.dart) | [file logging](example/file_logger_example.dart) | [buffered remote](example/buffered_remote_logger_example.dart)

## License

BSD 3-Clause. See [LICENSE](LICENSE).
