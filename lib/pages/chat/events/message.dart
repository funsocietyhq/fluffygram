// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/telegram_palette.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/member_actions_popup_menu_button.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../../config/app_config.dart';
import '../sticker_picker_dialog.dart';
import '../telegram_motion.dart';
import 'album_grid.dart';
import 'bubble_shape.dart';
import 'message_content.dart';
import 'message_reactions.dart';
import 'message_status_tick.dart';
import 'reply_content.dart';
import 'state_message.dart';
import 'swipe_to_reply.dart';
import 'unread_divider.dart';

class Message extends StatelessWidget {
  final Event event;
  final Event? nextEvent;
  final Event? previousEvent;
  final bool displayReadMarker;
  final void Function(Event) onSelect;

  /// T40.1: opens Telegram's context menu for this row, anchored on the given
  /// global position - Telegram's `ChatMessageCell.java:557` `didLongPress`
  /// hands the row AND the touch point to the screen, which opens the menu.
  /// Null where a caller builds no menu (the thread view, the tests): there
  /// the long press keeps selecting the row.
  final void Function(Event event, Offset position)? onContextPress;
  final void Function(Event) onInfoTab;
  final void Function(String) scrollToEventId;
  final void Function() onSwipe;
  final void Function() onMention;
  final void Function() onEdit;
  final void Function(String eventId)? enterThread;
  final bool longPressSelect;
  final bool selected;
  final bool singleSelected;
  final Timeline timeline;
  final bool highlightMarker;

  /// T70: the jump counter behind `highlightMarker`. It keys the highlight
  /// animation so a re-jump to the same event replays the fade.
  final int highlightMarkerToken;
  final bool animateIn;
  final bool wallpaperMode;
  final ScrollController scrollController;
  final List<Color> colors;
  final void Function()? onExpand;
  final bool isCollapsed;
  final Set<String> bigEmojis;

  /// The media run this event anchors, when the timeline grouped it into an
  /// album (see `album_grid.dart`). Null when the event draws alone.
  final List<Event>? albumRun;

