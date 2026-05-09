# Custom printers

hyper_logger ships with printers for every common environment. But if you
need to send logs to a remote service, write to a file, or format output
in a way that the built-in printers don't support, you can write your
own.

## The `LogPrinter` interface

```dart
abstract class LogPrinter {
  void log(LogEntry entry);
}
```

One method. Every printer receives a `LogEntry` with `level`, `message`,
`loggerName`, `time`, `error`, `stackTrace`, and `object`. No dependency
on `package:logging`. `LogEntry` is hyper_logger's own type.

## Built-in printers

| Printer | Purpose |
|---|---|
| `ComposablePrinter` | Decorator pipeline (boxes, colors, emoji, timestamps) |
| `GcpJsonPrinter` | One JSON object per line, Google Cloud Logging shape |
| `AwsJsonPrinter` | One JSON object per line, AWS CloudWatch shape |
| `AzureJsonPrinter` | One JSON object per line, Azure Application Insights `traces` shape |
| `RotatingFilePrinter` | Append to a file, with optional size/time rotation, gzip, and retention |
| `DirectPrinter` | Raw `entry.message` passthrough, no formatting |
| `WebConsolePrinter` | Chrome DevTools `console.*` APIs with CSS styling |
| `ThrottledPrinter` | Rate-limiting wrapper around any printer |
| `MultiPrinter` | Fan-out wrapper that dispatches each entry to a list of printers |

### ComposablePrinter

This is the printer behind `terminal()`, `human()`, and `ci()` presets. It
takes a list of decorators that configure the output style, then runs
each log entry through a three-stage pipeline: content extraction, style
resolution, and rendering.

![Terminal output](../assets/preview_terminal.png)

```dart
ComposablePrinter(
  [
    const EmojiDecorator(),
    const BoxDecorator(lineLength: 100),
    const AnsiColorDecorator(),
    const PrefixDecorator(),
  ],
  methodCount: 10,          // Stack trace frames to show
  errorMethodCount: 20,     // More frames for error-level logs (null = use methodCount)
  excludePaths: ['package:noisy_dep/'],  // Hide frames from these libraries
  showAsyncGaps: true,      // Show "asynchronous gap" separators in stack traces
  output: print,            // Where formatted lines go
);
```

| Parameter | Type | Default | Effect |
|---|---|---|---|
| `decorators` | `List<LogDecorator>` | required | Style configuration. Order doesn't matter. |
| `methodCount` | `int` | `10` | Number of stack trace frames to include |
| `errorMethodCount` | `int?` | `null` | Frame count for error-level logs. Falls back to `methodCount`. |
| `excludePaths` | `List<String>` | `[]` | Library paths to exclude from stack traces |
| `showAsyncGaps` | `bool` | `false` | Show async gap separators between traces |
| `output` | `LogOutput` | `print` | Output sink callback |

`ComposablePrinter` also exposes a `format(LogEntry)` method that
returns the formatted lines as a `List<String>` without printing them.
Useful if you need to post-process the output.

### GcpJsonPrinter

Emits one JSON object per line in Google Cloud Logging's structured format.
Cloud Run, GKE, App Engine, and Cloud Functions parse this automatically:

```dart
const GcpJsonPrinter(output: print);
```

Output:

```json
{"severity":"INFO","message":"Daily intake logged","data":{"cups":4,"regret":false},"timestamp":"2026-04-08T12:00:00.000Z","logger":"CoffeeTracker"}
```

Level mapping to Cloud Logging severity:

| LogLevel | Severity |
|---|---|
| `trace`, `debug` | `DEBUG` |
| `info` | `INFO` |
| `warning` | `WARNING` |
| `error` | `ERROR` |
| `fatal` | `CRITICAL` |

### AwsJsonPrinter

Emits one JSON object per line in a shape suited to AWS CloudWatch Logs and
AWS Lambda. Uses CloudWatch's `level` field (rather than GCP's `severity`)
and CloudWatch's level naming (`WARN` and `FATAL`):

```dart
const AwsJsonPrinter(output: print);
```

