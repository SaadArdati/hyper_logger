# hyper_logger

Composable, decorator-driven logging for Dart with CSS-cascade-style resolution,
true-color ANSI output, and environment-aware presets.

Built on Dart's [`logging`](https://pub.dev/packages/logging) package.

---

## Why hyper_logger?

Most logging libraries force you to pick from a fixed set of formats. hyper_logger
takes a different approach: **decorators** write flags into a style property bag,
a **resolver** computes the final visual style, and **renderers** apply it. The
decorators are order-independent and compose freely, so you assemble exactly the
output you need without subclassing or forking.

```
LogRecord
  -> ContentExtractor.extract()   (parse sections, className, methodName)
  -> StyleResolver.resolve()      (map LogStyle flags -> ResolvedStyle)
  -> LogRenderer.render()         (assemble output lines)
```

## Features

- **Order-independent decorators** -- box borders, emoji, ANSI colors, timestamps, and type prefixes compose in any combination.
- **True-color (24-bit) ANSI** -- muted background colors per log level using `ESC[38;2;R;G;Bm` / `ESC[48;2;R;G;Bm`. Custom colors via `AnsiColor.fromRGB()` or `AnsiColor.fromHex()`.
- **Automatic class and method extraction** -- the type parameter `<T>` resolves the class name, and the call-site stack trace resolves the method name. No manual tagging required.
- **Environment auto-detection** -- `.automatic()` detects Cloud Run, CI, IDE, or terminal and selects the best preset. Used by default on native platforms.
- **Named presets** -- `.terminal()`, `.ide()`, `.ci()`, `.cloudRun()` cover the most common environments in one call.
- **Structured JSON output** -- `JsonPrinter` emits one JSON object per line, compatible with Google Cloud Logging severity mapping.
- **Web-native console output** -- `WebConsolePrinter` routes to `console.log` / `console.warn` / `console.error` and uses `console.groupCollapsed` for structured entries. Auto-selected on web platforms.
- **Crash reporting and analytics delegates** -- attach a `CrashReportingDelegate` or `AnalyticsDelegate` to forward warnings, errors, and performance events to services like Crashlytics or Firebase Analytics.
- **Silent mode** -- suppress all output in tests without tearing down the logger tree. Costs 9ns per call.
- **Auto-initialization** -- no mandatory `init()` call; the logger bootstraps with platform defaults on first use.
- **`HyperLoggerMixin`** -- mix into any class for `logInfo`, `logDebug`, `logWarning`, `logError`, and `logStopwatch` methods that carry the host class's type automatically.
- **`HyperLoggerWrapper`** -- per-feature logger instances with rich `LoggerOptions`: disable, per-wrapper log level, tags, default crash-reporting behavior. Cached by type + options.
- **Performance-first** -- single extraction pass, pure style resolver, cached logger instances per type. Disabled loggers cost 5ns.
- **Platform-adaptive** -- conditional import selects `LogPrinterPresets.automatic()` on native and `WebConsolePrinter` on web.

## Quick start

### Zero-config usage

Call any static method on `HyperLogger`. It auto-initializes with the platform
default printer on first use:

```dart
import 'package:hyper_logger/hyper_logger.dart';

void main() {
  HyperLogger.info<App>('Application started');
  HyperLogger.debug<AuthService>('Token refreshed', data: {'expiresIn': 3600});
  HyperLogger.warning<ApiClient>('Rate limit approaching');
  HyperLogger.error<Database>(
    'Query failed',
    exception: StateError('connection closed'),
    stackTrace: StackTrace.current,
  );
}
```

Terminal preset output:

```
┌──────────────────────────────────────────────────────────────────────────
│ 💡 [App.main] Application started
└──────────────────────────────────────────────────────────────────────────
┌──────────────────────────────────────────────────────────────────────────
│ 🐛 [AuthService.main] Token refreshed
├┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
│ {
│   "expiresIn": 3600
│ }
└──────────────────────────────────────────────────────────────────────────
┌──────────────────────────────────────────────────────────────────────────
│ ⚠️ [ApiClient.main] Rate limit approaching
└──────────────────────────────────────────────────────────────────────────
┌──────────────────────────────────────────────────────────────────────────
│ ⛔ [Database.main] Query failed
├┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
│ Bad state: connection closed
├┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
│ #0  main    package:my_app/main.dart  12:5
│ #1  ...
└──────────────────────────────────────────────────────────────────────────
```

### Automatic class and method names

The generic type parameter `<T>` automatically becomes the class name prefix.
When no explicit `method` is passed, hyper_logger extracts the calling method
name from the stack trace at the call site:

```dart
class PortfolioCubit {
  void loadPositions() {
    HyperLogger.info<PortfolioCubit>('Fetching positions');
    // Output: 💡 [PortfolioCubit.loadPositions] Fetching positions
    //              ^^^^^^^^^^^^^^^               ^^^^^^^^^^^^^^^
    //              from <T>                      from stack trace
  }
}
```

You can also provide the method name explicitly to skip the stack trace capture
(slightly faster):

```dart
HyperLogger.info<ApiClient>('Request sent', method: 'fetchUser');
// Output: 💡 [ApiClient.fetchUser] Request sent
```

### Explicit initialization

Choose a preset or build a custom printer:

```dart
void main() {
  HyperLogger.init(
    printer: LogPrinterPresets.terminal(),
  );

  HyperLogger.info<App>('Ready');
}
```

## Presets

Each preset returns a ready-to-use `LogPrinter` for a specific environment:

| Preset                          | Type                | Decorators                        | Best for           |
|---------------------------------|---------------------|-----------------------------------|--------------------|
| `LogPrinterPresets.automatic()` | (varies)            | best-effort environment detection | Default / unknown  |
| `LogPrinterPresets.terminal()`  | `ComposablePrinter` | emoji + box + ANSI color + prefix | Local dev terminal |
| `LogPrinterPresets.ide()`       | `ComposablePrinter` | emoji + prefix                    | IDE run console    |
| `LogPrinterPresets.ci()`        | `ComposablePrinter` | timestamp + prefix                | CI/CD log streams  |
| `LogPrinterPresets.cloudRun()`  | `JsonPrinter`       | structured JSON per line          | Google Cloud Run   |

```dart
// Auto-detect -- picks the best preset for the current environment
HyperLogger.init(printer: LogPrinterPresets.automatic());

// Or pick explicitly
HyperLogger.init(printer: LogPrinterPresets.ci());
HyperLogger.init(printer: LogPrinterPresets.cloudRun());
```

**IDE preset output:**

```
💡 [AuthBloc.onLogin] User logged in successfully
⚠️ [ApiClient.request] Rate limit approaching
```

**CI preset output:**

```
2026-04-02T10:30:00.000Z [INFO] [AuthBloc.onLogin] User logged in successfully
2026-04-02T10:30:01.000Z [WARN] [ApiClient.request] Rate limit approaching
```

**Cloud Run preset output (JSON):**

```json
{"severity":"INFO","message":"User logged in successfully","timestamp":"2026-04-02T10:30:00.000Z","logger":"AuthBloc"}
```

### Environment auto-detection

`LogPrinterPresets.automatic()` inspects environment variables and stdout
capabilities to select the best preset. This is the default on native platforms
when no printer is specified.

Detection order (first match wins):

| Priority | Signal                                                           | Selected preset                    |
|----------|------------------------------------------------------------------|------------------------------------|
| 1        | `K_SERVICE` env var                                              | `cloudRun` (JSON)                  |
| 2        | `CI`, `GITHUB_ACTIONS`, `GITLAB_CI`, `JENKINS_URL`, etc.         | `ci`                               |
| 3        | `IDEA_INITIAL_DIRECTORY`, `JETBRAINS_IDE`, `TERM_PROGRAM=vscode` | `ide`                              |
| 4        | ANSI escape code support detected                                | `terminal`                         |
| 5        | Fallback                                                         | plain (timestamp + emoji + prefix) |

