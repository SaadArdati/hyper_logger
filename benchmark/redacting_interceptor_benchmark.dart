// ignore_for_file: avoid_print
import 'package:hyper_logger/hyper_logger.dart';

import 'shared/noop_output.dart';
import 'shared/scenarios.dart';

/// Focused hot-path benchmarks for the fail-closed privacy sanitizer.
///
/// Run: dart run benchmark/redacting_interceptor_benchmark.dart
void main() {
  final output = NoopOutput();

  print('');
  print('RedactingInterceptor benchmark');
  print('=' * 72);

  _bench('ordinary text, no literal secrets', () {
    final redactor = RedactingInterceptor();
    return () =>
        output.call(redactor.redactText('User logged in successfully'));
  });

  _bench('ordinary text, three absent secrets', () {
    final redactor = RedactingInterceptor(
      secrets: const ['production-token', 'database-password', 'signing-key'],
    );
    return () =>
        output.call(redactor.redactText('User logged in successfully'));
  });

  _bench('JSON text, no literal secrets', () {
    final redactor = RedactingInterceptor();
    return () =>
        output.call(redactor.redactText('{"event":"login","success":true}'));
  });

  _bench('complete simple LogEntry', () {
    final redactor = RedactingInterceptor();
    return () {
      final entry = redactor(BenchmarkScenarios.simpleInfo);
      if (entry != null) output.call(entry.message);
    };
  });

  _bench('LogEntry with ordinary structured keys', () {
    final redactor = RedactingInterceptor();
    return () {
      final entry = redactor(BenchmarkScenarios.withData);
      if (entry != null) output.call(entry.message);
    };
  });

  _bench('map with a credential-bearing key', () {
    final redactor = RedactingInterceptor();
    const value = {
      'https://user:password@example.test/?access_token=oauth': true,
    };
    return () {
      final redacted = redactor.redactObject(value)! as Map;
      output.call(redacted.keys.single as String);
    };
  });

  _bench('active HTTP credential removal', () {
    final redactor = RedactingInterceptor();
    return () =>
        output.call(redactor.redactText('Authorization: Basic dXNlcjpwYXNz'));
  });

  _bench('native INFO pipeline, no sanitizer', () {
    HyperLogger.init(
      printer: DirectPrinter(output: output.call),
      captureStackTrace: false,
    );
    return () => HyperLogger.info<String>('ordinary message');
  });

  _bench('native INFO pipeline with redactor', () {
    final redactor = RedactingInterceptor();
    HyperLogger.init(
      printer: DirectPrinter(output: output.call),
      sanitizers: [redactor.call],
      captureStackTrace: false,
    );
    return () => HyperLogger.info<String>('ordinary message');
  });

  var suppressedSanitizerCalls = 0;
  _bench('silent error with no eligible sink', () {
    final redactor = RedactingInterceptor(secrets: const ['ignored-secret']);
    HyperLogger.init(
      printer: DirectPrinter(output: output.call),
      mode: LogMode.silent,
      sanitizers: [
        (entry) {
          suppressedSanitizerCalls++;
          return redactor(entry);
        },
      ],
      captureStackTrace: false,
    );
    return () =>
        HyperLogger.error<String>('ignored-secret', skipCrashReporting: true);
  });
  if (suppressedSanitizerCalls != 0) {
    throw StateError('no-sink benchmark unexpectedly ran its sanitizer');
  }

  final overlappingSecret = '${List.filled(32768, 'a').join()}b';
  final overlappingReplacement = List.filled(65536, 'a').join();
  _benchConstruction('constructor, overlapping replacement', () {
    final redactor = RedactingInterceptor(
      secrets: [overlappingSecret],
      replacement: overlappingReplacement,
    );
    output.call(redactor.replacement);
  });

  print('');
  print('NoopOutput received ${output.callCount} calls.');
}

const _warmupIterations = 2000;
const _samples = 12;
const _iterationsPerSample = 20000;

void _bench(String name, void Function() Function() setup) {
  final run = setup();
  for (var index = 0; index < _warmupIterations; index++) {
    run();
  }

  final timings = <double>[];
  final stopwatch = Stopwatch();
  for (var sample = 0; sample < _samples; sample++) {
    stopwatch
      ..reset()
      ..start();
    for (var index = 0; index < _iterationsPerSample; index++) {
      run();
    }
    stopwatch.stop();
    timings.add(stopwatch.elapsedMicroseconds * 1000 / _iterationsPerSample);
  }
  timings.sort();
  final median = timings[timings.length ~/ 2];
  final throughput = 1000000000 / median;
  print(
    '${name.padRight(44)} '
    '${_formatDuration(median).padLeft(9)} '
    '${_formatThroughput(throughput).padLeft(12)}',
  );
}

void _benchConstruction(String name, void Function() run) {
  for (var index = 0; index < 2; index++) {
    run();
  }

  const samples = 8;
  const iterations = 5;
  final timings = <double>[];
  final stopwatch = Stopwatch();
  for (var sample = 0; sample < samples; sample++) {
    stopwatch
      ..reset()
      ..start();
    for (var index = 0; index < iterations; index++) {
      run();
    }
    stopwatch.stop();
    timings.add(stopwatch.elapsedMicroseconds * 1000 / iterations);
  }
  timings.sort();
  final median = timings[timings.length ~/ 2];
  final throughput = 1000000000 / median;
  print(
    '${name.padRight(44)} '
    '${_formatDuration(median).padLeft(9)} '
    '${_formatThroughput(throughput).padLeft(12)}',
  );
}

String _formatDuration(double nanoseconds) => nanoseconds >= 1000
    ? '${(nanoseconds / 1000).toStringAsFixed(2)} us/op'
    : '${nanoseconds.toStringAsFixed(0)} ns/op';

String _formatThroughput(double operationsPerSecond) =>
    operationsPerSecond >= 1000000
    ? '${(operationsPerSecond / 1000000).toStringAsFixed(2)} M/s'
    : '${(operationsPerSecond / 1000).toStringAsFixed(1)} K/s';
