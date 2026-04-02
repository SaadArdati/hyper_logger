import 'package:hyper_logger/hyper_logger.dart';
import 'package:test/test.dart';

void main() {
  group('AnsiColor', () {
    group('construction', () {
      test('const constructor stores value', () {
        final color = AnsiColor(0xFF112233);
        expect(color.value, 0xFF112233);
      });

      test('fromRGB packs channels into value', () {
        final color = AnsiColor.fromRGB(0x11, 0x22, 0x33);
        expect(color.r, 0x11);
        expect(color.g, 0x22);
        expect(color.b, 0x33);
      });

      test('fromRGB extracts correct channels', () {
        final color = AnsiColor.fromRGB(255, 128, 0);
        expect(color.r, 255);
        expect(color.g, 128);
        expect(color.b, 0);
      });

      test('fromHex parses 6-digit with hash', () {
        final color = AnsiColor.fromHex('#FF8000');
        expect(color.r, 0xFF);
        expect(color.g, 0x80);
        expect(color.b, 0x00);
      });

      test('fromHex parses 6-digit without hash', () {
        final color = AnsiColor.fromHex('FF8000');
        expect(color.r, 0xFF);
        expect(color.g, 0x80);
        expect(color.b, 0x00);
      });

      test('fromHex parses 3-digit with hash', () {
        final color = AnsiColor.fromHex('#F80');
        expect(color.r, 0xFF);
        expect(color.g, 0x88);
        expect(color.b, 0x00);
      });

      test('fromHex parses 3-digit without hash', () {
        final color = AnsiColor.fromHex('F80');
        expect(color.r, 0xFF);
        expect(color.g, 0x88);
        expect(color.b, 0x00);
      });

      test('fromHex is case-insensitive', () {
        final lower = AnsiColor.fromHex('ff8000');
        final upper = AnsiColor.fromHex('FF8000');
        expect(lower, equals(upper));
      });

      test('fromHex throws on invalid length', () {
        expect(() => AnsiColor.fromHex('#FFFF'), throwsFormatException);
        expect(() => AnsiColor.fromHex('FF'), throwsFormatException);
        expect(() => AnsiColor.fromHex('#FFFFFFF'), throwsFormatException);
      });

      test('fromHex throws on invalid characters', () {
        expect(() => AnsiColor.fromHex('#GGHHII'), throwsFormatException);
      });
    });

    group('component extraction', () {
      test('r extracts red channel', () {
        final color = AnsiColor.fromRGB(0xAB, 0x00, 0x00);
        expect(color.r, 0xAB);
      });

      test('g extracts green channel', () {
        final color = AnsiColor.fromRGB(0x00, 0xCD, 0x00);
        expect(color.g, 0xCD);
      });

      test('b extracts blue channel', () {
        final color = AnsiColor.fromRGB(0x00, 0x00, 0xEF);
        expect(color.b, 0xEF);
      });

      test('channels are independent', () {
        final color = AnsiColor.fromRGB(0x12, 0x34, 0x56);
        expect(color.r, 0x12);
        expect(color.g, 0x34);
        expect(color.b, 0x56);
      });
    });

    group('ANSI codes', () {
      test('fg produces correct 24-bit foreground escape', () {
        final color = AnsiColor.fromRGB(100, 200, 50);
        expect(color.fg, '\x1b[38;2;100;200;50m');
      });

      test('bg produces correct 24-bit background escape', () {
        final color = AnsiColor.fromRGB(100, 200, 50);
        expect(color.bg, '\x1b[48;2;100;200;50m');
      });

      test('fg for black', () {
        expect(AnsiColor.black.fg, '\x1b[38;2;0;0;0m');
      });

      test('bg for white', () {
        expect(AnsiColor.white.bg, '\x1b[48;2;255;255;255m');
      });
    });

    group('none sentinel', () {
      test('none produces empty fg string', () {
        final color = AnsiColor.none();
        expect(color.fg, '');
      });

      test('none produces empty bg string', () {
        final color = AnsiColor.none();
        expect(color.bg, '');
      });

      test('none has sentinel value', () {
        final color = AnsiColor.none();
        expect(color.value, -1);
      });

      test('none instances are equal', () {
        final a = AnsiColor.none();
        final b = AnsiColor.none();
        expect(a, equals(b));
      });

      test('isNone returns true for none', () {
        final color = AnsiColor.none();
        expect(color.isNone, isTrue);
      });

      test('isNone returns false for regular color', () {
        final color = AnsiColor.fromRGB(255, 0, 0);
        expect(color.isNone, isFalse);
      });
    });

    group('reset', () {
      test('reset is the ANSI reset sequence', () {
        expect(AnsiColor.reset, '\x1b[0m');
      });
    });

    group('withBrightness', () {
      test('factor 1.0 returns same color', () {
        final color = AnsiColor.fromRGB(100, 150, 200);
        final result = color.withBrightness(1.0);
        expect(result.r, 100);
        expect(result.g, 150);
        expect(result.b, 200);
      });

      test('factor 0.0 returns black', () {
        final color = AnsiColor.fromRGB(100, 150, 200);
        final result = color.withBrightness(0.0);
        expect(result.r, 0);
        expect(result.g, 0);
        expect(result.b, 0);
      });

      test('factor 0.5 halves channels', () {
        final color = AnsiColor.fromRGB(100, 200, 50);
        final result = color.withBrightness(0.5);
        expect(result.r, 50);
        expect(result.g, 100);
        expect(result.b, 25);
      });

      test('factor > 1.0 clamps at 255', () {
        final color = AnsiColor.fromRGB(200, 200, 200);
        final result = color.withBrightness(2.0);
        expect(result.r, 255);
        expect(result.g, 255);
        expect(result.b, 255);
      });

      test('negative factor clamps at 0', () {
        final color = AnsiColor.fromRGB(100, 150, 200);
        final result = color.withBrightness(-1.0);
        expect(result.r, 0);
        expect(result.g, 0);
        expect(result.b, 0);
      });

      test('none returns same none instance', () {
        final color = AnsiColor.none();
        final result = color.withBrightness(0.5);
        expect(result.isNone, isTrue);
        expect(identical(result, color), isTrue);
      });
    });

    group('hex output', () {
      test('produces uppercase hex string with hash', () {
        final color = AnsiColor.fromRGB(0xFF, 0x80, 0x00);
        expect(color.hex, '#FF8000');
      });

      test('pads single-digit channels', () {
        final color = AnsiColor.fromRGB(0x01, 0x02, 0x03);
        expect(color.hex, '#010203');
      });

      test('black is #000000', () {
        expect(AnsiColor.black.hex, '#000000');
      });

      test('white is #FFFFFF', () {
        expect(AnsiColor.white.hex, '#FFFFFF');
      });
    });

    group('named constants', () {
      test('red', () {
        expect(AnsiColor.red.r, 255);
        expect(AnsiColor.red.g, 0);
        expect(AnsiColor.red.b, 0);
      });

      test('green', () {
        expect(AnsiColor.green.r, 0);
        expect(AnsiColor.green.g, 255);
        expect(AnsiColor.green.b, 0);
      });

      test('blue', () {
        expect(AnsiColor.blue.r, 0);
        expect(AnsiColor.blue.g, 0);
        expect(AnsiColor.blue.b, 255);
      });

      test('white', () {
        expect(AnsiColor.white.r, 255);
        expect(AnsiColor.white.g, 255);
        expect(AnsiColor.white.b, 255);
      });

      test('black', () {
        expect(AnsiColor.black.r, 0);
        expect(AnsiColor.black.g, 0);
        expect(AnsiColor.black.b, 0);
      });

      test('yellow', () {
        expect(AnsiColor.yellow.r, 255);
        expect(AnsiColor.yellow.g, 255);
        expect(AnsiColor.yellow.b, 0);
      });

      test('cyan', () {
        expect(AnsiColor.cyan.r, 0);
        expect(AnsiColor.cyan.g, 255);
        expect(AnsiColor.cyan.b, 255);
      });

      test('magenta', () {
        expect(AnsiColor.magenta.r, 255);
        expect(AnsiColor.magenta.g, 0);
        expect(AnsiColor.magenta.b, 255);
      });

      test('orange', () {
        expect(AnsiColor.orange.r, 255);
        expect(AnsiColor.orange.g, 165);
        expect(AnsiColor.orange.b, 0);
      });

      test('gray', () {
        expect(AnsiColor.gray.r, 128);
        expect(AnsiColor.gray.g, 128);
        expect(AnsiColor.gray.b, 128);
      });

      test('lightGray', () {
        expect(AnsiColor.lightGray.r, 192);
        expect(AnsiColor.lightGray.g, 192);
        expect(AnsiColor.lightGray.b, 192);
      });

      test('darkGray', () {
        expect(AnsiColor.darkGray.r, 64);
        expect(AnsiColor.darkGray.g, 64);
        expect(AnsiColor.darkGray.b, 64);
      });

      test('all named constants are available', () {
        final colors = [
          AnsiColor.black,
          AnsiColor.white,
          AnsiColor.red,
          AnsiColor.green,
          AnsiColor.blue,
          AnsiColor.yellow,
          AnsiColor.cyan,
          AnsiColor.magenta,
          AnsiColor.orange,
          AnsiColor.gray,
          AnsiColor.lightGray,
          AnsiColor.darkGray,
        ];
        expect(colors, hasLength(12));
      });
    });

    group('equality', () {
      test('equal colors have same operator==', () {
        final a = AnsiColor.fromRGB(10, 20, 30);
        final b = AnsiColor.fromRGB(10, 20, 30);
        expect(a, equals(b));
      });

      test('different colors are not equal', () {
        final a = AnsiColor.fromRGB(10, 20, 30);
        final b = AnsiColor.fromRGB(10, 20, 31);
        expect(a, isNot(equals(b)));
      });

      test('equal colors have same hashCode', () {
        final a = AnsiColor.fromRGB(10, 20, 30);
        final b = AnsiColor.fromRGB(10, 20, 30);
        expect(a.hashCode, equals(b.hashCode));
      });

      test('none equals none', () {
        final a = AnsiColor.none();
        final b = AnsiColor.none();
        expect(a, equals(b));
      });

      test('none does not equal black', () {
        final none = AnsiColor.none();
        expect(none, isNot(equals(AnsiColor.black)));
      });
    });

    group('toString', () {
      test('regular color includes hex', () {
        final color = AnsiColor.fromRGB(255, 128, 0);
        expect(color.toString(), contains('FF8000'));
      });

      test('none identifies itself', () {
        final color = AnsiColor.none();
        expect(color.toString(), contains('none'));
      });
    });
  });
}
