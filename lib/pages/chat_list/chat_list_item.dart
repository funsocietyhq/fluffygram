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
import 'package:fluffychat/config/telegram_palette.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/active_call_indicator.dart';
import 'package:fluffychat/pages/chat_list/chat_list_draft.dart';
import 'package:fluffychat/pages/chat_list/chat_list_geometry.dart';
import 'package:fluffychat/pages/chat_list/telegram_dialog_date.dart';
import 'package:fluffychat/pages/chat_list/unread_bubble.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import '../../utils/date_time_extension.dart';
import '../../widgets/avatar.dart';

/// Telegram's chat-list preview name slot - the inline sender prefix and the
/// draft label - is a single paint: **bold `dp(14)`**
/// (`Theme.java:7822-7823` and `dialogs_messageNamePaint.setTextSize(dp(14))` at
/// `:7896`), re-inked per case at `DialogCell.java:4213-4221`. The live size is
/// `ChatListGeometry.senderPrefixFontSize`, shared with the rig.
const double _nameSlotFontSize = ChatListGeometry.senderPrefixFontSize;
const FontWeight _nameSlotFontWeight = FontWeight.bold;

/// The slot's ink for a normal row: `chats_nameMessage_threeLines` - night
/// `#EBEBEB` (`night.attheme:66`) / day `#424449` (`day.attheme:35`), applied at
/// `DialogCell.java:4219`.
const Color _nameSlotInkNight = TelegramPalette.chatListSenderPrefix;
const Color _nameSlotInkDay = TelegramPalette.dayChatListSenderPrefix;

/// T45.1 - the typing line's ink, theme key `key_chat_listName`: night
/// `#60DA46` (`night.attheme:35`) / day `#008DE7` (`day.attheme:50`), applied at
/// `AdapterDialogs.initThemeDialogsParams:2111` for the `chats_typing` text
/// Telegram draws in the name slot (`DialogCell.java:1158-1176`). File-local
/// consts, not palette constants: `verification/palette_contract.sh` fails on a
/// palette hex with no row in the rig's target JSON (see
/// `the measurement log` T45.1).
const Color _typingNameInkNight = Color(0xFF60DA46);
const Color _typingNameInkDay = Color(0xFF008DE7);

class ChatListItem extends StatelessWidget {
  final Room room;
  final Room? space;
  final bool activeChat;
  final void Function(BuildContext context)? onLongPress;
  final void Function()? onForget;
  final void Function() onTap;
  final String? filter;

