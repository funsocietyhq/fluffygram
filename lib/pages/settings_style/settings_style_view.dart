// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'dart:ui';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:fluffychat/config/chat_backgrounds.dart';
import 'package:fluffychat/config/imported_theme.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/telegram_palette.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/bubble_shape.dart';
import 'package:fluffychat/pages/chat/events/state_message.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/utils/color_value.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/app_config.dart';
import 'settings_style.dart';

class SettingsStyleView extends StatelessWidget {
  final SettingsStyleController controller;

  const SettingsStyleView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const colorPickerSize = 32.0;
    final client = Matrix.of(context).client;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
        title: Text(L10n.of(context).changeTheme),
      ),
      backgroundColor: theme.colorScheme.surface,
      body: MaxWidthBody(
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: SegmentedButton<ThemeMode>(
                selected: {controller.currentTheme},
                onSelectionChanged: (selected) =>
                    controller.switchTheme(selected.single),
                segments: [
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(L10n.of(context).lightTheme),
                    icon: const Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(L10n.of(context).darkTheme),
                    icon: const Icon(Icons.dark_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(L10n.of(context).systemTheme),
                    icon: const Icon(Icons.auto_mode_outlined),
                  ),
                ],
              ),
            ),
            Divider(color: theme.dividerColor),
            ListTile(
              title: Text(
                L10n.of(context).accentColor,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Telegram's accent picker: 7 swatches, the tap writes the key.
            _AccentSwatchRow(
              selectedIndex: controller.accentIndex,
              onSelect: controller.setAccentIndex,
            ),
            Divider(color: theme.dividerColor),
            ListTile(
              title: Text(
                L10n.of(context).setColorTheme,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DynamicColorBuilder(
              builder: (light, dark) {
                final systemColor =
                    Theme.of(context).brightness == Brightness.light
                    ? light?.primary
                    : dark?.primary;
                final colors = [null, AppConfig.chatColor, ...Colors.primaries];
                if (systemColor == null) {
                  colors.remove(null);
                }
                return GridView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 64,
                  ),
                  itemCount: colors.length,
                  itemBuilder: (context, i) {
                    final color = colors[i];
                    return Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Tooltip(
                        message: color == null
                            ? L10n.of(context).systemTheme
                            : '#${color.hexValue.toRadixString(16).toUpperCase()}',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(colorPickerSize),
                          onTap: () => controller.setChatColor(color),
                          child: Material(
                            color: color ?? systemColor,
                            elevation: 6,
                            borderRadius: BorderRadius.circular(
                              colorPickerSize,
                            ),
                            child: SizedBox(
                              width: colorPickerSize,
                              height: colorPickerSize,
                              child: controller.currentColor == color
                                  ? Center(
                                      child: Icon(
                                        Icons.check,
                                        size: 16,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimary,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            Divider(color: theme.dividerColor),
            ListTile(
              title: Text(
                L10n.of(context).messagesStyle,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            StreamBuilder(
              stream: client.onSync.stream.where(
                (syncUpdate) =>
                    syncUpdate.accountData?.any(
                      (accountData) =>
                          accountData.type ==
                          ApplicationAccountConfigExtension.accountDataKey,
                    ) ??
                    false,
              ),
              builder: (context, snapshot) {
                final accountConfig = client.applicationAccountConfig;

                return Column(
                  mainAxisSize: .min,
                  children: [
                    MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(
                          AppSettings.fontSizeFactor.value,
                        ),
                      ),
                      child: AnimatedContainer(
                        duration: FluffyThemes.animationDuration,
                        curve: FluffyThemes.animationCurve,
                        decoration: const BoxDecoration(),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (accountConfig.wallpaperUrl != null)
                              Opacity(
                                opacity: controller.wallpaperOpacity,
                                child: ImageFiltered(
                                  imageFilter: ImageFilter.blur(
                                    sigmaX: controller.wallpaperBlur,
                                    sigmaY: controller.wallpaperBlur,
                                  ),
                                  child: MxcImage(
                                    key: ValueKey(accountConfig.wallpaperUrl),
                                    uri: accountConfig.wallpaperUrl,
                                    fit: BoxFit.cover,
                                    isThumbnail: true,
                                    width: FluffyThemes.columnWidth * 2,
                                    height: 212,
                                  ),
                                ),
                              ),
                            Column(
                              mainAxisSize: .min,
                              children: [
                                const SizedBox(height: 16),
                                StateMessage(
                                  Event(
                                    eventId: 'style_dummy',
                                    room: Room(
                                      id: '!style_dummy',
                                      client: client,
                                    ),
                                    content: {'membership': 'join'},
                                    type: EventTypes.RoomMember,
                                    senderId: client.userID!,
                                    originServerTs: DateTime.now(),
                                    stateKey: client.userID,
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.only(
                                    left: 12 + 12 + Avatar.defaultSize,
                                    right: 12,
                                    top: accountConfig.wallpaperUrl == null
                                        ? 0
                                        : 12,
                                    bottom: 12,
                                  ),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: theme.bubbleColor,
                                      borderRadius: BorderRadius.circular(
                                        AppConfig.borderRadius,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        'Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor',
                                        style: TextStyle(
                                          color: theme.onBubbleColor,
                                          fontSize: AppConfig.messageFontSize,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: 12,
                                      left: 12,
                                      top: accountConfig.wallpaperUrl == null
                                          ? 0
                                          : 12,
                                      bottom: 12,
                                    ),
                                    child: Material(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(
                                        AppConfig.borderRadius,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        child: Text(
                                          'Lorem ipsum dolor sit amet',
                                          style: TextStyle(
                                            color: theme.colorScheme.onSurface,
                                            fontSize: AppConfig.messageFontSize,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Divider(color: theme.dividerColor),
                    ListTile(
                      title: TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: theme.colorScheme.secondaryContainer,
                          foregroundColor:
                              theme.colorScheme.onSecondaryContainer,
                        ),
                        onPressed: controller.setWallpaper,
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(L10n.of(context).setWallpaper),
                      ),
                      trailing: accountConfig.wallpaperUrl == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.delete_outlined),
                              color: theme.colorScheme.error,
                              onPressed: controller.deleteChatWallpaper,
                            ),
                    ),
                    if (accountConfig.wallpaperUrl != null) ...[
                      ListTile(title: Text(L10n.of(context).opacity)),
                      Slider.adaptive(
                        min: 0.1,
                        max: 1.0,
                        divisions: 9,
                        semanticFormatterCallback: (d) => d.toString(),
                        value: controller.wallpaperOpacity,
                        onChanged: controller.updateWallpaperOpacity,
                        onChangeEnd: controller.saveWallpaperOpacity,
                      ),
                      ListTile(title: Text(L10n.of(context).blur)),
                      Slider.adaptive(
                        min: 0.0,
                        max: 10.0,
                        divisions: 10,
                        semanticFormatterCallback: (d) => d.toString(),
                        value: controller.wallpaperBlur,
                        onChanged: controller.updateWallpaperBlur,
                        onChangeEnd: controller.saveWallpaperBlur,
                      ),
                    ],
                  ],
                );
              },
            ),
            ListTile(
              title: Text(L10n.of(context).fontSize),
              // Telegram's row names the size it lands on, not a multiplier:
              // 12..24sp, 16sp at factor 1.0.
              subtitle: Text('${controller.messageTextSp.round()} sp'),
            ),
            Slider.adaptive(
              min: TelegramBubbleGeometry.minMessageTextSp,
              max: TelegramBubbleGeometry.maxMessageTextSp,
              // 1sp steps over Telegram's 12..24sp range.
              divisions:
                  (TelegramBubbleGeometry.maxMessageTextSp -
                          TelegramBubbleGeometry.minMessageTextSp)
                      .round(),
              value: controller.messageTextSp,
              semanticFormatterCallback: (d) => '${d.round()} sp',
              onChanged: controller.changeMessageTextSp,
            ),
            ListTile(
              title: Text(L10n.of(context).bubbleWidth),
              // The cap is clamped to the window width when the bubble draws,
              // so a big value here can never overflow the chat.
              // The dp cap is derived: percent x the chat column (T39).
              subtitle: Text('${controller.bubbleWidthPercent} %'),
            ),
            Slider.adaptive(
              min: TelegramBubbleGeometry.minBubbleWidthPercent.toDouble(),
              max: TelegramBubbleGeometry.maxBubbleWidthPercent.toDouble(),
              // 1% steps over the 50..100 % range, as Telegram desktop.
              divisions:
                  TelegramBubbleGeometry.maxBubbleWidthPercent -
                  TelegramBubbleGeometry.minBubbleWidthPercent,
              value: controller.bubbleWidthPercent.toDouble(),
              semanticFormatterCallback: (d) => '${d.round()} %',
              onChanged: (d) => controller.changeBubbleWidthPercent(d.round()),
            ),
            SwitchListTile.adaptive(
              title: Text(L10n.of(context).animations),
              value: controller.animationsEnabled,
              onChanged: controller.setAnimationsEnabled,
            ),
            SwitchListTile.adaptive(
              title: Text(L10n.of(context).coloredSenderNames),
              value: controller.colorSenderNames,
              onChanged: controller.setColorSenderNames,
            ),
            // Telegram's "Chat background" row: the same sheet the chat header
            // opens, scoped to every chat. The store listenable repaints the
            // dot when the sheet writes the key.
            ListenableBuilder(
              listenable: ChatBackgrounds.store,
              builder: (context, _) => ListTile(
                title: Text(L10n.of(context).chatBackground),
                subtitle: Text(L10n.of(context).chatBackgroundGlobalHint),
                trailing: _BackgroundDot(
                  color: ChatBackgrounds.clampToTheme(
                    controller.chatBackground ?? theme.colorScheme.surface,
                    theme.brightness,
                  ),
                  ringColor: theme.colorScheme.onSurfaceVariant,
                ),
                onTap: controller.pickChatBackground,
              ),
            ),
            // Telegram's theme import (T8): the group exports a theme from
            // Telegram, picks the `.attheme` file here and the chat takes its
            // colours. The file text is device-local - nothing is uploaded.
            ListenableBuilder(
              listenable: ImportedTheme.store,
              builder: (context, _) => ListTile(
                title: Text(L10n.of(context).importTelegramTheme),
                subtitle: Text(
                  controller.hasImportedTheme
                      ? L10n.of(
                          context,
                        ).importedThemeActive(controller.importedThemeName)
                      : L10n.of(context).importTelegramThemeHint,
                ),
                trailing: controller.hasImportedTheme
                    ? TextButton.icon(
                        onPressed: controller.removeImportedTheme,
                        icon: const Icon(Icons.link_off),
                        label: Text(L10n.of(context).removeImportedTheme),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: controller.importTelegramTheme,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The filled circle at the end of the "Chat background" row: the fill the
/// chat will draw, so the row shows the setting, not a name.
class _BackgroundDot extends StatelessWidget {
  const _BackgroundDot({required this.color, required this.ringColor});

  final Color color;
  final Color ringColor;

  static const double size = 24;
  static const double ringWidth = 1;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: ringColor, width: ringWidth),
    ),
  );
}

/// Telegram's accent colour picker: a row of the 7
/// `TelegramPalette.accentValues` circles, the selected one under a ring with
/// a check. A tap writes `AppSettings.telegramAccentIndex` at once - Telegram
/// has no save button.
class _AccentSwatchRow extends StatelessWidget {
  const _AccentSwatchRow({required this.selectedIndex, required this.onSelect});

  final int selectedIndex;
  final void Function(int index) onSelect;

  static const double swatchSize = 36;
  static const double swatchGap = 6;
  static const double selectedRingWidth = 2;
  static const double checkSize = 16;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: swatchGap,
        vertical: swatchGap,
      ),
      // A Wrap, not a Row: 7 swatches always fit, they just break to a second
      // line on a narrow phone.
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          for (
            var index = 0;
            index < TelegramPalette.accentValues.length;
            index++
          )
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: swatchGap),
              child: InkWell(
                borderRadius: BorderRadius.circular(swatchSize),
                onTap: () => onSelect(index),
                child: Container(
                  width: swatchSize,
                  height: swatchSize,
                  decoration: BoxDecoration(
                    color: TelegramPalette.accentValues[index],
                    shape: BoxShape.circle,
                    border: index == selectedIndex
                        ? Border.all(
                            color: theme.colorScheme.onSurface,
                            width: selectedRingWidth,
                          )
                        : null,
                  ),
                  child: index == selectedIndex
                      ? const Center(
                          // White glyph on every accent: it is a bubble ink.
                          child: Icon(
                            Icons.check,
                            size: checkSize,
                            color: TelegramPalette.dayTextOnBubble,
                          ),
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
