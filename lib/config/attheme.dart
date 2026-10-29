// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'dart:ui';

/// Reader for Telegram's `.attheme` theme files (roadmap T8).
///
/// The format, measured on the five files Telegram ships
/// (`verification/attheme/README.md`): plain text, one `key=value` per line,
/// no sections, no quotes, ~500 lines. A value is a Java signed 32-bit ARGB
/// int (`chat_inBubble=-14737117`) or - for a minority of keys - a `#RRGGBB`
/// string (`chat_inTimeText=#7D7F81`). [parseAttheme] hands back every value
/// as an unsigned ARGB int, so `chat_inBubble` lands as `0xFF1F2123`.
///
/// This file imports `dart:ui` and nothing else: no `AppSettings`, no
/// `package:fluffychat`. That is what lets
/// `verification/spec_app/sync_from_fork.sh` copy it into the golden rig and
/// the rig score the role mapping. The pref keys, the store and the file
/// picker live in `lib/config/imported_theme.dart`.
///
/// Telegram's own theme engine is GPLv2 Java (`Theme.java`); this is an
/// independent implementation of the file format, not a port of that code.

/// The UTF-8 byte order mark some exports put in front of the first key.
const String atthemeBom = '\uFEFF';

const int _radixHex = 16;
const int _rgbDigits = 6;
const int _argbDigits = 8;
const int _opaqueAlpha = 0xFF000000;
const int _rgbMask = 0xFFFFFF;
const int _argbBits = 32;

/// Every key/value pair of a `.attheme` file as `key -> unsigned ARGB`.
///
/// Blanks, lines with no `=` and values that are neither a signed int nor a
/// `#RRGGBB` / `#AARRGGBB` string are skipped, so a partial or hand-edited
/// theme still parses. A repeated key keeps the **last** value, which is what
/// Telegram's reader does: `night.attheme` repeats `chats_menuTopShadow` and
/// `code_comment`, `darkblue.attheme` repeats 4 keys.
Map<String, int> parseAttheme(String source) {
  final text = source.startsWith(atthemeBom)
      ? source.substring(atthemeBom.length)
      : source;
  final values = <String, int>{};
  for (final rawLine in text.split('\n')) {
    // Files exported on Windows end their lines with CR.
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;
    final equals = line.indexOf('=');
    if (equals < 1) continue;
    final key = line.substring(0, equals).trim();
    if (key.isEmpty) continue;
    final value = _parseArgb(line.substring(equals + 1).trim());
    if (value == null) continue;
    values[key] = value;
  }
  return values;
}

/// One value -> unsigned ARGB, or null when the text is not a colour.
int? _parseArgb(String value) {
  if (value.startsWith('#')) {
    final digits = value.substring(1);
    final parsed = int.tryParse(digits, radix: _radixHex);
    if (parsed == null) return null;
    if (digits.length == _rgbDigits) return _opaqueAlpha | parsed;
    if (digits.length == _argbDigits) return parsed.toUnsigned(_argbBits);
    return null;
  }
  // Signed decimal int32. `toUnsigned` is the `& 0xFFFFFFFF` of Java land and
  // stays correct when Dart compiles to JavaScript numbers.
  return int.tryParse(value)?.toUnsigned(_argbBits);
}

/// The chat roles this fork applies, each with the `.attheme` key it reads.
/// Real keys of `night.attheme` - `chat_wallpaper`, `chat_inBubble`,
/// `chat_outBubble`, `chat_inTimeText`, `chat_outTimeText`,
/// `chat_inReplyNameText`, `chat_outReplyNameText`, `chat_inReplyLine`,
/// `divider`, `windowBackgroundChecked`.
const Map<String, String> atthemeRoleKeys = {
  'wallpaper': 'chat_wallpaper',
  'bubbleIncoming': 'chat_inBubble',
  'bubbleOutgoing': 'chat_outBubble',
  // Newer themes ship a gradient on the own bubble. The five shipped fixtures
  // carry only `chat_outBubbleGradient`; Start/End are read when present.
  'bubbleOutgoingGradient': 'chat_outBubbleGradient',
  'bubbleOutgoingGradientStart': 'chat_outBubbleGradientStart',
  'bubbleOutgoingGradientEnd': 'chat_outBubbleGradientEnd',
  'timestampIn': 'chat_inTimeText',
  'timestampOut': 'chat_outTimeText',
  'replyNameIn': 'chat_inReplyNameText',
  'replyNameOut': 'chat_outReplyNameText',
  'replyLineIn': 'chat_inReplyLine',
  'divider': 'divider',
  'windowBackgroundChecked': 'windowBackgroundChecked',
  'serviceText': 'chat_serviceText',
};