  const Message(
    this.event, {
    this.nextEvent,
    this.previousEvent,
    this.displayReadMarker = false,
    this.longPressSelect = false,
    required this.bigEmojis,
    required this.onSelect,
    this.onContextPress,
    required this.onInfoTab,
    required this.scrollToEventId,
    required this.onSwipe,
    this.selected = false,
    required this.onEdit,
    required this.singleSelected,
    required this.timeline,
    this.highlightMarker = false,
    this.highlightMarkerToken = 0,
    this.animateIn = false,
    this.wallpaperMode = false,
    required this.onMention,
    required this.scrollController,
    required this.colors,
    this.onExpand,
    required this.enterThread,
    this.isCollapsed = false,
    this.albumRun,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!{
      EventTypes.Message,
      EventTypes.Sticker,
      EventTypes.CallInvite,
      PollEventContent.startType,
    }.contains(event.type)) {
      if (event.type.startsWith('m.call.')) {
        return const SizedBox.shrink();
      }
      return StateMessage(event, onExpand: onExpand, isCollapsed: isCollapsed);
    }

    if (event.type == EventTypes.Message &&
        event.messageType == EventTypes.KeyVerificationRequest) {
      return StateMessage(event);
    }

    final client = Matrix.of(context).client;
    final ownMessage = event.senderId == client.userID;
    final alignment = ownMessage ? Alignment.topRight : Alignment.topLeft;

    var color = theme.bubbleColorIncoming;
    // T71 (2026-10-28): the time used to print only when this row started a
    // run (`!previousEventSameSender`) or crossed an environment
    // (`sameEnvironment`). Owner: "every message should have timestamp, even
    // if i send multiple in a row" - a user's captures show a time in
    // every bubble (the reference capture, every row reads
    // 11:23 AM). Every sent row now carries its time; the grouping rules
    // that use `previousEventSameSender` (gap, tail, sender name) are
    // untouched.

    final nextEventSameSender =
        nextEvent != null &&
        {EventTypes.Message, EventTypes.Sticker}.contains(nextEvent!.type) &&
        nextEvent!.senderId == event.senderId &&
        nextEvent!.originServerTs.sameEnvironment(event.originServerTs);

    final previousEventSameSender =
        previousEvent != null &&
        {
          EventTypes.Message,
          EventTypes.Sticker,
        }.contains(previousEvent!.type) &&
        previousEvent!.senderId == event.senderId &&
        previousEvent!.originServerTs.sameEnvironment(event.originServerTs);

    final textColor = ownMessage
        ? theme.onBubbleColor
        : theme.colorScheme.onSurface;

    // Telegram paints a sender name with that sender's OWN palette colour -
    // the `avatar_nameInMessage*` keys of Telegram's own ThemeColors.java. The
    // a user's capture measures a gold #E8AB5A name inside a gold-named
    // sender's bubble; `stringToColor` already returns exactly that palette
    // entry for a user id. The old value was Material's seeded derivative of
    // the same colour (`name.colorScheme.primary`), which is why build 6's
    // names read muddy (#BD883A) next to Telegram's #E8AB5A.
    // Telegram's "Colored sender names" switch: off draws the name in the
    // secondary ink instead.
    // Keyed on the sender ID (finding 22): the reply quote bar and the quoted
    // name already hash the sender id, and Telegram keys its per-sender colour
    // on the account, not on a display name. Keying this label on the display
    // name printed one person in two colours on one screen.
    Color senderNameColor(String key) => AppSettings.colorSenderNames.value
        ? stringToColor(key)
        : TelegramPalette.textSecondary;

    final linkColor = ownMessage
        ? theme.brightness == Brightness.light
              ? theme.colorScheme.primaryFixed
              : theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.primary;

    final rowMainAxisAlignment = ownMessage
        ? MainAxisAlignment.end
        : MainAxisAlignment.start;

    final displayEvent = event.getDisplayEvent(timeline);
    // Telegram: 16dp on every corner, the tail-side bottom corner tight at 4dp.
    final tailOnLeft = !ownMessage;
    final borderRadius = TelegramBubbleShape.borderRadius(
      tailOnLeft: tailOnLeft,
    );
    const avatarSize = TelegramBubbleGeometry.avatarSize;
    final noBubble =
        ({
          MessageTypes.Video,
          MessageTypes.Image,
          MessageTypes.Sticker,
        }.contains(event.messageType) &&
        event.fileDescription == null &&
        !event.redacted);

    // T22 stage 1 (the measurement log "Media messages live inside a bubble
    // container"): Telegram draws an image or video row INSIDE a bubble
    // container - `a measurement crop` shows one rounded container
    // holding the sender name at its top-left and the media edge to edge under
    // it, while `a measurement crop` shows our tiles floating on
    // the black page. The row already builds the box (`ShapeDecoration` with
    // `TelegramBubbleShape` below) and the name line already sits in the
    // bubble's own column (`showSenderName`); only the fill was switched off
    // for media. So an image or video row fills its container with the bubble
    // colour now, edge to edge, with no inner padding (Telegram rule 2 of the
    // album-grid capture) and with the tile geometry, mosaic columns, gaps and
    // clustering in `album_grid.dart` untouched. Sticker rows keep Telegram's
    // box-less surface: Telegram floats a sticker without a bubble.
    final mediaContainer =
        noBubble && event.messageType != MessageTypes.Sticker;

    // Telegram draws the tail on the last (newest) message of a run by one
    // sender: `previousEvent` is the newer neighbour in the reversed timeline.
    final showTail = !noBubble && !previousEventSameSender;
    final tailInset = showTail ? TelegramBubbleGeometry.tailWidth : 0.0;

    // T22 stage 2 (the measurement log "Media messages live inside a bubble
    // container"): an album run draws its OWN container, and Telegram's rule is
    // about the container - its first line is the sender name
    // (`a measurement crop`). The row that anchors a run builds
    // that container even when its older neighbour is another photo of the same
    // sender, which is what happens to the overflow album of a burst longer than
    // `TelegramAlbumGeometry.maxRunLength`: the HEAD drive render
    // `shots/demo/demo-04-older-3.png` shows bob's 2-tile overflow container
    // with no name line, while his 10-tile container above it keeps one. So an
    // album anchor prints the name too, through the same `showSenderName` block
    // below - still no second name renderer.
    final anchoredRun = albumRun;
    final anchorsAlbumContainer =
        anchoredRun != null &&
        anchoredRun.length >= TelegramAlbumGeometry.minRunLength &&
        anchoredRun.first.eventId == event.eventId;

    // Telegram prints the group sender's name INSIDE the bubble at its top-left
    // and only on the first (oldest) message of a run by one sender: in this
    // reversed timeline `nextEvent` is the older neighbour, so
    // `!nextEventSameSender` is the start of the run. A direct chat prints no
    // name and neither does a message you sent yourself. An album anchor is a
    // run start of its own: it opens a new container.
    final showSenderName =
        (!nextEventSameSender || anchorsAlbumContainer) &&
        !ownMessage &&
        !event.room.isDirectChat;

    if (ownMessage) {
      color = displayEvent.status.isError
          ? Colors.redAccent
          : theme.bubbleColor;
    }

    final sentReactions = <String>{};
    if (singleSelected) {
      sentReactions.addAll(
        event
            .aggregatedEvents(timeline, RelationshipTypes.reaction)
            .where(
              (event) =>
                  event.senderId == event.room.client.userID &&
                  event.type == 'm.reaction',
            )
            .map(
              (event) => event.content
                  .tryGetMap<String, Object?>('m.relates_to')
                  ?.tryGet<String>('key'),
            )
            .whereType<String>(),
      );
    }

    final hasReactions = event.hasAggregatedEvents(
      timeline,
      RelationshipTypes.reaction,
    );

    final threadChildren = event.aggregatedEvents(
      timeline,
      RelationshipTypes.thread,
    );
    final isEdited = event.hasAggregatedEvents(
      timeline,
      RelationshipTypes.edit,
    );

    final showReactionPicker =
        singleSelected && event.room.canSendDefaultMessages;

    final enterThread = this.enterThread;
    final sender = event.senderFromMemoryOrFallback;

    final wallpaperTextShadow = !wallpaperMode
        ? null
        : [
            Shadow(
              offset: Offset(0.0, 0.0),
              blurRadius: 2,
              color: theme.colorScheme.surface,
            ),
          ];
    final eventStateTextColor = theme.colorScheme.onSurface;

    // Telegram draws the timestamp and the tick glyphs INSIDE the bubble, at
    // the end of its last text line. A bubble without a bubble background
    // (image, sticker, video) has no text line to sit on, so it keeps the
    // meta line below the media.
    // Only a text bubble can carry the meta inline: `MessageContent` hands it
    // to `HtmlMessage`. Media, voice, polls and files have their own content
    // widget and keep the meta line below the bubble.
    final metaInline =
        !noBubble &&
        !event.redacted &&
        {
          MessageTypes.Text,
          MessageTypes.Notice,
          MessageTypes.Emote,
          MessageTypes.None,
        }.contains(event.messageType);
    final bubbleMeta = !metaInline
        ? null
        : _BubbleMeta(
            event: event,
            ownMessage: ownMessage,
            showTime: event.status.isSent,
            detailedTime: selected,
            isEdited: isEdited,
            ink: ownMessage
                ? theme.timestampOnOutgoingBubble
                : theme.timestampOnIncomingBubble,
            shadows: wallpaperTextShadow,
          );
    // The box the in-bubble meta takes at the end of the message text. The
    // text span reserves it, so the last line wraps around the meta and the
    // meta can sit in the bubble's bottom-right corner - the placement the
    // a user's captures show (`11:13 AM` on its own line, flush right, under a
    // long incoming text). Without the reserve the meta is an inline span and
    // a time that does not fit on the last line lands in the bottom-LEFT
    // corner, which is what the first device render printed.
    final bubbleMetaReserve = bubbleMeta?.reserveSize(
      context,
      DefaultTextStyle.of(context).style,
    );

    // T11 finding 8: the meta row of a row that keeps its time BELOW the
    // bubble - media, voice, file, poll, sticker. It is a child of the bubble's
    // own column (see the `Column` under `alignment`), which is exactly as wide
    // as the bubble, so the time ends at the bubble's TRAILING edge - the rule
    // a user's capture measures (`10:05 (ticks)` under the voice bubbles in
    // a measurement crop, right aligned) and the rule the first
    // render broke (`5:35 AM` at the left of mallory's photo, demo-03).
    // A text bubble carries its time inside (finding 3's `bubbleMeta`), so this
    // row is empty for it and prints only a sending / failed status.
    // T30 (ROADMAP T11 finding 18): a user's capture sits the group avatar's
    // bottom edge on the bubble box bottom (disc y 715..822 px against the box
    // bottom y ~820 px at 2.625 px/dp). The row below carries the avatar as a
    // cross-axis-end child, so the avatar's bottom is the ROW's bottom: the
    // time line under a media row would push it below the bubble. This fixed
    // height box makes the space under the bubble a known constant, and the
    // avatar takes the same inset - one constant ties the two, so the two
    // bottom edges are flush by construction. 14 dp is the height of the 12sp
    // meta line (`timestampMetaBoxHeight`).
    const mediaMetaBoxHeight = TelegramBubbleGeometry.timestampMetaBoxHeight;
    final avatarBottomInset = bubbleMeta == null ? mediaMetaBoxHeight : 0.0;
    final belowBubbleMeta = Row(
      mainAxisSize: .min,
      children: [
        const SizedBox(width: 8),
        // Bubbled messages carry the time and the
        // edited label inline (see `bubbleMeta`).
        if (bubbleMeta == null && event.status.isSent)
          Text(
            ' ${selected ? event.originServerTs.localizedDetailedTime(context) : event.originServerTs.localizedTimeOfDay(context)}',
            style: TextStyle(
              color: ownMessage
                  ? theme.timestampOnOutgoingBubble
                  : theme.timestampOnIncomingBubble,
              fontSize: TelegramBubbleGeometry.timestampFontSize,
              shadows: wallpaperTextShadow,
            ),
          ),
        if (bubbleMeta == null && isEdited) ...[
          Text(
            ' ',
            style: TextStyle(
              fontSize: TelegramBubbleGeometry.timestampFontSize,
            ),
          ),
          Text(
            L10n.of(context).edited,
            style: TextStyle(
              color: theme.timestampOnIncomingBubble,
              fontSize: TelegramBubbleGeometry.timestampFontSize,
              shadows: wallpaperTextShadow,
            ),
          ),
        ],
        if (event.status == EventStatus.error) ...[
          Text(' ', style: TextStyle(fontSize: 11)),
          Text(
            L10n.of(context).couldNotBeSent,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.error,
              shadows: wallpaperTextShadow,
            ),
          ),
          Text(' ', style: TextStyle(fontSize: 11)),
          Icon(
            Icons.error_outlined,
            size: 14,
            color: theme.colorScheme.error,
            shadows: wallpaperTextShadow,
          ),
        ],
        if (event.status == EventStatus.sending) ...[
          Text(
            switch (event.fileSendingStatus) {
              null => L10n.of(context).sending,
              FileSendingStatus.generatingThumbnail => L10n.of(
                context,
              ).generatingThumbnail,
              FileSendingStatus.encrypting => L10n.of(context).encrypting,
              FileSendingStatus.uploading => L10n.of(context).uploading,
            },
            style: TextStyle(
              color: eventStateTextColor,
              fontSize: 11,
              shadows: wallpaperTextShadow,
            ),
          ),
          Text(' ', style: TextStyle(fontSize: 11)),
          SizedBox.square(
            dimension: 11,
            child: CircularProgressIndicator(strokeWidth: 1),
          ),
        ],
      ],
    );
    return Center(
      child: SwipeToReply(
        key: ValueKey(event.transactionId ?? event.eventId),
        rightToLeft: AppSettings.swipeRightToLeftToReply.value,
        onReply: onSwipe,
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: FluffyThemes.maxTimelineWidth,
          ),
          // Same-sender gap 2dp; sender-change gap 8.5dp, which is the
          // measured 8.0 dp of black between the two bubbles
          // (`TelegramBubbleGeometry.senderGapPerSide`). One message carries
          // half of each gap top and bottom, the neighbour the other half.
          padding: EdgeInsets.only(
            left: 8.0,
            right: 8.0,
            top: nextEventSameSender
                ? TelegramBubbleGeometry.groupGapPerSide
                : TelegramBubbleGeometry.senderGapPerSide,
            bottom: previousEventSameSender || previousEvent == null
                ? TelegramBubbleGeometry.groupGapPerSide
                : TelegramBubbleGeometry.senderGapPerSide,
          ),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: ownMessage ? .end : .start,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: GestureDetector(
                      // No ink splash on a bubble (target behaviour: "no
                      // ripple on bubbles"). The selection tint is the
                      // Material below, not an ink spread.
                      //
                      // T57: outside selection mode a tap in the row's empty
                      // area opens the row's context menu, the same action the
                      // long press takes. Owner instruction 2026-10-27: "Tapping
                      // outside of a message bubble should bring up the menu
                      // (same as long tap), not automatically select it." It did
                      // select: this layer called `onSelect`. `onTapUp` is the
                      // tap callback that carries a position - `onTap` carries
                      // none - and the menu opens at the touch point, as the
                      // `onLongPressStart` below does. Inside selection mode this
                      // layer stays inert and the checkbox column keeps the
                      // select action.
                      onTapUp: longPressSelect
                          ? null
                          : (details) {
                              final onContextPress = this.onContextPress;
                              if (onContextPress == null) {
                                onSelect(event);
                              } else {
                                onContextPress(event, details.globalPosition);
                              }
                            },
                      child: highlightMarker && !selected
                          ? // T70 (2026-10-28): the row the timeline just
                            // jumped to lights up and fades, Telegram's
                            // presentation. `getHighlightAlpha`
                            // (`ChatMessageCell.java:23119`) holds full alpha
                            // while `highlightProgress` - set to 1000 by
                            // `setHighlightedAnimated` (line 12543) - counts
                            // down above 300, then returns progress / 300:
                            // 700 ms full, 300 ms linear fade. The token key
                            // restarts the cycle on a re-jump to the same
                            // event; chat.dart retires the marker at the end
                            // of the cycle. Before this the tint was
                            // permanent: nothing ever cleared the marker.
                            TweenAnimationBuilder<double>(
                              key: ValueKey(
                                'jump-highlight-$highlightMarkerToken',
                              ),
                              // The curve carries the 700 ms hold: the tween
                              // 1.0 -> 0.0 shaped by it is full alpha while
                              // the curve sits at 0 (t <= 0.7), then runs out
                              // linearly. (`TweenSequence` is not used: it is
                              // `Tween<T?>`, a type the builder rejects.)
                              tween: Tween(begin: 1.0, end: 0.0),
                              curve: const _TelegramHighlightFade(),
                              duration: const Duration(milliseconds: 1000),
                              builder: (context, alpha, _) => Material(
                                borderRadius: BorderRadius.circular(
                                  AppConfig.borderRadius / 2,
                                ),
                                color: theme.colorScheme.secondaryContainer
                                    .withAlpha((128 * alpha).round()),
                              ),
                            )
                          : Material(
                              borderRadius: BorderRadius.circular(
                                AppConfig.borderRadius / 2,
                              ),
                              color: selected
                                  ? theme.colorScheme.secondaryContainer
                                        .withAlpha(128)
                                  : Colors.transparent,
                            ),
                    ),
                  ),
                  // T30: `.end`, not `.start`. Telegram bottoms the group
                  // sender's avatar on the bubble box (see the
                  // `avatarBottomInset` note above); `.start` pinned it to the
                  // top of the row.
                  Row(
                    crossAxisAlignment: .end,
                    mainAxisAlignment: rowMainAxisAlignment,
                    children: [
                      if (longPressSelect && !event.redacted)
                        SizedBox(
                          height: avatarSize,
                          width: avatarSize,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: L10n.of(context).select,
                            icon: Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                            ),
                            onPressed: () => onSelect(event),
                          ),
                        )
                      // Telegram shows the avatar on the last (newest) message
                      // of a run by one sender; the other messages of the run
                      // keep the 42dp column as a spacer.
                      else if (previousEventSameSender || ownMessage)
                        SizedBox(width: avatarSize)
                      else
                        FutureBuilder<User?>(
                          future: event.fetchSenderUser(),
                          builder: (context, snapshot) {
                            final user = snapshot.data ?? sender;
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: avatarBottomInset,
                              ),
                              child: Avatar(
                                mxContent: user.avatarUrl,
                                name: user.calcDisplayname(),
                                onTap: () => showMemberActionsPopupMenu(
                                  context: context,
                                  user: user,
                                  onMention: onMention,
                                ),
                                size: avatarSize,
                                presenceUserId: user.stateKey,
                                presenceBackgroundColor: wallpaperMode
                                    ? Colors.transparent
                                    : null,
                              ),
                            );
                          },
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: .start,
                          mainAxisSize: .min,
                          children: [
                            // T18 U2 (T11 finding 2): Telegram paints NOTHING in
                            // front of a group sender name in the timeline -
                            // `a measurement crop` puts `mallory`,
                            // `bob` and `sue` at the avatar edge with no glyph.
                            // Upstream painted a room-role glyph here
                            // (`Icons.add_moderator_outlined` for a moderator,
                            // `Icons.admin_panel_settings` for an admin), and on
                            // the demo render it reads as a cross-signing shield
                            // sitting above the sender name. The glyph is not
                            // drawn in timeline rows any more; docs/UPSTREAM.md
                            // records what the fork hides and where the user can
                            // still see it. Nothing else moved: this column now
                            // starts at the bubble itself.

                            Container(
                              alignment: alignment,
                              // Incoming: 6dp gap after the 42dp avatar = 56dp
                              // from the screen edge. Outgoing: 3dp after the
                              // 8dp list margin = 11dp. The tail wedge reaches
                              // into that edge margin, so the bubble column
                              // stays aligned across a sender run.
                              padding: EdgeInsets.only(
                                left: TelegramBubbleGeometry
                                    .incomingGapAfterAvatar,
                                right: tailOnLeft
                                    ? 0
                                    : TelegramBubbleGeometry
                                          .outgoingGapAfterEdge,
                              ),
                              // T11 finding 8: the bubble and the meta row that
                              // sits below a media row form ONE column, which is
                              // as wide as the bubble. That is what puts the
                              // media time at the bubble's trailing edge for an
                              // incoming row as well as an outgoing one.
                              child: Column(
                                mainAxisSize: .min,
                                crossAxisAlignment: .end,
                                children: [
                                  GestureDetector(
                                    onDoubleTap:
                                        AppSettings.doubleTapToReact.value &&
                                            event.room.canSendDefaultMessages
                                        ? () {
                                            HapticFeedback.lightImpact();
                                            final emoji = AppSettings
                                                .doubleTapReaction
                                                .value;
                                            final existingReaction = event
                                                .aggregatedEvents(
                                                  timeline,
                                                  RelationshipTypes.reaction,
                                                )
                                                .firstWhereOrNull(
                                                  (e) =>
                                                      e.senderId ==
                                                          event
                                                              .room
                                                              .client
                                                              .userID &&
                                                      e.content
                                                              .tryGetMap<
                                                                String,
                                                                Object?
                                                              >('m.relates_to')
                                                              ?.tryGet<String>(
                                                                'key',
                                                              ) ==
                                                          emoji,
                                                );
                                            if (existingReaction != null) {
                                              existingReaction.redactEvent();
                                            } else {
                                              event.room.sendReaction(
                                                event.eventId,
                                                emoji,
                                              );
                                            }
                                          }
                                        : null,
                                    // T69 (2026-10-28): a tap ON THE BUBBLE
                                    // opens the row's context menu at the
                                    // touch point. Telegram 13.1.1 fires
                                    // `createMenu` from the cell's own click
                                    // (`ChatActivity.java:1870`), which is why
                                    // on a user's phone a tap on ANY part of
                                    // a message - the pinned rows they raised
                                    // are plain timeline rows - answers. T57
                                    // wired this for the row's empty area only:
                                    // a layer behind the bubble. The bubble had
                                    // no tap handler, so a tap on the text fell
                                    // through. Children keep priority in the
                                    // arena: links open, media opens the
                                    // viewer, the quote panel jumps.
                                    onTapUp: longPressSelect
                                        ? null
                                        : (details) {
                                            final onContextPress =
                                                this.onContextPress;
                                            if (onContextPress == null) {
                                              onSelect(event);
                                            } else {
                                              onContextPress(
                                                event,
                                                details.globalPosition,
                                              );
                                            }
                                          },
                                    // T40.1: a long press opens the row's
                                    // context menu at the touch point, as
                                    // Telegram's `didLongPress` does
                                    // (ChatMessageCell.java:557). Selection
                                    // mode is entered from the menu's "Select"
                                    // item, never by the press itself; inside
                                    // selection mode the press keeps adding to
                                    // the selection. `onLongPressStart` is the
                                    // Flutter callback that carries a position
                                    // - `onLongPress` carries none.
                                    onLongPressStart: longPressSelect
                                        ? null
                                        : (details) {
                                            HapticFeedback.heavyImpact();
                                            final onContextPress =
                                                this.onContextPress;
                                            if (onContextPress == null) {
                                              onSelect(event);
                                            } else {
                                              onContextPress(
                                                event,
                                                details.globalPosition,
                                              );
                                            }
                                          },
                                    child: _AnimateIn(
                                      key: ValueKey(
                                        event.transactionId ?? event.eventId,
                                      ),
                                      animateIn: animateIn,
                                      child: Container(
                                        decoration: ShapeDecoration(
                                          color: mediaContainer || !noBubble
                                              ? color
                                              : Colors.transparent,
                                          shape: TelegramBubbleShape(
                                            tail: showTail,
                                            tailOnLeft: tailOnLeft,
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: BubbleBackground(
                                          colors: colors,
                                          ignore:
                                              noBubble ||
                                              !ownMessage ||
                                              MediaQuery.highContrastOf(
                                                context,
                                              ),
                                          scrollController: scrollController,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppConfig.borderRadius,
                                                  ),
                                            ),
                                            constraints: BoxConstraints(
                                              // Cap: the user's bubble width
                                              // setting (280dp default), clamped to
                                              // the window, incl. the tail.
                                              maxWidth:
                                                  TelegramBubbleGeometry.maxBubbleWidthForWindow(
                                                    MediaQuery.sizeOf(
                                                      context,
                                                    ).width,
                                                    // Telegram's column formula
                                                    // charges the incoming row
                                                    // dp(52) for its avatar
                                                    // (MessageObject.java:8531).
                                                    outgoing: ownMessage,
                                                  ) -
                                                  tailInset,
                                            ),
                                            child: Column(
                                              mainAxisSize: .min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: <Widget>[
                                                // T14b finding 15: Telegram's group
                                                // sender name sits inside the
                                                // bubble at its top-left, in the
                                                // sender's own palette colour,
                                                // above the reply quote panel.
                                                // Measured on the reference capture of 
                                                // the reference capture (2.75 px/dp): the gold
                                                // name starts at x=187 and the body
                                                // text under it at x=188, i.e. the
                                                // name shares the body's 12dp left
                                                // padding; the name's top sits 53 px
                                                // (19 dp) above the body line's top
                                                // against a 49 px (17.8 dp) body
                                                // pitch, so Telegram adds about 1.5
                                                // dp of leading under the name.
                                                if (showSenderName)
                                                  FutureBuilder<User?>(
                                                    future: event
                                                        .fetchSenderUser(),
                                                    builder: (context, snapshot) {
                                                      final displayname =
                                                          snapshot.data
                                                              ?.calcDisplayname() ??
                                                          sender
                                                              .calcDisplayname();
                                                      // T34 finding 14: the
                                                      // name is the first
                                                      // line INSIDE the fill.
                                                      // Its box top sits
                                                      // `senderNameTopInset`
                                                      // (4.6 dp) below the
                                                      // fill's top edge -
                                                      // Telegram's name
                                                      // inks 6.9 dp inside
                                                      // the fill, and its
                                                      // own code puts the
                                                      // box at dp(10) from
                                                      // the bubble top
                                                      // (ChatMessageCell.java
                                                      // :21330) with the
                                                      // content at dp(12) +
                                                      // name height + dp(1)
                                                      // (:20321). A media
                                                      // container keeps
                                                      // paddingV: its own
                                                      // measured pairs are the
                                                      // album container rows.
                                                      return Padding(
                                                        padding: EdgeInsets.only(
                                                          left:
                                                              TelegramBubbleGeometry
                                                                  .paddingH,
                                                          right:
                                                              TelegramBubbleGeometry
                                                                  .paddingH,
                                                          top: mediaContainer
                                                              ? TelegramBubbleGeometry
                                                                    .paddingV
                                                              : TelegramBubbleGeometry
                                                                    .senderNameTopInset,
                                                          bottom: TelegramBubbleGeometry
                                                              .senderNameGapBelow,
                                                        ),
                                                        child: Text(
                                                          displayname,
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color:
                                                                senderNameColor(
                                                                  event
                                                                      .senderId,
                                                                ),
                                                            fontSize:
                                                                TelegramBubbleGeometry
                                                                    .senderNameFontSize,
                                                            shadows:
                                                                wallpaperTextShadow,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                if (event.inReplyToEventId(
                                                      includingFallback: false,
                                                    ) !=
                                                    null)
                                                  FutureBuilder<Event?>(
                                                    future: event.getReplyEvent(
                                                      timeline,
                                                    ),
                                                    builder:
                                                        (
                                                          BuildContext context,
                                                          snapshot,
                                                        ) {
                                                          final replyEvent =
                                                              snapshot.hasData
                                                              ? snapshot.data!
                                                              : Event(
                                                                  eventId:
                                                                      event
                                                                          .inReplyToEventId() ??
                                                                      '\$fake_event_id',
                                                                  content: {
                                                                    'msgtype':
                                                                        'm.text',
                                                                    'body':
                                                                        '...',
                                                                  },
                                                                  senderId: event
                                                                      .senderId,
                                                                  type:
                                                                      'm.room.message',
                                                                  room: event
                                                                      .room,
                                                                  status:
                                                                      EventStatus
                                                                          .sent,
                                                                  originServerTs:
                                                                      DateTime.now(),
                                                                );
                                                          return Padding(
                                                            padding: const EdgeInsets.only(
                                                              top: 8,
                                                              left: TelegramBubbleGeometry
                                                                  .quoteInsetLeft,
                                                              right: TelegramBubbleGeometry
                                                                  .quoteInsetRight,
                                                            ),
                                                            child: Material(
                                                              color: Colors
                                                                  .transparent,
                                                              borderRadius:
                                                                  ReplyContent
                                                                      .borderRadius,
                                                              child: GestureDetector(
                                                                // Tap jumps to the
                                                                // quoted message; no
                                                                // ink on the bubble.
                                                                onTap: () =>
                                                                    scrollToEventId(
                                                                      replyEvent
                                                                          .eventId,
                                                                    ),
                                                                child: AbsorbPointer(
                                                                  child: ReplyContent(
                                                                    replyEvent,
                                                                    ownMessage:
                                                                        ownMessage,
                                                                    timeline:
                                                                        timeline,
                                                                    // The quote tints its panel with the quoted
                                                                    // sender over the fill of THIS bubble,
                                                                    // so an outgoing quote on the accent-derived
                                                                    // fill and an incoming quote on
                                                                    // `bubbleColorIncoming` each get their own
                                                                    // measured panel.
                                                                    bubbleFill:
                                                                        color,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                  ),
                                                MessageContent(
                                                  displayEvent,
                                                  textColor: textColor,
                                                  linkColor: linkColor,
                                                  albumRun: albumRun,
                                                  onAlbumTileLongPress:
                                                      onSelect,
                                                  onInfoTab: onInfoTab,
                                                  borderRadius: borderRadius,
                                                  timeline: timeline,
                                                  selected: selected,
                                                  bigEmojis: bigEmojis,
                                                  inlineMeta: bubbleMeta,
                                                  inlineMetaReserve:
                                                      bubbleMetaReserve,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // T30: fixed height, so the avatar's
                                  // `avatarBottomInset` lands its bottom on the
                                  // bubble box bottom above the meta line.
                                  if (bubbleMeta == null)
                                    SizedBox(
                                      height: mediaMetaBoxHeight,
                                      child: belowBubbleMeta,
                                    )
                                  else
                                    belowBubbleMeta,
                                ],
                              ),
                            ),

                            AnimatedSize(
                              duration: TelegramMotion.animationDuration,
                              curve: FluffyThemes.animationCurve,
                              alignment: Alignment.bottomCenter,
                              child: !hasReactions
                                  ? const SizedBox.shrink()
                                  : Container(
                                      alignment: ownMessage
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      padding: EdgeInsets.only(
                                        top: 1.0,
                                        left: 8.0,
                                        right: ownMessage ? 0 : 12.0,
                                      ),
                                      child: MessageReactions(event, timeline),
                                    ),
                            ),
                            Align(
                              alignment: ownMessage
                                  ? Alignment.bottomRight
                                  : Alignment.bottomLeft,
                              child: AnimatedSize(
                                duration: TelegramMotion.animationDuration,
                                curve: FluffyThemes.animationCurve,
                                child: showReactionPicker
                                    ? Padding(
                                        padding: const EdgeInsets.all(4.0),
                                        child: Material(
                                          elevation: 4,
                                          borderRadius: BorderRadius.circular(
                                            AppConfig.borderRadius,
                                          ),
                                          shadowColor: theme.colorScheme.surface
                                              .withAlpha(128),
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              mainAxisSize: .min,
                                              children: [
                                                ...AppConfig.defaultReactions.map(
                                                  (emoji) => IconButton(
                                                    padding: EdgeInsets.zero,
                                                    icon: Center(
                                                      child: Opacity(
                                                        opacity:
                                                            sentReactions
                                                                .contains(emoji)
                                                            ? 0.33
                                                            : 1,
                                                        child: Text(
                                                          emoji,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 20,
                                                              ),
                                                          textAlign:
                                                              TextAlign.center,
                                                        ),
                                                      ),
                                                    ),
                                                    onPressed:
                                                        sentReactions.contains(
                                                          emoji,
                                                        )
                                                        ? null
                                                        : () {
                                                            onSelect(event);
                                                            event.room
                                                                .sendReaction(
                                                                  event.eventId,
                                                                  emoji,
                                                                );
                                                          },
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.add_reaction_outlined,
                                                  ),
                                                  tooltip: L10n.of(
                                                    context,
                                                  ).customReaction,
                                                  onPressed: () async {
                                                    final emoji = await showAdaptiveBottomSheet<String>(
                                                      context: context,
                                                      builder: (context) => Scaffold(
                                                        appBar: AppBar(
                                                          title: Text(
                                                            L10n.of(
                                                              context,
                                                            ).customReaction,
                                                          ),
                                                          leading: CloseButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                  context,
                                                                ).pop(null),
                                                          ),
                                                        ),
                                                        body: SizedBox(
                                                          height:
                                                              double.infinity,
                                                          child: DefaultTabController(
                                                            length: 2,
                                                            child: Column(
                                                              children: [
                                                                TabBar(
                                                                  tabs: [
                                                                    Tab(
                                                                      text: L10n.of(
                                                                        context,
                                                                      ).emojis,
                                                                    ),
                                                                    Tab(
                                                                      text: L10n.of(
                                                                        context,
                                                                      ).stickers,
                                                                    ),
                                                                  ],
                                                                ),
                                                                Expanded(
                                                                  child: TabBarView(
                                                                    children: [
                                                                      EmojiPicker(
                                                                        onEmojiSelected:
                                                                            (
                                                                              _,
                                                                              emoji,
                                                                            ) =>
                                                                                Navigator.of(
                                                                                  context,
                                                                                ).pop(
                                                                                  emoji.emoji,
                                                                                ),
                                                                        config: Config(
                                                                          locale: Localizations.localeOf(
                                                                            context,
                                                                          ),
                                                                          emojiViewConfig: const EmojiViewConfig(
                                                                            backgroundColor:
                                                                                Colors.transparent,
                                                                          ),
                                                                          bottomActionBarConfig: const BottomActionBarConfig(
                                                                            enabled:
                                                                                false,
                                                                          ),
                                                                          categoryViewConfig: CategoryViewConfig(
                                                                            initCategory:
                                                                                Category.SMILEYS,
                                                                            backspaceColor:
                                                                                theme.colorScheme.primary,
                                                                            iconColor: theme.colorScheme.primary.withAlpha(
                                                                              128,
                                                                            ),
                                                                            iconColorSelected:
                                                                                theme.colorScheme.primary,
                                                                            indicatorColor:
                                                                                theme.colorScheme.primary,
                                                                            backgroundColor:
                                                                                theme.colorScheme.surface,
                                                                          ),
                                                                          skinToneConfig: SkinToneConfig(
                                                                            dialogBackgroundColor: Color.lerp(
                                                                              theme.colorScheme.surface,
                                                                              theme.colorScheme.primaryContainer,
                                                                              0.75,
                                                                            )!,
                                                                            indicatorColor:
                                                                                theme.colorScheme.onSurface,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      StickerPickerDialog(
                                                                        room: event
                                                                            .room,
                                                                        usage: ImagePackUsage
                                                                            .emoticon,
                                                                        onSelected:
                                                                            (
                                                                              sticker,
                                                                            ) =>
                                                                                Navigator.of(
                                                                                  context,
                                                                                ).pop(
                                                                                  sticker.url.toString(),
                                                                                ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                    if (emoji == null) {
                                                      return;
                                                    }
                                                    if (sentReactions.contains(
                                                      emoji,
                                                    )) {
                                                      return;
                                                    }
                                                    onSelect(event);

                                                    await event.room
                                                        .sendReaction(
                                                          event.eventId,
                                                          emoji,
                                                        );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (enterThread != null)
                AnimatedSize(
                  duration: TelegramMotion.animationDuration,
                  curve: FluffyThemes.animationCurve,
                  alignment: Alignment.bottomCenter,
                  child: threadChildren.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(
                            top: 2.0,
                            bottom: 8.0,
                            left: avatarSize + 8,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: FluffyThemes.columnWidth * 1.5,
                            ),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                foregroundColor:
                                    theme.colorScheme.onSecondaryContainer,
                                backgroundColor:
                                    theme.colorScheme.secondaryContainer,
                              ),
                              onPressed: () => enterThread(event.eventId),
                              icon: const Icon(Icons.message),
                              label: Text(
                                '${L10n.of(context).countReplies(threadChildren.length)} | ${threadChildren.first.calcLocalizedBodyFallback(MatrixLocals(L10n.of(context)), withSenderNamePrefix: true)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                ),
              // T47: Telegram's "Unread Messages" row at the first unread
              // message of the session - 40 dp, 27 dp filled band, arrow at its
              // right end, bold 14 label (`ChatUnreadCell.java:37-52, 73`).
              // Upstream drew two hairlines around a 11 px `readUpToHere` pill.
              if (displayReadMarker) const TelegramUnreadDivider(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The meta line Telegram draws inside the bubble, at the end of the last
/// text line: `[time] [edited] [ticks]`, 12sp, in the timestamp tint.
/// T70 (2026-10-28): Telegram's jump-highlight time shape. `getHighlightAlpha`
/// (`ChatMessageCell.java:23119`) is 1.0 while `highlightProgress` - set to
/// 1000 by `setHighlightedAnimated` (line 12543) and decremented by frame
/// time (line 20216) - stays at or above 300, then falls off as
/// progress / 300. Over a 1000 ms tween that is this curve: nothing for the
/// first 700 ms of the tween (the tween value stays at its start, full
/// alpha), then a linear run to the end (alpha zero) in the last 300 ms.
class _TelegramHighlightFade extends Curve {
  const _TelegramHighlightFade();

  @override
  double transform(double t) => t <= 0.7 ? 0.0 : (t - 0.7) / 0.3;
}

class _BubbleMeta extends StatelessWidget {
  const _BubbleMeta({
    required this.event,
    required this.ownMessage,
    required this.showTime,
    required this.detailedTime,
    required this.isEdited,
    required this.ink,
    required this.shadows,
  });

  final Event event;
  final bool ownMessage;
  final bool showTime;

  /// Long-press selection shows the full date and time, as before.
  final bool detailedTime;
  final bool isEdited;
  final Color ink;
  final List<Shadow>? shadows;

  /// The time the row prints: the time of day, or the full date on a selected
  /// message. The 12-hour `AM`/`PM` form is what this group's phones show.
  String timeLabel(BuildContext context) => detailedTime
      ? event.originServerTs.localizedDetailedTime(context)
      : event.originServerTs.localizedTimeOfDay(context);

  /// The box this row occupies at the end of the message text: the inline gap,
  /// the time, the `(edited)` label and - on your own bubbles - the tick box.
  /// Measured with a `TextPainter` over the same styles the row draws, and at
  /// the row's own text size (the row opts out of the message text size knob,
  /// so the text scaler stays out of this measurement too).
  Size reserveSize(BuildContext context, TextStyle bodyStyle) {
    final style = bodyStyle.copyWith(
      fontSize: TelegramBubbleGeometry.timestampFontSize,
    );
    final painter = TextPainter(textDirection: TextDirection.ltr);
    // The gutter Telegram's `getTimeExtra()` reserves with the time box, plus
    // the box's own margin to the bubble's inner edge - the last text line
    // ends before both (`ChatMessageCell.java:3396`, phone 47.2 dp).
    var width =
        TelegramBubbleGeometry.timestampInlineGap +
        TelegramBubbleGeometry.timestampReserveGap;
    var height = 0.0;
    void measure(String text) {
      painter.text = TextSpan(text: text, style: style);
      painter.layout();
      width += painter.width;
      if (painter.height > height) height = painter.height;
    }

    if (showTime) measure(timeLabel(context));
    if (isEdited) {
      measure(
        showTime ? ' ${L10n.of(context).edited}' : L10n.of(context).edited,
      );
    }
    if (ownMessage) {
      width += TelegramBubbleGeometry.tickGlyphSize;
      if (TelegramBubbleGeometry.tickGlyphSize > height) {
        height = TelegramBubbleGeometry.tickGlyphSize;
      }
    }
    return Size(
      width,
      height > 0 ? height : TelegramBubbleGeometry.timestampMetaBoxHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    const timestampStyle = TextStyle(
      fontSize: TelegramBubbleGeometry.timestampFontSize,
    );
    return MediaQuery(
      // Telegram's in-bubble timestamp stays 12sp (`timestamp_sp`): the message
      // text size knob (`AppSettings.fontSizeFactor`, applied as a text scaler
      // over the timeline) scales the body, the sender name and the composer -
      // not the time and not the tick glyphs, so this row opts out.
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTime)
            Text(
              timeLabel(context),
              style: timestampStyle.copyWith(color: ink, shadows: shadows),
            ),
          if (isEdited)
            Text(
              showTime
                  ? ' ${L10n.of(context).edited}'
                  : L10n.of(context).edited,
              style: timestampStyle.copyWith(color: ink, shadows: shadows),
            ),
          if (ownMessage) MessageStatusTick(event: event),
        ],
      ),
    );
  }
}

class BubbleBackground extends StatelessWidget {
  const BubbleBackground({
    super.key,
    required this.scrollController,
    required this.colors,
    required this.ignore,
    required this.child,
  });

  final ScrollController scrollController;
  final List<Color> colors;
  final bool ignore;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (ignore) return child;
    return CustomPaint(
      painter: BubblePainter(
        repaint: scrollController,
        colors: colors,
        context: context,
      ),
      child: child,
    );
  }
}

class BubblePainter extends CustomPainter {
  BubblePainter({
    required this.context,
    required this.colors,
    required super.repaint,
  });

  final BuildContext context;
  final List<Color> colors;
  ScrollableState? _scrollable;

  @override
  void paint(Canvas canvas, Size size) {
    final scrollable = _scrollable ??= Scrollable.of(context);
    final scrollableBox = scrollable.context.findRenderObject() as RenderBox;
    final scrollableRect = Offset.zero & scrollableBox.size;
    final bubbleBox = context.findRenderObject() as RenderBox;

    final origin = bubbleBox.localToGlobal(
      Offset.zero,
      ancestor: scrollableBox,
    );
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        scrollableRect.topCenter,
        scrollableRect.bottomCenter,
        colors,
        [0.0, 1.0],
        TileMode.clamp,
        Matrix4.translationValues(-origin.dx, -origin.dy, 0.0).storage,
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(BubblePainter oldDelegate) {
    final scrollable = Scrollable.of(context);
    final oldScrollable = _scrollable;
    _scrollable = scrollable;
    return scrollable.position != oldScrollable?.position;
  }
}

class _AnimateIn extends StatefulWidget {
  final bool animateIn;
  final Widget child;
  const _AnimateIn({required this.animateIn, required this.child, super.key});

  @override
  State<_AnimateIn> createState() => __AnimateInState();
}

class __AnimateInState extends State<_AnimateIn> {
  bool _animationFinished = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.animateIn) return widget.child;
    if (!_animationFinished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _animationFinished = true;
        });
      });
    }

    return AnimatedSize(
      duration: TelegramMotion.animationDuration,
      curve: FluffyThemes.animationCurve,
      child: _animationFinished ? widget.child : const SizedBox.shrink(),
    );
  }
}
