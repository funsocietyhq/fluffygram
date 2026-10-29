// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/chat_backgrounds.dart';
import 'package:fluffychat/config/telegram_palette.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// Telegram's chat background picker (roadmap T5B): the solid swatches of
/// `TelegramPalette.chatBackgroundValues`, the current pick under a ring and a
/// check, plus a "Default" row that clears the pick. With a [roomId] the pick
/// is stored for that chat only (`AppSettings.chatBackgrounds`), without one it
/// is the global pick (`AppSettings.chatBackground`). A tap applies at once and
/// closes the sheet - Telegram has no save button.
Future<void> showChatBackgroundPicker({
  required BuildContext context,
  String? roomId,
}) => showAdaptiveBottomSheet<void>(
  context: context,
  builder: (sheetContext) => _ChatBackgroundPickerSheet(roomId: roomId),
);

class _ChatBackgroundPickerSheet extends StatelessWidget {
  const _ChatBackgroundPickerSheet({this.roomId});

  /// null = the global scope, every chat.
  final String? roomId;

  static const double swatchSize = 44;
  static const double swatchGap = 8;
  static const double ringWidth = 3;
  static const double checkSize = 20;
  static const double sheetPadding = 16;
  static const double noteFontSize = 12;

  /// The pick of this sheet's scope, before the contrast guard.
  Color? get _picked => roomId == null
      ? ChatBackgrounds.global
      : ChatBackgrounds.forRoom(roomId!);

  Future<void> _pick(BuildContext context, Color? color) async {
    final room = roomId;
    if (room == null) {
      await ChatBackgrounds.setGlobal(color);
    } else {
      await ChatBackgrounds.setForRoom(room, color);
    }
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final picked = _picked;
    final brightness = theme.brightness;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(sheetPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.chatBackground,
              style: TextStyle(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: sheetPadding),
            // A Wrap, not a Row: every swatch fits, they just break to a second
            // line on a narrow phone.
            Wrap(
              spacing: swatchGap,
              runSpacing: swatchGap,
              children: [
                for (final color in TelegramPalette.chatBackgroundValues)
                  _Swatch(
                    color: ChatBackgrounds.clampToTheme(color, brightness),
                    selected: picked?.toARGB32() == color.toARGB32(),
                    onTap: () => _pick(context, color),
                  ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              // The dot has no tap of its own: the row carries it.
              leading: _Swatch(
                color: theme.colorScheme.surface,
                selected: picked == null,
                // The default row paints the page itself, so a ring is the only
                // thing that reads on it.
                ringColor: theme.colorScheme.onSurfaceVariant,
              ),
              title: Text(l10n.chatBackgroundDefault),
              onTap: () => _pick(context, null),
            ),
            Text(
              l10n.chatBackgroundContrastNote,
              style: const TextStyle(
                fontSize: noteFontSize,
                color: TelegramPalette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One round pick of the sheet: a filled circle, the chosen one under a ring
/// with a check (the style of `_AccentSwatchRow` on the style page).
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    this.onTap,
    this.ringColor,
  });

  final Color color;
  final bool selected;

  /// null when a parent row already carries the tap.
  final void Function()? onTap;

  /// Set on a swatch that paints the page colour: the fill cannot carry the
  /// selection, so the ring draws in this ink instead.
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(
        _ChatBackgroundPickerSheet.swatchSize,
      ),
      onTap: onTap,
      child: Container(
        width: _ChatBackgroundPickerSheet.swatchSize,
        height: _ChatBackgroundPickerSheet.swatchSize,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(
                  color:
                      ringColor ??
                      theme.colorScheme.onSurface, // the ring on the pick
                  width: _ChatBackgroundPickerSheet.ringWidth,
                )
              : null,
        ),
        child: selected && ringColor == null
            ? const Center(
                // White glyph on every swatch: it is a bubble ink.
                child: Icon(
                  Icons.check,
                  size: _ChatBackgroundPickerSheet.checkSize,
                  color: TelegramPalette.dayTextOnBubble,
                ),
              )
            : null,
      ),
    );
  }
}
