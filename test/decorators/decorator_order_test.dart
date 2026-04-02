import 'package:hyper_logger/hyper_logger.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Applies [decorators] in order to a fresh [LogStyle] and returns it.
LogStyle _apply(List<LogDecorator> decorators) {
  final style = LogStyle();
  for (final d in decorators) {
    d.apply(style);
  }
  return style;
}

/// Verifies that all permutations of [decorators] produce the same flag values
/// for every field touched by those decorators.
///
/// [verify] receives each resulting [LogStyle] and should call `expect`.
void _assertOrderIndependent(
  List<LogDecorator> decorators,
  void Function(LogStyle) verify,
) {
  final permutations = _permute(decorators);
  for (final perm in permutations) {
    verify(_apply(perm));
  }
}

/// Returns all permutations of [items].
List<List<T>> _permute<T>(List<T> items) {
  if (items.isEmpty) return [[]];
  final result = <List<T>>[];
  for (var i = 0; i < items.length; i++) {
    final rest = [...items]..removeAt(i);
    for (final perm in _permute(rest)) {
      result.add([items[i], ...perm]);
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ---- Individual decorator correctness ------------------------------------

  group('BoxDecorator', () {
    test('sets box=true with default lineLength', () {
      final style = _apply([const BoxDecorator()]);
      expect(style.box, isTrue);
      expect(style.lineLength, 120);
    });

    test('sets custom lineLength', () {
      final style = _apply([const BoxDecorator(lineLength: 80)]);
      expect(style.box, isTrue);
      expect(style.lineLength, 80);
    });
  });

  group('EmojiDecorator', () {
    test('sets emoji=true with no custom emojis', () {
      final style = _apply([const EmojiDecorator()]);
      expect(style.emoji, isTrue);
      expect(style.levelEmojis, isNull);
    });

    test('sets custom emojis', () {
      final emojis = {Level.INFO: '💡', Level.WARNING: '⚠️'};
      final style = _apply([EmojiDecorator(customEmojis: emojis)]);
      expect(style.emoji, isTrue);
      expect(style.levelEmojis, same(emojis));
    });
  });

  group('AnsiColorDecorator', () {
    test('sets ansiColors=true with no custom colors', () {
      final style = _apply([const AnsiColorDecorator()]);
      expect(style.ansiColors, isTrue);
      expect(style.levelColors, isNull);
    });

    test('sets custom level colors', () {
      final colors = {Level.SEVERE: AnsiColor.red};
      final style = _apply([AnsiColorDecorator(customLevelColors: colors)]);
      expect(style.ansiColors, isTrue);
      expect(style.levelColors, same(colors));
    });
  });

  group('TimestampDecorator', () {
    test('sets timestamp=true with default formatter', () {
      final style = _apply([const TimestampDecorator()]);
      expect(style.timestamp, isTrue);
      expect(style.dateTimeFormatter, isNotNull);
      final dt = DateTime(2026, 1, 15, 12, 30);
      expect(style.dateTimeFormatter!(dt), dt.toIso8601String());
    });

    test('sets custom formatter', () {
      String myFormat(DateTime dt) => '${dt.year}';
      final style = _apply([TimestampDecorator(formatter: myFormat)]);
      expect(style.timestamp, isTrue);
      expect(style.dateTimeFormatter, same(myFormat));
    });
  });

  group('PrefixDecorator', () {
    test('sets prefix=true', () {
      // LogStyle.prefix defaults to true; explicitly verify the decorator sets it.
      final style = LogStyle()..prefix = false;
      const PrefixDecorator().apply(style);
      expect(style.prefix, isTrue);
    });
  });

  // ---- Order independence --------------------------------------------------

  group('order independence — Box + Color + Emoji', () {
    final decorators = [
      const BoxDecorator(),
      const AnsiColorDecorator(),
      const EmojiDecorator(),
    ];

    test('all 6 permutations set the same flags', () {
      _assertOrderIndependent(decorators, (style) {
        expect(style.box, isTrue, reason: 'box should be true');
        expect(style.ansiColors, isTrue, reason: 'ansiColors should be true');
        expect(style.emoji, isTrue, reason: 'emoji should be true');
        // Unrelated flags must remain at their defaults.
        expect(style.timestamp, isFalse);
        expect(style.prefix, isTrue); // LogStyle default
      });
    });
  });

  group('order independence — custom config preserved', () {
    final customEmojis = {Level.INFO: '🔵'};
    final customColors = {Level.WARNING: AnsiColor.yellow};
    String customFormatter(DateTime dt) => dt.millisecondsSinceEpoch.toString();

    final decorators = [
      const BoxDecorator(lineLength: 200),
      EmojiDecorator(customEmojis: customEmojis),
      AnsiColorDecorator(customLevelColors: customColors),
      TimestampDecorator(formatter: customFormatter),
      const PrefixDecorator(),
    ];

    test('all permutations preserve custom config', () {
      _assertOrderIndependent(decorators, (style) {
        expect(style.lineLength, 200);
        expect(style.levelEmojis, same(customEmojis));
        expect(style.levelColors, same(customColors));
        expect(style.dateTimeFormatter, same(customFormatter));
        expect(style.box, isTrue);
        expect(style.emoji, isTrue);
        expect(style.ansiColors, isTrue);
        expect(style.timestamp, isTrue);
        expect(style.prefix, isTrue);
      });
    });
  });

  group('order independence — all decorators together', () {
    final decorators = [
      const BoxDecorator(),
      const EmojiDecorator(),
      const AnsiColorDecorator(),
      const TimestampDecorator(),
      const PrefixDecorator(),
    ];

    test('all 120 permutations produce correct flags', () {
      _assertOrderIndependent(decorators, (style) {
        expect(style.box, isTrue);
        expect(style.emoji, isTrue);
        expect(style.ansiColors, isTrue);
        expect(style.timestamp, isTrue);
        expect(style.prefix, isTrue);
        expect(style.lineLength, 120); // BoxDecorator default
        expect(style.levelEmojis, isNull);
        expect(style.levelColors, isNull);
        expect(
          style.dateTimeFormatter,
          isNotNull,
        ); // TimestampDecorator default
      });
    });
  });

  group('decorators do not overwrite each other\'s fields', () {
    test('BoxDecorator does not touch emoji/ansiColors/timestamp/prefix', () {
      final style = _apply([const BoxDecorator()]);
      expect(style.emoji, isFalse);
      expect(style.ansiColors, isFalse);
      expect(style.timestamp, isFalse);
      expect(style.levelEmojis, isNull);
      expect(style.levelColors, isNull);
      expect(style.dateTimeFormatter, isNull);
    });

    test('EmojiDecorator does not touch box/ansiColors/timestamp', () {
      final style = _apply([const EmojiDecorator()]);
      expect(style.box, isFalse);
      expect(style.ansiColors, isFalse);
      expect(style.timestamp, isFalse);
      expect(style.lineLength, 120);
      expect(style.levelColors, isNull);
      expect(style.dateTimeFormatter, isNull);
    });

    test('AnsiColorDecorator does not touch box/emoji/timestamp', () {
      final style = _apply([const AnsiColorDecorator()]);
      expect(style.box, isFalse);
      expect(style.emoji, isFalse);
      expect(style.timestamp, isFalse);
      expect(style.lineLength, 120);
      expect(style.levelEmojis, isNull);
      expect(style.dateTimeFormatter, isNull);
    });

    test('TimestampDecorator does not touch box/emoji/ansiColors', () {
      final style = _apply([const TimestampDecorator()]);
      expect(style.box, isFalse);
      expect(style.emoji, isFalse);
      expect(style.ansiColors, isFalse);
      expect(style.lineLength, 120);
      expect(style.levelEmojis, isNull);
      expect(style.levelColors, isNull);
    });
  });
}
