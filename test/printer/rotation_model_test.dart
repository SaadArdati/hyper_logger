@TestOn('vm')
library;

import 'package:hyper_logger/hyper_logger.dart';
import 'package:test/test.dart';

void main() {
  group('FileRotation', () {
    test('size defaults to continuous cadence', () {
      final r = FileRotation.size(1024);
      expect(r.maxBytes, 1024);
      expect(r.interval, isNull);
      expect(r.unconditional, isFalse);
      expect(r.cadence, Cadence.continuous);
      expect(r.discard, isFalse);
    });

    test('size accepts explicit onStart cadence', () {
      final r = FileRotation.size(1024, cadence: Cadence.onStart);
      expect(r.cadence, Cadence.onStart);
    });

    test('size with maxBytes <= 0 throws', () {
      expect(() => FileRotation.size(0), throwsArgumentError);
      expect(() => FileRotation.size(-1), throwsArgumentError);
    });

    test('interval defaults to continuous, validates positivity', () {
      final r = FileRotation.interval(const Duration(hours: 1));
      expect(r.interval, const Duration(hours: 1));
      expect(r.cadence, Cadence.continuous);
      expect(() => FileRotation.interval(Duration.zero), throwsArgumentError);
      expect(
        () => FileRotation.interval(const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });

    test('daily is interval of 1 day', () {
      final r = FileRotation.daily();
      expect(r.interval, const Duration(days: 1));
      expect(r.cadence, Cadence.continuous);
    });

    test('daily accepts onStart cadence', () {
      expect(
        FileRotation.daily(cadence: Cadence.onStart).cadence,
        Cadence.onStart,
      );
    });

    test('onStart is unconditional and start-only', () {
      final r = FileRotation.onStart();
      expect(r.unconditional, isTrue);
      expect(r.cadence, Cadence.onStart);
      expect(r.discard, isFalse);
      expect(r.maxBytes, isNull);
      expect(r.interval, isNull);
    });

    test('onStart can discard', () {
      expect(FileRotation.onStart(discard: true).discard, isTrue);
    });
  });

  group('FileRetention', () {
    test('defaults are keep-all, no compress', () {
      final r = FileRetention();
      expect(r.maxFiles, isNull);
      expect(r.maxAge, isNull);
      expect(r.compress, isFalse);
    });

    test('validates maxFiles > 0 or null', () {
      expect(() => FileRetention(maxFiles: 0), throwsArgumentError);
      expect(() => FileRetention(maxFiles: -3), throwsArgumentError);
      expect(FileRetention(maxFiles: 5).maxFiles, 5);
    });

    test('validates maxAge > zero or null', () {
      expect(() => FileRetention(maxAge: Duration.zero), throwsArgumentError);
      expect(
        () => FileRetention(maxAge: const Duration(days: -1)),
        throwsArgumentError,
      );
      expect(
        FileRetention(maxAge: const Duration(days: 30)).maxAge,
        const Duration(days: 30),
      );
    });

    test('compress can be enabled', () {
      expect(FileRetention(compress: true).compress, isTrue);
    });
  });
}
