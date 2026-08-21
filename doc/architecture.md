# Architecture

This page is for contributors and curious developers who want to
understand how hyper_logger works internally. You don't need any of this
to use the library.

## Pipeline overview

Every log call flows through the same pipeline:

```
HyperLogger call                         third-party logging.LogRecord
  |                                       |
  v                                       v
Eligible native sink?                 Eligible printer sink?
  |                                       |
  v                                       v
LogMessage + LogEntry                  LogEntry.fromLogRecord
  |                                       |
  +-------------------+-------------------+
                      |
                      v
                 _handleEntry
  |
  v
Interceptors (run in order; first one to return null drops the entry)
  |
  v
Sanitizers (run in order; null or throw drops the entry from every sink)
  |
  +--> CrashReportingDelegate for native warning/error/fatal only
  |      (fire-and-forget)
  |
  +--> LogPrinter.log(LogEntry), unless output is silent
         |
         v
       ComposablePrinter pipeline:
         ContentExtractor.extract()  -> ExtractionResult
         StyleResolver.resolve()     -> resolved styles
         LogRenderer.render()        -> output lines
         output(line)                -> print() or custom sink
```

Private dispatch arguments carry routing intent until after the shared
interceptor and sanitizer pipeline. For native warning/error/fatal calls,
crash reporting and printers therefore receive the same sanitized `LogEntry`.
`LogMessage.reportToCrashReporting` mirrors that native decision as metadata
for custom printers, but changing the field does not control delegate routing.
Third-party `logging.LogRecord` values are deliberately printer-only and never
reach the crash delegate; silent mode discards them before conversion. Native
delegate-eligible records still complete sanitization in silent mode when a
delegate is attached. With no eligible sink, conversion and the entire pipeline
are skipped.

## Key design decisions

### The `logging` package is an explicit integration dependency

HyperLogger-native calls use `LogEntry`, `LogLevel`, and `LogMode`, while
`package:logging` supplies the level hierarchy and inbound bridge for
third-party records. Most consumers do not need to import it. Adapter APIs do
intentionally expose `logging.Level` through `LogLevel` conversions and
`logging.LogRecord` through `LogEntry.fromLogRecord`, however, so integration
code may import it directly.

Native calls construct `LogEntry` directly and cannot expose raw payloads to
other root-stream subscribers. A third-party `logging.LogRecord` is converted
once in `_handleLogRecord` before joining `_handleEntry`. The pipeline after
that conversion is package-agnostic; replacing `package:logging` itself would
still require a migration of the public adapter APIs.

### Sanitization is a one-way boundary

Ordinary interceptors are intentionally failure-isolated: a throwing
interceptor is skipped. Sanitizers have the opposite failure contract. A
`null` result, exception, traversal limit, cycle, or unsafe redaction
composition drops the entry before both output arms. The previous entry is
never restored after sanitization begins.

The built-in redactor is split into a small public facade and private policy,
structured-walker, protocol-parser, text-coordinator, and literal-matcher
modules. Supported representations are decoded with exact rules rather than
credential-shaped regexes. Original and final structured paths are both
checked, and changed text is re-inspected until it reaches the bounded safe
fixed point. This prevents replacement text from creating a sensitive JSON,
HTTP, URI/form, or structured representation after the corresponding check.

