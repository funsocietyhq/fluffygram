// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:fluffychat/config/telegram_palette.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat_list/chat_list_geometry.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class UnreadBubble extends StatelessWidget {
  final Room room;
  const UnreadBubble({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final unread = room.isUnreadOrInvited;
    final hasNotifications = room.notificationCount > 0;
    final isMuted = room.pushRuleState != PushRuleState.notify;
    final highlighted = room.highlightCount > 0;
    final showsCount = hasNotifications || room.markedUnread;
    // Telegram's badge is BADGE_SIZE 20.666 dp high at dp(11.5) corners
    // (DialogCell.java:1230, 5342). A wider pill grows to the left for longer
    // counts, like Telegram's, and the count prints raw (DialogCell.java:2126,
    // no 99+ cap).
    final countDigits = room.notificationCount.toString().length;
    final visible = unread || room.hasNewMessages || hasNotifications;
    final width = !visible
        ? 0.0
        : ChatListGeometry.badgeMinWidth +
              (countDigits > 1 ? (countDigits - 1) * 6.0 : 0.0);
    // The badge fill is Telegram's chats_unreadCounter accent blue: #399EF3
    // at night (night.attheme:79) and #24AEF7 by day (day.attheme:41), with
    // white digits in both themes (T44). A muted counter is not filled:
    // DialogCell.java:5279-5288 strokes a 2 dp outline of chats_pinnedOverlay
    // blended over the row background, and the digits take
    // chats_unreadCounterMuted. A mention keeps the theme's error colour.
    final mutedOutline = isMuted && !highlighted;
    final badgeColor = mutedOutline
        ? Colors.transparent
        : highlighted
        ? theme.colorScheme.error
        : (night
              ? TelegramPalette.chatListUnreadBadge
              : TelegramPalette.dayChatListUnreadBadge);
    final badgeTextColor = highlighted
        ? theme.colorScheme.onError
        : mutedOutline
        ? (night
              ? TelegramPalette.chatListUnreadBadgeMuted
              : TelegramPalette.dayChatListUnreadBadgeMuted)
        : (night
              ? TelegramPalette.unreadBadgeText
              : TelegramPalette.dayUnreadBadgeText);
    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(
        horizontal: ChatListGeometry.badgeTextPadding,
      ),
      height: visible ? ChatListGeometry.badgeHeight : 0,
      width: width,
      decoration: BoxDecoration(
        color: badgeColor,
        // DialogCell.java:5279-5283: Style.STROKE, setStrokeWidth(dp(2)),
        // Join.ROUND, Cap.ROUND.
        border: mutedOutline
            ? Border.all(
                color: night
                    ? TelegramPalette.chatListUnreadBadgeMutedOutline
                    : TelegramPalette.dayChatListUnreadBadgeMutedOutline,
                width: 2,
              )
            : null,
        borderRadius: BorderRadius.circular(ChatListGeometry.badgeRadius),
      ),
      child: showsCount
          ? Text(
              room.notificationCount.toString(),
              style: TextStyle(
                color: badgeTextColor,
                fontSize: ChatListGeometry.badgeFontSize,
                fontWeight: FontWeight.w500,
              ),
              textAlign: .center,
            )
          : const SizedBox.shrink(),
    );
  }
}