You can query the detected environment directly:

```dart
final env = const EnvironmentDetector().detect();
print(env); // RuntimeEnvironment.terminal
```

## Custom composition

Build your own printer by combining decorators. Order does not matter -- each
decorator writes to a non-overlapping subset of `LogStyle` fields:

```dart
final printer = ComposablePrinter([
  const EmojiDecorator(),
  const AnsiColorDecorator(),
  const PrefixDecorator(),
]);

HyperLogger.init(printer: printer);
HyperLogger.info<App>('Started');
// Output: 💡 [App.main] Started
//         (with muted blue ANSI background, no box)
```

### Available decorators

| Decorator            | LogStyle fields                  | Effect                               |
|----------------------|----------------------------------|--------------------------------------|
| `BoxDecorator`       | `box`, `lineLength`              | Box-drawing border around each entry |
| `EmojiDecorator`     | `emoji`, `levelEmojis`           | Level-specific emoji prefix          |
| `AnsiColorDecorator` | `ansiColors`, `levelColors`      | 24-bit ANSI foreground/background    |
| `TimestampDecorator` | `timestamp`, `dateTimeFormatter` | ISO-8601 timestamp section           |
| `PrefixDecorator`    | `prefix`                         | `[ClassName.method]` bracket prefix  |

### Decorator customization

Override defaults by passing parameters to individual decorators:

```dart
final printer = ComposablePrinter([
  const EmojiDecorator(customEmojis: {Level.INFO: 'ℹ️ ', Level.SEVERE: '🔥 '}),
  AnsiColorDecorator(customLevelColors: {Level.WARNING: AnsiColor.fromHex('#FFA500')}),
  const BoxDecorator(lineLength: 100),
  const TimestampDecorator(),
  const PrefixDecorator(),
]);
```

## Log levels

hyper_logger maps Dart's `logging` levels to semantic convenience methods:

| Method                       | Level     | Delegates                                         |
|------------------------------|-----------|---------------------------------------------------|
| `HyperLogger.trace<T>()`     | `FINEST`  | --                                                |
| `HyperLogger.debug<T>()`     | `FINE`    | --                                                |
| `HyperLogger.info<T>()`      | `INFO`    | --                                                |
| `HyperLogger.warning<T>()`   | `WARNING` | `CrashReportingDelegate.log()`                    |
| `HyperLogger.error<T>()`     | `SEVERE`  | `CrashReportingDelegate.recordError()`            |
| `HyperLogger.fatal<T>()`     | `SHOUT`   | `CrashReportingDelegate.recordError(fatal: true)` |
| `HyperLogger.stopwatch<T>()` | `INFO`    | `AnalyticsDelegate.logPerformance()`              |

Set the global threshold:

```dart
HyperLogger.setLogLevel(Level.WARNING); // Only WARNING and above
```

## Structured data

Attach a `data` payload to any log call. Maps and iterables are pretty-printed
as indented JSON; other objects use `toString()`:

```dart
HyperLogger.info<Portfolio>('Positions loaded', data: {
  'count': 12,
  'totalValue': 45230.50,
  'currency': 'USD',
});
```

Terminal output:

```
┌──────────────────────────────────────────────────────────────────────────
│ 💡 [Portfolio.load] Positions loaded
├┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
│ {
│   "count": 12,
│   "totalValue": 45230.5,
│   "currency": "USD"
│ }
└──────────────────────────────────────────────────────────────────────────
```

## HyperLoggerMixin

Mix `HyperLoggerMixin<T>` into a class to get instance methods that carry the
type parameter automatically:

```dart
class AuthService with HyperLoggerMixin<AuthService> {
  void login(String email) {
    logInfo('Login attempt', data: {'email': email});
    // Output: 💡 [AuthService.login] Login attempt
    //         { "email": "user@example.com" }
  }
}
```

