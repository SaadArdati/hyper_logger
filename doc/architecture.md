# Architecture

## Pipeline overview

```
HyperLogger.info<MyClass>('msg', data: {...})
  |
  v
LogMessage (message + type + data + callerStackTrace)
  |
  v
logging.LogRecord (via package:logging internally)
  |
  v
_handleLogRecord
  |
  v
LogEntry.fromLogRecord (conversion boundary — logging package hidden from here on)
  |
  v
LogPrinter.log(LogEntry)
  |
  v
ComposablePrinter pipeline:
  ContentExtractor.extract()  → ExtractionResult (sections, className, methodName)
  StyleResolver.resolve()     → ResolvedSectionStyle / ResolvedBorderStyle
  LogRenderer.render()        → List<String> output lines
  output(line)                → print() or custom sink
```

## Key design decisions

### The `logging` package is an internal detail

The public API uses `LogEntry`, `LogLevel`, and `LogMode` exclusively.
`package:logging` is used internally for its hierarchical logger tree and
root record stream, but consumers never import it. The conversion from
`logging.LogRecord` to `LogEntry` happens once in `_handleLogRecord`.

### CSS-cascade style resolution

Decorators write flags into a mutable `LogStyle` property bag at printer
construction time. Each decorator owns a non-overlapping set of fields,
making application order irrelevant.

The `StyleResolver` reads the frozen `LogStyle` and produces concrete
`ResolvedSectionStyle` values. This is the only place where flag
interactions live — downstream renderers apply styles blindly.

### Single-pass extraction

`ContentExtractor` performs one pass over the `LogEntry` to produce all
`LogSection`s (message, data, error, stack trace), plus `className` and
`methodName`. All expensive work (JSON serialization, stack trace parsing,
caller extraction) happens here and only here.

### Fire-and-forget delegate with error boundary

Delegate calls (`CrashReportingDelegate`) are wrapped in `_fireDelegate`,
which catches both synchronous throws and async Future rejections. Logging
never crashes the app, even if your Crashlytics SDK throws.

### Release-mode type name suppression

`T.toString()` returns minified names in dart2js release builds.
`ContentExtractor` checks `bool.fromEnvironment('dart.vm.product')` and
skips type rendering in release mode to avoid garbled output.

## Type hierarchy

```
LogPrinter (interface)
  ├── ComposablePrinter (decorator pipeline)
  ├── JsonPrinter (Cloud Logging JSON)
  ├── DirectPrinter (raw passthrough)
  ├── WebConsolePrinter (Chrome DevTools)
  └── ThrottledPrinter (rate-limiting wrapper)

LogDecorator (abstract)
  ├── BoxDecorator
  ├── EmojiDecorator
  ├── AnsiColorDecorator
  ├── TimestampDecorator
  └── PrefixDecorator

ScopedLoggerApi<T> (interface)
  └── ScopedLogger<T> (cached implementation)

HyperLoggerMixin<T> (mixin, optional scopedLogger)
```

## Dependencies

| Package | Purpose |
|---|---|
| `logging` | Internal logger tree and record stream |
| `stack_trace` | Stack trace parsing and caller extraction |
| `universal_io` | Cross-platform `dart:io` for ANSI detection |
| `web` | Web console APIs for `WebConsolePrinter` |
