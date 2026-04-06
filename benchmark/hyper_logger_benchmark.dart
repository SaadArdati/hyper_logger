// ignore_for_file: avoid_print
import 'package:hyper_logger/hyper_logger.dart';

import 'shared/noop_output.dart';
import 'shared/scenarios.dart';

/// Comprehensive benchmark suite for hyper_logger.
///
/// Measures:
/// 1. Throughput per preset (messages/sec) — simple message
/// 2. Throughput with structured data
/// 3. Throughput with error + stack trace
/// 4. Disabled/filtered message cost (should be near-zero)
/// 5. Varied message throughput (prevents constant folding)
/// 6. Raw baseline (DirectPrinter, bare ComposablePrinter)
///
/// Run: dart run benchmark/hyper_logger_benchmark.dart
void main() {
  print('');
  print('hyper_logger benchmark suite');
  print('=' * 70);
  print('');
  print(
    'Each benchmark: $_kWarmup warmup iterations, '
    '$_kSamples samples of $_kIterationsPerSample iterations each.',
  );
  print('Reports: median ns/op, mean ns/op, min ns/op, stddev, ops/sec');
  print('');

  // ── 1. Throughput per preset — simple INFO message ────────────────────

  _header('1. Simple INFO message — throughput per preset');

  final noop = NoopOutput();

  _bench('DirectPrinter', () {
    final p = DirectPrinter(output: noop.call);
    return () => p.log(BenchmarkScenarios.simpleInfo);
  });

  _bench('ComposablePrinter (bare, no decorators)', () {
    final p = ComposablePrinter(const [], output: noop.call);
    return () {
      final lines = p.format(BenchmarkScenarios.simpleInfo);
      for (int i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    };
  });

  _bench('Preset: ci (timestamp + prefix)', () {
    final p = LogPrinterPresets.ci(output: noop.call);
    return () {
      final lines = p.format(BenchmarkScenarios.simpleInfo);
      for (int i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    };
  });

  _bench('Preset: ide (emoji + prefix)', () {
    final p = LogPrinterPresets.ide(output: noop.call);
    return () {
      final lines = p.format(BenchmarkScenarios.simpleInfo);
      for (int i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    };
  });

  _bench('Preset: terminal (emoji + box + color + prefix)', () {
    final p = LogPrinterPresets.terminal(output: noop.call);
    return () {
      final lines = p.format(BenchmarkScenarios.simpleInfo);
      for (int i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    };
  });

  _bench('Preset: cloudRun (JSON)', () {
    final p = LogPrinterPresets.cloudRun(output: noop.call);
    return () {
      final lines = p.format(BenchmarkScenarios.simpleInfo);
      for (int i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    };
  });

  // ── 2. With structured data ───────────────────────────────────────────

  _header('2. INFO message with structured data (Map)');

  _bench('Preset: terminal', () {
    final p = LogPrinterPresets.terminal(output: noop.call);
    return () {
      final lines = p.format(BenchmarkScenarios.withData);
      for (int i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    };
  });

  _bench('Preset: ci', () {
    final p = LogPrinterPresets.ci(output: noop.call);
    return () {
      final lines = p.format(BenchmarkScenarios.withData);
      for (int i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    };
  });

  _bench('Preset: cloudRun (JSON)', () {
    final p = LogPrinterPresets.cloudRun(output: noop.call);
    return () {
      final lines = p.format(BenchmarkScenarios.withData);
      for (int i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    };
  });

  // ── 3. With error + stack trace ───────────────────────────────────────

  _header('3. SEVERE message with error + stack trace');

  _bench('Preset: terminal', () {
    final p = LogPrinterPresets.terminal(output: noop.call);
    return () {
      final lines = p.format(BenchmarkScenarios.withError);
      for (int i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    };
  });

  _bench('Preset: ci', () {
    final p = LogPrinterPresets.ci(output: noop.call);
    return () {
      final lines = p.format(BenchmarkScenarios.withError);
      for (int i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    };
  });

  _bench('Preset: cloudRun (JSON)', () {
    final p = LogPrinterPresets.cloudRun(output: noop.call);
    return () {
      final lines = p.format(BenchmarkScenarios.withError);
      for (int i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    };
  });

  // ── 4. Disabled / filtered message cost ───────────────────────────────

  _header('4. Disabled / filtered message cost');

  _bench('ScopedLogger (mode: disabled)', () {
    HyperLogger.init(
      printer: DirectPrinter(output: noop.call),
      mode: LogMode.silent,
    );
    final wrapper = ScopedLogger<String>(
      options: const LoggerOptions(mode: LogMode.disabled),
    );
    return () => wrapper.info('should be suppressed');
  });

  _bench('ScopedLogger (minLevel: WARNING, sending INFO)', () {
    HyperLogger.init(
      printer: DirectPrinter(output: noop.call),
      mode: LogMode.silent,
    );
    final wrapper = ScopedLogger<String>(
      options: const LoggerOptions(minLevel: LogLevel.warning),
    );
    return () => wrapper.info('should be filtered');
  });

  _bench('Silent mode (HyperLogger.init mode: silent)', () {
    HyperLogger.init(
      printer: DirectPrinter(output: noop.call),
      mode: LogMode.silent,
    );
    return () => HyperLogger.info<String>('suppressed by silent');
  });

  // ── 5. Varied messages (anti constant-folding) ────────────────────────

  _header('5. Varied messages (100 unique records, round-robin)');

  _bench('Preset: terminal', () {
    final p = LogPrinterPresets.terminal(output: noop.call);
    final records = BenchmarkScenarios.varied;
    int idx = 0;
    return () {
      final lines = p.format(records[idx % records.length]);
      for (int i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
      idx++;
    };
  });

  _bench('Preset: ci', () {
    final p = LogPrinterPresets.ci(output: noop.call);
    final records = BenchmarkScenarios.varied;
    int idx = 0;
    return () {
      final lines = p.format(records[idx % records.length]);
      for (int i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
      idx++;
    };
  });

  _bench('Preset: cloudRun (JSON)', () {
    final p = LogPrinterPresets.cloudRun(output: noop.call);
    final records = BenchmarkScenarios.varied;
    int idx = 0;
    return () {
      final lines = p.format(records[idx % records.length]);
      for (int i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
      idx++;
    };
  });

  // ── 6. Different log levels through terminal ──────────────────────────

  _header('6. Different log levels — terminal preset');

  for (final entry in {
    'DEBUG (FINE)': BenchmarkScenarios.simpleDebug,
    'INFO': BenchmarkScenarios.simpleInfo,
    'WARNING': BenchmarkScenarios.simpleWarning,
    'SEVERE': BenchmarkScenarios.simpleSevere,
  }.entries) {
    _bench('Level: ${entry.key}', () {
      final p = LogPrinterPresets.terminal(output: noop.call);
      return () {
        final lines = p.format(entry.value);
        for (int i = 0; i < lines.length; i++) {
          noop.call(lines[i]);
        }
      };
    });
  }

  print('');
  print('=' * 70);
  print('Done. NoopOutput received ${noop.callCount} calls total.');
}

// ── Benchmark infrastructure ──────────────────────────────────────────────────

const int _kWarmup = 500;
const int _kSamples = 20;
const int _kIterationsPerSample = 10000;

void _header(String title) {
  print('');
  print('── $title ${'─' * (66 - title.length)}');
  print('');
  print(
    '  ${'Name'.padRight(52)} '
    '${'median'.padLeft(8)} '
    '${'mean'.padLeft(8)} '
    '${'min'.padLeft(8)} '
    '${'stddev'.padLeft(8)} '
    '${'ops/sec'.padLeft(12)}',
  );
  print('  ${'─' * 100}');
}

/// Runs a benchmark.
///
/// [setupFn] returns the hot function to measure. Setup runs once outside
/// the measurement loop.
void _bench(String name, void Function() Function() setupFn) {
  final fn = setupFn();

  // Warmup
  for (int i = 0; i < _kWarmup; i++) {
    fn();
  }

  // Collect samples
  final durations = <double>[];
  final sw = Stopwatch();

  for (int s = 0; s < _kSamples; s++) {
    sw
      ..reset()
      ..start();
    for (int i = 0; i < _kIterationsPerSample; i++) {
      fn();
    }
    sw.stop();
    final nsPerOp = (sw.elapsedMicroseconds * 1000) / _kIterationsPerSample;
    durations.add(nsPerOp);
  }

  // Statistics
  durations.sort();
  final median = durations[durations.length ~/ 2];
  final mean = durations.reduce((a, b) => a + b) / durations.length;
  final min = durations.first;

  final variance =
      durations.map((d) => (d - mean) * (d - mean)).reduce((a, b) => a + b) /
      durations.length;
  final stddev = _sqrt(variance);
  final opsPerSec = (1e9 / median).round();

  print(
    '  ${name.padRight(52)} '
    '${_fmtNs(median).padLeft(8)} '
    '${_fmtNs(mean).padLeft(8)} '
    '${_fmtNs(min).padLeft(8)} '
    '${_fmtNs(stddev).padLeft(8)} '
    '${_fmtOps(opsPerSec).padLeft(12)}',
  );
}

String _fmtNs(double ns) {
  if (ns >= 1e6) return '${(ns / 1e6).toStringAsFixed(1)}ms';
  if (ns >= 1e3) return '${(ns / 1e3).toStringAsFixed(1)}us';
  return '${ns.toStringAsFixed(0)}ns';
}

String _fmtOps(int ops) {
  if (ops >= 1e6) return '${(ops / 1e6).toStringAsFixed(2)}M';
  if (ops >= 1e3) return '${(ops / 1e3).toStringAsFixed(1)}K';
  return '$ops';
}

/// Integer square root approximation via Newton's method (avoids dart:math).
double _sqrt(double x) {
  if (x <= 0) return 0;
  double guess = x / 2;
  for (int i = 0; i < 20; i++) {
    guess = (guess + x / guess) / 2;
  }
  return guess;
}
