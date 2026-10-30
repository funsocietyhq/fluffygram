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

import 'package:desktop_drop/desktop_drop.dart';
import 'package:fluffychat/config/chat_backgrounds.dart';
import 'package:fluffychat/config/recent_gifs.dart';
import 'package:fluffychat/config/recent_stickers.dart';
import 'package:fluffychat/config/telegram_palette.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_app_bar_list_tile.dart';
import 'package:fluffychat/pages/chat/chat_app_bar_title.dart';
import 'package:fluffychat/pages/chat/chat_event_list.dart';
import 'package:fluffychat/pages/chat/chat_search_panel.dart';
import 'package:fluffychat/pages/chat/pinned_events.dart';
import 'package:fluffychat/pages/chat/pinned_message_bar.dart';
import 'package:fluffychat/pages/chat/reply_display.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/widgets/chat_settings_popup_menu.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../utils/stream_extension.dart';
import 'chat_emoji_picker.dart';
import 'chat_input_row.dart';
import 'event_context_menu.dart';
import 'telegram_motion.dart';

/// T40.2 - the geometry of the selection action bar that Telegram's own source
/// does not settle for Flutter. The measured values are theirs, with the line:
/// the count is 18 dp bold in the action-icon ink
/// (`ui/ChatActivity.java:10367-10369`), its format is `"%d Selected"`
/// (`res/values/strings.xml:6588` via `ChatActivity.java:19676`), it sits at
/// the leading edge with `dp(8)` of right padding (`ChatActivity.java:10372`)
/// and every action item is `dp(48)` wide (`ChatActivity.java:10377`).
/// PROVISIONAL: the two Flutter-side insets below have no counterpart in the
/// reference tree - the AppBar's own leading/title spacing maths is Flutter's -
/// and are retuned from a user's capture (ROADMAP T40.2 open list).
class TelegramSelectionBar {
  /// `ChatActivity.java:10367` - `setTextSize(dp(18))`, dp and not sp, so the
  /// system font scale does not touch it.
  static const double countFontSize = 18;

  /// `ChatActivity.java:10372` - `setRightPadding(dp(8))`, the gap between the
  /// count and the first action.
  static const double countRightPadding = 8;

  /// `ChatActivity.java:10374` - `LayoutHelper.createLinear(0, MATCH_PARENT,
  /// 1.0f, 85, 0, 5, 0)`: the count starts dp(85) from the bar's left edge,
  /// past the action-mode close button. The Flutter AppBar spends 56 dp of
  /// that on the leading slot, so the title spacing is the rest.
  /// PROVISIONAL.
  static const double countTitleSpacing = 29;
}

class ChatView extends StatelessWidget {
  final ChatController controller;

  const ChatView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bottomSheetPadding = FluffyThemes.isColumnMode(context) ? 16.0 : 8.0;
    final scrollUpBannerEventId = controller.scrollUpBannerEventId;

    final accountConfig = Matrix.of(context).client.applicationAccountConfig;

