// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/attheme.dart';
import 'package:fluffychat/config/imported_theme.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/telegram_palette.dart';
import 'package:fluffychat/utils/telegram_bubble_fill.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

abstract class FluffyThemes {
  static const double columnWidth = 380.0;

  static const double maxTimelineWidth = columnWidth * 2;

  static const double navRailWidth = 80.0;

  static bool isColumnModeByWidth(double width) =>
      width > columnWidth * 2 + navRailWidth;

  static bool isColumnMode(BuildContext context) =>
      isColumnModeByWidth(MediaQuery.sizeOf(context).width);

  static bool isThreeColumnMode(BuildContext context) =>
      MediaQuery.sizeOf(context).width > FluffyThemes.columnWidth * 3.5;

  static LinearGradient backgroundGradient(BuildContext context, int alpha) {
    final colorScheme = Theme.of(context).colorScheme;
    return LinearGradient(
      begin: Alignment.topCenter,
      colors: [
        colorScheme.primaryContainer.withAlpha(alpha),
        colorScheme.secondaryContainer.withAlpha(alpha),
        colorScheme.tertiaryContainer.withAlpha(alpha),
        colorScheme.primaryContainer.withAlpha(alpha),
      ],
    );
  }

  static const Duration animationDuration = Duration(milliseconds: 250);
  static const Curve animationCurve = Curves.easeInOut;

  /// The theme accent: the picked `TelegramPalette.accentValues` entry, the
  /// one [buildTheme] seeds the colour scheme from. Telegram paints the reply
  /// quote bar and the quoted sender name in this colour (T11 finding 9), so
  /// widgets that need the accent read it here and do not re-derive it.
  static Color get accent => accentFor();

  /// Telegram's accent picker wins: index >= 0 takes one of the 7 presets.
  /// Index -1 (a colour from the old picker) keeps `colorSchemeSeedInt`, and
  /// an explicit [seed] argument (dynamic colour) stays the last fallback.
  static Color accentFor({Color? seed}) {
    final accentIndex = AppSettings.telegramAccentIndex.value;
    return accentIndex >= 0 && accentIndex < TelegramPalette.accentValues.length
        ? TelegramPalette.accentValues[accentIndex]
        : (seed ?? Color(AppSettings.colorSchemeSeedInt.value));
  }

  /// Telegram tints its night chat chrome with the theme accent, where this fork
  /// let the Material elevation overlay lighten it to a neutral grey. On the
  /// a user's Pixel with the shipped accent `#4D506E` the chat header pill reads
  /// `#282E3B` - the accent at 0.53 over the black chat page - and the circles
  /// behind the back arrow, the overflow and the scroll-down FAB `#262B38` -
  /// 0.50. The fork painted them `#1E1E1E` and `#2C2C2E`, flat grey capsules on
  /// a black page. Values: `the measurement log` finding 30, same-phone pair
  /// of 2026-10-26 14:50. The day theme keeps its own surfaces: no day chrome
  /// value is measured, so none is claimed here.
  static Color chatChromeFill(
    BuildContext context, {
    required int accentAlpha,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surface;
    if (scheme.brightness != Brightness.dark) return base;
    return Color.alphaBlend(accent.withAlpha(accentAlpha), base);
  }

  /// Ink drawn on top of an accent-coloured fill: the accent itself when it
  /// already reads on [fill], otherwise a neutral ink chosen from [fill]'s
  /// brightness. Owner decision 2026-10-26 (user item 4): the chat-list
  /// compose widgets fill with the accent and take their icon ink from here,
  /// so fill and foreground cannot drift from the accent picker.
  static const double accentInkMinContrast = 3;

  static Color accentInk({required Color fill, Color? seed}) {
    final accent = accentFor(seed: seed);
    final accentLum = accent.computeLuminance();
    final fillLum = fill.computeLuminance();
    final hi = accentLum > fillLum ? accentLum : fillLum;
    final lo = accentLum > fillLum ? fillLum : accentLum;
    if ((hi + 0.05) / (lo + 0.05) >= accentInkMinContrast) return accent;
    return ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
        ? TelegramPalette.textOnBubble
        : Colors.black;
  }

  /// The field the chat list paints its rows, chips and search bar on. Telegram's
  /// list sits on a raised dark field (measured `#181818` on a user's chat-list
  /// capture), not on the black chat page. The day theme keeps its own surface: no
  /// light capture has arrived, so no day chat-list value is claimed.
  static Color chatListField(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.light
        ? scheme.surface
        : TelegramPalette.chatListBackground;
  }

  static ThemeData buildTheme(
    BuildContext context,
    Brightness brightness, [
    Color? seed,
  ]) {
    // Telegram: flat black chat surfaces at night, day grey by day. The
    // user seed still drives primary/secondary/tertiary. Values: TelegramPalette.
    // An imported .attheme (T8) wins over both: `chat_wallpaper` is its chat
    // field. Null = no import, so the built-in theme of this brightness shows.
    final imported = ImportedTheme.palette;
    final chatBackground =
        imported?.wallpaper ??
        (brightness == Brightness.dark
            ? TelegramPalette.chatBackground
            : TelegramPalette.dayChatBackground);
    final accent = accentFor(seed: seed);
    final colorScheme =
        ColorScheme.fromSeed(
          brightness: brightness,
          seedColor: accent,
          dynamicSchemeVariant: DynamicSchemeVariant.rainbow,
        ).copyWith(
          surface: chatBackground,
          surfaceContainerLowest: chatBackground,
          surfaceContainerLow: chatBackground,
          surfaceContainer: chatBackground,
          surfaceContainerHigh: chatBackground,
          surfaceContainerHighest: chatBackground,
        );
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final dividerColor =
        imported?.divider ??
        (brightness == Brightness.dark
            ? TelegramPalette.divider
            : colorScheme.surfaceContainer);
    return ThemeData(
      visualDensity: VisualDensity.standard,
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      // Telegram message text: 16 sp, line height 1.22 (target typography).
      textTheme:
          (brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light())
              .textTheme
              .copyWith(bodyLarge: const TextStyle(fontSize: 16, height: 1.22)),
      dividerColor: dividerColor,
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          iconColor: colorScheme.onSurface,
          disabledIconColor: colorScheme.onSurface,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: colorScheme.onSurface.withAlpha(128),
        selectionHandleColor: colorScheme.secondary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
        ),
        contentPadding: const EdgeInsets.all(12),
      ),
      chipTheme: ChipThemeData(
        showCheckmark: false,
        backgroundColor: colorScheme.surfaceContainer,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        ),
      ),
      appBarTheme: AppBarTheme(
        toolbarHeight: isColumnMode ? 72 : 56,
        surfaceTintColor: isColumnMode ? colorScheme.surface : null,
        backgroundColor: isColumnMode ? colorScheme.surface : null,
        actionsPadding: isColumnMode
            ? const EdgeInsets.symmetric(horizontal: 16.0)
            : null,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: brightness.reversed,
          statusBarBrightness: brightness,
          systemNavigationBarIconBrightness: brightness.reversed,
          systemNavigationBarColor: colorScheme.surface,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(width: 1, color: colorScheme.primary),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colorScheme.primary),
            borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        strokeCap: StrokeCap.round,
        color: colorScheme.primary,
        refreshBackgroundColor: colorScheme.primaryContainer,
      ),
      snackBarTheme: isColumnMode
          ? const SnackBarThemeData(
              showCloseIcon: true,
              behavior: SnackBarBehavior.floating,
              width: FluffyThemes.columnWidth * 1.5,
            )
          : const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.secondaryContainer,
          foregroundColor: colorScheme.onSecondaryContainer,
          elevation: 0,
          padding: const EdgeInsets.all(16),
          textStyle: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