The standards basis is documented in [Redaction and sanitizers](redaction.md):
[OWASP logging guidance](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html),
[RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html),
[RFC 9112](https://www.rfc-editor.org/rfc/rfc9112.html),
[RFC 3986](https://www.rfc-editor.org/rfc/rfc3986.html),
[RFC 6750](https://www.rfc-editor.org/rfc/rfc6750.html),
[RFC 8259](https://www.rfc-editor.org/rfc/rfc8259.html),
[RFC 7468](https://www.rfc-editor.org/rfc/rfc7468.html), and the
[OpenTelemetry URL conventions](https://opentelemetry.io/docs/specs/semconv/url/).

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
crashes the app, even if your Crashlytics SDK throws. Dispatch occurs after
sanitization and before printer output.

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
  `LogPrinterPresets.automatic()`, which detects GCP / AWS / Azure / CI by
  environment markers, then falls through to a `human(capabilities)` preset
  composed from the live stdout's ANSI / TTY / width. Azure markers cover App
  Service, Functions, and Container Apps.
- **Web** (`printer_factory_web.dart`): Returns `WebConsolePrinter()`.

Detection runs once at init time, not per log call.

## Performance

Numbers below were captured on 2026-08-21 with Dart 3.13.0 stable's JIT VM on
macOS arm64 by running `dart run benchmark/hyper_logger_benchmark.dart`,
`dart run benchmark/cloud_parity_benchmark.dart`,
`dart run benchmark/deep_dive_benchmark.dart`, and
`dart run benchmark/redacting_interceptor_benchmark.dart`. Both absolute
results and ratios depend on the CPU, SDK, compiler mode, process state, and
workload; re-run the scripts in the deployment-like environment whose behavior
matters.

### Hot path (formatting cost per record)

| Printer                                 | Median  | Throughput  |
| --------------------------------------- | ------: | ----------: |
| `DirectPrinter` (raw passthrough)       |    12ns |  87.0M ops/s |
| `ComposablePrinter` (no decorators)     |   278ns |   3.6M ops/s |
| `LogPrinterPresets.human(ansi+pipe)`    |   445ns |   2.2M ops/s |
| `LogPrinterPresets.ci`                  |   589ns |   1.7M ops/s |
| `LogPrinterPresets.gcp` / `aws` / `azure` | ~1.1µs | ~900K ops/s |
| `LogPrinterPresets.terminal` (full UI)  |   1.7µs |   591K ops/s |

The terminal preset is the slowest because it composes every decorator
(emoji, box, ANSI color, prefix) and walks the section list multiple
times to build a multi-line bordered render. Cloud printers skip the
section pipeline entirely and emit a single JSON line.

### Disabled and filtered paths

These are the calls in production code where the global mode or scoped
filter rejects the entry. They take the following near-zero-cost fast paths:

| Operation                                    | Cost  | Throughput   |
| -------------------------------------------- | ----: | -----------: |
| `LogMode.silent` short-circuit               |   5ns |  208M ops/s  |
| `ScopedLogger(mode: disabled)` early return  |  14ns | 72.5M ops/s  |
| `ScopedLogger(minLevel: WARNING)` filtering INFO | 14ns | 72.5M ops/s |

The dispatch overhead of a filtered call is tiny, but Dart evaluates arguments
before entering the logging method. Use `HyperLogger.isEnabled(...)` around
expensive argument construction. An `if (kDebugMode)` guard is unnecessary when
only the logging call itself needs filtering.

### Sanitizer hot paths

The focused `benchmark/redacting_interceptor_benchmark.dart` covers both the
redactor and its placement in the native pipeline under the runtime described
above:

| Operation | Cost | Throughput |
|---|---:|---:|
| Ordinary text, no literal secrets | 169ns | 5.90M ops/s |
| Ordinary text, three absent secrets | 292ns | 3.42M ops/s |
| JSON text, no literal secrets | 1.22µs | 822K ops/s |
| Complete simple `LogEntry` | 692ns | 1.44M ops/s |
| Structured entry with ordinary keys | 4.08µs | 245K ops/s |
| Active HTTP credential removal and revalidation | 976ns | 1.02M ops/s |
| Native INFO pipeline without sanitizers | 280ns | 3.58M ops/s |
| Native INFO pipeline with the redactor | 904ns | 1.11M ops/s |
| No eligible sink | 16ns | 61.0M ops/s |

Unchanged strings and ordinary structured keys use allocation-conscious fast
paths. Only changed representations pay for fixed-point revalidation. As with
the printer measurements, re-run the benchmark on target hardware before using
absolute numbers as a capacity estimate.

### Cloud printer parity

The three cloud printers share a common base (`CloudJsonPrinterBase`)
and performed within 7% of each other across these scenarios in this run:

| Scenario             | GCP    | AWS    | Azure  |
| -------------------- | -----: | -----: | -----: |
| Simple INFO          | 1113ns | 1055ns | 1040ns |
| INFO with `data` map | 1990ns | 1985ns | 1957ns |
| ERROR with stack     |  23.7µs |  24.0µs |  24.0µs |

In this run, `AzureJsonPrinter` is marginally faster on the simple path because
its numeric `severityLevel` skips the string-switch the others need. On the
data-payload scenario it nests user context under `customDimensions`
(per the AppInsights data model) instead of merging at root, but the
extra map allocation is small enough not to show up.

### Error-path latency is dominated by stack-trace parsing

A `SEVERE`-level entry with an `exception` and `stackTrace` cost roughly
690–710µs on terminal/CI presets in this run—orders of magnitude more than a
plain INFO. The matching deep-dive breakdown is:

| Step                                              | Median  |
| ------------------------------------------------- | ------: |
| `StackTrace.current` capture | 633ns |
| `Chain.forTrace(StackTrace.current)` (raw parse) | 126.7µs |
| `StackTraceParser` (filtering + formatting, n=10) | 177.8µs |
| `CallerExtractor.extract` | 149.6µs |
| `ContentExtractor.extract` (full error record) | 709.1µs |
| `ContentExtractor.extract` (simple INFO, no stack) | 66ns |
| Bare `ComposablePrinter` error (`methodCount: 0`) | 442ns |

Cloud printers (GCP/AWS/Azure) skip the chain parse — they pass the
stack trace through `toString()` straight into the JSON — so error
records cost roughly 24µs, not the 690–710µs measured for terminal/CI. That
asymmetry is intentional: human readers want pretty per-frame output; cloud
aggregators want raw text.

If your service emits sustained high-rate error logs and you don't need
stack-trace grooming, prefer a cloud printer or configure the composable
printer/preset with `methodCount: 0` and a null or zero `errorMethodCount`. That
made the complete bare-printer error path 442ns in this run. The extractor
checks the effective frame count before constructing a stack chain, so this
fast path does not inspect the attached trace.

### Stack-capture cost

`captureStackTrace: true` (the default) calls `StackTrace.current` on
every log call that doesn't pass an explicit `method:`. Capture alone measured
633ns per call in this run. On a hot loop, set `captureStackTrace: false` in
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

Created directly for native calls or from a third-party `logging.LogRecord` in
`_handleLogRecord()`. This is the public-facing record type that printers
receive. For native calls, the `object` field contains the `LogMessage`, which
printers like
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
| `logging` | Public level/record adapters and inbound third-party record stream |
| `stack_trace` | Stack trace parsing and caller extraction |
| `universal_io` | Cross-platform `dart:io` for ANSI detection |
| `web` | Web console APIs for `WebConsolePrinter` |
