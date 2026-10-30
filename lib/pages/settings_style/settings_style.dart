// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/chat_backgrounds.dart';
import 'package:fluffychat/config/imported_theme.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/bubble_shape.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/widgets/chat_background_picker_sheet.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/theme_builder.dart';
import 'package:material_ui/material_ui.dart';

import '../../widgets/matrix.dart';
import 'settings_style_view.dart';

class SettingsStyle extends StatefulWidget {
  const SettingsStyle({super.key});

  @override
  SettingsStyleController createState() => SettingsStyleController();
}

class SettingsStyleController extends State<SettingsStyle> {
  void setChatColor(Color? color) {
    AppSettings.colorSchemeSeedInt.setItem(
      color?.toARGB32() ?? AppSettings.colorSchemeSeedInt.defaultValue,
    );
    // A colour from this old picker is a custom seed: it only reaches the
    // theme when the accent swatch row hands the seed back (`index` -1).
    AppSettings.telegramAccentIndex.setItem(-1);
    ThemeController.of(context).setPrimaryColor(color);
  }

  // --- Telegram appearance knobs (T5A): every one reads and writes its
  // `AppSettings` key, so the value survives a restart. ---

  /// Selected `TelegramPalette.accentValues` index, -1 = custom seed.
  int get accentIndex => AppSettings.telegramAccentIndex.value;

  Future<void> setAccentIndex(int index) async {
    final themeController = ThemeController.of(context);
    await AppSettings.telegramAccentIndex.setItem(index);
    // buildTheme() reads the key, so the app theme needs one rebuild.
    themeController.refreshTheme();
    setState(() {});
  }

  /// The message text size in sp (Telegram: 12..24, default 16), stored as the
  /// `AppSettings.fontSizeFactor` factor of `AppConfig.messageFontSize`.
  double get messageTextSp => TelegramBubbleGeometry.userMessageTextSp;

  Future<void> changeMessageTextSp(double sp) =>
      changeFontSizeFactor(sp / AppConfig.messageFontSize);

  /// The bubble width, percent of the chat column (Telegram desktop's model,
  /// 50..100, default 72; T39).
  int get bubbleWidthPercent => TelegramBubbleGeometry.userBubbleWidthPercent;

  Future<void> changeBubbleWidthPercent(int percent) async {
    await AppSettings.bubbleWidthPercent.setItem(percent);
    setState(() {});
  }

  bool get animationsEnabled => AppSettings.animationsEnabled.value;

  Future<void> setAnimationsEnabled(bool enabled) async {
    await AppSettings.animationsEnabled.setItem(enabled);
    setState(() {});
  }

  /// Telegram's global chat background (T5B). Null = the theme's own chat
  /// field. The value lives in `AppSettings.chatBackground`, device-local.
  Color? get chatBackground => ChatBackgrounds.global;

  /// Opens the swatch sheet for the global background - the same sheet the
  /// chat header opens, scoped to every chat.
  Future<void> pickChatBackground() =>
      showChatBackgroundPicker(context: context);

  bool get colorSenderNames => AppSettings.colorSenderNames.value;

  Future<void> setColorSenderNames(bool enabled) async {
    await AppSettings.colorSenderNames.setItem(enabled);
    setState(() {});
  }

  // --- The imported Telegram theme (T8): the file text lives in
  // `AppSettings.importedAttheme`, so the import survives a restart. ---

  /// Name of the imported `.attheme` file, '' when none is imported.
  String get importedThemeName => ImportedTheme.fileName;

  bool get hasImportedTheme => ImportedTheme.isImported;

  /// Opens the system picker for one `.attheme` file and applies it. A file
  /// with no parsable colour is refused and stores nothing, so a wrong pick
  /// cannot leave the app half-themed.
  Future<void> importTelegramTheme() async {
    final themeController = ThemeController.of(context);
    final result = await ImportedTheme.pickAndImportFile();
    switch (result) {
      case AtthemeImportResult.imported:
        // `FluffyThemes.buildTheme` reads the imported palette, so the app
        // theme needs one rebuild - the same call the accent picker uses.
        themeController.refreshTheme();
        setState(() {});
        break;
      case AtthemeImportResult.invalid:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.of(context).importedThemeNotATheme)),
        );
        break;
      case AtthemeImportResult.cancelled:
        break;
    }
  }

  /// Clears both keys and restores the built-in palette.
  Future<void> removeImportedTheme() async {
    final themeController = ThemeController.of(context);
    await ImportedTheme.clear();
    themeController.refreshTheme();
    setState(() {});
  }

  Future<void> setWallpaper() async {
    final client = Matrix.of(context).client;
    final picked = await selectFiles(context, type: FileType.image);
    final pickedFile = picked.firstOrNull;
    if (pickedFile == null) return;
    if (!mounted) return;

    await showFutureLoadingDialog(
      context: context,
      future: () async {
        final url = await client.uploadContent(
          await pickedFile.readAsBytes(),
          filename: pickedFile.name,
        );
        await client.updateApplicationAccountConfig(
          ApplicationAccountConfig(wallpaperUrl: url),
        );
      },
    );
  }

  double get wallpaperOpacity =>
      _wallpaperOpacity ??
      Matrix.of(context).client.applicationAccountConfig.wallpaperOpacity ??
      0.5;

  double? _wallpaperOpacity;

  Future<void> saveWallpaperOpacity(double opacity) async {
    final client = Matrix.of(context).client;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => client.updateApplicationAccountConfig(
        ApplicationAccountConfig(wallpaperOpacity: opacity),
      ),
    );
    if (result.isValue) return;

    setState(() {
      _wallpaperOpacity = client.applicationAccountConfig.wallpaperOpacity;
    });
  }

  void updateWallpaperOpacity(double opacity) {
    setState(() {
      _wallpaperOpacity = opacity;
    });
  }

  double get wallpaperBlur =>
      _wallpaperBlur ??
      Matrix.of(context).client.applicationAccountConfig.wallpaperBlur ??
      0.5;
  double? _wallpaperBlur;

  Future<void> saveWallpaperBlur(double blur) async {
    final client = Matrix.of(context).client;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => client.updateApplicationAccountConfig(
        ApplicationAccountConfig(wallpaperBlur: blur),
      ),
    );
    if (result.isValue) return;

    setState(() {
      _wallpaperBlur = client.applicationAccountConfig.wallpaperBlur;
    });
  }

  void updateWallpaperBlur(double blur) {
    setState(() {
      _wallpaperBlur = blur;
    });
  }

  void deleteChatWallpaper() => showFutureLoadingDialog(
    context: context,
    future: () => Matrix.of(context).client.setApplicationAccountConfig(
      const ApplicationAccountConfig(wallpaperUrl: null, wallpaperBlur: null),
    ),
  );

  ThemeMode get currentTheme => ThemeController.of(context).themeMode;
  Color? get currentColor => ThemeController.of(context).primaryColor;

  void switchTheme(ThemeMode? newTheme) {
    if (newTheme == null) return;
    switch (newTheme) {
      case ThemeMode.light:
        ThemeController.of(context).setThemeMode(ThemeMode.light);
        break;
      case ThemeMode.dark:
        ThemeController.of(context).setThemeMode(ThemeMode.dark);
        break;
      case ThemeMode.system:
        ThemeController.of(context).setThemeMode(ThemeMode.system);
        break;
    }
    setState(() {});
  }

  Future<void> changeFontSizeFactor(double d) async {
    await AppSettings.fontSizeFactor.setItem(d);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => SettingsStyleView(this);
}
