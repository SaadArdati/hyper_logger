// ignore_for_file: avoid_print
import 'package:hyper_logger/hyper_logger.dart';
import 'package:hyper_logger/src/extraction/caller_extractor.dart';
import 'package:logging/logging.dart' as logging;
import 'package:stack_trace/stack_trace.dart' as st;

import 'shared/noop_output.dart';
import 'shared/scenarios.dart';

/// Deep-dive benchmarks targeting the three hotspots found in the main suite:
///
/// 1. Stack trace parsing (~400us) — where does the time go?
/// 2. Bare ComposablePrinter overhead (402ns) — extraction pipeline cost
/// 3. Silent mode vs disabled wrapper (803ns vs 5ns) — the 160x gap
///
/// Run: dart run benchmark/deep_dive_benchmark.dart
void main() {
  logging.hierarchicalLoggingEnabled = true;
  logging.Logger.root.level = logging.Level.OFF;

  final noop = NoopOutput();

  print('');
  print('hyper_logger deep-dive benchmarks');
  print('=' * 70);
  print('');
  print(
    'Config: $_kWarmup warmup, $_kSamples samples x '
    '$_kIterationsPerSample iterations',
  );
  print('');

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. STACK TRACE PARSING BREAKDOWN
  // ═══════════════════════════════════════════════════════════════════════════

  _header('1a. Chain.forTrace — raw parsing cost');

  // Capture a real stack trace once, reuse for consistent measurement.
  final realStack = StackTrace.current;

  _bench('Chain.forTrace(StackTrace.current)', () {
    return () {
      final chain = st.Chain.forTrace(realStack);
      noop.callCount += chain.traces.length; // prevent DCE
    };
  });

  _header('1b. StackTraceParser.parse — filtering + formatting');

  final _ = st.Chain.forTrace(realStack);

  _bench('StackTraceParser (methodCount=10)', () {
    final parser = StackTraceParser(
      methodCount: 10,
      excludePaths: const [],
      showAsyncGaps: false,
    );
    return () {
      final lines = parser.parse(realStack, isError: true);
      noop.callCount += lines.length;
    };
  });

  _bench('StackTraceParser (methodCount=3)', () {
    final parser = StackTraceParser(
      methodCount: 3,
      excludePaths: const [],
      showAsyncGaps: false,
    );
    return () {
      final lines = parser.parse(realStack, isError: true);
      noop.callCount += lines.length;
    };
  });

  _bench('StackTraceParser (methodCount=0, skip entirely)', () {
    final parser = StackTraceParser(
      methodCount: 0,
      excludePaths: const [],
      showAsyncGaps: false,
    );
    return () {
      final lines = parser.parse(realStack, isError: true);
      noop.callCount += lines.length;
    };
  });

  _header('1c. CallerExtractor — class/method extraction');

  _bench('CallerExtractor.extract(StackTrace.current)', () {
    final extractor = CallerExtractor();
    return () {
      final info = extractor.extract(realStack);
      if (info != null) noop.callCount++;
    };
  });

  _header('1d. Full error pipeline breakdown');

  _bench('ContentExtractor.extract (error record)', () {
    final extractor = ContentExtractor(
      stackTraceParser: StackTraceParser(
        methodCount: 10,
        excludePaths: const [],
        showAsyncGaps: false,
      ),
      callerExtractor: CallerExtractor(),
    );
    return () {
      final result = extractor.extract(BenchmarkScenarios.withError);
      noop.callCount += result.sections.length;
    };
  });

  _bench('ContentExtractor.extract (simple INFO, no stack)', () {
    final extractor = ContentExtractor(
      stackTraceParser: StackTraceParser(
        methodCount: 10,
        excludePaths: const [],
        showAsyncGaps: false,
      ),
      callerExtractor: CallerExtractor(),
    );
    return () {
      final result = extractor.extract(BenchmarkScenarios.simpleInfo);
      noop.callCount += result.sections.length;
    };
  });

  _header('1e. StyleResolver + Renderer (no extraction)');

  // Pre-extract so we only measure resolve + render.
  final preExtracted = ContentExtractor(
    stackTraceParser: StackTraceParser(
      methodCount: 10,
      excludePaths: const [],
      showAsyncGaps: false,
    ),
    callerExtractor: CallerExtractor(),
  ).extract(BenchmarkScenarios.simpleInfo);

  final preExtractedError = ContentExtractor(
    stackTraceParser: StackTraceParser(
      methodCount: 10,
      excludePaths: const [],
      showAsyncGaps: false,
    ),
    callerExtractor: CallerExtractor(),
  ).extract(BenchmarkScenarios.withError);

  _bench('Resolve + render (simple INFO, terminal style)', () {
    final style = LogStyle()
      ..emoji = true
      ..box = true
      ..ansiColors = true
      ..prefix = true;
    final resolver = StyleResolver();
    final renderer = LogRenderer(sectionRenderer: SectionRenderer());
    return () {
      final lines = renderer.render(preExtracted, style, resolver);
      noop.callCount += lines.length;
    };
  });

  _bench('Resolve + render (error with stack, terminal style)', () {
    final style = LogStyle()
      ..emoji = true
      ..box = true
      ..ansiColors = true
      ..prefix = true;
    final resolver = StyleResolver();
    final renderer = LogRenderer(sectionRenderer: SectionRenderer());
    return () {
      final lines = renderer.render(preExtractedError, style, resolver);
      noop.callCount += lines.length;
    };
  });

  _bench('Resolve + render (simple INFO, bare style)', () {
    final style = LogStyle()..prefix = false;
    final resolver = StyleResolver();
    final renderer = LogRenderer(sectionRenderer: SectionRenderer());
    return () {
      final lines = renderer.render(preExtracted, style, resolver);
      noop.callCount += lines.length;
    };
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. BARE COMPOSABLEPRINTER OVERHEAD
  // ═══════════════════════════════════════════════════════════════════════════

  _header('2. Bare ComposablePrinter pipeline breakdown');

  _bench('format() → full pipeline (bare printer)', () {
    final p = ComposablePrinter(const [], output: noop.call);
    return () {
      final lines = p.format(BenchmarkScenarios.simpleInfo);
      noop.callCount += lines.length;
    };
  });

  // CallerExtractor is called on every LogMessage because method was
  // provided in our scenario. Let's test with and without.
  _bench('format() simple record WITHOUT LogMessage.method', () {
    final p = ComposablePrinter(const [], output: noop.call);
    // Build a record whose LogMessage has no method set, forcing
    // CallerExtractor to try extraction from callerStackTrace.
    final msg = LogMessage('hello', String);
    final record = logging.LogRecord(
      logging.Level.INFO,
      'hello',
      'Test',
      null,
      null,
      null,
      msg,
    );
    return () {
      final lines = p.format(record);
      noop.callCount += lines.length;
    };
  });

  _bench(
    'format() simple record WITH LogMessage.method (skips caller extraction)',
    () {
      final p = ComposablePrinter(const [], output: noop.call);
      final msg = LogMessage('hello', String, method: 'doWork');
      final record = logging.LogRecord(
        logging.Level.INFO,
        'hello',
        'Test',
        null,
        null,
        null,
        msg,
      );
      return () {
        final lines = p.format(record);
        noop.callCount += lines.length;
      };
    },
  );

  _bench('format() plain string record (no LogMessage)', () {
    final p = ComposablePrinter(const [], output: noop.call);
    final record = logging.LogRecord(logging.Level.INFO, 'hello world', 'Test');
    return () {
      final lines = p.format(record);
      noop.callCount += lines.length;
    };
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. SILENT MODE vs DISABLED WRAPPER
  // ═══════════════════════════════════════════════════════════════════════════

  _header('3. Silent mode cost breakdown');

  _bench('Wrapper disabled: true (early return)', () {
    HyperLogger.init(printer: DirectPrinter(output: noop.call), silent: true);
    final wrapper = HyperLoggerWrapper<String>(
      options: const LoggerOptions(disabled: true),
    );
    return () => wrapper.info('suppressed');
  });

  _bench('HyperLogger.info (silent: true)', () {
    HyperLogger.init(printer: DirectPrinter(output: noop.call), silent: true);
    return () => HyperLogger.info<String>('suppressed');
  });

  _bench('_ensureInitialized + _getLogger (core overhead)', () {
    // This measures the static dispatch path that silent mode still executes:
    // _ensureInitialized → _log → LogMessage() → _getLogger → logger.log
    // Even though the listener drops it, the LogRecord is allocated.
    HyperLogger.init(printer: DirectPrinter(output: noop.call), silent: true);
    // Warm the logger cache for type String
    HyperLogger.info<String>('warmup');
    return () => HyperLogger.info<String>('suppressed');
  });

  _bench('LogMessage construction alone', () {
    return () {
      final msg = LogMessage('test', String, method: 'bench');
      noop.callCount += msg.message.length;
    };
  });

  _bench('logging.Logger.log (logging package overhead)', () {
    final logger = logging.Logger('BenchLogger');
    logger.level = logging.Level.ALL;
    return () {
      logger.log(logging.Level.INFO, 'test message');
    };
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. STRING ALLOCATION PATTERNS
  // ═══════════════════════════════════════════════════════════════════════════

  _header('4. String operations');

  _bench('String.split("\\n") on single-line message', () {
    const msg = 'User logged in successfully';
    return () {
      final parts = msg.split('\n');
      noop.callCount += parts.length;
    };
  });

  _bench('String interpolation: "\$a \$b"', () {
    const a = '2026-04-02T10:30:00Z';
    const b = '[INFO]';
    return () {
      final s = '$a $b';
      noop.callCount += s.length;
    };
  });

  _bench('StringBuffer (3 appends)', () {
    return () {
      final sb = StringBuffer()
        ..write('prefix ')
        ..write('message text')
        ..write(' suffix');
      final s = sb.toString();
      noop.callCount += s.length;
    };
  });

  _bench('AnsiColor.fg getter (cached)', () {
    final color = AnsiColor.fromRGB(0, 23, 59);
    return () {
      noop.callCount += color.fg.length;
    };
  });

  _bench('AnsiColor.bg getter (cached)', () {
    final color = AnsiColor.fromRGB(0, 23, 59);
    return () {
      noop.callCount += color.bg.length;
    };
  });

  print('');
  print('=' * 70);
  print('Done. NoopOutput: ${noop.callCount} calls.');
}

// ── Benchmark infrastructure (same as main suite) ─────────────────────────────

const int _kWarmup = 500;
const int _kSamples = 20;
const int _kIterationsPerSample = 10000;

void _header(String title) {
  print('');
  print('── $title ${'─' * (66 - title.length).clamp(0, 66)}');
  print('');
  print(
    '  ${'Name'.padRight(60)} '
    '${'median'.padLeft(8)} '
    '${'mean'.padLeft(8)} '
    '${'min'.padLeft(8)} '
    '${'ops/sec'.padLeft(12)}',
  );
  print('  ${'─' * 102}');
}

void _bench(String name, void Function() Function() setupFn) {
  final fn = setupFn();

  for (int i = 0; i < _kWarmup; i++) {
    fn();
  }

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
    durations.add((sw.elapsedMicroseconds * 1000) / _kIterationsPerSample);
  }

  durations.sort();
  final median = durations[durations.length ~/ 2];
  final mean = durations.reduce((a, b) => a + b) / durations.length;
  final min = durations.first;
  final opsPerSec = (1e9 / median).round();

  print(
    '  ${name.padRight(60)} '
    '${_fmtNs(median).padLeft(8)} '
    '${_fmtNs(mean).padLeft(8)} '
    '${_fmtNs(min).padLeft(8)} '
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