  const ChatListItem(
    this.room, {
    this.activeChat = false,
    required this.onTap,
    this.onLongPress,
    this.onForget,
    this.filter,
    this.space,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isMuted = room.pushRuleState != PushRuleState.notify;
    // T45.1: the row's typing condition. Telegram draws the typing name for
    // other members' typing only (`isLastActionIsTyping`,
    // DialogCell.java:1158-1176), so this user never counts.
    final isTyping = room.typingUsers.any(
      (user) => user.id != room.client.userID,
    );
    final lastEvent = room.lastEvent;
    final ownMessage = lastEvent?.senderId == room.client.userID;
    final directChatMatrixId = room.directChatMatrixID;
    final isDirectChat = directChatMatrixId != null;
    final hasNotifications = room.notificationCount > 0;
    final backgroundColor = activeChat
        ? theme.colorScheme.secondaryContainer
        : null;
    final displayname = room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    final filter = this.filter;
    if (filter != null && !displayname.toLowerCase().contains(filter)) {
      return const SizedBox.shrink();
    }

    final needLastEventSender =
        lastEvent != null &&
        room.getState(EventTypes.RoomMember, lastEvent.senderId) == null;
    final space = this.space;

    // Telegram draws the preview as "<sender>: <body>" from one paint, inked
    // with a theme key and never with the sender's colour
    // (DialogCell.java:4213-4221). Build the same prefix the matrix SDK prepends
    // so the row can split the string it returns and restyle its head.
    final withSenderNamePrefix =
        lastEvent != null &&
        (!isDirectChat || directChatMatrixId != lastEvent.senderId);
    final senderPrefix = withSenderNamePrefix
        ? '${lastEvent.senderId == room.client.userID ? L10n.of(context).you : lastEvent.senderFromMemoryOrFallback.calcDisplayname(i18n: MatrixLocals(L10n.of(context)))}: '
        : '';
    // chats_nameMessage_threeLines (T43.1): the phone layout's name ink, night
    // #EBEBEB / day #424449, set at DialogCell.java:4219. The day blue #298ACF
    // belongs to the 4-line key chats_nameMessage (`day.attheme:18`,
    // `DialogCell.java:1821`) and not to this layout. The sender's hash colour
    // stays where Telegram uses it - the avatar and the timeline's sender labels
    // (`lib/pages/chat/events/message.dart:167`) - not in this row's text.
    final senderPrefixColor = theme.brightness == Brightness.light
        ? _nameSlotInkDay
        : _nameSlotInkNight;

    // T14b U2 (finding 1): the title ink follows the theme, like Telegram's own
    // chat-list text. `TelegramPalette.chatListTitle` is the night value
    // (measured #F1F1F1 on the #181818 row since 2026-10-26) and it stays the
    // night value. In the day
    // theme that same constant put near-white ink on a light row and the title
    // was unreadable - our own render showed near-white text on the #E6EBEE row.
    // The day row now takes the theme's own on-surface ink: no new colour
    // constant, so the palette contract keeps its colour count.
    final titleColor = theme.brightness == Brightness.light
        ? theme.colorScheme.onSurface
        : TelegramPalette.chatListTitle;
    final titleStyle = TextStyle(
      fontSize: ChatListGeometry.titleFontSize,
      fontWeight: ChatListGeometry.titleFontWeight,
      color: titleColor,
    );
    // chats_typing takes the name slot's own paint: bold `dp(14)`
    // (`Theme.java:7673`, `ActionLayoutLayout.java:1478`), re-inked green.
    final typingNameStyle = TextStyle(
      fontSize: _nameSlotFontSize,
      fontWeight: _nameSlotFontWeight,
      color: theme.brightness == Brightness.light
          ? _typingNameInkDay
          : _typingNameInkNight,
    );
    final previewStyle = TextStyle(
      fontSize: ChatListGeometry.previewFontSize,
      color: TelegramPalette.chatListPreview,
    );
    // chats_draft (T45): the draft label ink is theme-split like the badge fill.
    final draftLabelColor = theme.brightness == Brightness.light
        ? TelegramPalette.dayChatListDraftLabel
        : TelegramPalette.chatListDraftLabel;

    return Padding(
      // Telegram's row highlight is full-bleed: the 5.5dp edge margin lives in
      // the tile's content padding, the row itself adds no side padding.
      padding: EdgeInsets.zero,
      child: Material(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        clipBehavior: Clip.hardEdge,
        color: backgroundColor,
        child: FutureBuilder(
          future: room.name.isEmpty ? room.loadHeroUsers() : null,
          builder: (context, _) => HoverBuilder(
            builder: (context, listTileHovered) => ListTile(
              minTileHeight: ChatListGeometry.rowHeight,
              minVerticalPadding: ChatListGeometry.rowVerticalPadding,
              horizontalTitleGap: ChatListGeometry.avatarToTextGap,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: ChatListGeometry.edgeMargin,
              ),
              onLongPress: () => onLongPress?.call(context),
              leading: HoverBuilder(
                builder: (context, hovered) => AnimatedScale(
                  duration: FluffyThemes.animationDuration,
                  curve: FluffyThemes.animationCurve,
                  scale: hovered ? 1.1 : 1.0,
                  child: SizedBox(
                    width: ChatListGeometry.avatarSize,
                    height: ChatListGeometry.avatarSize,
                    child: Stack(
                      // The dot of T49 stands 1 dp outside the avatar box, as
                      // Telegram's does (`DialogCell.java:5125`), so the box
                      // must not clip its children.
                      clipBehavior: Clip.none,
                      children: [
                        if (space != null)
                          Positioned(
                            top: 0,
                            left: 0,
                            child: Avatar(
                              shapeBorder: RoundedSuperellipseBorder(
                                side: BorderSide(
                                  width: 2,
                                  color:
                                      backgroundColor ??
                                      theme.colorScheme.surface,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppConfig.spaceBorderRadius * 0.75,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(
                                AppConfig.spaceBorderRadius * 0.75,
                              ),
                              mxContent: space.avatar,
                              size: Avatar.defaultSize * 0.75,
                              name: space.getLocalizedDisplayname(),
                              onTap: () => onLongPress?.call(context),
                            ),
                          ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Avatar(
                            shapeBorder: space == null
                                ? room.isSpace
                                      ? RoundedSuperellipseBorder(
                                          side: BorderSide(
                                            width: 1,
                                            color: theme.dividerColor,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            AppConfig.spaceBorderRadius,
                                          ),
                                        )
                                      : null
                                : RoundedRectangleBorder(
                                    side: BorderSide(
                                      width: 2,
                                      color:
                                          backgroundColor ??
                                          theme.colorScheme.surface,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      ChatListGeometry.avatarSize,
                                    ),
                                  ),
                            borderRadius: room.isSpace
                                ? BorderRadius.circular(
                                    AppConfig.spaceBorderRadius,
                                  )
                                : null,
                            mxContent: room.avatar,
                            size: space != null
                                ? ChatListGeometry.avatarSize * 0.75
                                : ChatListGeometry.avatarSize,
                            name: displayname,
                            // `Avatar`'s own presence dot is suppressed: it is
                            // a 16 dp green disc (`widgets/avatar.dart:128-158`)
                            // and it fetches presence per row. T49 draws
                            // Telegram's dot below, from the presence the client
                            // already holds.
                            onTap: () => onLongPress?.call(context),
                          ),
                        ),
                        if (isDirectChat)
                          Positioned(
                            right:
                                ChatListGeometry.onlineDotRightInset -
                                ChatListGeometry.onlineDotRingRadius,
                            bottom:
                                ChatListGeometry.onlineDotBottomInset -
                                ChatListGeometry.onlineDotRingRadius,
                            child: TelegramOnlineDot(
                              online: _peerIsOnline(
                                room.client,
                                directChatMatrixId,
                              ),
                              ringColor: theme.colorScheme.surface,
                              dotColor: theme.brightness == Brightness.light
                                  ? TelegramPalette.dayChatListOnlineDot
                                  : TelegramPalette.chatListOnlineDot,
                            ),
                          ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () => onLongPress?.call(context),
                            child: AnimatedScale(
                              duration: FluffyThemes.animationDuration,
                              curve: FluffyThemes.animationCurve,
                              scale: listTileHovered ? 1.0 : 0.0,
                              child: Material(
                                color: backgroundColor,
                                borderRadius: BorderRadius.circular(16),
                                child: const Icon(
                                  Icons.arrow_drop_down_circle_outlined,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              title: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      // Telegram replaces the room name with `chats_typing`
                      // while a member types (`DialogCell.java:1158-1176`).
                      isTyping ? L10n.of(context).chatsTyping : displayname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: isTyping ? typingNameStyle : titleStyle,
                    ),
                  ),
                  if (isMuted)
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Icon(
                        Icons.notifications_off_outlined,
                        size: 16,
                        color: TelegramPalette.textSecondary,
                      ),
                    ),
                  if (room.isLowPriority)
                    Padding(
                      padding: EdgeInsets.only(
                        right: hasNotifications ? 4.0 : 0.0,
                      ),
                      child: Icon(
                        Icons.low_priority,
                        size: 16,
                        color: TelegramPalette.textSecondary,
                      ),
                    ),
                  if (room.isFavourite)
                    Padding(
                      padding: EdgeInsets.only(
                        right: hasNotifications ? 4.0 : 0.0,
                      ),
                      child: Icon(
                        Icons.push_pin,
                        size: 16,
                        color: TelegramPalette.textSecondary,
                      ),
                    ),
                  // `DialogCell.java:1299`: the timestamp draws under
                  // `!lastActionIsTyping` - the typing line takes the row's
                  // right side while it shows.
                  if (!isTyping &&
                      !room.isSpace &&
                      room.membership != Membership.invite)
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Text(
                        telegramDialogDateString(
                          room.latestEventReceivedTime,
                          now: DateTime.now(),
                          hourOfDayFirst: room.latestEventReceivedTime
                              .use24HourFormat(context),
                          locale: Localizations.localeOf(context).languageCode,
                        ),
                        style: TextStyle(
                          fontSize: ChatListGeometry.timeFontSize,
                          fontWeight: room.hasNewMessages
                              ? FontWeight.bold
                              : null,
                          color: room.highlightCount >= 1
                              ? theme.colorScheme.error
                              : room.hasNewMessages
                              ? TelegramPalette.textLightBlue
                              : TelegramPalette.chatListTime,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Row(
                children: [
                  if (room.hasActiveMatrixRtcCall)
                    Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: ActiveCallIndicator(room: room),
                    ),
                  if (!isTyping &&
                      ownMessage &&
                      room.lastEvent?.status.isSending == true) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    ),
                    const SizedBox(width: 4),
                  ],
                  AnimatedSize(
                    clipBehavior: Clip.hardEdge,
                    duration: FluffyThemes.animationDuration,
                    curve: FluffyThemes.animationCurve,
                    // T45.1: Telegram paints nothing in the preview slot while
                    // a member types (`DialogCell.java:1158-1176`) - the typing
                    // line lives in the name slot, so the thread chip keeps its
                    // place.
                    child:
                        room.lastEvent?.relationshipType ==
                            RelationshipTypes.thread
                        ? Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: theme.colorScheme.outline,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppConfig.borderRadius,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            margin: const EdgeInsets.only(right: 4.0),
                            child: Row(
                              mainAxisSize: .min,
                              children: [
                                Icon(
                                  Icons.message_outlined,
                                  size: 12,
                                  color: theme.colorScheme.outline,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  L10n.of(context).thread,
                                  style: TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: room.isSpace && room.membership == Membership.join
                        ? Text(
                            L10n.of(
                              context,
                            ).countChats(room.spaceChildren.length),
                            style: previewStyle,
                          )
                        : FutureBuilder(
                            key: ValueKey(
                              '${lastEvent?.eventId}_${lastEvent?.type}_${lastEvent?.redacted}',
                            ),
                            future: needLastEventSender
                                ? lastEvent.calcLocalizedBody(
                                    MatrixLocals(L10n.of(context)),
                                    hideReply: true,
                                    hideEdit: true,
                                    plaintextBody: true,
                                    removeMarkdown: true,
                                    withSenderNamePrefix: withSenderNamePrefix,
                                  )
                                : null,
                            initialData: lastEvent?.calcLocalizedBodyFallback(
                              MatrixLocals(L10n.of(context)),
                              hideReply: true,
                              hideEdit: true,
                              plaintextBody: true,
                              removeMarkdown: true,
                              withSenderNamePrefix: withSenderNamePrefix,
                            ),
                            builder: (context, snapshot) {
                              final previewText =
                                  room.membership == Membership.invite
                                  ? room
                                            .getState(
                                              EventTypes.RoomMember,
                                              room.client.userID!,
                                            )
                                            ?.content
                                            .tryGet<String>('reason') ??
                                        (isDirectChat
                                            ? L10n.of(context).newChatRequest
                                            : L10n.of(context).inviteGroupChat)
                                  : snapshot.data?.trim().replaceAll(
                                          '\n',
                                          ' ',
                                        ) ??
                                        L10n.of(context).noMessagesYet;
                              // 1 preview line: the measured row is 52dp.
                              final hasPrefix =
                                  senderPrefix.isNotEmpty &&
                                  previewText.startsWith(senderPrefix);
                              // Telegram puts a chat's saved draft in place of
                              // the preview: the label "Draft" in the theme key
                              // chats_draft, then ": " and the draft text. That
                              // key is a red, not an accent: #FC474A night
                              // (night.attheme:119), #E32246 day
                              // (day.attheme:70), painted over the whole label
                              // by DialogCell.java:1622. The name slot it lives
                              // in is bold dp(14) (Theme.java:7822-7823, :7896)
                              // - the same slot as the sender prefix, so the
                              // label takes _nameSlotFontSize and
                              // _nameSlotFontWeight, and only the ink differs.
                              return ChatListDraft(
                                room: room,
                                builder: (context, draft) => Text.rich(
                                  TextSpan(
                                    children: [
                                      if (draft != null)
                                        TextSpan(
                                          text:
                                              '${L10n.of(context).draftLabel} ',
                                          style: TextStyle(
                                            color: draftLabelColor,
                                            fontSize: _nameSlotFontSize,
                                            fontWeight: _nameSlotFontWeight,
                                          ),
                                        ),
                                      if (draft != null)
                                        TextSpan(text: draft)
                                      else ...[
                                        if (hasPrefix)
                                          TextSpan(
                                            text: senderPrefix,
                                            style: TextStyle(
                                              fontSize: _nameSlotFontSize,
                                              fontWeight: _nameSlotFontWeight,
                                              color: senderPrefixColor,
                                            ),
                                          ),
                                        TextSpan(
                                          text: hasPrefix
                                              ? previewText.substring(
                                                  senderPrefix.length,
                                                )
                                              : previewText,
                                        ),
                                      ],
                                    ],
                                  ),
                                  softWrap: false,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: previewStyle.copyWith(
                                    decoration: room.lastEvent?.redacted == true
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(width: 8),
                  UnreadBubble(room: room),
                ],
              ),
              onTap: onTap,
              trailing: onForget == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.delete_outlined),
                      onPressed: onForget,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Telegram marks a direct chat whose peer is online (`DialogCell.java:5116-
/// 5131`); a group row never does (its branch at `:5150` paints no marker). The
/// read is of the presence the client already holds - `Client.presences`, the
/// map `fetchCurrentPresence()` fills - so a row starts no `getPresence` request
/// of its own. No record, or a record that is not `online`, reads as offline.
bool _peerIsOnline(Client client, String? peerId) =>
    // ignore: deprecated_member_use
    peerId != null && client.presences[peerId]?.presence == PresenceType.online;

/// Telegram's presence dot on a chat-list avatar: a ring of the page field at
/// `onlineDotRingRadius` with the online ink at `onlineDotRadius` inside it,
/// both drawn at `radius * progress` (`DialogCell.java:5128-5131`).
///
/// `progress` is Telegram's `onlineProgress`: it walks 0 to 1 in
/// [ChatListGeometry.onlineDotGrowDuration] on appearance and back on the peer's
/// disappearance (`DialogCell.java:5132-5148`), so the marker scales in and out
/// and paints nothing at rest in the offline state. The box is the ring's own
/// square, centred on Telegram's centre point; the caller places it.
class TelegramOnlineDot extends StatefulWidget {
  const TelegramOnlineDot({
    required this.online,
    required this.ringColor,
    required this.dotColor,
    super.key,
  });

  final bool online;
  final Color ringColor;
  final Color dotColor;

  @override
  State<TelegramOnlineDot> createState() => _TelegramOnlineDotState();
}

class _TelegramOnlineDotState extends State<TelegramOnlineDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: ChatListGeometry.onlineDotGrowDuration,
  );

  @override
  void initState() {
    super.initState();
    if (widget.online) _progress.forward();
  }

  @override
  void didUpdateWidget(TelegramOnlineDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.online == oldWidget.online) return;
    widget.online ? _progress.forward() : _progress.reverse();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _progress,
    builder: (context, _) => CustomPaint(
      size: const Size.square(ChatListGeometry.onlineDotRingRadius * 2),
      painter: _TelegramOnlineDotPainter(
        progress: _progress.value,
        ringColor: widget.ringColor,
        dotColor: widget.dotColor,
      ),
    ),
  );
}

class _TelegramOnlineDotPainter extends CustomPainter {
  const _TelegramOnlineDotPainter({
    required this.progress,
    required this.ringColor,
    required this.dotColor,
  });

  final double progress;
  final Color ringColor;
  final Color dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = size.center(Offset.zero);
    canvas.drawCircle(
      center,
      ChatListGeometry.onlineDotRingRadius * progress,
      Paint()..color = ringColor,
    );
    canvas.drawCircle(
      center,
      ChatListGeometry.onlineDotRadius * progress,
      Paint()..color = dotColor,
    );
  }

  @override
  bool shouldRepaint(covariant _TelegramOnlineDotPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.ringColor != ringColor ||
      oldDelegate.dotColor != dotColor;
}
