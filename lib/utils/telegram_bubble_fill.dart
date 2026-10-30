// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

typedef _Hsv = ({double hue, double saturation, double brightness});

/// The outgoing bubble fill, derived from the chat accent the way Telegram
/// derives it (roadmap T13 finding 13).
///
/// Telegram writes its own rule in two places. `Theme.java:1660` puts the
/// accent of the user's "Messages" colour straight into `chat_outBubble`, and
/// `Theme.adaptHue(color, hueFromColor)` (`Theme.java:1991`) is how Telegram
/// tints a base colour with an accent: take the reference hue, pull saturation
/// 25 percent toward it, keep the base's own brightness. This file copies that
/// rule instead of shipping a measured hex, so a user who picks another accent
/// gets another bubble fill, exactly like Telegram does.
///
/// Measured on a user's Pixel with the slate accent: outgoing `#4C5369`
/// (second reading `#4D546A`), incoming `#1E1E20`, page background `#000000`.
/// With `TelegramPalette.accentSlate #4D506E` this rule produces `#4F526C`:
/// 3, 1 and 3 units away per channel from `#4C5369`, inside the noise of
/// sampling a translucent bubble over a chat field.
abstract final class TelegramBubbleFill {
  /// `Theme.adaptHue`'s lerp factor: saturation moves 25 percent from the base
  /// toward the accent's saturation. Telegram's own constant (`Theme.java:1999`).
  static const double saturationPull = 0.25;

  /// The second step: mix a little of the grey at the same brightness back in.
  /// A Telegram bubble is drawn over the chat field, so what a screenshot reads
  /// is a touch less saturated than the accent that produced it. 0.04 keeps the
  /// slate default inside the measured band; 0.2 and above washes the tint out.
  static const double neutralBlend = 0.04;

  /// The outgoing bubble fill for [accent]: hue and 25 percent of the
  /// saturation come from the accent, brightness stays the theme's own
  /// [baseBubble], then [neutralBlend] of the same-brightness grey is mixed in.
  static Color outgoing({required Color accent, required Color baseBubble}) =>
      blendTowardNeutral(adaptHue(baseBubble, accent), neutralBlend);

  /// Telegram's `Theme.adaptHue(color, hueFromColor)`: [color] keeps its
  /// brightness and alpha, takes [hueFrom]'s hue, and pulls its saturation 25
  /// percent toward [hueFrom]'s. Same HSV space and same lerp as Telegram's
  /// `Color.colorToHSV` / `Color.HSVToColor` pair.
  static Color adaptHue(Color color, Color hueFrom) {
    final reference = _hsvOf(hueFrom);
    final base = _hsvOf(color);
    return _fromHsv(
      reference.hue,
      base.saturation +
          (reference.saturation - base.saturation) * saturationPull,
      base.brightness,
      ((color.toARGB32() >> 24) & 0xFF) / 255.0,
    );
  }

  /// The grey with zero saturation at [color]'s brightness, mixed in by
  /// [amount]: 0 keeps the colour, 1 leaves grey.
  static Color blendTowardNeutral(Color color, double amount) {
    final grey = _fromHsv(0, 0, _hsvOf(color).brightness, 1.0);
    return Color.lerp(color, grey, amount)!;
  }

  /// HSV reads of a colour, exposed so `test/telegram_fidelity/` can assert the
  /// rule (hue taken, saturation pulled 25 percent, brightness kept) and not
  /// only the produced hex.
  static double hueOf(Color color) => _hsvOf(color).hue;
  static double saturationOf(Color color) => _hsvOf(color).saturation;
  static double brightnessOf(Color color) => _hsvOf(color).brightness;

  static _Hsv _hsvOf(Color color) {
    final argb = color.toARGB32();
    final r = ((argb >> 16) & 0xFF) / 255.0;
    final g = ((argb >> 8) & 0xFF) / 255.0;
    final b = (argb & 0xFF) / 255.0;
    final max = r > g ? (r > b ? r : b) : (g > b ? g : b);
    final min = r < g ? (r < b ? r : b) : (g < b ? g : b);
    final delta = max - min;
    double hue;
    if (delta == 0) {
      hue = 0;
    } else if (max == r) {
      hue = 60 * ((g - b) / delta);
    } else if (max == g) {
      hue = 60 * ((b - r) / delta + 2);
    } else {
      hue = 60 * ((r - g) / delta + 4);
    }
    if (hue < 0) hue += 360;
    return (
      hue: hue,
      saturation: max == 0 ? 0.0 : delta / max,
      brightness: max,
    );
  }

  static Color _fromHsv(
    double hue,
    double saturation,
    double brightness, [
    double alpha = 1.0,
  ]) {
    final h = ((hue % 360) + 360) % 360;
    final chroma = brightness * saturation.clamp(0.0, 1.0);
    final x = chroma * (1 - ((h / 60) % 2 - 1).abs());
    final m = brightness - chroma;
    final (r, g, b) = switch ((h / 60).floor() % 6) {
      0 => (chroma, x, 0.0),
      1 => (x, chroma, 0.0),
      2 => (0.0, chroma, x),
      3 => (0.0, x, chroma),
      4 => (x, 0.0, chroma),
      _ => (chroma, 0.0, x),
    };
    int channel(double v) => (((v + m) * 255).round().clamp(0, 255));
    return Color.fromRGBO(
      channel(r),
      channel(g),
      channel(b),
      alpha.clamp(0.0, 1.0),
    );
  }
}
