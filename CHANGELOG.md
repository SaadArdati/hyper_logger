## 0.0.1

- Initial release.
- Composable decorator pipeline with order-independent application.
- Built-in decorators: emoji, ANSI color (24-bit true color), box borders, timestamps, class/method prefix.
- Environment presets: `terminal()`, `ide()`, `ci()`, `cloudRun()`, `automatic()`.
- Automatic environment detection (Cloud Run, CI, IDE, terminal).
- `JsonPrinter` for structured JSON logging (Google Cloud Logging compatible).
- `WebConsolePrinter` for browser DevTools output.
- `HyperLoggerMixin` for instance-method logging with automatic type resolution.
- `HyperLoggerWrapper` with `LoggerOptions` for per-module configuration.
- Crash reporting and analytics delegate support.
- Silent mode for tests.
- Auto-initialization with platform defaults.
