// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'bubble_shape.dart';

/// Telegram's status glyphs of an **own** message, drawn inside the bubble
/// after the inline timestamp. This fork had no tick glyphs before T4: read
/// state was only the avatar row in `seen_by_row.dart`, which stays.
///
/// The states are read client-locally, no protocol change:
/// - `EventStatus.sending` -> single check, faded
/// - `EventStatus.sent` (local echo, server has not confirmed) -> single check
/// - `EventStatus.synced` (the server has the event) -> double check
/// - at least one receipt -> double check in the read tint. In a group chat
///   "read" means one receipt, like Telegram: the users are not enumerated.
class MessageStatusTick extends StatelessWidget {
  const MessageStatusTick({required this.event, super.key});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.timestampOnOutgoingBubble;
    // Telegram draws ticks only on your own messages. A failed send keeps the
    // text status line below the bubble with its own error icon.
    if (event.senderId != event.room.client.userID ||
        event.status == EventStatus.error) {
      return const SizedBox.shrink();
    }
    final (glyph, color, opacity) = switch (event.status) {
      EventStatus.sending => (
        Icons.check,
        ink,
        TelegramBubbleGeometry.sendingTickOpacity,
      ),
      EventStatus.sent => (Icons.check, ink, 1.0),
      EventStatus.synced || EventStatus.error => (
        Icons.done_all,
        event.receipts.isEmpty ? ink : theme.readTickOnOutgoingBubble,
        1.0,
      ),
    };
    return Opacity(
      opacity: opacity,
      child: SizedBox.square(
        dimension: TelegramBubbleGeometry.tickGlyphSize,
        child: Icon(
          glyph,
          size: TelegramBubbleGeometry.tickGlyphSize,
          color: color,
        ),
      ),
    );
  }
}
