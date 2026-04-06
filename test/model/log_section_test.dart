import 'package:hyper_logger/src/model/log_section.dart';
import 'package:test/test.dart';

void main() {
  group('SectionKind', () {
    test('has all expected values', () {
      expect(
        SectionKind.values,
        containsAll([
          SectionKind.message,
          SectionKind.data,
          SectionKind.error,
          SectionKind.stackTrace,
          SectionKind.timestamp,
        ]),
      );
    });

    test('has exactly 5 values', () {
      expect(SectionKind.values, hasLength(5));
    });
  });

  group('LogSection', () {
    test('stores kind', () {
      const section = LogSection(SectionKind.message, ['hello']);
      expect(section.kind, SectionKind.message);
    });

    test('stores lines', () {
      const section = LogSection(SectionKind.data, ['line1', 'line2']);
      expect(section.lines, ['line1', 'line2']);
    });

    test('stores empty lines list', () {
      const section = LogSection(SectionKind.error, []);
      expect(section.lines, isEmpty);
    });

    test('stores multi-line content for stackTrace kind', () {
      final lines = ['frame1', 'frame2', 'frame3'];
      final section = LogSection(SectionKind.stackTrace, lines);
      expect(section.kind, SectionKind.stackTrace);
      expect(section.lines, lines);
    });

    test('stores timestamp kind', () {
      const section = LogSection(SectionKind.timestamp, [
        '2026-01-01T00:00:00',
      ]);
      expect(section.kind, SectionKind.timestamp);
      expect(section.lines, hasLength(1));
    });
  });
}