/// The 7 sender-name keys, in `sender_colors_night` order
/// (red, orange, purple, green, cyan, blue, pink). Telegram spells purple
/// `Violet` in the key name.
const List<String> atthemeSenderColorKeys = [
  'avatar_nameInMessageRed',
  'avatar_nameInMessageOrange',
  'avatar_nameInMessageViolet',
  'avatar_nameInMessageGreen',
  'avatar_nameInMessageCyan',
  'avatar_nameInMessageBlue',
  'avatar_nameInMessagePink',
];

/// The 8 accent keys every shipped `.attheme` carries. `colorAccent0..7`
/// exists in none of the five shipped files, so these are the accent set.
const List<String> atthemeAccentColorKeys = [
  'color_blue',
  'color_lightblue',
  'color_green',
  'color_lightgreen',
  'color_orange',
  'color_purple',
  'color_red',
  'color_yellow',
];

/// The chat colours of one parsed theme, read by role.
///
/// A role the file does not define reads back as `null`, so a partial theme
/// applies only what it defines and every other surface keeps the built-in
/// [TelegramPalette] value.
class AtthemePalette {
  const AtthemePalette(this.values);

  /// Parse [source] the way [parseAttheme] does.
  factory AtthemePalette.parse(String source) =>
      AtthemePalette(parseAttheme(source));

  /// Every key of the file with its unsigned ARGB value.
  final Map<String, int> values;

  bool get isEmpty => values.isEmpty;

  /// The raw ARGB of a role ([atthemeRoleKeys]) or of a key named directly,
  /// and null when the theme does not define it.
  int? argb(String role) => values[atthemeRoleKeys[role] ?? role];

  /// The colour of a role: the 24-bit rgb of [argb] under an opaque alpha.
  Color? color(String role) {
    final value = argb(role);
    if (value == null) return null;
    return Color(_opaqueAlpha | (value & _rgbMask));
  }

  /// `chat_wallpaper` - the chat background fill.
  Color? get wallpaper => color('wallpaper');

  /// `chat_inBubble`.
  Color? get bubbleIncoming => color('bubbleIncoming');

  /// `chat_outBubble`.
  Color? get bubbleOutgoing => color('bubbleOutgoing');

  /// `chat_outBubbleGradient`, the far end of the own-bubble gradient.
  Color? get bubbleOutgoingGradient => color('bubbleOutgoingGradient');

  /// `chat_inTimeText`.
  Color? get timestampIn => color('timestampIn');

  /// `chat_outTimeText`.
  Color? get timestampOut => color('timestampOut');

  /// `chat_inReplyNameText`.
  Color? get replyNameIn => color('replyNameIn');

  /// `chat_outReplyNameText`.
  Color? get replyNameOut => color('replyNameOut');

  /// `chat_inReplyLine`, the accent bar of a reply quote.
  Color? get replyLineIn => color('replyLineIn');

  /// `divider`.
  Color? get divider => color('divider');

  /// `windowBackgroundChecked`, the checked/tinted surface.
  Color? get windowBackgroundChecked => color('windowBackgroundChecked');

  /// `chat_serviceText`, the ink of a state event line.
  Color? get serviceText => color('serviceText');

  /// The theme's 7 sender colours in `sender_colors_night` order, or null
  /// when the theme defines fewer than all 7: a partial set would move people
  /// between slots of the hash, so the built-in palette stays in that case.
  List<int>? get senderColors {
    final colors = <int>[];
    for (final key in atthemeSenderColorKeys) {
      final value = values[key];
      if (value == null) return null;
      colors.add(value);
    }
    return colors;
  }

  /// The theme's accent colours ([atthemeAccentColorKeys]), the ones it
  /// defines. Exposed for the accent picker; the built-in
  /// `TelegramPalette.accentValues` swatch row is a compile-time list and the
  /// palette contract forbids new colours, so these do not replace it.
  List<Color> get accentColors => [
    for (final key in atthemeAccentColorKeys)
      if (values[key] case final value?)
        Color(_opaqueAlpha | (value & _rgbMask)),
  ];
}
