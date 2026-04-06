# Configuration

## `HyperLogger.init()`

| Parameter | Type | Default | Effect |
|---|---|---|---|
| `printer` | `LogPrinter?` | auto-detected | The printer to use |
| `mode` | `LogMode` | `enabled` | Global logging mode |
| `logFilter` | `LogFilter?` | `null` | Per-entry filter predicate |
| `captureStackTrace` | `bool` | `true` | Auto-extract caller method from stack trace. Disable for ~700ns savings per call. |
| `configureLoggingPackage` | `bool` | `true` | Sets `hierarchicalLoggingEnabled` and root level on `package:logging`. Set `false` if another package manages logging config. |
| `maxCacheSize` | `int` | `256` | LRU cache size for loggers and scoped instances |

```dart
HyperLogger.init(
  printer: LogPrinterPresets.terminal(),
  mode: LogMode.enabled,
  captureStackTrace: true,
  logFilter: (entry) => !entry.loggerName.contains('NoisyLib'),
);
```

## Log levels

```dart
HyperLogger.setLogLevel(LogLevel.warning); // Only WARNING and above
```

### `LogLevel` enum

| Value | Label | Emoji | Maps to |
|---|---|---|---|
| `trace` | TRACE | (none) | `Level.FINEST` |
| `debug` | DEBUG | `🐛` | `Level.FINE` |
| `info` | INFO | `💡` | `Level.INFO` |
| `warning` | WARN | `⚠️` | `Level.WARNING` |
| `error` | ERROR | `⛔` | `Level.SEVERE` |
| `fatal` | FATAL | `👾` | `Level.SHOUT` |

### Guarding expensive arguments

```dart
if (HyperLogger.isEnabled(LogLevel.debug)) {
  final snapshot = computeExpensiveDebugState();
  HyperLogger.debug<Engine>('State dump', data: snapshot);
}
```

## Log filtering

The `logFilter` receives a `LogEntry` and returns `false` to suppress:

```dart
HyperLogger.init(
  logFilter: (entry) {
    // Suppress noisy Supabase GoTrue messages
    final name = entry.loggerName.toLowerCase();
    if (name.contains('gotrue')) return false;
    if (name.contains('supabase') && name.contains('auth')) return false;
    return true;
  },
);
```

`LogEntry` fields available for filtering: `level`, `message`, `loggerName`,
`time`, `error`, `stackTrace`, `object`.

## Structured data

Attach a `data` payload to any log call. Maps and iterables are pretty-printed
as indented JSON:

```dart
HyperLogger.info<Portfolio>('Positions loaded', data: {
  'count': 12,
  'totalValue': 45230.50,
  'currency': 'USD',
});
```

## Explicit method names

Pass `method:` to skip the stack trace capture (~700ns faster per call):

```dart
HyperLogger.info<ApiClient>('Request sent', method: 'fetchUser');
```

Or disable stack trace capture globally:

```dart
HyperLogger.init(captureStackTrace: false);
```

## ANSI colors

`AnsiColor` supports true-color (24-bit) terminals:

```dart
AnsiColor.fromRGB(255, 165, 0)    // orange
AnsiColor.fromHex('#FFA500')       // same orange
AnsiColor(0xFFFFA500)              // raw 0xAARRGGBB

final muted = AnsiColor.orange.withBrightness(0.3);
```

Override colors per level:

```dart
AnsiColorDecorator(customLevelColors: {
  LogLevel.warning: AnsiColor.fromHex('#FFA500'),
})
```

Override emojis per level:

```dart
EmojiDecorator(customEmojis: {
  LogLevel.info: 'ℹ️ ',
  LogLevel.error: '🔥 ',
})
```
