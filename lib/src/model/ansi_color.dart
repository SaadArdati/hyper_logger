/// True-color (24-bit) ANSI color for terminal output.
///
/// Stores color as a 0xAARRGGBB integer (alpha is ignored). Provides
/// foreground and background ANSI escape sequences using the 24-bit
/// `ESC[38;2;R;G;Bm` / `ESC[48;2;R;G;Bm` format.
class AnsiColor {
  /// The raw color value in 0xAARRGGBB format. Alpha is ignored.
  ///
  /// A value of -1 indicates the [none] sentinel.
  final int value;

  /// Creates an [AnsiColor] from a raw 0xAARRGGBB integer.
  AnsiColor(this.value);

  /// Creates an [AnsiColor] from individual red, green, and blue channels.
  ///
  /// Each channel should be in the range 0–255. Channels outside this range
  /// produce undefined behavior.
  AnsiColor.fromRGB(int r, int g, int b)
    : value = 0xFF000000 | (r << 16) | (g << 8) | b;

  /// Sentinel value representing no color.
  ///
  /// Produces empty strings for [fg] and [bg], allowing conditional rendering.
  AnsiColor.none() : value = -1;

  /// Parses a hex color string into an [AnsiColor].
  ///
  /// Accepts the following formats:
  /// - `#RRGGBB` or `RRGGBB` (6-digit)
  /// - `#RGB` or `RGB` (3-digit, each digit is doubled)
  ///
  /// Throws a [FormatException] if the string is not a valid hex color.
  factory AnsiColor.fromHex(String hex) {
    var s = hex;
    if (s.startsWith('#')) {
      s = s.substring(1);
    }

    int r, g, b;

    if (s.length == 6) {
      final parsed = int.tryParse(s, radix: 16);
      if (parsed == null) {
        throw FormatException('Invalid hex color: $hex');
      }
      r = (parsed >> 16) & 0xFF;
      g = (parsed >> 8) & 0xFF;
      b = parsed & 0xFF;
    } else if (s.length == 3) {
      final parsed = int.tryParse(s, radix: 16);
      if (parsed == null) {
        throw FormatException('Invalid hex color: $hex');
      }
      r = ((parsed >> 8) & 0xF) * 0x11;
      g = ((parsed >> 4) & 0xF) * 0x11;
      b = (parsed & 0xF) * 0x11;
    } else {
      throw FormatException('Invalid hex color length: $hex');
    }

    return AnsiColor.fromRGB(r, g, b);
  }

  /// Whether this is the [none] sentinel.
  bool get isNone => value == -1;

  /// The red channel (0–255).
  ///
  /// Undefined for [none] instances.
  int get r => (value >> 16) & 0xFF;

  /// The green channel (0–255).
  ///
  /// Undefined for [none] instances.
  int get g => (value >> 8) & 0xFF;

  /// The blue channel (0–255).
  ///
  /// Undefined for [none] instances.
  int get b => value & 0xFF;

  /// ANSI escape sequence for setting this as the foreground color.
  ///
  /// Returns an empty string for [none].
  late final String fg = isNone ? '' : '\x1b[38;2;$r;$g;${b}m';

  /// ANSI escape sequence for setting this as the background color.
  ///
  /// Returns an empty string for [none].
  late final String bg = isNone ? '' : '\x1b[48;2;$r;$g;${b}m';

  /// Returns this color's hex representation as `#RRGGBB` (uppercase).
  ///
  /// Undefined for [none] instances.
  late final String hex = () {
    final rHex = r.toRadixString(16).toUpperCase().padLeft(2, '0');
    final gHex = g.toRadixString(16).toUpperCase().padLeft(2, '0');
    final bHex = b.toRadixString(16).toUpperCase().padLeft(2, '0');
    return '#$rHex$gHex$bHex';
  }();

  /// Returns a new [AnsiColor] with brightness scaled by [factor].
  ///
  /// A factor of 1.0 returns the same color, 0.0 returns black, and
  /// values above 1.0 brighten (clamped to 255 per channel).
  ///
  /// Returns `this` unchanged when [isNone] is true.
  AnsiColor withBrightness(double factor) {
    if (isNone) return this;
    final newR = (r * factor).round().clamp(0, 255);
    final newG = (g * factor).round().clamp(0, 255);
    final newB = (b * factor).round().clamp(0, 255);
    return AnsiColor.fromRGB(newR, newG, newB);
  }

  /// The ANSI reset sequence that clears all formatting.
  static const String reset = '\x1b[0m';

  // ---- Named constants ----

  /// Pure black: RGB(0, 0, 0).
  static final AnsiColor black = AnsiColor.fromRGB(0, 0, 0);

  /// Pure white: RGB(255, 255, 255).
  static final AnsiColor white = AnsiColor.fromRGB(255, 255, 255);

  /// Pure red: RGB(255, 0, 0).
  static final AnsiColor red = AnsiColor.fromRGB(255, 0, 0);

  /// Pure green: RGB(0, 255, 0).
  static final AnsiColor green = AnsiColor.fromRGB(0, 255, 0);

  /// Pure blue: RGB(0, 0, 255).
  static final AnsiColor blue = AnsiColor.fromRGB(0, 0, 255);

  /// Pure yellow: RGB(255, 255, 0).
  static final AnsiColor yellow = AnsiColor.fromRGB(255, 255, 0);

  /// Pure cyan: RGB(0, 255, 255).
  static final AnsiColor cyan = AnsiColor.fromRGB(0, 255, 255);

  /// Pure magenta: RGB(255, 0, 255).
  static final AnsiColor magenta = AnsiColor.fromRGB(255, 0, 255);

  /// Orange: RGB(255, 165, 0).
  static final AnsiColor orange = AnsiColor.fromRGB(255, 165, 0);

  /// Gray: RGB(128, 128, 128).
  static final AnsiColor gray = AnsiColor.fromRGB(128, 128, 128);

  /// Light gray: RGB(192, 192, 192).
  static final AnsiColor lightGray = AnsiColor.fromRGB(192, 192, 192);

  /// Dark gray: RGB(64, 64, 64).
  static final AnsiColor darkGray = AnsiColor.fromRGB(64, 64, 64);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AnsiColor && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => isNone ? 'AnsiColor.none' : 'AnsiColor($hex)';
}
