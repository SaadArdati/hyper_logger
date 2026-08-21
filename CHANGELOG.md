## Unreleased

## 0.3.0

### Added

- Add `HyperLogger.shutdown()` for graceful teardown that stays disabled until
  the next explicit `init()`.
- Add null-safe `copyWith` transformations to `LogEntry` and `LogMessage`.
- Add an ordered, fail-closed `sanitizers` chain that protects printers and
  crash-reporting delegates after ordinary interceptors.
- Rebuild `RedactingInterceptor` around exact structured keys and paths, HTTP
  field names, URI/form parameter names, JSON decoding, RFC 7468 boundaries,
  bounded traversal, and configured literal secrets. Literal matching uses a
  bounded linear-time multi-pattern automaton, with fail-closed limits on
  matcher construction and sanitized output expansion.
- Add explicit environment-secret collection, application-object encoders,
  exact wildcard paths, and configurable unknown-value handling.
- Add a standards-backed redaction guide covering exact behavior, limits,
  performance, testing, and limitations; mirror every cited source in the
  public Dart API documentation.

### Changed

- Skip record allocation, conversion, interceptors, and sanitizers when the
  current mode and routing flags leave no eligible printer or crash delegate.
- Route native calls directly into the sanitized pipeline; `package:logging`
  remains an inbound bridge for third-party records and never broadcasts raw
  HyperLogger payloads to unrelated root-stream subscribers. Code that relied
  on observing HyperLogger-native calls through `Logger.root.onRecord` should
  use a `LogPrinter`, interceptor, or sanitizer instead.
- Make `LogEntry.message` and `LogEntry.loggerName` canonical across built-in
  printers and synchronize the `LogMessage.message` compatibility mirror after
  every interceptor and sanitizer stage.
- Expose `LogMessage.reportToCrashReporting` as immutable routing metadata so
  custom printers can honor `skipCrashReporting`; delegate dispatch still uses
  the pipeline's internal routing decision.
- Replace the redactor's `sensitiveKeyPattern` parameter with exact
  `RedactionPolicy` sets. Migration: configure `sensitiveKeys`,
  `sensitiveHeaderNames`, and `sensitiveQueryParameters`, and pass the new
  required exact `environmentKeys` list to `fromEnvironment`.
- Skip stack-trace inspection and chain construction when the effective
  `methodCount` is zero; `errorMethodCount` remains the error-entry override.

### Security

- Ensure sanitizer exceptions and `null` results drop entries before every
  configured sink instead of restoring an earlier unsanitized value.
- Revalidate changed candidates to a bounded fixed point so replacement
  composition cannot synthesize an unchecked JSON, HTTP, URI/form, literal, or
  final structured-path representation.
- Reject duplicate decoded names in selected environment JSON, cycles,
  unsupported values when `UnknownValueHandling.dropEntry` is selected, and
  all configured resource-limit violations.
- Keep constructor and pipeline diagnostics generic so confidential input is
  not reflected through errors.

## 0.2.2+2

- Shrink the published archive from 1.1 MB to 168 KB. The README and docs now
  reference the preview images by absolute GitHub URL, so pub.dev proxies them
  from the repository and the PNGs no longer ship to every `pub get`. The
  images themselves are back to full 2x resolution.

## 0.2.2+1

- Restore the README preview images on pub.dev. 0.2.2 excluded `assets/` from
  the published archive.

## 0.2.2

- Compress assets & add .pubignore.
- `LogPrinterPresets.automatic`, `.human`, `.terminal`, and `.ci` now
  forward the full `ComposablePrinter` tuning surface — `methodCount`,
  `errorMethodCount`, `excludePaths`, `showAsyncGaps`, and
  `suppressTypeNames`. Previously a preset only took `output`, so tuning
  stack-trace depth or frame filtering meant abandoning the preset and
  composing the decorator list by hand. On `automatic` the parameters
  reach the `ci`/`human` arms only; the cloud arms emit a raw
  `stackTrace.toString()` and have nothing to tune.
- `ComposablePrinter.defaultMethodCount` — the default frame count (10),
  exposed so wrappers can mirror it instead of copying the literal.

## 0.2.1

- Shorten the package description to satisfy pub.dev's character guideline.

## 0.2.0

### Breaking

- `RotatingFilePrinter` rotation API redesigned. The single
  `rotationConfig: FileRotationConfig.…` parameter is replaced by:
  - `rotations: List<FileRotation>` — a list of rotation rules, each a
    trigger (`FileRotation.size` / `.interval` / `.daily` / `.onStart`)
    crossed with a `Cadence` (`continuous`, checked on every write, or
    `onStart`, checked once when the file opens). Rules compose as a union
    (the first to fire rotates), so size **and** time triggers can now be
    combined. An empty list (the default) appends forever.
  - `retention: FileRetention?` — shared archive policy (`maxFiles`,
    `maxAge`, `compress`). `maxBytes`/`interval` now live on the rule;
    retention knobs moved here.
  - `FileRotationConfig` is removed.

  Migration: `FileRotationConfig.size(maxBytes: N, maxFiles: M, compress: c)`
  → `rotations: [FileRotation.size(N)], retention: FileRetention(maxFiles: M, compress: c)`;
  `FileRotationConfig.interval(interval: D)` → `rotations: [FileRotation.interval(D)]`.

### Added

- `FileRotation.onStart({bool discard})` — rotate (archive) or discard the
  existing log on every process start, e.g. a fresh `server.log` per run.
- `FileRetention.maxAge` — delete rotated archives older than a given
  duration (age parsed from the archive's filename timestamp), pruned on
  each rotation alongside `maxFiles`.

## 0.1.0

- Initial public release.
