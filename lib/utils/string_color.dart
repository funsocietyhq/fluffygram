// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:fluffychat/config/imported_theme.dart';
import 'package:fluffychat/config/telegram_palette.dart';
import 'package:material_ui/material_ui.dart';

/// The fixed 7-colour Telegram night sender palette
/// (`sender_colors_night` in verification/telegram-target.json).
const List<int> stringColorValues = TelegramPalette.senderColorValues;

/// The sender colour for a user id: a stable hash into the fixed
/// 7-colour Telegram palette, so a person keeps one colour everywhere. An
/// imported `.attheme` (T8) that defines all 7 `avatar_nameInMessage*` keys
/// replaces that palette - the hash and the slot count do not change, so a
/// person keeps one colour across the app, and the reply-quote bar of
/// `reply_content.dart` follows the same ink for free.
Color stringToColor(String s) {
  final values = ImportedTheme.palette?.senderColors ?? stringColorValues;
  return Color(
    values[s.codeUnits.fold<int>(0, (a, b) => a + b) % values.length],
  );
}

extension StringColor on String {
  static final _colorSchemeCache = <String, ColorScheme>{};

  ColorScheme get colorScheme =>
      _colorSchemeCache[this] ??= ColorScheme.fromSeed(
        seedColor: stringToColor(this),
        dynamicSchemeVariant: DynamicSchemeVariant.rainbow,
      );
}