    return PopScope(
      canPop:
          controller.selectedEvents.isEmpty &&
          !controller.showEmojiPicker &&
          controller.activeThreadId == null,
      onPopInvokedWithResult: (pop, _) async {
        if (pop) return;
        if (controller.selectedEvents.isNotEmpty) {
          controller.clearSelectedEvents();
        } else if (controller.showEmojiPicker) {
          controller.emojiPickerAction();
        } else if (controller.activeThreadId != null) {
          controller.closeThread();
        }
      },
      child: StreamBuilder(
        stream: controller.room.client.onRoomState.stream
            .where((update) => update.roomId == controller.room.id)
            .rateLimit(const Duration(seconds: 1)),
        builder: (context, snapshot) => FutureBuilder(
          future: controller.loadTimelineFuture,
          builder: (BuildContext context, snapshot) {
            var appbarBottomHeight = 0.0;
            final activeThreadId = controller.activeThreadId;
            if (activeThreadId != null) {
              appbarBottomHeight += ChatAppBarListTile.fixedHeight;
            }
            if (controller.room.pinnedEventIds.isNotEmpty &&
                activeThreadId == null) {
              // The pinned bar is Telegram's raised panel, taller than the
              // 40 dp rows the thread tile and the banner keep.
              appbarBottomHeight += PinnedMessageBar.fixedHeight;
            }
            if (scrollUpBannerEventId != null && activeThreadId == null) {
              appbarBottomHeight += ChatAppBarListTile.fixedHeight;
            }
            return Scaffold(
              key: Key('chat_page'),
              extendBodyBehindAppBar: true,
              appBar: AppBar(
                shape: FluffyThemes.isColumnMode(context)
                    ? Border(
                        bottom: BorderSide(color: theme.dividerColor, width: 1),
                      )
                    : null,
                actionsIconTheme: IconThemeData(
                  color: controller.selectedEvents.isEmpty
                      ? TelegramPalette.textTertiary
                      : theme.colorScheme.onTertiaryContainer,
                ),
                backgroundColor: controller.selectedEvents.isEmpty
                    ? controller.activeThreadId != null
                          ? theme.colorScheme.secondaryContainer
                          : FluffyThemes.chatChromeFill(
                              context,
                              accentAlpha: 135,
                            ).withAlpha(240)
                    : theme.colorScheme.tertiaryContainer,
                // Telegram adds no Material elevation overlay on top of this
                // fill - the accent blend above is the whole colour, and the
                // icon circles take it too (finding 30: pill `#282E3B`, circles
                // `#262B38` on a user's phone, the fork read `#1E1E1E` and
                // `#2C2C2E`).
                surfaceTintColor: Colors.transparent,
                automaticallyImplyLeading: false,
                leading: controller.selectMode
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: controller.clearSelectedEvents,
                        tooltip: L10n.of(context).close,
                        color: theme.colorScheme.onTertiaryContainer,
                      )
                    : activeThreadId != null
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: controller.closeThread,
                        tooltip: L10n.of(context).backToMainChat,
                        color: theme.colorScheme.onSecondaryContainer,
                      )
                    : FluffyThemes.isColumnMode(context)
                    ? null
                    : const Center(child: BackButton()),
                titleSpacing: controller.selectMode
                    ? TelegramSelectionBar.countTitleSpacing
                    : FluffyThemes.isColumnMode(context)
                    ? 24
                    : 0,
                // Telegram carries the selection count at the leading edge of
                // the action bar in action mode: 18 dp bold in the same ink as
                // the action icons, spelled "%d Selected"
                // (ChatActivity.java:10366-10374 + 19676, res/values/strings.xml:6588).
                // ARB key `countSelected` (T42) mirrors plurals
                // MessagesSelected_one/_other (res/values/strings.xml:6588-6589):
                // one form for both quantities.
                title: controller.selectMode
                    ? Padding(
                        padding: const EdgeInsets.only(
                          right: TelegramSelectionBar.countRightPadding,
                        ),
                        child: Text(
                          L10n.of(
                            context,
                          ).countSelected(controller.selectedEvents.length),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: TelegramSelectionBar.countFontSize,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onTertiaryContainer,
                          ),
                        ),
                      )
                    : ChatAppBarTitle(controller),
                actions: [
                  // Telegram's action row, in their add order
                  // (ChatActivity.java:10377-10396): Save-to-file, Edit, Copy,
                  // Forward, Delete. Tag, Favorites and Share are not in the
                  // set we can reach (Matrix has no favorites, Telegram keeps
                  // Share hidden in a chat, Tag is Saved Messages + premium),
                  // and Reply is not a bar action for them at all - it lives in
                  // the bottom layout (ChatActivity.java:19555), the composer
                  // surface. Their bar has no overflow menu, so the popup that
                  // carried Pin / Save / Info / Report is gone: Pin, Forward and
                  // Info are context-menu items (T40.1) and Save is item 1 here.
                  if (controller.selectMode) ...[
                    if (controller.canSaveSelectedEvent)
                      IconButton(
                        icon: const Icon(Icons.download_outlined),
                        tooltip: L10n.of(context).downloadFile,
                        onPressed: () => controller.saveSelectedEvent(context),
                      ),
                    if (controller.canEditSelectedEvents)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: L10n.of(context).edit,
                        onPressed: controller.editSelectedEventAction,
                      ),
                    IconButton(
                      icon: const Icon(Icons.copy_outlined),
                      tooltip: L10n.of(context).copyToClipboard,
                      onPressed: controller.copyEventsAction,
                    ),
                    // Telegram's Forward (`msg_forward`, ChatActivity.java:10387,
                    // item 6 of the row) - the fork's `forwardEventsAction`
                    // (chat.dart:1228) existed in the controller and had never
                    // reached this bar.
                    IconButton(
                      icon: const Icon(Icons.forward),
                      tooltip: L10n.of(context).forward,
                      onPressed: controller.forwardEventsAction,
                    ),
                    if (controller.canRedactSelectedEvents)
                      IconButton(
                        icon: const Icon(Icons.delete_outlined),
                        tooltip: L10n.of(context).redactMessage,
                        onPressed: controller.redactEventsAction,
                      ),
                  ] else if (!controller.room.isArchived) ...[
                    // Telegram's group header carries no call buttons (user
                    // decision 2026-10-26, finding 15): the MatrixRTC start/
                    // join affordance lives in ChatSettingsPopupMenu, the
                    // three-dot menu. Only the Customise row and the menu
                    // remain here.
                    // The Customise sheet and the group call live in the
                    // three-dot menu, as Telegram carries them in its menu.
                    IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: 'Search',
                      onPressed: controller.toggleChatSearch,
                    ),
                    ChatSettingsPopupMenu(controller.room, true),
                  ],
                ],
                bottom: PreferredSize(
                  preferredSize: Size.fromHeight(appbarBottomHeight),
                  child: Column(
                    mainAxisSize: .min,
                    children: [
                      TelegramChatSearchPanel(
                        controller: controller,
                        onClose: controller.toggleChatSearch,
                        open: controller.chatSearchOpen,
                      ),
                      PinnedEvents(controller),
                      if (activeThreadId != null)
                        SizedBox(
                          height: ChatAppBarListTile.fixedHeight,
                          child: Center(
                            child: TextButton.icon(
                              onPressed: () =>
                                  controller.scrollToEventId(activeThreadId),
                              icon: const Icon(Icons.message),
                              label: Text(L10n.of(context).replyInThread),
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    theme.colorScheme.onSecondaryContainer,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (scrollUpBannerEventId != null &&
                          activeThreadId == null)
                        ChatAppBarListTile(
                          leading: IconButton(
                            color: theme.colorScheme.onSurfaceVariant,
                            icon: const Icon(Icons.close),
                            tooltip: L10n.of(context).close,
                            onPressed: () {
                              controller.discardScrollUpBannerEventId();
                              controller.setReadMarker();
                            },
                          ),
                          title: L10n.of(context).jumpToLastReadMessage,
                          trailing: TextButton(
                            onPressed: () {
                              controller.scrollToEventId(scrollUpBannerEventId);
                              controller.discardScrollUpBannerEventId();
                            },
                            child: Text(L10n.of(context).jump),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // The jump-to-latest circle is a Positioned in the body Stack,
              // 11dp above the composer: the Scaffold FAB slot sits on
              // Material's 16dp margins and brings a 40dp circle with a
              // splash and an elevation shadow.
              body: NotificationListener<SizeChangedLayoutNotification>(
                onNotification: (SizeChangedLayoutNotification notification) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => controller.updateInputBarHeight(),
                  );
                  return true;
                },
                child: DropTarget(
                  onDragDone: controller.onDragDone,
                  onDragEntered: controller.onDragEntered,
                  onDragExited: controller.onDragExited,
                  child: SafeArea(
                    top: false,
                    child: Stack(
                      children: <Widget>[
                        // The picked chat background (T5B): this chat's own
                        // pick, then the global one, then nothing - with
                        // nothing the theme's chat surface and the account
                        // wallpaper below keep drawing as before. Bubbles keep
                        // their own fills, so only the field behind the
                        // timeline changes.
                        Positioned.fill(
                          child: ListenableBuilder(
                            listenable: ChatBackgrounds.store,
                            builder: (context, _) => ColoredBox(
                              color:
                                  ChatBackgrounds.resolve(
                                    context,
                                    controller.room.id,
                                  ) ??
                                  theme.colorScheme.surface,
                            ),
                          ),
                        ),
                        if (accountConfig.wallpaperUrl != null)
                          Opacity(
                            opacity: accountConfig.wallpaperOpacity ?? 0.5,
                            child: ImageFiltered(
                              imageFilter: ui.ImageFilter.blur(
                                sigmaX: accountConfig.wallpaperBlur ?? 0.0,
                                sigmaY: accountConfig.wallpaperBlur ?? 0.0,
                              ),
                              child: MxcImage(
                                cacheKey: accountConfig.wallpaperUrl.toString(),
                                uri: accountConfig.wallpaperUrl,
                                fit: BoxFit.cover,
                                height: MediaQuery.sizeOf(context).height,
                                width: MediaQuery.sizeOf(context).width,
                                isThumbnail: false,
                                placeholder: (_) => Container(),
                              ),
                            ),
                          ),
                        GestureDetector(
                          onTap: controller.clearSingleSelectedEvent,
                          child: ScrollConfiguration(
                            // Telegram has no overscroll glow and no pull
                            // spinner on Android (target behaviours). Chat
                            // timeline only - the rest of the app keeps the
                            // platform scroll behaviour.
                            behavior: const TelegramScrollBehavior().copyWith(
                              overscroll: false,
                            ),
                            child: ChatEventList(
                              controller: controller,
                              // The body draws behind the AppBar, so the
                              // timeline has to be pushed below its bottom slot
                              // (the pinned-message bar and the banners).
                              appBarBottomInset: appbarBottomHeight,
                              // T40.1: the long press opens Telegram's menu on
                              // the row. The view owns the dispatch - the menu
                              // file only draws the list.
                              onContextPress: (event, position) =>
                                  _openEventContextMenu(
                                    context,
                                    controller,
                                    event,
                                    position,
                                  ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: TelegramMotion.jumpToLatestRightMargin,
                          // The composer box carries a bottom margin of its
                          // own; the circle sits 11dp above its top edge.
                          bottom:
                              (controller.inputBarHeight ??
                                  (72 +
                                      (FluffyThemes.isColumnMode(context)
                                          ? 16
                                          : 0))) -
                              bottomSheetPadding +
                              TelegramMotion.jumpToLatestAboveComposerGap,
                          child: _JumpToLatestButton(
                            visible:
                                controller.showScrollDownButton &&
                                controller.selectedEvents.isEmpty,
                            onPressed: controller.scrollDown,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: SizeChangedLayoutNotifier(
                            child: Container(
                              key: controller.inputBarKey,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    theme.colorScheme.surface.withAlpha(0),
                                    theme.colorScheme.surface,
                                    theme.colorScheme.surface,
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Container(
                                // Finding 21: the pill's inset is the row's
                                // own `edgeMargin` (9 dp ≈ the measured 7.6 dp),
                                // so this container adds no horizontal margin at
                                // phone width - `EdgeInsets.all` stacked 8 dp on
                                // top of it and the pill rendered at 17 dp.
                                margin: EdgeInsets.symmetric(
                                  vertical: bottomSheetPadding,
                                  horizontal: FluffyThemes.isColumnMode(context)
                                      ? 16.0
                                      : 0.0,
                                ),
                                constraints: const BoxConstraints(
                                  maxWidth: FluffyThemes.maxTimelineWidth,
                                ),
                                child: controller.room.isExtinct
                                    ? ElevatedButton.icon(
                                        icon: const Icon(Icons.chevron_right),
                                        label: Text(
                                          L10n.of(context).enterNewChat,
                                        ),
                                        onPressed: controller.goToNewRoomAction,
                                      )
                                    : !controller.room.canSendDefaultMessages &&
                                          controller.room.membership !=
                                              Membership.invite
                                    ? const SizedBox.shrink()
                                    : Material(
                                        clipBehavior: Clip.hardEdge,
                                        color:
                                            controller.selectedEvents.isNotEmpty
                                            ? theme
                                                  .colorScheme
                                                  .tertiaryContainer
                                            : theme
                                                  .colorScheme
                                                  .surfaceContainer,
                                        borderRadius: BorderRadius.circular(32),
                                        child:
                                            controller.room.membership ==
                                                .invite
                                            ? Row(
                                                children: [
                                                  Expanded(
                                                    child: TextButton.icon(
                                                      style: TextButton.styleFrom(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              16,
                                                            ),
                                                        foregroundColor: theme
                                                            .colorScheme
                                                            .error,
                                                      ),
                                                      icon: const Icon(
                                                        Icons.cancel_outlined,
                                                      ),
                                                      onPressed:
                                                          controller.leaveChat,
                                                      label: Text(
                                                        L10n.of(
                                                          context,
                                                        ).decline,
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: TextButton.icon(
                                                      style: TextButton.styleFrom(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              16,
                                                            ),
                                                      ),
                                                      icon: const Icon(
                                                        Icons.check_outlined,
                                                      ),
                                                      onPressed:
                                                          controller.joinChat,
                                                      label: Text(
                                                        L10n.of(context).accept,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : controller
                                                      .room
                                                      .isAbandonedDMRoom ==
                                                  true
                                            ? Row(
                                                children: [
                                                  Expanded(
                                                    child: TextButton.icon(
                                                      style: TextButton.styleFrom(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              16,
                                                            ),
                                                        foregroundColor: theme
                                                            .colorScheme
                                                            .error,
                                                      ),
                                                      icon: const Icon(
                                                        Icons.archive_outlined,
                                                      ),
                                                      onPressed:
                                                          controller.leaveChat,
                                                      label: Text(
                                                        L10n.of(context).leave,
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: TextButton.icon(
                                                      style: TextButton.styleFrom(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              16,
                                                            ),
                                                      ),
                                                      icon: const Icon(
                                                        Icons.forum_outlined,
                                                      ),
                                                      onPressed: controller
                                                          .recreateChat,
                                                      label: Text(
                                                        L10n.of(
                                                          context,
                                                        ).reopenChat,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : Column(
                                                mainAxisSize: .min,
                                                children: [
                                                  ReplyDisplay(controller),
                                                  ChatInputRow(controller),
                                                  ChatEmojiPicker(controller),
                                                ],
                                              ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                        if (controller.dragging)
                          Container(
                            color: theme.scaffoldBackgroundColor.withAlpha(230),
                            alignment: Alignment.center,
                            child: const Icon(Icons.upload_outlined, size: 100),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Telegram's jump-to-latest control: a flat 40dp circle, 11dp above the
/// composer, with a chevron. No Material splash, no elevation shadow, no hero
/// tag - it fades and scales in and out (target: "jump FAB fade", "no ripple",
/// "no elevation shadows").
class _JumpToLatestButton extends StatelessWidget {
  const _JumpToLatestButton({required this.visible, required this.onPressed});

  final bool visible;
  final void Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    return AnimatedScale(
      scale: visible ? 1 : TelegramMotion.jumpToLatestHiddenScale,
      duration: TelegramMotion.chromeFadeDuration,
      curve: TelegramMotion.chromeFadeCurve,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: TelegramMotion.chromeFadeDuration,
        curve: TelegramMotion.chromeFadeCurve,
        child: IgnorePointer(
          ignoring: !visible,
          child: Tooltip(
            message: L10n.of(context).jumpToLastReadMessage,
            child: GestureDetector(
              onTap: onPressed,
              child: Container(
                width: TelegramMotion.jumpToLatestSize,
                height: TelegramMotion.jumpToLatestSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Telegram's scroll-down FAB is accent-tinted, not the bubble
                  // fill: `#262B38` = the accent at 0.50 over the black chat
                  // page on a user's phone (finding 30; the fork read
                  // `#2C2C2E`).
                  // T36 (2026-10-27): the flat measured disc. The blend above
                  // (T36 `50c2e00f4`, accent at 0.50 over the surface) painted
                  // (70,72,94) on a user's phone at build 21 - a custom
                  // accent in Settings moves the blend off the target; the cap
                  // reads (79,82,108) for the same accent. Probe on
                  // the reference capture; target `jump_fab_night`.
                  color: night
                      ? TelegramPalette.jumpFabNight
                      : theme.bubbleColorIncoming,
                ),
                child: Center(
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: TelegramMotion.jumpToLatestChevronSize,
                    // jump_to_latest_chevron #9CA3AF.
                    color: night
                        ? TelegramPalette.textTertiary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// T40.1: the long-press menu for one timeline row - Telegram's
/// `ChatMessageCell.java:557` `didLongPress`, which hands the row and the
/// touch point to the screen, and the screen opens the menu there.
///
/// `event_context_menu.dart` draws the list and returns the picked item; this
/// is where the item meets the `ChatController` verbs. Every verb reads
/// `selectedEvents`, so the items that need one select this row first, exactly
/// the way the selection action bar above does.
Future<void> _openEventContextMenu(
  BuildContext context,
  ChatController controller,
  Event event,
  Offset position,
) async {
  final room = controller.room;
  final sent = event.status.isSent;
  final isPinned = room.pinnedEventIds.contains(event.eventId);
  final actions = telegramContextActionsFor(
    event: event,
    ownMessage: event.senderId == room.client.userID,
    // Single-row reads of the controller's own gates:
    // `canEditSelectedEvents` (chat.dart:1217) and `canPinSelectedEvents`
    // (chat.dart:1206).
    canEdit: !controller.isArchived,
    isPinned: isPinned,
    canPin:
        !controller.isArchived &&
        sent &&
        room.canChangeStateEvent(EventTypes.RoomPinnedEvents),
    canRedact: event.canRedact,
  );
  final chosen = await showTelegramEventContextMenu(
    context,
    position: position,
    actions: actions,
    isPinned: isPinned,
    // T125: which verb the GIF item shows - "Add to gifs" or "Remove from
    // gifs". A read of the local store, no network.
    inGifTray: RecentGifs.holds(event),
    // T142: the same read for the sticker item.
    inStickerDrawer: RecentStickers.holds(event),
  );
  if (chosen == null || !context.mounted) return;

  void selectThen(void Function() verb) {
    controller.clearSelectedEvents();
    controller.onSelectMessage(event);
    verb();
  }

  switch (chosen) {
    case TelegramContextAction.reply:
      controller.replyAction(replyTo: event);
    case TelegramContextAction.quote:
      // Telegram's Quote: the reply relation, plus the quoted text as a quote
      // block in the composer. Matrix draws a leading `> ` as a quote block.
      controller.replyAction(replyTo: event);
      controller.sendController.text =
          '> ${event.body}\n\n${controller.sendController.text}';
      controller.inputFocus.requestFocus();
    case TelegramContextAction.copy:
      selectThen(controller.copyEventsAction);
    case TelegramContextAction.forward:
      selectThen(() => controller.forwardEventsAction());
    case TelegramContextAction.select:
      // Selection mode is entered here and nowhere else (T40.2 owns the bar).
      controller.onSelectMessage(event);
    case TelegramContextAction.pin:
      // pinEvent() unpins when the single selected row is already pinned.
      selectThen(controller.pinEvent);
    case TelegramContextAction.save:
      selectThen(() => controller.saveSelectedEvent(context));
    case TelegramContextAction.gifs:
      // T125 (user, 2026-10-30: "'Add to gifs' should be an option on gifs
      // and animated webps"; "Even if I remove something from my gif tray, it
      // comes back when I restart the app"). One item, two verbs, both on the
      // device-local store: `addFromEvent` writes a row marked `added` (mine
      // or a friend's GIF, no download and no re-encode) and lifts any
      // tombstone, `removeForEvent` drops every row of that media id and
      // tombstones the url so no writer brings it back. `RecentGifs` fires its
      // own notifier, so an open tray repaints; no selection mode, so no
      // `selectThen`.
      if (RecentGifs.holds(event)) {
        await RecentGifs.removeForEvent(event);
      } else {
        await RecentGifs.addFromEvent(event);
      }
    case TelegramContextAction.stickers:
      // T142 : one item, two verbs on the device-local
      // drawer list. `RecentStickers` fires its notifier (T56.2.2), so an open
      // sticker tray repaints at once.
      if (RecentStickers.holds(event)) {
        await RecentStickers.removeForEvent(event);
      } else {
        await RecentStickers.addFromEvent(event);
      }
    case TelegramContextAction.copyLink:
      final link = telegramEventLink(event.body);
      if (link != null) await Clipboard.setData(ClipboardData(text: link));
    case TelegramContextAction.info:
      controller.showEventInfo(event);
    case TelegramContextAction.edit:
      selectThen(controller.editSelectedEventAction);
    case TelegramContextAction.delete:
      selectThen(() => controller.redactEventsAction());
  }
}
