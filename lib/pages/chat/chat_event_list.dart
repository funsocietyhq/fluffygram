// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/encryption_info.dart';
import 'package:fluffychat/pages/chat/events/album_grid.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/chat/seen_by_row.dart';
import 'package:fluffychat/pages/chat/typing_indicators.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/mxc_image_viewer.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../../config/app_config.dart';
import '../../utils/date_time_extension.dart';

/// Telegram's day pill: the centred marker that names the day of the messages
/// under it. The timeline has ONE pill widget, and both paths call it - a
/// message that draws its own row, and an album member that draws no tiles of
/// its own (roadmap T7). Same fills, same insets, same bold text.
Widget telegramDatePill(BuildContext context, DateTime date) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Material(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius * 2),
          color: theme.colorScheme.inverseSurface.withAlpha(200),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
            child: Text(
              date.localizedDate(context),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onInverseSurface,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class ChatEventList extends StatelessWidget {
  final ChatController controller;

  /// Height of the AppBar bottom slot the timeline has to clear: the
  /// pinned-message bar and the banners shown in it (`chat_view.dart` sums them
  /// into the slot height). Passed in by the chat view, which knows which of
  /// them are on screen.
  final double appBarBottomInset;

  /// T40.1: opens a row's Telegram context menu at the touch point. The chat
  /// view builds it, because the verbs live on `ChatController`; the timeline
  /// only passes it down to the row (`event_context_menu.dart`).
  final void Function(Event event, Offset position)? onContextPress;

  const ChatEventList({
    super.key,
    required this.controller,
    this.appBarBottomInset = 0,
    this.onContextPress,
  });

  /// Top padding of the timeline.
  ///
  /// The chat Scaffold draws its body behind the AppBar
  /// (`extendBodyBehindAppBar: true`), so the AppBar bottom slot - the
  /// pinned-message bar, the 'reply in thread' row and the 'jump to last read
  /// message' row - covers the top of the timeline. `8` is the timeline's own
  /// breathing room, `viewPaddingTop` the status bar the slot sits on, and
  /// `appBarBottomInset` the slot itself. Without the last term the first
  /// timeline row is hidden behind the pinned-message bar.
  static double telegramTimelineTopInset({
    required double appBarBottomInset,
    required double viewPaddingTop,
  }) => 8 + viewPaddingTop + appBarBottomInset;

  @override
  Widget build(BuildContext context) {
    final timeline = controller.timeline;
    final theme = Theme.of(context);

    if (controller.room.membership == .invite) {
      final room = controller.room;
      final inviteState = room.unsafeGetUserFromMemoryOrFallback(
        room.client.userID!,
      );
      final sender = room
          .unsafeGetUserFromMemoryOrFallback(inviteState.senderId)
          .calcDisplayname();
      final nameOrAlias = room.name.isNotEmpty
          ? room.name
          : room.canonicalAlias.isNotEmpty
          ? room.canonicalAlias
          : null;
      final roomAvatar = room.avatar;

      return Center(
        child: Container(
          padding: const EdgeInsets.all(32.0),
          alignment: .center,
          constraints: BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisAlignment: .center,
            crossAxisAlignment: .center,
            spacing: 16,
            children: [
              Avatar(
                mxContent: roomAvatar,
                name: room.getLocalizedDisplayname(),
                size: Avatar.defaultSize * 2.5,
                onTap: roomAvatar != null
                    ? () => showDialog(
                        context: context,
                        builder: (_) => MxcImageViewer(roomAvatar),
                      )
                    : null,
                borderRadius: room.isSpace
                    ? BorderRadius.circular(AppConfig.spaceBorderRadius * 2.5)
                    : null,
              ),
              Text(
                nameOrAlias == null
                    ? L10n.of(context).youInvitedBy(sender)
                    : room.isSpace
                    ? L10n.of(
                        context,
                      ).senderHasInvitedYouToTheSpace(sender, nameOrAlias)
                    : L10n.of(
                        context,
                      ).senderHasInvitedYouToTheChat(sender, nameOrAlias),
                textAlign: .center,
              ),
            ],
          ),
        ),
      );
    }

    if (timeline == null) {
      return const Center(child: CupertinoActivityIndicator());
    }

    final colors = [theme.secondaryBubbleColor, theme.bubbleColor];

    final horizontalPadding = FluffyThemes.isColumnMode(context) ? 8.0 : 0.0;

    final events = timeline.events.filterByVisibleInGui(
      threadId: controller.activeThreadId,
    );

    // Telegram shows a burst of photos as one album. The groups are computed
    // here, at render time, from the events the timeline already has; nothing
    // is written to any event. The list keeps every event at its own index, so
    // scroll indices, keys and date separators are unchanged.
    final albumCluster =
        telegramAlbumGridEnabled && controller.selectedEvents.isEmpty
        ? TelegramAlbumCluster.of(events)
        : const TelegramAlbumCluster.disabled();

    // create a map of eventId --> index to greatly improve performance of
    // ListView's findChildIndexCallback
    final thisEventsKeyMap = <String, int>{};
    for (var i = 0; i < events.length; i++) {
      thisEventsKeyMap[events[i].eventId] = i;
    }

    final hasWallpaper =
        controller.room.client.applicationAccountConfig.wallpaperUrl != null;

    return SelectionArea(
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(AppSettings.fontSizeFactor.value),
        ),
        child: ListView.custom(
          padding: EdgeInsets.only(
            top: telegramTimelineTopInset(
              appBarBottomInset: appBarBottomInset,
              viewPaddingTop: MediaQuery.paddingOf(context).top,
            ),
            bottom:
                8 +
                (controller.inputBarHeight ??
                    (72 + (FluffyThemes.isColumnMode(context) ? 16 : 0))),
            left: horizontalPadding,
            right: horizontalPadding,
          ),
          reverse: true,
          controller: controller.scrollController,
          keyboardDismissBehavior: PlatformInfos.isIOS
              ? ScrollViewKeyboardDismissBehavior.onDrag
              : ScrollViewKeyboardDismissBehavior.manual,
          childrenDelegate: SliverChildBuilderDelegate(
            (BuildContext context, int i) {
              // Footer to display typing indicator and read receipts:
              if (i == 0) {
                if (timeline.canRequestFuture) {
                  return Center(
                    child: TextButton.icon(
                      onPressed: timeline.isRequestingFuture
                          ? null
                          : controller.requestFuture,
                      icon: timeline.isRequestingFuture
                          ? CircularProgressIndicator.adaptive(strokeWidth: 2)
                          : const Icon(Icons.arrow_downward_outlined),
                      label: Text(L10n.of(context).loadMore),
                    ),
                  );
                }
                return Column(
                  mainAxisSize: .min,
                  children: [
                    if (events.isNotEmpty) SeenByRow(event: events.first),
                    TypingIndicators(controller),
                    EncryptionInfo(room: controller.room),
                  ],
                );
              }

              // Request history button or progress indicator:
              if (i == events.length + 1) {
                if (controller.activeThreadId != null ||
                    !timeline.canRequestHistory) {
                  return const SizedBox.shrink();
                }
                return Builder(
                  builder: (context) {
                    final visibleIndex = timeline.events.lastIndexWhere(
                      (event) =>
                          !event.isCollapsedState && event.isVisibleInGui,
                    );
                    if (visibleIndex > timeline.events.length - 50) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        controller.requestHistory,
                      );
                    }
                    return Center(
                      child: TextButton.icon(
                        onPressed: timeline.isRequestingHistory
                            ? null
                            : controller.requestHistory,
                        icon: timeline.isRequestingHistory
                            ? CircularProgressIndicator.adaptive(strokeWidth: 2)
                            : const Icon(Icons.arrow_upward_outlined),
                        label: Text(L10n.of(context).loadMore),
                      ),
                    );
                  },
                );
              }
              i--;

              // The message at this index:
              final event = events[i];
              final animateIn =
                  (event.transactionId ?? event.eventId) ==
                  controller.animateInEventId;

              final nextEvent = i + 1 < events.length ? events[i + 1] : null;
              final previousEvent = i > 0 ? events[i - 1] : null;

              // A member of an album that another bubble draws: keep the index
              // (the list and its keys count on it) and draw nothing. Not even
              // a day pill: a pill here would sit inside the container, between
              // its tiles, and Telegram draws no divider there. The pill for a
              // day change inside a run belongs to the run's anchor row, above
              // the mosaic - `albumCluster.datePillAt` (roadmap T27).
              if (albumCluster.isHiddenAt(i)) {
                return AutoScrollTag(
                  key: ValueKey(event.transactionId ?? event.eventId),
                  index: i,
                  controller: controller.scrollController,
                  child: const SizedBox.shrink(),
                );
              }

              // Collapsed state event
              final canExpand =
                  event.isCollapsedState &&
                  nextEvent?.isCollapsedState == true &&
                  previousEvent?.isCollapsedState != true;
              final isCollapsed =
                  event.isCollapsedState &&
                  previousEvent?.isCollapsedState == true &&
                  !controller.expandedEventIds.contains(event.eventId);

              // One decision, one widget, for a clustered run and for a plain
              // message: the cluster answers the plain day question and moves a
              // run's pill onto the row that draws the container.
              final displayDate = albumCluster.datePillAt(i, events);

              return AutoScrollTag(
                key: ValueKey(event.transactionId ?? event.eventId),
                index: i,
                controller: controller.scrollController,
                child: Column(
                  mainAxisSize: .min,
                  children: [
                    if (!isCollapsed && displayDate)
                      telegramDatePill(context, event.originServerTs),
                    Message(
                      event,
                      albumRun: albumCluster.runAt(i),
                      bigEmojis: controller.bigEmojis,
                      animateIn: animateIn,
                      onSwipe: () => controller.replyAction(replyTo: event),
                      onInfoTab: controller.showEventInfo,
                      onMention: () => controller.sendController.text +=
                          '${event.senderFromMemoryOrFallback.mention} ',
                      highlightMarker:
                          controller.scrollToEventIdMarker == event.eventId,
                      highlightMarkerToken:
                          controller.scrollToEventIdMarker == event.eventId
                          ? controller.scrollToEventIdMarkerToken
                          : 0,
                      onSelect: controller.onSelectMessage,
                      onContextPress: onContextPress,
                      scrollToEventId: controller.scrollToEventId,
                      longPressSelect: controller.selectedEvents.isNotEmpty,
                      selected: controller.selectedEvents.any(
                        (e) => e.eventId == event.eventId,
                      ),
                      singleSelected:
                          controller.selectedEvents.singleOrNull?.eventId ==
                          event.eventId,
                      onEdit: controller.editSelectedEventAction,
                      timeline: timeline,
                      displayReadMarker:
                          i > 0 &&
                          controller.readMarkerEventId == event.eventId,
                      nextEvent: nextEvent,
                      previousEvent: previousEvent,
                      wallpaperMode: hasWallpaper,
                      scrollController: controller.scrollController,
                      colors: colors,
                      isCollapsed: isCollapsed,
                      enterThread: controller.activeThreadId == null
                          ? controller.enterThread
                          : null,
                      onExpand: canExpand
                          ? () => controller.expandEventsFrom(
                              event,
                              !controller.expandedEventIds.contains(
                                event.eventId,
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              );
            },
            childCount: events.length + 2,
            findChildIndexCallback: (key) =>
                controller.findChildIndexCallback(key, thisEventsKeyMap),
          ),
        ),
      ),
    );
  }
}
