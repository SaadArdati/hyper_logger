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
Interceptors (run in order; first one to return null drops the entry)
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
  `LogPrinterPresets.automatic()`, which detects GCP / AWS / CI by
  environment markers, then falls through to a `human(capabilities)`
  preset composed from the live stdout's ANSI / TTY / width.
- **Web** (`printer_factory_web.dart`): Returns `WebConsolePrinter()`.

Detection runs once at init time, not per log call.

## Performance

Numbers below are from `benchmark/hyper_logger_benchmark.dart` and
`benchmark/cloud_parity_benchmark.dart` (Apple Silicon, Dart VM, AOT).
Re-run them on your hardware before quoting them anywhere that matters
— absolute throughput is machine-dependent; the ratios are not.

### Hot path (formatting cost per record)

| Printer                                 | Median  | Throughput  |
| --------------------------------------- | ------: | ----------: |
| `DirectPrinter` (raw passthrough)       |    11ns |  90.1M ops/s |
| `ComposablePrinter` (no decorators)     |   411ns |   2.4M ops/s |
| `LogPrinterPresets.human(ansi+pipe)`    |   573ns |   1.8M ops/s |
| `LogPrinterPresets.ci`                  |   732ns |   1.4M ops/s |
| `LogPrinterPresets.gcp` / `aws` / `azure` | ~1.1µs | ~900K ops/s |
| `LogPrinterPresets.terminal` (full UI)  |   1.8µs |   565K ops/s |

The terminal preset is the slowest because it composes every decorator
(emoji, box, ANSI color, prefix) and walks the section list multiple
times to build a multi-line bordered render. Cloud printers skip the
section pipeline entirely and emit a single JSON line.

### Disabled and filtered paths

These are the calls in production code where the global mode or scoped
filter rejects the entry — they should be free, and they are:

| Operation                                    | Cost  | Throughput   |
| -------------------------------------------- | ----: | -----------: |
| `LogMode.silent` short-circuit               |  10ns |   96M ops/s  |
| `ScopedLogger(mode: disabled)` early return  |  14ns |   71M ops/s  |
| `ScopedLogger(minLevel: WARNING)` filtering INFO | 14ns | 70M ops/s |

The takeaway: leaving `HyperLogger.debug<T>(...)` or
`HyperLogger.trace<T>(...)` calls in production code costs nothing as
long as the global mode or a scoped `minLevel` filters them out. There
is no need to wrap them in `if (kDebugMode)` guards.

### Cloud printer parity

The three cloud printers share a common base (`CloudJsonPrinterBase`)
and perform within 5% of each other across all scenarios:

| Scenario             | GCP    | AWS    | Azure  |
| -------------------- | -----: | -----: | -----: |
| Simple INFO          | 1132ns | 1117ns | 1074ns |
| INFO with `data` map | 1967ns | 1990ns | 1910ns |
| ERROR with stack     |  22.2µs |  22.4µs |  22.4µs |

`AzureJsonPrinter` is marginally faster on the simple path because its
numeric `severityLevel` skips the string-switch the others need. On the
data-payload scenario it nests user context under `customDimensions`
(per the AppInsights data model) instead of merging at root, but the
extra map allocation is small enough not to show up.

### Error-path latency is dominated by stack-trace parsing

A `SEVERE`-level entry with an `exception` and `stackTrace` costs
~430µs on terminal/CI presets — orders of magnitude more than a
plain INFO. The breakdown (from `benchmark/deep_dive_benchmark.dart`):

| Step                                              | Median  |
| ------------------------------------------------- | ------: |
| `Chain.forTrace(StackTrace.current)` (raw parse)  |  28.6µs |
| `StackTraceParser` (filtering + formatting, n=10) |  84.3µs |
| `CallerExtractor.extract`                         |  51.7µs |
| `ContentExtractor.extract` (full error record)    | 427.9µs |
| `ContentExtractor.extract` (simple INFO, no stack) |  185ns |

Cloud printers (GCP/AWS/Azure) skip the chain parse — they pass the
stack trace through `toString()` straight into the JSON — so error
records cost ~22µs, not ~430µs. That asymmetry is intentional: human
readers want pretty per-frame output; cloud aggregators want raw text.

If your service emits sustained high-rate error logs and you don't need
stack-trace grooming, prefer a cloud printer (or
`StackTraceParser(methodCount: 0)` to skip parsing entirely — that
drops the cost back to ~21ns).

### Stack-capture cost

`captureStackTrace: true` (the default) calls `StackTrace.current` on
every log call that doesn't pass an explicit `method:`. Cost: ~700ns
per call. On a hot loop, set `captureStackTrace: false` in
`HyperLogger.init(...)` and pass `method:` explicitly; on a normal app
this is in the noise.

## Type hierarchy

```
LogPrinter (interface)
  ├── ComposablePrinter (decorator pipeline)
  ├── CloudJsonPrinterBase (internal — shared cloud JSON formatter)
  │     ├── GcpJsonPrinter (Google Cloud Logging JSON)
  │     ├── AwsJsonPrinter (AWS CloudWatch JSON)
  │     └── AzureJsonPrinter (Azure Application Insights traces)
  ├── RotatingFilePrinter (file output with rotation, gzip, retention)
  ├── DirectPrinter (raw passthrough)
  ├── WebConsolePrinter (Chrome DevTools)
  ├── ThrottledPrinter (rate-limiting wrapper)
  └── MultiPrinter (fan-out wrapper)

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
`ComposablePrinter`, `GcpJsonPrinter`, and `AwsJsonPrinter` unwrap to access
structured data.

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