extension on Brightness {
  Brightness get reversed =>
      this == Brightness.dark ? Brightness.light : Brightness.dark;
}

extension BubbleColorTheme on ThemeData {
  /// A `.attheme` role of the imported theme (T8), then this brightness' own
  /// [TelegramPalette] value. Every getter below takes the same shape, so one
  /// imported file repaints the whole timeline and nothing else moves.
  static Color _role(
    Color? Function(AtthemePalette? palette) imported,
    Color builtIn,
  ) => imported(ImportedTheme.palette) ?? builtIn;

  /// Outgoing bubble fill: the theme accent run through `TelegramBubbleFill`
  /// (finding 13), based on this brightness' own stock bubble colour - night
  /// #4F556C, day #2D7ED5 - or the imported theme's `chat_outBubble`, which
  /// still wins when a `.attheme` is loaded.
  Color get bubbleColor => _role(
    (palette) => palette?.bubbleOutgoing,
    TelegramBubbleFill.outgoing(
      accent: FluffyThemes.accent,
      baseBubble: brightness == Brightness.light
          ? TelegramPalette.dayBubbleOutgoing
          : TelegramPalette.bubbleOutgoing,
    ),
  );

  /// Bubble text ink. `.attheme` has no text-on-bubble key, so this one stays
  /// on the built-in theme of the brightness.
  Color get onBubbleColor => brightness == Brightness.light
      ? TelegramPalette.dayTextOnBubble
      : TelegramPalette.textOnBubble;

  /// Incoming bubble fill: night #1E1E20, day #F0F0F0, or the imported
  /// theme's `chat_inBubble`.
  Color get bubbleColorIncoming => _role(
    (palette) => palette?.bubbleIncoming,
    brightness == Brightness.light
        ? TelegramPalette.dayBubbleIncoming
        : TelegramPalette.bubbleIncoming,
  );

  Color get secondaryBubbleColor => bubbleColorIncoming;

  /// Timestamp / "Edited" ink of an own bubble. Measured in a user's
  /// night theme: `timestamp_in_outgoing` = `edited_label` = #909AAB.
  /// The read tick glyph keeps `read_tick` #B4BCC8 (T4 adds the glyphs).
  Color get timestampOnOutgoingBubble => _role(
    (palette) => palette?.timestampOut,
    brightness == Brightness.light
        ? TelegramPalette.dayTimestampOutgoing
        : TelegramPalette.timestampInk,
  );

  /// Read tick glyph ink of an own bubble (`read_tick`, measured #B6BECA):
  /// night #B4BCC8, day theme's outgoing timestamp tint.
  Color get readTickOnOutgoingBubble => brightness == Brightness.light
      ? TelegramPalette.dayTimestampOutgoing
      : TelegramPalette.timestampOutgoing;

  /// Timestamp tint of a foreign bubble (also the "Edited" label): night
  /// #8CA0B3, day #939599.
  Color get timestampOnIncomingBubble => _role(
    (palette) => palette?.timestampIn,
    brightness == Brightness.light
        ? TelegramPalette.dayTimestampIncoming
        : TelegramPalette.timestampIncoming,
  );
}
