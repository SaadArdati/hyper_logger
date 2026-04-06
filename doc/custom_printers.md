# Custom printers

## The `LogPrinter` interface

```dart
abstract class LogPrinter {
  void log(LogEntry entry);
}
```

Every printer receives a `LogEntry` with `level`, `message`, `object`,
`loggerName`, `time`, `error`, and `stackTrace`. No dependency on
`package:logging` — `LogEntry` is hyper_logger's own type.

## Built-in printers

| Printer | Purpose |
|---|---|
| `ComposablePrinter` | Decorator pipeline (boxes, colors, emoji, timestamps) |
| `JsonPrinter` | One JSON object per line (Cloud Logging compatible) |
| `DirectPrinter` | Raw `entry.message` passthrough |
| `WebConsolePrinter` | Chrome DevTools `console.*` APIs |
| `ThrottledPrinter` | Rate-limiting wrapper around any printer |

## Writing a custom printer

See [example/buffered_remote_logger_example.dart](../example/buffered_remote_logger_example.dart)
for a complete, runnable implementation of a buffered remote log printer
that batches entries and flushes them periodically.

```

## Decorator composition

Decorators write flags into a `LogStyle` property bag. Each decorator
owns a non-overlapping set of fields, so order is irrelevant:

```dart
final printer = ComposablePrinter([
  const EmojiDecorator(),
  const BoxDecorator(lineLength: 100),
  const AnsiColorDecorator(),
  const TimestampDecorator(),
  const PrefixDecorator(),
]);
```

| Decorator | Fields | Effect |
|---|---|---|
| `BoxDecorator` | `box`, `lineLength` | Box-drawing border |
| `EmojiDecorator` | `emoji`, `levelEmojis` | Level emoji prefix |
| `AnsiColorDecorator` | `ansiColors`, `levelColors` | 24-bit ANSI colors |
| `TimestampDecorator` | `timestamp`, `dateTimeFormatter` | ISO-8601 timestamp |
| `PrefixDecorator` | `prefix` | `[Class.method]` bracket prefix |

## Writing a custom decorator

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

## ThrottledPrinter

Wraps any printer to prevent high-frequency logging from choking the
process:

```dart
final printer = ThrottledPrinter(
  LogPrinterPresets.terminal(),
  maxPerSecond: 30,    // Forward up to 30 entries/sec
  maxQueueSize: 200,   // Queue excess, drop oldest if full
);

HyperLogger.init(printer: printer);
```

When the queue overflows, a summary is emitted:
`... 4800 log entries dropped (throttled)`.

Call `flush()` on shutdown to drain remaining entries.

## Custom output sinks

Every printer that produces text output accepts a `LogOutput` callback:

```dart
// Route through Flutter's debugPrint (with Android throttling)
final printer = LogPrinterPresets.terminal(
  output: (s) => debugPrint(s),
);

// Write to a file (see example/file_logger_example.dart for a full example)
final printer = LogPrinterPresets.ci(
  output: (s) => logFile.writeAsStringSync('$s\n', mode: FileMode.append),
);

// Capture in tests
final captured = <String>[];
final printer = DirectPrinter(output: captured.add);
```
