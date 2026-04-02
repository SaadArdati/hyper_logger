import 'package:hyper_logger/hyper_logger.dart';
import 'package:test/test.dart';

void main() {
  group('LogStyle defaults', () {
    late LogStyle style;

    setUp(() => style = LogStyle());

    test('box defaults to false', () => expect(style.box, isFalse));
    test('emoji defaults to false', () => expect(style.emoji, isFalse));
    test(
      'ansiColors defaults to false',
      () => expect(style.ansiColors, isFalse),
    );
    test('timestamp defaults to false', () => expect(style.timestamp, isFalse));
    test('prefix defaults to true', () => expect(style.prefix, isTrue));
    test('lineLength defaults to 120', () => expect(style.lineLength, 120));
    test('stackTraceMethodCount defaults to null', () {
      expect(style.stackTraceMethodCount, isNull);
    });
    test(
      'levelEmojis defaults to null',
      () => expect(style.levelEmojis, isNull),
    );
    test(
      'levelColors defaults to null',
      () => expect(style.levelColors, isNull),
    );
    test('dateTimeFormatter defaults to null', () {
      expect(style.dateTimeFormatter, isNull);
    });
  });

  group('LogStyle mutability', () {
    test('box can be set to true', () {
      final style = LogStyle()..box = true;
      expect(style.box, isTrue);
    });

    test('emoji can be set to true', () {
      final style = LogStyle()..emoji = true;
      expect(style.emoji, isTrue);
    });

    test('ansiColors can be set to true', () {
      final style = LogStyle()..ansiColors = true;
      expect(style.ansiColors, isTrue);
    });

    test('timestamp can be set to true', () {
      final style = LogStyle()..timestamp = true;
      expect(style.timestamp, isTrue);
    });

    test('prefix can be set to false', () {
      final style = LogStyle()..prefix = false;
      expect(style.prefix, isFalse);
    });

    test('lineLength can be changed', () {
      final style = LogStyle()..lineLength = 80;
      expect(style.lineLength, 80);
    });

    test('stackTraceMethodCount can be set', () {
      final style = LogStyle()..stackTraceMethodCount = 5;
      expect(style.stackTraceMethodCount, 5);
    });

    test('dateTimeFormatter can be set and called', () {
      final style = LogStyle()
        ..dateTimeFormatter = (dt) => dt.toIso8601String();
      final dt = DateTime(2026, 1, 1);
      expect(style.dateTimeFormatter!(dt), dt.toIso8601String());
    });
  });
}