Available methods: `logInfo`, `logDebug`, `logWarning`, `logError`, `logStopwatch`.

## HyperLoggerWrapper

Use `HyperLogger.withOptions<T>()` to get a cached logger instance with rich
configuration via `LoggerOptions`. Useful for feature flags, per-module verbosity
control, and subsystem tagging:

```dart
class PaymentService {
  final log = HyperLogger.withOptions<PaymentService>(tag: 'payments');

  void process() {
    log.info('Processing payment');
    // Output: 💡 [PaymentService.process] [payments] Processing payment
  }
}

// Disable logging for a noisy module (costs 5ns per call)
final silentLog = HyperLogger.withOptions<NoisyModule>(disabled: true);
silentLog.info('This is suppressed'); // no-op
```

### LoggerOptions

| Option               | Type          | Default | Effect                                                             |
|----------------------|---------------|---------|--------------------------------------------------------------------|
| `disabled`           | `bool`        | `false` | No-op all logging                                                  |
| `minLevel`           | `Level?`      | `null`  | Per-wrapper level filter (e.g., only WARNING+ from a noisy module) |
| `tag`                | `String?`     | `null`  | Prepends `[tag] ` to every message                                 |
| `skipCrashReporting` | `bool`        | `false` | Default for error calls (call-site can still override)             |
| `printer`            | `LogPrinter?` | `null`  | Per-wrapper printer override                                       |

```dart
// Per-wrapper minimum level -- only warnings and above
final log = HyperLogger.withOptions<NoisyService>(minLevel: Level.WARNING);
log.info('filtered out');    // no-op (INFO < WARNING)
log.warning('gets through'); // Output: ⚠️ [NoisyService] gets through

// Skip crash reporting by default for non-critical errors
final log = HyperLogger.withOptions<Analytics>(skipCrashReporting: true);
log.error('not sent to Crashlytics');

// Full LoggerOptions object
final log = HyperLogger.withOptions<Billing>(
  options: LoggerOptions(
    tag: 'billing',
    minLevel: Level.INFO,
    skipCrashReporting: false,
  ),
);
```

Wrappers implement `HyperLoggerApi<T>`, making them easy to mock in tests.
Instances are cached by type + options, so repeated calls with the same arguments
return the same instance.

## Crash reporting and analytics

Attach service delegates after initialization to forward specific log events to
external services:

```dart
class MyCrashReporter implements CrashReportingDelegate {
  @override
  Future<void> log(String message) async {
    // Forward to Crashlytics, Sentry, etc.
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    String? reason,
  }) async {
    // Forward to Crashlytics, Sentry, etc.
  }
}

class MyAnalytics implements AnalyticsDelegate {
  @override
  Future<void> logPerformance(String name, Duration duration, {String? source}) async {
    // Forward to Firebase Analytics, etc.
  }
}

void main() {
  HyperLogger.init();
  HyperLogger.attachServices(
    crashReporting: MyCrashReporter(),
    analytics: MyAnalytics(),
  );

  HyperLogger.warning<Api>('Rate limit hit');
  // -> prints warning AND calls MyCrashReporter.log('Rate limit hit')

  HyperLogger.error<Api>('Request failed', exception: TimeoutException('5s'));
  // -> prints error AND calls MyCrashReporter.recordError(...)

  final sw = Stopwatch()..start();
  // ... work ...
  sw.stop();
  HyperLogger.stopwatch<Api>('API call', sw);
  // -> prints "API call (123ms)" AND calls MyAnalytics.logPerformance(...)
}
```

Delegate calls are fire-and-forget -- their futures are ignored so logging never
blocks the caller. Delegates still fire in silent mode.

## Log filtering

Apply a filter to suppress noisy log records:

```dart
HyperLogger.init(
  logFilter: HyperLogger.defaultLogFilter, // suppresses Supabase GoTrue noise
);

// Or provide a custom filter
HyperLogger.init(
  logFilter: (record) => !record.loggerName.contains('NoisyLib'),
);
```