Output:

```json
{"timestamp":"2026-04-08T12:00:00.000Z","level":"INFO","message":"Daily intake logged","data":{"cups":4,"regret":false},"logger":"CoffeeTracker"}
```

Level mapping to CloudWatch level:

| LogLevel | Level |
|---|---|
| `trace` | `TRACE` |
| `debug` | `DEBUG` |
| `info` | `INFO` |
| `warning` | `WARN` |
| `error` | `ERROR` |
| `fatal` | `FATAL` |

### DirectPrinter

The simplest possible printer. Passes `entry.message` straight to the
output callback with no formatting, no colors, no boxes:

```dart
const DirectPrinter(output: print);
```

This is primarily useful for tests (capture output into a list) and for
environments where any formatting would be a problem.

### RotatingFilePrinter

Appends entries to disk with optional rotation by size or interval,
optional gzip compression of rotated files, retention via `maxFiles`,
and async path resolution. IO-only — constructing it on web throws
`UnsupportedError`.

```dart
final filePrinter = RotatingFilePrinter(
  baseFilePathProvider: () => '/var/log/app.log',
  rotationConfig: FileRotationConfig.size(
    maxBytes: 10 * 1024 * 1024,  // 10 MB
    maxFiles: 5,
    compress: true,
  ),
);

HyperLogger.init(printer: filePrinter);
```

#### Async path resolution (Flutter, path_provider)

`baseFilePathProvider` may return a `Future`. Records logged before the
path resolves are buffered in memory (default 1000, configurable via
`pendingBufferSize`) and flushed on the first successful resolution.

