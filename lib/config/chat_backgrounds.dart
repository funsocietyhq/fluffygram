// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/telegram_palette.dart';
import 'package:material_ui/material_ui.dart';

/// The chat background the user picked (roadmap T5B). Telegram keeps its chat
/// wallpapers on the device (`chatWallpaper_<account>_<dialogId>` in
/// SharedPreferences), so this is appearance state only: nothing here reads or
/// writes Matrix room state. `AppSettings.chatBackground` holds the global pick
/// and `AppSettings.chatBackgrounds` the per-chat map
/// `{"!room:server": "#RRGGBB"}`.
///
/// Precedence at draw time: the chat's own pick, then the global pick, then the
/// theme's own chat field (`TelegramPalette.chatBackground` at night).
abstract class ChatBackgrounds {
  /// Writes notify through this listenable, because `SharedPreferences` has
  /// none: a chat view and the style page wrap the parts they draw in a
  /// `ListenableBuilder` on it, so a pick repaints at once.
  static final ChatBackgroundStore store = ChatBackgroundStore();

  /// The global pick. Null = no global pick, so the theme's chat field shows.
  static Color? get global => _parse(AppSettings.chatBackground.value);

  /// This room's own pick. Null = the room has no override.
  static Color? forRoom(String roomId) => _parse(_roomMap()[roomId]);

  /// The fill a chat draws behind its timeline. Null = paint nothing, which
  /// leaves the theme's chat surface and the account wallpaper untouched.
  static Color? resolve(BuildContext context, String roomId) {
    final picked = forRoom(roomId) ?? global;
    if (picked == null) return null;
    return clampToTheme(picked, Theme.of(context).brightness);
  }

  static Future<void> setGlobal(Color? color) async {
    await AppSettings.chatBackground.setItem(
      color == null ? _noPick : _hex(color),
    );
    store.notify();
  }

  static Future<void> setForRoom(String roomId, Color? color) async {
    final map = Map<String, Object?>.from(_roomMap());
    if (color == null) {
      map.remove(roomId);
    } else {
      map[roomId] = _hex(color);
    }
    await AppSettings.chatBackgrounds.setItem(jsonEncode(map));
    store.notify();
  }

  /// The contrast guard. The timeline draws its own chrome (date pill, unread
  /// separator, typing line) in one ink pair per theme, so a picked field may
  /// not cross to the bright side of the field the theme was measured with: a
  /// pick that is lighter than the incoming bubble is darkened down to that
  /// bubble's lightness, and in the day theme a pick darker than the day
  /// incoming bubble is lifted up to it. No per-background text colour exists.
  static Color clampToTheme(Color background, Brightness brightness) {
    final field = HSLColor.fromColor(
      brightness == Brightness.dark
          ? TelegramPalette.bubbleIncoming
          : TelegramPalette.dayBubbleIncoming,
    );
    final picked = HSLColor.fromColor(background);
    final insideTheme = brightness == Brightness.dark
        ? picked.lightness <= field.lightness
        : picked.lightness >= field.lightness;
    if (insideTheme) return background;
    return picked.withLightness(field.lightness).toColor();
  }

  static Map<String, Object?> _roomMap() {
    final Object? decoded;
    try {
      decoded = jsonDecode(AppSettings.chatBackgrounds.value);
    } on FormatException {
      return const {};
    }
    if (decoded is! Map) return const {};
    return Map<String, Object?>.from(decoded);
  }

  static const String _noPick = '';
  static const int _hexDigits = 6;
  static const int _radixHex = 16;
  static const int _redShift = 16;
  static const int _greenShift = 8;
  static const int _channelMask = 0xFF;
  static const int _rgbMask = 0xFFFFFF;

  static String _hex(Color color) =>
      '#${(color.toARGB32() & _rgbMask).toRadixString(_radixHex).padLeft(_hexDigits, '0').toUpperCase()}';

  static Color? _parse(Object? value) {
    if (value is! String) return null;
    final digits = value.startsWith('#') ? value.substring(1) : value;
    if (digits.length != _hexDigits) return null;
    final rgb = int.tryParse(digits, radix: _radixHex);
    if (rgb == null) return null;
    return Color.fromRGBO(
      (rgb >> _redShift) & _channelMask,
      (rgb >> _greenShift) & _channelMask,
      rgb & _channelMask,
      1,
    );
  }
}

/// The write side of [ChatBackgrounds]. `ChatBackgrounds.setGlobal()` and
/// `.setForRoom()` call [notify] once the value is in `AppSettings`.
class ChatBackgroundStore extends ChangeNotifier {
  void notify() => notifyListeners();
}