## Silent mode for tests

Suppress all printer output without tearing down the logger tree:

```dart
void main() {
  setUp(() {
    HyperLogger.init(silent: true);
  });

  tearDown(() {
    HyperLogger.reset(); // clean slate for each test
  });
}
```

Silent mode costs 9ns per log call. Crash reporting and analytics delegates
still fire in silent mode.

## ANSI colors

`AnsiColor` supports true-color (24-bit) terminals with multiple construction
methods:

```dart
AnsiColor.fromRGB(255, 165, 0)    // orange
AnsiColor.fromHex('#FFA500')       // same orange
AnsiColor.fromHex('F80')           // shorthand
AnsiColor(0xFFFFA500)              // raw 0xAARRGGBB

// Derive variants
final muted = AnsiColor.orange.withBrightness(0.3);

// Use in escape sequences
print('${AnsiColor.red.fg}Red text${AnsiColor.reset}');
print('${AnsiColor.blue.bg}Blue background${AnsiColor.reset}');
```

Named constants: `AnsiColor.black`, `.white`, `.red`, `.green`, `.blue`,
`.yellow`, `.cyan`, `.magenta`, `.orange`, `.gray`, `.lightGray`, `.darkGray`.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  HyperLogger (static API)                                       │
│    info / debug / warning / error / fatal / stopwatch / trace   │
├─────────────────────────────────────────────────────────────────┤
│  LogMessage → logging.LogRecord → Logger.root.onRecord          │
├─────────────────────────────────────────────────────────────────┤
│  LogPrinter                                                     │
│    ├── ComposablePrinter (decorator pipeline)                   │
│    │     ├── ContentExtractor (single-pass parse)               │
│    │     ├── StyleResolver (CSS-cascade resolution)             │
│    │     └── LogRenderer + SectionRenderer                      │
│    ├── JsonPrinter (Cloud Logging JSON)                         │
│    ├── WebConsolePrinter (Chrome DevTools)                      │
│    └── DirectPrinter (raw passthrough)                          │
├─────────────────────────────────────────────────────────────────┤
│  Delegates (optional, fire-and-forget)                          │
│    ├── CrashReportingDelegate                                   │
│    └── AnalyticsDelegate                                        │
└─────────────────────────────────────────────────────────────────┘
```

### Pipeline detail

1. **Decorators** (`LogDecorator` subclasses) write flags into a mutable `LogStyle` property bag at printer construction time. Each decorator owns a non-overlapping set of fields, so application order is irrelevant.

2. **ContentExtractor** performs a single-pass parse of each `LogRecord` into an `ExtractionResult` containing pre-split `LogSection`s (message, data, error, stack trace), plus the resolved `className` (from the `<T>` type parameter) and `methodName` (from the call-site stack trace). All expensive work (JSON serialization, stack-trace parsing, caller extraction) happens here.

3. **StyleResolver** reads the frozen `LogStyle` and maps it to `ResolvedSectionStyle` and `ResolvedBorderStyle` values. This is the only place where flag interactions live -- downstream renderers apply styles without conditional logic.

4. **LogRenderer** orchestrates section iteration, delegates per-line formatting to `SectionRenderer`, and wraps output with borders when boxing is enabled.

## Dependencies

| Package                                                 | Purpose                                     |
|---------------------------------------------------------|---------------------------------------------|
| [`logging`](https://pub.dev/packages/logging)           | Dart's standard logging infrastructure      |
| [`stack_trace`](https://pub.dev/packages/stack_trace)   | Stack trace parsing and caller extraction   |
| [`universal_io`](https://pub.dev/packages/universal_io) | Cross-platform `dart:io` for ANSI detection |
| [`meta`](https://pub.dev/packages/meta)                 | `@visibleForTesting` annotations            |
| [`web`](https://pub.dev/packages/web)                   | Web console API for `WebConsolePrinter`     |

## License

See the repository root for license details.
