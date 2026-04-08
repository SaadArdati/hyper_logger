## 0.1.0

- Initial public release.
- Composable decorator pipeline with order-independent application.
- Built-in decorators: emoji, ANSI color (24-bit true color), box borders, timestamps, class/method prefix.
- Environment presets: `terminal()`, `ide()`, `ci()`, `cloudRun()`, `automatic()`.
- Automatic environment detection (Cloud Run, CI, IDE, terminal).
- `JsonPrinter` for structured JSON logging (Google Cloud Logging compatible).
- `WebConsolePrinter` for browser DevTools output.
- `ThrottledPrinter` for rate-limited output in hot loops.
- `HyperLoggerMixin` for instance-method logging with automatic type resolution.
- `ScopedLogger` with `LoggerOptions` for per-module configuration.
- Crash reporting delegate support (`CrashReportingDelegate`).
- `LogMode` enum (`enabled`, `silent`, `disabled`) at both global and per-scope levels.
- Auto-initialization with platform defaults. Zero config required.
- Trimmed public API surface: pipeline internals no longer exported from barrel.