For Flutter callers, depend on
[`path_provider`](https://pub.dev/packages/path_provider) and import it
explicitly — `hyper_logger` does not transitively expose it.

```dart
import 'package:path_provider/path_provider.dart';

final filePrinter = RotatingFilePrinter(
  baseFilePathProvider: () async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/logs/app.log';
  },
);
```

#### Rotation policies

| Constructor | Trigger |
|---|---|
| `FileRotationConfig.size(maxBytes: N)` | rotate when file reaches N bytes |
| `FileRotationConfig.daily()` | rotate every 24 hours |
| `FileRotationConfig.interval(interval: D)` | rotate every `D` |

`compress: true` gzips rotated files (`.log.gz`). `maxFiles: N`
deletes the oldest rotated siblings on each rotation. Time-based
rotation honors the file's last-modified time, so a process that
restarts mid-day inherits the previous run's window.

#### Output format

The default `defaultFileLineFormatter` writes one human-readable line
per entry: `<ISO timestamp> [LEVEL] <logger>: <message>`. `data` and
`context` are appended as JSON segments (`data={...} context={...}`)
so values with spaces, quotes, or nested structures are encoded
unambiguously. For machine-parseable output, pass a `formatter`
backed by a JSON printer:

```dart
final json = GcpJsonPrinter(output: (_) {});
RotatingFilePrinter(
  baseFilePathProvider: () => '/var/log/app.jsonl',
  formatter: (entry) => json.format(entry).single,
);
```

#### Lifecycle

Call `await close()` on shutdown to flush pending writes, await any
in-flight gzip compressions, and release the file handle. `flush()`
does the same without closing — useful as a periodic safety net (e.g.
on app suspend). Both are idempotent and safe under concurrent callers.

```dart
await filePrinter.flush();   // periodic
await filePrinter.close();   // teardown
```

#### Error visibility

By default, IO failures (path resolution, write, rotation, compression)
write a single line to `stderr`. Pass an `onError` callback to forward
to your monitoring system instead:

```dart
RotatingFilePrinter(
  baseFilePathProvider: () => '/var/log/app.log',
  onError: (error, stack) => sentry.captureException(error, stack),
);
```

The handler is `FutureOr<void>` (sync or async). A throwing or rejecting
handler is contained — logging never crashes the app. Reentrant calls
back into the same printer (handler logs through `HyperLogger`) are
guarded against stack overflow.

### WebConsolePrinter

Used automatically on web platforms. Uses Chrome DevTools APIs for
structured output:

```dart
WebConsolePrinter(
  methodCount: 8,        // Stack trace frames
  errorMethodCount: null, // Falls back to methodCount
);
```

Each log entry becomes a `console.groupCollapsed` call with CSS-styled
headers (colored badges per level). Inside the group:

- `console.log` for the message text
- `console.dir` for structured data (native expandable object tree)
- CSS-styled `console.log` for exceptions
- Formatted stack trace text

You don't need to configure this manually. It's selected automatically
when running on web.

![Web console output](../assets/preview_web_console.png)

## Decorator composition

Decorators configure the output style by writing flags into a `LogStyle`
property bag at construction time:

```dart
final printer = ComposablePrinter([
  const EmojiDecorator(),
  const BoxDecorator(lineLength: 100),
  const AnsiColorDecorator(),
  const TimestampDecorator(),
  const PrefixDecorator(),
]);
```

Each decorator owns a non-overlapping set of fields, so order is
irrelevant. Shuffle them, reorder them, the output stays the same.

![Custom colors](../assets/preview_custom_colors.png)

| Decorator | Fields | Effect |
|---|---|---|
| `BoxDecorator` | `box`, `lineLength` | Box-drawing border around log entries |
| `EmojiDecorator` | `emoji`, `levelEmojis` | Level emoji prefix (e.g. 💡 for info) |
| `AnsiColorDecorator` | `ansiColors`, `levelColors` | 24-bit ANSI terminal colors |
| `TimestampDecorator` | `timestamp`, `dateTimeFormatter` | ISO-8601 timestamp (or custom format) |
| `PrefixDecorator` | `prefix` | `[ClassName.methodName]` bracket prefix |

### Customizing decorators

Most decorators accept optional parameters:

```dart
// Custom line width for the box
const BoxDecorator(lineLength: 80)

// Custom emoji per level
EmojiDecorator(customEmojis: {
  LogLevel.info: 'ℹ️ ',
  LogLevel.error: '🔥 ',
})

// Custom colors per level
AnsiColorDecorator(customLevelColors: {
  LogLevel.warning: AnsiColor.fromHex('#FFA500'),
})

// Custom timestamp format
TimestampDecorator(formatter: (dt) => '${dt.hour}:${dt.minute}:${dt.second}')
```

See [Configuration: ANSI colors](configuration.md#ansi-colors) for the
full `AnsiColor` API.

### Writing a custom decorator

```dart
class VerboseDecorator extends LogDecorator {
  const VerboseDecorator();

  @override
  void apply(LogStyle style) {
    style.box = true;
    style.emoji = true;
    style.timestamp = true;
    style.prefix = true;
    style.ansiColors = true;
  }
}
```

`LogStyle` fields you can set:

| Field | Type | Default | Description |
|---|---|---|---|
| `box` | `bool` | `false` | Draw box border |
| `emoji` | `bool` | `false` | Show emoji prefix |
| `ansiColors` | `bool` | `false` | Apply ANSI color codes |
| `timestamp` | `bool` | `false` | Include timestamp section |
| `prefix` | `bool` | `true` | Show `[Class.method]` prefix |
| `lineLength` | `int` | `120` | Max line width |
| `levelEmojis` | `Map<LogLevel, String>?` | `null` | Per-level emoji overrides |
| `levelColors` | `Map<LogLevel, AnsiColor>?` | `null` | Per-level color overrides |
| `dateTimeFormatter` | `DateTimeFormatter?` | `null` | Custom timestamp formatter |

> **Note:** `prefix` is the asymmetric default — `true`, while every
> other boolean field defaults to `false`. So `ComposablePrinter([])`
> with no decorators still emits `[Type.method]`. To get a truly
> minimal output, pass an empty decorator list AND set
> `printer.style.prefix = false` (or use `DirectPrinter` instead).

## ThrottledPrinter

Sometimes you put a log line in a function that triggers thousands of
times per second. Your Dart process hangs while the console tries to
catch up, and you can't even hot-restart until it finishes.
`ThrottledPrinter` prevents this by rate-limiting any printer:

```dart
final printer = ThrottledPrinter(
  LogPrinterPresets.terminal(),
  maxPerSecond: 30,    // default: 30
  maxQueueSize: 200,   // default: 500
);

HyperLogger.init(printer: printer);
```

Entries up to `maxPerSecond` are forwarded immediately. Excess entries
are queued and drained gradually. When the queue exceeds `maxQueueSize`,
the oldest entries are dropped and a summary is emitted:

![Throttled output](../assets/preview_throttled.png)

Call `flush()` on app shutdown to drain remaining entries:

```dart
// In your app's dispose or shutdown logic:
(printer as ThrottledPrinter).flush();
```

## MultiPrinter

`HyperLogger.init` takes a single `printer:`. When you want one entry to
land in more than one place — terminal *and* file, file *and* cloud,
primary *and* fallback — wrap the children in `MultiPrinter`:

```dart
HyperLogger.init(
  printer: MultiPrinter([
    LogPrinterPresets.terminal(),                    // pretty for humans
    RotatingFilePrinter(                             // archive to disk
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

Each entry is dispatched to every child in the order you listed.
Children are isolated from each other: a printer that throws does
**not** prevent the rest from receiving the entry. After all children
have run, if any threw, `MultiPrinter` raises a `MultiPrinterError`
aggregating the per-child failures (with their original index in the
list and the original stack trace each child threw). `HyperLogger`'s
pipeline catches that and routes it through `setPipelineErrorHandler`
(rate-limited to once per source per session), so a failing fan-out
isn't silently lost — you find out which child is broken and why.

```dart
HyperLogger.setPipelineErrorHandler((source, error, _) {
  if (error is MultiPrinterError) {
    for (final c in error.childErrors) {
      sentry.captureException('child[${c.index}] failed: ${c.error}');
    }
  }
});
```

`dispose()` fans out to every child even if one throws — but per the
`LogPrinter.dispose` contract (best-effort, no listener), dispose
failures are swallowed individually and aren't aggregated.

`MultiPrinter` is itself a `LogPrinter`, so it composes with everything
else in the package:

```dart
// Throttle the entire fan-out as a unit.
ThrottledPrinter(MultiPrinter([terminal, file]), maxPerSecond: 100);

// Throttle ONLY the remote sink, leave the file alone.
MultiPrinter([
  ThrottledPrinter(remote, maxPerSecond: 50),
  file,
]);

// Nested fan-outs (a fanout-of-fanouts).
MultiPrinter([cheap, MultiPrinter([expensive1, expensive2])]);
```

The list passed at construction is snapshotted — mutating the source
afterward does not affect the printer.

## Writing a custom printer

Implement `LogPrinter` and do whatever you want with the `LogEntry`:

```dart
class BufferedRemotePrinter implements LogPrinter {
  final List<LogEntry> _buffer = [];
  final int batchSize;
  final void Function(List<LogEntry> batch) onFlush;

  BufferedRemotePrinter({this.batchSize = 50, required this.onFlush});

  @override
  void log(LogEntry entry) {
    _buffer.add(entry);
    if (_buffer.length >= batchSize) flush();
  }

  void flush() {
    if (_buffer.isEmpty) return;
    final batch = List<LogEntry>.of(_buffer);
    _buffer.clear();
    onFlush(batch);
  }
}
```

See [example/buffered_remote_logger_example.dart](../example/buffered_remote_logger_example.dart)
for a complete, runnable version of this.

## Custom output sinks

Every printer that produces text output accepts a `LogOutput` callback:

```dart
// Route through Flutter's debugPrint (prevents Android log truncation)
final printer = LogPrinterPresets.terminal(
  output: (s) => debugPrint(s),
);

// Write to a file
final printer = LogPrinterPresets.ci(
  output: (s) => logFile.writeAsStringSync('$s\n', mode: FileMode.append),
);

// Capture in tests
final captured = <String>[];
final printer = DirectPrinter(output: captured.add);
```
