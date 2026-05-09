// ignore_for_file: avoid_print
import 'package:hyper_logger/hyper_logger.dart';

import 'shared/noop_output.dart';
import 'shared/scenarios.dart';

/// Compares the three cloud JSON printers against each other to verify
/// that the round-10b CloudJsonPrinterBase refactor didn't introduce
/// regressions and that AzureJsonPrinter (numeric severityLevel +
/// nested customDimensions) is in the same performance class.
///
/// Run: `dart run benchmark/cloud_parity_benchmark.dart`
void main() {
  print('Cloud JSON printer parity benchmark');
  print('=' * 70);

  final noop = NoopOutput();
  const warmup = 500;
  const samples = 20;
  const iter = 10000;

  void bench(String name, void Function() body) {
    for (var i = 0; i < warmup; i++) {
      body();
    }
    final medians = <int>[];
    for (var s = 0; s < samples; s++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < iter; i++) {
        body();
      }
      sw.stop();
      medians.add(sw.elapsedMicroseconds);
    }
    medians.sort();
    final medianUs = medians[medians.length ~/ 2];
    final nsPerOp = (medianUs * 1000) ~/ iter;
    final opsPerSec = nsPerOp == 0 ? 0 : 1000000000 ~/ nsPerOp;
    print(
      '  ${name.padRight(50)}  ${nsPerOp.toString().padLeft(6)}ns'
      '  ${(opsPerSec / 1000).toStringAsFixed(1).padLeft(7)}K ops/sec',
    );
  }

  print('');
  print('── 1. Simple INFO ───────────────────────────────────────────────');
  {
    final p = GcpJsonPrinter(output: noop.call);
    bench('GcpJsonPrinter', () {
      final lines = p.format(BenchmarkScenarios.simpleInfo);
      for (var i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    });
  }
  {
    final p = AwsJsonPrinter(output: noop.call);
    bench('AwsJsonPrinter', () {
      final lines = p.format(BenchmarkScenarios.simpleInfo);
      for (var i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    });
  }
  {
    final p = AzureJsonPrinter(output: noop.call);
    bench('AzureJsonPrinter', () {
      final lines = p.format(BenchmarkScenarios.simpleInfo);
      for (var i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    });
  }

  print('');
  print('── 2. INFO with structured data ────────────────────────────────');
  {
    final p = GcpJsonPrinter(output: noop.call);
    bench('GcpJsonPrinter (flat at root)', () {
      final lines = p.format(BenchmarkScenarios.withData);
      for (var i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    });
  }
  {
    final p = AwsJsonPrinter(output: noop.call);
    bench('AwsJsonPrinter (flat at root)', () {
      final lines = p.format(BenchmarkScenarios.withData);
      for (var i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    });
  }
  {
    final p = AzureJsonPrinter(output: noop.call);
    bench('AzureJsonPrinter (nests under customDimensions)', () {
      final lines = p.format(BenchmarkScenarios.withData);
      for (var i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    });
  }

  print('');
  print('── 3. SEVERE with error + stack trace ──────────────────────────');
  {
    final p = GcpJsonPrinter(output: noop.call);
    bench('GcpJsonPrinter', () {
      final lines = p.format(BenchmarkScenarios.withError);
      for (var i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    });
  }
  {
    final p = AwsJsonPrinter(output: noop.call);
    bench('AwsJsonPrinter', () {
      final lines = p.format(BenchmarkScenarios.withError);
      for (var i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    });
  }
  {
    final p = AzureJsonPrinter(output: noop.call);
    bench('AzureJsonPrinter', () {
      final lines = p.format(BenchmarkScenarios.withError);
      for (var i = 0; i < lines.length; i++) {
        noop.call(lines[i]);
      }
    });
  }

  print('');
  print('Done. NoopOutput received ${noop.callCount} calls.');
}
