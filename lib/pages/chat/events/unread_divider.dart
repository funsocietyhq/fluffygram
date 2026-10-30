// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:fluffychat/config/telegram_palette.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/bubble_shape.dart';
import 'package:flutter/material.dart';

/// Telegram's "Unread Messages" divider row, drawn above the first unread
/// message of a session. Dart port of `ui/Cells/ChatUnreadCell.java` (roadmap
/// T47): the cell is a `FrameLayout` that adds a full-width coloured band
/// (`:37-39`), the `ic_ab_new` arrow inside that band at its right end
/// (`:42-45`), and the label centred in the whole row (`:48-52`). Every number
/// is in `TelegramBubbleGeometry` with its source line, and the colours are the
/// three `chat_unreadMessagesStart*` theme keys.
///
/// FluffyChat upstream drew this slot as two hairline `Divider`s around a small
/// translucent pill carrying `readUpToHere` at 11 px: no band, no arrow, no
/// bold label. Telegram's cell states the row, so the slot takes its numbers.
class TelegramUnreadDivider extends StatelessWidget {
  const TelegramUnreadDivider({super.key});

  /// `chat_unreadMessagesStartBackground` (`ChatUnreadCell.java:38`): night
  /// `#212122` (`night.attheme:350`), day `#3499E6` (`day.attheme:233`).
  static Color backgroundColorOf(Brightness brightness) =>
      brightness == Brightness.dark
      ? TelegramPalette.unreadDividerBackground
      : TelegramPalette.dayUnreadDividerBackground;

  /// `chat_unreadMessagesStartArrowIcon` (`:43`): night `#6D6D6F`
  /// (`night.attheme:87`), day `#C6E7FA` (`day.attheme:47`).
  static Color arrowColorOf(Brightness brightness) =>
      brightness == Brightness.dark
      ? TelegramPalette.unreadDividerArrow
      : TelegramPalette.dayUnreadDividerArrow;

  /// `chat_unreadMessagesStartText` (`:50`): night white at alpha `0xDB`
  /// blended over the night band (`#C1C1C1`), day opaque `#FFFFFF`
  /// (`day.attheme:1`). See `the measurement log` "T47" for the blend.
  static Color labelColorOf(Brightness brightness) =>
      brightness == Brightness.dark
      ? TelegramPalette.unreadDividerText
      : TelegramPalette.dayUnreadDividerText;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return SizedBox(
      // Telegram's row fills the chat column. Here it fills the column the
      // timeline hands it - the bubble column, which `message.dart` caps at
      // `FluffyThemes.maxTimelineWidth` and pads 8 dp per side; a true
      // full-width row is a `ChatEventList` item, named in ROADMAP T40.4.
      width: double.infinity,
      height: TelegramBubbleGeometry.unreadDividerRowHeight, // :73
      child: Stack(
        children: [
          // The band: MATCH_PARENT x 27 at LEFT|TOP with a 7 dp top margin
          // (ChatUnreadCell.java:39), painted with the theme fill (:38).
          Positioned(
            left: 0,
            right: 0,
            top: TelegramBubbleGeometry.unreadDividerBandTopMargin,
            height: TelegramBubbleGeometry.unreadDividerBandHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(color: backgroundColorOf(brightness)),
              // The arrow sits in the band at RIGHT|CENTER_VERTICAL with a
              // 10 dp right margin (:45) and 2 dp of top padding (:44).
              // `Icons.expand_more` stands in for `ic_ab_new` (:42): a chevron
              // down at the band's right edge, and their vector assets stay in
              // their own tree (AGENTS.md ground rule 2).
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(
                    right: TelegramBubbleGeometry.unreadDividerArrowRightMargin,
                    top: TelegramBubbleGeometry.unreadDividerArrowTopPadding,
                  ),
                  child: Icon(
                    Icons.expand_more,
                    size: TelegramBubbleGeometry.unreadDividerArrowSize,
                    color: arrowColorOf(brightness),
                  ),
                ),
              ),
            ),
          ),
          // The label: Gravity.CENTER with 32 dp side margins (:52), 14 dp
          // bold (:49, :51) in the theme label ink (:50), bottom padding 1 dp
          // (:48).
          Center(
            child: Padding(
              padding: const EdgeInsets.only(
                left: TelegramBubbleGeometry.unreadDividerLabelSideMargin,
                right: TelegramBubbleGeometry.unreadDividerLabelSideMargin,
                bottom: 1,
              ),
              child: Text(
                L10n.of(context).unreadMessages,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: TelegramBubbleGeometry.unreadDividerLabelFontSize,
                  fontWeight: FontWeight.bold,
                  color: labelColorOf(brightness),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
