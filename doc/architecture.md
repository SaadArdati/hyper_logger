# Architecture

This page is for contributors and curious developers who want to
understand how hyper_logger works internally. You don't need any of this
to use the library.

## Pipeline overview

Every log call flows through the same pipeline:

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
LogEntry.fromLogRecord (conversion boundary; logging package hidden from here on)
  |
  v
LogFilter (if configured, can suppress the entry here)
  |
  v
LogPrinter.log(LogEntry)
  |
  v
ComposablePrinter pipeline:
  ContentExtractor.extract()  -> ExtractionResult (sections, className, methodName)
  StyleResolver.resolve()     -> ResolvedSectionStyle / ResolvedBorderStyle
  LogRenderer.render()        -> List<String> output lines
  output(line)                -> print() or custom sink
```

Delegate calls (crash reporting) happen separately, before the entry
enters this pipeline. They fire directly in the `warning()`, `error()`,
and `fatal()` methods, before `_log()` is called.

## Key design decisions

### The `logging` package is an internal detail

The public API uses `LogEntry`, `LogLevel`, and `LogMode` exclusively.
`package:logging` is used internally for its hierarchical logger tree and
root record stream, but consumers never import it. The conversion from
`logging.LogRecord` to `LogEntry` happens once in `_handleLogRecord`.

This means you can use hyper_logger without knowing that `package:logging`
exists underneath. It also means the logging package could be swapped out
without changing the public API.

### CSS-cascade style resolution

Decorators write flags into a mutable `LogStyle` property bag at printer
construction time. Each decorator owns a non-overlapping set of fields,
making application order irrelevant.

The `StyleResolver` reads the frozen `LogStyle` and produces concrete
`ResolvedSectionStyle` values. This is the only place where flag
interactions live. Downstream renderers apply styles blindly.

### Single-pass extraction

`ContentExtractor` performs one pass over the `LogEntry` to produce all
`LogSection`s (message, data, error, stack trace), plus `className` and
`methodName`. All expensive work (JSON serialization, stack trace
parsing, caller extraction) happens here and only here.

Performance-conscious details:

- **String splitting fast path**: single-line messages (the common case)
  skip the `split('\n')` call entirely and return a single-element list
  directly, avoiding unnecessary list allocation.
- **Chain caching**: `Chain.forTrace()` (from `package:stack_trace`) is
  expensive. ContentExtractor builds it once and shares it between the
  `StackTraceParser` and `CallerExtractor`.
- **Direct for-loops**: `SectionRenderer` uses indexed for-loops instead
  of `.map().toList()` to avoid iterator and closure overhead.
- **StringBuffer reuse**: `ResolvedSectionStyle.apply()` uses a
  `StringBuffer` to build each line without intermediate string
  allocations.

### Fire-and-forget delegate with error boundary

Delegate calls (`CrashReportingDelegate`) are wrapped in
`fireDelegateSafely` (in `delegates/delegate_safety.dart`), which
catches both synchronous throws and async Future rejections. The
returned Future is not awaited, just error-handled. Logging never
crashes the app, even if your Crashlytics SDK throws.

### Release-mode type name suppression

In release builds with `dart2js`, `T.toString()` returns minified names
like `aB` or `cD`. Rendering these in log output produces garbled text.
`ContentExtractor` checks `bool.fromEnvironment('dart.vm.product')` and
skips type rendering entirely in release mode. Stack trace caller
extraction still works since it operates on frame member names, not
`Type.toString()`.

### Platform-aware printer selection

Printer selection is handled through conditional exports:

- **Native** (`printer_factory_native.dart`): Returns
  `LogPrinterPresets.automatic()`, which detects Cloud Run, CI, IDE,
  terminal ANSI support, or falls back to plain text.
- **Web** (`printer_factory_web.dart`): Returns `WebConsolePrinter()`.

Detection runs once at init time, not per log call.

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

## Internal data flow

### LogMessage

Created in `HyperLogger._log<T>()`. Carries the message, structured
data, the caller type `T`, an optional method name, and the captured
stack trace (if `captureStackTrace` is true and no explicit `method` was
provided).

### LogEntry

Created from `logging.LogRecord` in `_handleLogRecord()`. This is the
public-facing record type that printers receive. The `object` field
contains the original `LogMessage`, which printers like
`ComposablePrinter` and `JsonPrinter` unwrap to access structured data.

### ExtractionResult

Produced by `ContentExtractor.extract()`. Contains the parsed
`LogSection` list (message, data, error, stack trace sections), the
extracted `className` and `methodName`, log level, and timestamp.

### CallerInfo

A `({String className, String methodName})` record returned by
`CallerExtractor`. It filters out internal frames from `package:hyper_logger/`
and `package:logging/`, then extracts the first non-internal frame with a
member name.

## Dependencies

| Package | Purpose |
|---|---|
| `logging` | Internal logger tree and record stream |
| `stack_trace` | Stack trace parsing and caller extraction |
| `universal_io` | Cross-platform `dart:io` for ANSI detection |
| `web` | Web console APIs for `WebConsolePrinter` |
