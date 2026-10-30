// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/config/recent_gifs.dart';
import 'package:fluffychat/config/recent_stickers.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat_view.dart';
import 'package:fluffychat/pages/chat/event_info_dialog.dart';
import 'package:fluffychat/pages/chat/events/album_grid.dart';
import 'package:fluffychat/pages/chat/start_poll_bottom_sheet.dart';
import 'package:fluffychat/pages/chat/trust_user_key_dialog.dart';
import 'package:fluffychat/pages/chat/utils/web_file_to_x_file.dart';
import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/error_reporter.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/other_party_can_receive.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/show_scaffold_dialog.dart';
import 'package:fluffychat/utils/telegram_gif.dart';
import 'package:fluffychat/utils/telegram_gif_file.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:universal_html/universal_html.dart' as web;

import '../../utils/account_bundles.dart';
import '../../utils/localized_exception_extension.dart';
import 'send_file_dialog.dart';
import 'send_location_dialog.dart';

class ChatPage extends StatelessWidget {
  final String roomId;
  final List<ShareItem>? shareItems;
  final String? eventId;
  final Timeline? timeline;
  final String? action;

  const ChatPage({
    super.key,
    required this.roomId,
    this.eventId,
    this.shareItems,
    this.timeline,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final room =
        timeline?.room ?? Matrix.of(context).client.getRoomById(roomId);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).oopsSomethingWentWrong)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
          ),
        ),
      );
    }

    return ChatPageWithRoom(
      key: Key('chat_page_${roomId}_${eventId}_$action'),
      room: room,
      shareItems: shareItems,
      eventId: eventId,
      timeline: timeline,
      action: action,
    );
  }
}

class ChatPageWithRoom extends StatefulWidget {
  final Room room;
  final List<ShareItem>? shareItems;
  final String? eventId;
  final Timeline? timeline;
  final String? action;

  const ChatPageWithRoom({
    super.key,
    required this.room,
    this.shareItems,
    this.eventId,
    this.timeline,
    this.action,
  });

  @override
  ChatController createState() => ChatController();
}

class ChatController extends State<ChatPageWithRoom>
    with WidgetsBindingObserver {
  Room get room => sendingClient.getRoomById(roomId) ?? widget.room;

  late Client sendingClient;

  Timeline? timeline;

  String? activeThreadId;

  late final Set<String> bigEmojis;

  late final String readMarkerEventId;

  String get roomId => widget.room.id;

  final AutoScrollController scrollController = AutoScrollController();

  late final FocusNode inputFocus;

  Timer? typingCoolDown;
  Timer? typingTimeout;
  bool currentlyTyping = false;
  bool dragging = false;

  final GlobalKey inputBarKey = GlobalKey();

  void onDragEntered(_) => setState(() => dragging = true);

  void onDragExited(_) => setState(() => dragging = false);

  Future<void> onDragDone(DropDoneDetails details) async {
    setState(() => dragging = false);
    if (details.files.isEmpty) return;

    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: details.files,
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  bool get canSaveSelectedEvent =>
      selectedEvents.length == 1 &&
      {
        MessageTypes.Video,
        MessageTypes.Image,
        MessageTypes.Sticker,
        MessageTypes.Audio,
        MessageTypes.File,
      }.contains(selectedEvents.single.messageType);

  void saveSelectedEvent(BuildContext context) =>
      selectedEvents.single.saveFile(context);

  List<Event> selectedEvents = [];

  final Set<String> unfolded = {};

  Event? replyEvent;

  Event? editEvent;

  bool _scrolledUp = false;

  bool get showScrollDownButton =>
      _scrolledUp || timeline?.allowNewEvent == false;

  bool get selectMode => selectedEvents.isNotEmpty;

  final int _loadHistoryCount = 100;

  String pendingText = '';

  bool showEmojiPicker = false;

  String? get threadLastEventId {
    final threadId = activeThreadId;
    if (threadId == null) return null;
    return timeline?.events
        .filterByVisibleInGui(threadId: threadId)
        .firstOrNull
        ?.eventId;
  }

  void enterThread(String eventId) => setState(() {
    activeThreadId = eventId;
    selectedEvents.clear();
  });

  void closeThread() => setState(() {
    activeThreadId = null;
    selectedEvents.clear();
  });

  Future<void> recreateChat() async {
    final room = this.room;
    final userId = room.directChatMatrixID;
    if (userId == null) {
      throw Exception(
        'Try to recreate a room with is not a DM room. This should not be possible from the UI!',
      );
    }
    await showFutureLoadingDialog(
      context: context,
      future: () => room.invite(userId),
    );
  }

  Future<void> joinChat() async {
    final success = await showFutureLoadingDialog(
      context: context,
      future: () async {
        await room.join(waitForSync: true);
      },
    );
    if (!mounted) return;
    if (success.error != null) return;
    if (room.isSpace) {
      context.go('/rooms?spaceId=${room.id}');
      return;
    }
    await _tryLoadTimeline();
  }

  Future<void> leaveChat() async {
    if (room.membership == .invite) {
      final blockConsent = await showOkCancelAlertDialog(
        context: context,
        title: L10n.of(context).declineInvitation,
        message: L10n.of(context).doYouAlsoWantToBlock,
        cancelLabel: L10n.of(context).decline,
        okLabel: L10n.of(context).declineAndBlock,
        isDestructive: true,
      );
      if (blockConsent == null) return;
      if (!mounted) return;
      if (blockConsent == .ok) {
        final inviteEvent = room.getState(
          EventTypes.RoomMember,
          room.client.userID!,
        );
        context.go(
          '/rooms/settings/security/ignorelist',
          extra: inviteEvent?.senderId,
        );
        return;
      }
    }
    final success = await showFutureLoadingDialog(
      context: context,
      future: room.leave,
    );
    if (!mounted) return;
    if (success.error != null) return;
    context.go('/rooms');
  }

  Future<void> requestHistory([_]) async {
    Logs().v('Requesting history...');
    await timeline?.requestHistory(historyCount: _loadHistoryCount);
  }

  Future<void> requestFuture() async {
    final timeline = this.timeline;
    if (timeline == null) return;
    Logs().v('Requesting future...');

    final mostRecentEvent = timeline.events.filterByVisibleInGui().firstOrNull;

    await timeline.requestFuture(historyCount: _loadHistoryCount);

    if (mostRecentEvent != null) {
      setReadMarker(eventId: mostRecentEvent.eventId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final index = timeline.events.filterByVisibleInGui().indexOf(
          mostRecentEvent,
        );
        if (index >= 0) {
          scrollController.scrollToIndex(
            index,
            preferPosition: AutoScrollPosition.begin,
          );
        }
      });
    }
  }

  void _updateScrollController() {
    if (!mounted) {
      return;
    }
    if (!scrollController.hasClients) return;
    if (timeline?.allowNewEvent == false ||
        scrollController.position.pixels > 0 && _scrolledUp == false) {
      setState(() => _scrolledUp = true);
    } else if (scrollController.position.pixels <= 0 && _scrolledUp == true) {
      setState(() => _scrolledUp = false);
      setReadMarker();
    }
  }

  void _loadDraft() {
    final prefs = Matrix.of(context).store;
    final draft = prefs.getString('draft_$roomId');
    if (draft != null && draft.isNotEmpty) {
      sendController.text = draft;
    }
  }

  Future<void> _shareItems() async {
    final shareItems = widget.shareItems;
    if (shareItems == null || shareItems.isEmpty) return;
    if (!room.otherPartyCanReceiveMessages) {
      final theme = Theme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: theme.colorScheme.errorContainer,
          closeIconColor: theme.colorScheme.onErrorContainer,
          content: Text(
            L10n.of(context).otherPartyNotLoggedIn,
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
          showCloseIcon: true,
        ),
      );
      return;
    }
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!mounted || !proceed) return;
    for (final item in shareItems) {
      if (item is FileShareItem) continue;
      if (item is TextShareItem) room.sendTextEvent(item.value);
      if (item is ContentShareItem) room.sendEvent(item.value.copy());
    }
    final files = shareItems
        .whereType<FileShareItem>()
        .map((item) => item.value)
        .toList();
    if (files.isEmpty) return;
    showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  KeyEventResult _customEnterKeyHandling(FocusNode node, KeyEvent evt) {
    if (evt is KeyDownEvent &&
        evt.logicalKey == LogicalKeyboardKey.arrowUp &&
        !PlatformInfos.isMobile &&
        editEvent == null &&
        replyEvent == null &&
        sendController.text.isEmpty) {
      _editLastSentMessage();
      return KeyEventResult.handled;
    }

    if (evt is KeyDownEvent &&
        evt.logicalKey == LogicalKeyboardKey.escape &&
        editEvent != null) {
      _cancelEditWithConfirmation();
      return KeyEventResult.handled;
    }

    if (!HardwareKeyboard.instance.isShiftPressed &&
        evt.logicalKey.keyLabel == 'Enter' &&
        AppSettings.sendOnEnter.value) {
      if (evt is KeyDownEvent) {
        send();
      }
      return KeyEventResult.handled;
    } else if (evt.logicalKey.keyLabel == 'Enter' && evt is KeyDownEvent) {
      final currentLineNum =
          sendController.text
              .substring(0, sendController.selection.baseOffset)
              .split('\n')
              .length -
          1;
      final currentLine = sendController.text.split('\n')[currentLineNum];

      for (final pattern in [
        '- [ ] ',
        '- [x] ',
        '* [ ] ',
        '* [x] ',
        '- ',
        '* ',
        '+ ',
      ]) {
        if (currentLine.startsWith(pattern)) {
          if (currentLine == pattern) {
            return KeyEventResult.ignored;
          }
          sendController.text += '\n$pattern';
          return KeyEventResult.handled;
        }
      }

      return KeyEventResult.ignored;
    } else {
      return KeyEventResult.ignored;
    }
  }

  @override
  void initState() {
    inputFocus = FocusNode(onKeyEvent: _customEnterKeyHandling);

    scrollController.addListener(_updateScrollController);
    inputFocus.addListener(_inputFocusListener);

    _loadDraft();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shareItems();
      _checkMatrixRtcCallSupport();
      if (widget.action == 'call') {
        Matrix.of(context).activeCallRoomId.value = room.id;
      }
    });
    web.window.addEventListener('paste', _handleClipboardFilePasteWeb);

    super.initState();
    _displayChatDetailsColumn = ValueNotifier(
      AppSettings.displayChatDetailsColumn.value,
    );

    bigEmojis = defaultEmojiSet.fold(
      <String>{},
      (emojis, category) => {
        ...emojis,
        ...(category.emoji.map((emoji) => emoji.emoji)),
      },
    );

    sendingClient = Matrix.of(context).client;
    final lastEventThreadId =
        room.lastEvent?.relationshipType == RelationshipTypes.thread
        ? room.lastEvent?.relationshipEventId
        : null;
    readMarkerEventId = room.hasNewMessages
        ? lastEventThreadId ?? room.fullyRead
        : '';
    WidgetsBinding.instance.addObserver(this);
    _tryLoadTimeline();
  }

  Future<void> _checkMatrixRtcCallSupport() async {
    try {
      final urls = await room.client.getLiveKitServiceUrls();
      if (urls.isEmpty) return;
      setState(() {
        supportLiveKitCalls = true;
      });
    } catch (e) {
      Logs().d('Unable to check MatrixRTC call support', e);
    }
  }

  final Set<String> expandedEventIds = {};

  void expandEventsFrom(Event event, bool expand) {
    final events = timeline!.events.filterByVisibleInGui(
      threadId: activeThreadId,
    );
    final start = events.indexOf(event);
    setState(() {
      for (var i = start; i < events.length; i++) {
        final event = events[i];
        if (!event.isCollapsedState) return;
        if (expand) {
          expandedEventIds.add(event.eventId);
        } else {
          expandedEventIds.remove(event.eventId);
        }
      }
    });
  }

  Future<void> _tryLoadTimeline() async {
    if (room.membership == .invite) return;

    final initialEventId = widget.eventId;
    loadTimelineFuture = _getTimeline();
    try {
      await loadTimelineFuture;
      // We launched the chat with a given initial event ID:
      if (initialEventId != null) {
        scrollToEventId(initialEventId);
        return;
      }

      var readMarkerEventIndex = readMarkerEventId.isEmpty
          ? -1
          : timeline!.events
                .filterByVisibleInGui(
                  exceptionEventId: readMarkerEventId,
                  threadId: activeThreadId,
                )
                .indexWhere((e) => e.eventId == readMarkerEventId);

      // Read marker is existing but not found in first events. Try a single
      // requestHistory call before opening timeline on event context:
      if (readMarkerEventId.isNotEmpty && readMarkerEventIndex == -1) {
        await timeline?.requestHistory(historyCount: _loadHistoryCount);
        readMarkerEventIndex = timeline!.events
            .filterByVisibleInGui(
              exceptionEventId: readMarkerEventId,
              threadId: activeThreadId,
            )
            .indexWhere((e) => e.eventId == readMarkerEventId);
      }

      if (readMarkerEventIndex > 1) {
        Logs().v('Scroll up to visible event', readMarkerEventId);
        scrollToEventId(readMarkerEventId, highlightEvent: false);
      } else if (readMarkerEventId.isNotEmpty && readMarkerEventIndex == -1) {
        _showScrollUpMaterialBanner(readMarkerEventId);
      }

      // Mark room as read on first visit if requirements are fulfilled
      setReadMarker();

      if (!mounted) return;
    } catch (e, s) {
      ErrorReporter(context, 'Unable to load timeline').onErrorCallback(e, s);
      rethrow;
    }
  }

  String? scrollUpBannerEventId;

  void discardScrollUpBannerEventId() => setState(() {
    scrollUpBannerEventId = null;
  });

  void _showScrollUpMaterialBanner(String eventId) => setState(() {
    scrollUpBannerEventId = eventId;
  });

  String? animateInEventId;

  Future<void> _insert(int index) async {
    if (index > 0) return;
    final firstEvent = timeline?.events.firstOrNull;
    // T56.3.2: Telegram's GIF collection grows from every GIF this user
    // sends - the gallery picker, the tray tile, the same account on another
    // client. A photo fails the mimetype test; pagination inserts land at
    // index > 0, so old history never back-fills here (that seed is T56.3.1).
    // T113: this hook is **not** enough on its own, and was never the writer the
    // user needed - an own send inserts the SDK's url-less placeholder, so the
    // write lands on the row that plays the GIF instead
    // (`lib/pages/chat/events/message_content.dart`). What stays here is the
    // other-client case: an event that arrives already decrypted, with its url
    // in hand.
    if (firstEvent != null && firstEvent.senderId == room.client.userID) {
      await RecentGifs.recordFromEvent(firstEvent);
      // T142: the drawer's half of the same hook, and for the same reason the
      // GIF comment names - this catches a sticker sent from **this account on
      // another client**, which arrives already decrypted with its url in hand.
      // A sticker sent from this phone records itself at the send site
      // (`sendSticker()`, and the send dialog's sticker branch), because
      // `Room.sendEvent()` inserts a url-less placeholder here.
      if (firstEvent.messageType == MessageTypes.Sticker) {
        await RecentStickers.addFromEvent(firstEvent);
      }
    }
    final eventId = firstEvent?.transactionId ?? firstEvent?.eventId;
    animateInEventId = eventId;
    await Future.delayed(FluffyThemes.animationDuration);
    if (animateInEventId == eventId) animateInEventId = null;
  }

  void updateView() {
    if (!mounted) return;
    setReadMarker();
    setState(() {});
  }

  Future<void>? loadTimelineFuture;

  Future<void> _getTimeline({String? eventContextId}) async {
    final matrix = Matrix.of(context);
    await matrix.client.roomsLoading;
    await matrix.client.accountDataLoading;
    if (eventContextId != null &&
        (!eventContextId.isValidMatrixIdStrict() ||
            eventContextId.sigil != '\$')) {
      eventContextId = null;
    }
    try {
      timeline?.cancelSubscriptions();
      timeline =
          widget.timeline ??
          await room.getTimeline(
            onUpdate: updateView,
            onInsert: _insert,
            eventContextId: eventContextId,
          );
    } catch (e, s) {
      Logs().w('Unable to load timeline on event ID $eventContextId', e, s);
      if (!mounted) return;
      timeline = await room.getTimeline(onUpdate: updateView);
      if (!mounted) return;
      if (e is TimeoutException || e is IOException) {
        _showScrollUpMaterialBanner(eventContextId!);
      }
    }
    timeline!.requestKeys(onlineKeyBackupOnly: false);
    if (room.markedUnread) room.markUnread(false);

    return;
  }

  String? scrollToEventIdMarker;

  /// T70 (2026-10-28): bumps with every highlight jump, so a re-jump to the
  /// SAME event restarts the row's highlight animation - the marker string
  /// alone would leave the row's animation widget keyed identically and the
  /// fade would not replay. Telegram restarts unconditionally:
  /// `setHighlightedAnimated` writes `highlightProgress = 1000` every call
  /// (`ChatMessageCell.java:12541-12543`).
  int scrollToEventIdMarkerToken = 0;

  /// Ends Telegram's highlight cycle: `setHighlightedAnimated` runs
  /// `highlightProgress` for 1000 ms and `getHighlightAlpha` (line 23119)
  /// holds full alpha until 300 ms remain, then fades. The row paints the
  /// 700/300 split; this timer retires the marker when the cycle ends.
  Timer? _jumpHighlightTimer;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!mounted) return;
    setReadMarker();
  }

  String? _setReadMarkerEventId;

  void setReadMarker({String? eventId}) {
    // Do not send read markers when app is not in foreground
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    final setOnLatestEvent = eventId == null;

    // We only set read marker if we are at the bottom
    if (_scrolledUp && setOnLatestEvent) return;

    // We do not set read marker if we offer user the scroll up banner
    if (scrollUpBannerEventId != null) return;

    // We do not set read marker if timeline is empty
    final timeline = this.timeline;
    if (timeline == null || timeline.events.isEmpty) return;

    // Do not set read marker on rtc notification while call is active. This
    // mutes callkit.
    if (room.hasActiveMatrixRtcCall &&
        timeline.events.first.type == RtcNotificationContent.eventType) {
      return;
    }

    eventId ??= timeline.events.firstWhereOrNull((event) {
      if (event.eventId == room.lastEvent?.eventId) return true;
      if (room.client.pushruleEvaluator.match(event).notify) {
        return true;
      }
      final original = event.originalSource;
      if (original != null &&
          room.client.pushruleEvaluator
              .match(Event.fromMatrixEvent(original, room))
              .notify) {
        return true;
      }
      return false;
    })?.eventId;

    if (setOnLatestEvent && (room.hasNewMessages || room.isUnread)) {
      eventId ??=
          room.lastEvent?.eventId ?? timeline.events.firstOrNull?.eventId;
    }

    // There is no event we could place a read marker
    if (eventId == null) return;

    // This is a sending event, we do not set a readmarker yet
    if (eventId.isValidMatrixIdStrict() == false) return;

    // We are already setting a read marker on this event
    if (_setReadMarkerEventId == eventId) return;

    // Already set a read marker on this event
    if (room.fullyRead == eventId && !setOnLatestEvent) return;

    // Set a readmarker on a specific event, not latest, but room is not unread
    // at all.
    if (setOnLatestEvent &&
        !room.hasNewMessages &&
        room.notificationCount == 0) {
      return;
    }

    Logs().d('Set read marker...', eventId);
    _setReadMarkerEventId = eventId;
    // ignore: unawaited_futures
    timeline
        .setReadMarker(
          eventId: eventId,
          public: AppSettings.sendPublicReadReceipts.value,
        )
        .whenComplete(() {
          if (_setReadMarkerEventId == eventId) _setReadMarkerEventId = null;
        });
  }

  @override
  void dispose() {
    timeline?.cancelSubscriptions();
    timeline = null;
    _jumpHighlightTimer?.cancel();
    _storeInputTimeoutTimer?.cancel();
    typingCoolDown?.cancel();
    typingTimeout?.cancel();
    sendController.dispose();
    scrollController.dispose();
    inputFocus.removeListener(_inputFocusListener);
    inputFocus.dispose();
    _displayChatDetailsColumn.dispose();
    web.window.removeEventListener('paste', _handleClipboardFilePasteWeb);
    if (currentlyTyping) room.setTyping(false);
    MxcImage.clearCache(widget.room.id);
    super.dispose();
  }

  TextEditingController sendController = TextEditingController();

  void setSendingClient(Client c) {
    // first cancel typing with the old sending client
    if (currentlyTyping) {
      // no need to have the setting typing to false be blocking
      typingCoolDown?.cancel();
      typingCoolDown = null;
      room.setTyping(false);
      currentlyTyping = false;
    }
    // then cancel the old timeline
    // fixes bug with read reciepts and quick switching
    loadTimelineFuture = _getTimeline(eventContextId: room.fullyRead).onError(
      ErrorReporter(
        context,
        'Unable to load timeline after changing sending Client',
      ).onErrorCallback,
    );

    // then set the new sending client
    setState(() => sendingClient = c);
  }

  void setActiveClient(Client c) => setState(() {
    Matrix.of(context).setActiveClient(c);
  });

  Future<void> send() async {
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!mounted || !proceed) return;
    if (sendController.text.trim().isEmpty) return;
    _storeInputTimeoutTimer?.cancel();
    final prefs = Matrix.of(context).store;
    prefs.remove('draft_$roomId');
    var parseCommands = true;

    final commandMatch = RegExp(r'^\/(\w+)').firstMatch(sendController.text);
    if (commandMatch != null &&
        !sendingClient.commands.keys.contains(commandMatch[1]!.toLowerCase())) {
      final l10n = L10n.of(context);
      final dialogResult = await showOkCancelAlertDialog(
        context: context,
        title: l10n.commandInvalid,
        message: l10n.commandMissing(commandMatch[0]!),
        okLabel: l10n.sendAsText,
        cancelLabel: l10n.cancel,
      );
      if (dialogResult == OkCancelResult.cancel) return;
      parseCommands = false;
    }

    if (currentlyTyping) {
      typingCoolDown?.cancel();
      currentlyTyping = false;
      room.setTyping(false);
    }

    // ignore: unawaited_futures
    room.sendTextEvent(
      sendController.text,
      inReplyTo: replyEvent,
      editEventId: editEvent?.eventId,
      parseCommands: parseCommands,
      threadRootEventId: activeThreadId,
    );
    sendController.value = TextEditingValue(
      text: pendingText,
      selection: const TextSelection.collapsed(offset: 0),
    );

    setState(() {
      sendController.text = pendingText;
      _inputTextIsEmpty = pendingText.isEmpty;
      replyEvent = null;
      editEvent = null;
      pendingText = '';
    });
  }

  /// Telegram's sticker tray sends a sticker on one tap, and the sticker joins
  /// the tray's recents row once the send completes - a sticker whose send
  /// failed never enters the row. The recents write is a device-local
  /// preference; the send event itself is untouched.
  Future<void> sendSticker(ImagePackImageContent sticker) async {
    await room.sendEvent(
      {
        'body': sticker.body,
        'info': sticker.info ?? {},
        'url': sticker.url.toString(),
      },
      type: EventTypes.Sticker,
      threadRootEventId: activeThreadId,
      threadLastEventId: threadLastEventId,
    );
    await RecentStickers.record(sticker.url);
  }

  /// The GIF tray's tile sends the stored GIF on one tap - Telegram's tray has
  /// no preview screen on this path (`ui/Components/EmojiView.java:706`
  /// `Delegate.sendGif(...)`), and the GIF joins the tray's grid only once the
  /// send completes, so a failed send never enters it. The content is the
  /// shape `telegramEventIsGif()` recognises - an `m.image` whose
  /// `info['mimetype']` is `image/gif`, or since T123 `image/webp` - which is
  /// what makes the row autoplay (T56.4). T124: the mimetype sent is the
  /// stored row's own ([RecentGif.mimeType]), not a fixed `image/gif`, so a
  /// replay of an animated WebP GIF stays webp in `info`. The grid entry is not
  /// written here: the timeline insert hook
  /// `_insert()` (T56.3.2) records every GIF this user sends, this send
  /// included, so the store has exactly one writer.
  ///
  /// T56.3.3: the tile hands over its full [RecentGif] entry, and with a
  /// known size the content joins the gallery send's shape - the timeline
  /// media row reads its aspect from `info['w']`/`info['h']`, so the
  /// replayed row draws at the GIF's true size.
  /// T112: when the tile carries the `file` reference of a past encrypted
  /// send, that map goes into the content verbatim, so the homeserver stores
  /// no second copy - Synapse never de-duplicates (`media_repository.py`
  /// `create_or_update_content()` names every file after `random_string(24)`)
  /// and E2EE makes de-duplication impossible. The content is rebuilt from
  /// the tile's own fields, never copied out of the source event: a replay is
  /// a new top-level message, so it carries no `relatesTo` and no `m.mentions`
  /// from the send the tile came from.
  /// T117 (user, 2026-10-30: "if we send a gif that isn't in the chat we're
  /// sending it to, it pulls and sends the actual file"). Two paths:
  /// * the row came from **this** chat - re-send the reference, 313 bytes of
  ///   content and no upload (T112, `the measurement log` "POC");
  /// * the row came from another chat - this room has never seen those bytes,
  ///   so pull the file (media cache first, one download plus one decrypt on
  ///   a miss) and upload it here as a fresh attachment.
  Future<void> sendGif(RecentGif gif) async {
    final file = gif.file;
    if (gif.room == room.id && (file != null || !room.encrypted)) {
      await _sendGifByReference(gif, file);
      return;
    }
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final gifFile = await TelegramGifFile.file(gif, client: sendingClient);
    if (gifFile == null) {
      // No source event (left chat, or a row older than the event id) and no
      // cached file: there is nothing to upload. Drop the tile rather than
      // post a bubble nobody can open. T125: `tombstone: false` - the app
      // could not read the bytes, a user never said "I do not want this
      // GIF", so the row's source event must stay recordable (a re-open of
      // that chat, or an explicit "Add to gifs", can bring the tile back).
      await RecentGifs.remove(gif.url, room: gif.room, tombstone: false);
      return;
    }
    final Uint8List bytes;
    try {
      bytes = await gifFile.readAsBytes();
    } on Object catch (e) {
      debugPrint('[TelegramGif] cached file unreadable: $e');
      // T125: same reason as above - an unreadable cache is not a removal.
      await RecentGifs.remove(gif.url, room: gif.room, tombstone: false);
      return;
    }
    // T133 : a
    // Convert to gif clip replays as the kind of row it came from - a video that
    // carries the GIF marker - so the replayed bubble autostarts, muted and
    // looping, exactly like the send. Everything else replays as an animated
    // picture.
    final image = gif.video
        ? MatrixVideoFile(
            bytes: bytes,
            name: '${Uri.parse(gif.url).pathSegments.last}.${gif.fileExtension}',
            mimeType: gif.mimeType,
            width: gif.w > 0 ? gif.w : null,
            height: gif.h > 0 ? gif.h : null,
          )
        : MatrixImageFile(
      bytes: bytes,
      // T124: the extension follows the row's mimetype. matrix-dart picks an
      // image encoder from the file name in its resize path
      // (`matrix_file.dart:229-253`, `encodeNamedImage(fileName)`); this call
      // passes no shrink argument, so a `.gif` name on webp bytes is a wrong
      // hint rather than a wrong encode.
      name: '${Uri.parse(gif.url).pathSegments.last}.${gif.fileExtension}',
      // T124: not pinned to `image/gif` any more. The pin made a replayed WebP
      // GIF an event whose `info` claimed gif while its `file` said webp, and
      // other Matrix clients label the bubble from `info`; this fork hid the
      // mismatch because it sniffs magic bytes. T123 widened
      // `telegramEventIsGif()` to `image/webp` on an `m.image`, so the send is
      // still recognised as a GIF without the pin - the T56.2.1 reason for it
      // no longer holds.
      mimeType: gif.mimeType,
      width: gif.w > 0 ? gif.w : null,
      height: gif.h > 0 ? gif.h : null,
    );
    try {
      await room.sendFileEvent(
        image,
        // The marker rides along, or the replay is an ordinary video bubble.
        extraContent: gif.video ? {telegramMp4GifContentKey: true} : null,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(e.toLocalizedString(context))),
      );
    }
  }

  Future<void> _sendGifByReference(
    RecentGif gif,
    Map<String, Object?>? file,
  ) async {
    if (gif.video) {
      // T133: same media id, no re-upload, and the shape the row came from:
      // `m.video` plus `org.fluffygram.gif`. `info` carries no duration - the
      // store never kept one - and this fork hides the time badge on a marked
      // clip anyway (`events/video_player.dart`).
      await room.sendEvent(
        {
          'msgtype': 'm.video',
          'body': Uri.parse(gif.url).pathSegments.last,
          'url': gif.url,
          'info': {
            'mimetype': gif.mimeType,
            if (gif.w > 0 && gif.h > 0) ...{'w': gif.w, 'h': gif.h},
          },
          'file': ?file,
          telegramMp4GifContentKey: true,
        },
        type: EventTypes.Message,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      );
      return;
    }
    await room.sendEvent(
      {
        'msgtype': 'm.image',
        'body': Uri.parse(gif.url).pathSegments.last,
        'url': gif.url,
        'info': {
          // T124: the row's real type, so `info` and `file` never disagree.
          'mimetype': gif.mimeType,
          // With no known size this is exactly the T56.3 content.
          if (gif.w > 0 && gif.h > 0) ...{'w': gif.w, 'h': gif.h},
        },
        'file': ?file,
      },
      type: EventTypes.Message,
      threadRootEventId: activeThreadId,
      threadLastEventId: threadLastEventId,
    );
  }

  Future<void> sendFileAction({FileType type = FileType.any}) async {
    final files = await selectFiles(context, allowMultiple: true, type: type);
    if (files.isEmpty) return;
    if (!mounted) return;
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  Future<void> sendImageFromClipBoard(Uint8List? image) async {
    if (image == null) return;
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: [XFile.fromData(image)],
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  Future<void> openGalleryAction() async {
    inputFocus.unfocus();
    final files = await ImagePicker().pickMultipleMedia(
      requestFullMetadata: false,
    );
    // T129: also covers the cancel path - leaving the gallery with nothing
    // picked must not leave the keyboard open over an untouched composer.
    _dismissKeyboardAfterPicker();
    if (files.isEmpty) return;
    if (!mounted) return;

    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  Future<void> openCameraAction() async {
    inputFocus.unfocus();
    final file = await ImagePicker().pickImage(source: ImageSource.camera);
    _dismissKeyboardAfterPicker(); // T129
    if (file == null) return;
    if (!mounted) return;

    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: [file],
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  Future<void> _handleClipboardFilePasteWeb(web.Event event) async {
    if (event is! web.ClipboardEvent) return;

    final clipboardFiles = event.clipboardData?.files;
    final length = clipboardFiles?.length ?? 0;
    if (clipboardFiles == null || length < 1) return;

    // Browser will clear clipboardData when we await!
    // We MUST extract the files synchronously first.
    final localFiles = clipboardFiles.toList();

    if (localFiles.isEmpty) return;

    event.preventDefault();
    event.stopPropagation();

    final xFilesResult = await showFutureLoadingDialog(
      context: context,
      future: () async {
        // Convert one after another seems to be more stable
        final xFiles = <XFile>[];
        for (final file in localFiles) {
          xFiles.add(await webToXFile(file));
        }
        return xFiles;
      },
    );
    final xFiles = xFilesResult.result;
    if (xFiles == null || xFiles.isEmpty) return;

    if (!mounted) return;
    showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: xFiles,
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  Future<void> _handleClipboardImagePaste() async {
    final files = await Pasteboard.files();
    if (files.isNotEmpty) {
      if (!mounted) return;
      await showAdaptiveDialog(
        context: context,
        builder: (c) => SendFileDialog(
          files: files.map(XFile.new).toList(),
          room: room,
          outerContext: context,
          threadRootEventId: activeThreadId,
          threadLastEventId: threadLastEventId,
        ),
      );
      return;
    }
    final image = await Pasteboard.image;
    if (image != null) {
      await sendImageFromClipBoard(image);
      return;
    }
    // No image in clipboard — fall back to pasting text
    final textData = await Clipboard.getData('text/plain');
    if (textData?.text != null) {
      final selection = sendController.selection;
      final text = sendController.text;
      final newText = text.replaceRange(
        selection.start,
        selection.end,
        textData!.text!,
      );
      sendController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + textData.text!.length,
        ),
      );
      onInputBarChanged(sendController.text);
    }
  }

  Future<void> openVideoCameraAction() async {
    inputFocus.unfocus();
    final file = await ImagePicker().pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 1),
    );
    _dismissKeyboardAfterPicker(); // T129
    if (file == null) return;
    if (!mounted) return;

    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: [file],
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  Future<void> onVoiceMessageSend(
    String path,
    int duration,
    List<int> waveform,
    String fileName,
  ) async {
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!mounted || !proceed) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final bytesResult = await showFutureLoadingDialog(
      context: context,
      future: () => XFile(path).readAsBytes(),
    );
    final bytes = bytesResult.result;
    if (bytes == null) return;

    final mimeType = lookupMimeType(fileName, headerBytes: bytes);
    final extension = mimeType == null ? null : extensionFromMime(mimeType);
    if (extension != null) {
      fileName =
          'voice_message_${DateTime.now().millisecondsSinceEpoch}.$extension';
    }

    final file = MatrixAudioFile(
      bytes: bytes,
      name: fileName,
      mimeType: mimeType,
    );

    try {
      await room.sendFileEvent(
        file,
        inReplyTo: replyEvent,
        threadRootEventId: activeThreadId,
        extraContent: {
          'info': {...file.info, 'duration': duration},
          'org.matrix.msc3245.voice': {},
          'org.matrix.msc1767.audio': {
            'duration': duration,
            'waveform': waveform,
          },
        },
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(e.toLocalizedString(context))),
      );
      return;
    }
    setState(() {
      replyEvent = null;
    });
    return;
  }

  /// T129 (user, 2026-10-29: "Keyboard shouldn't auto pop up when I exit
  /// media gallery mode"). The `inputFocus.unfocus()` before a media pick does
  /// not survive the pick: the gallery/camera is a separate Android activity,
  /// and when ours resumes the system re-shows the soft keyboard for the window
  /// that held the text input connection. So the chat dismisses the keyboard
  /// AGAIN when the picker answer lands, and once more on the next frame for a
  /// resume that arrives after this callback.
  void _dismissKeyboardAfterPicker() {
    inputFocus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && inputFocus.hasFocus) inputFocus.unfocus();
    });
  }

  void hideEmojiPicker() {
    setState(() => showEmojiPicker = false);
  }

  void emojiPickerAction() {
    if (showEmojiPicker) {
      inputFocus.requestFocus();
    } else {
      inputFocus.unfocus();
    }
    setState(() => showEmojiPicker = !showEmojiPicker);
  }

  void _inputFocusListener() {
    if (showEmojiPicker && inputFocus.hasFocus) {
      setState(() => showEmojiPicker = false);
    }
  }

  Future<void> sendLocationAction() async {
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendLocationDialog(room: room),
    );
  }

  String _getSelectedEventString() {
    var copyString = '';
    if (selectedEvents.length == 1) {
      return selectedEvents.first.getDisplayEvent(timeline!).body;
    }
    for (final event in selectedEvents) {
      if (copyString.isNotEmpty) copyString += '\n\n';
      copyString += event.getDisplayEvent(timeline!).body;
    }
    return copyString;
  }

  void copyEventsAction() {
    Clipboard.setData(ClipboardData(text: _getSelectedEventString()));
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
  }

  Future<void> reportEventAction() async {
    final event = selectedEvents.single;
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (!mounted) return;
    final reason = await showTextInputDialog(
      context: context,
      title: l10n.whyDoYouWantToReportThis,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      hintText: l10n.reason,
    );
    if (reason == null || reason.isEmpty) return;
    if (!mounted) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => Matrix.of(
        context,
      ).client.reportEvent(event.roomId!, event.eventId, reason: reason),
    );
    if (result.error != null) return;
    if (!mounted) return;
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
    scaffoldMessenger.showSnackBar(
      SnackBar(content: Text(l10n.contentHasBeenReported)),
    );
  }

  Future<void> deleteErrorEventsAction() async {
    try {
      if (selectedEvents.any((event) => event.status != EventStatus.error)) {
        throw Exception(
          'Tried to delete failed to send events but one event is not failed to sent',
        );
      }
      for (final event in selectedEvents) {
        await event.cancelSend();
      }
      setState(selectedEvents.clear);
    } catch (e, s) {
      if (!mounted) return;
      ErrorReporter(
        context,
        'Error while delete error events action',
      ).onErrorCallback(e, s);
    }
  }

  Future<void> redactEventsAction() async {
    final reasonInput = selectedEvents.any((event) => event.status.isSent)
        ? await showTextInputDialog(
            context: context,
            title: L10n.of(context).redactMessage,
            message: L10n.of(context).redactMessageDescription,
            isDestructive: true,
            hintText: L10n.of(context).optionalRedactReason,
            maxLength: 255,
            maxLines: 3,
            minLines: 1,
            okLabel: L10n.of(context).remove,
            cancelLabel: L10n.of(context).cancel,
          )
        : null;
    if (reasonInput == null) return;
    final reason = reasonInput.isEmpty ? null : reasonInput;
    if (!mounted) return;
    await showFutureLoadingDialog(
      context: context,
      futureWithProgress: (onProgress) async {
        final count = selectedEvents.length;
        for (final (i, event) in selectedEvents.indexed) {
          onProgress(i / count);
          if (event.status.isSent) {
            if (event.canRedact) {
              await event.redactEvent(reason: reason);
            } else {
              final client = currentRoomBundle.firstWhere(
                (cl) => selectedEvents.first.senderId == cl!.userID,
                orElse: () => null,
              );
              if (client == null) {
                return;
              }
              final room = client.getRoomById(roomId)!;
              await Event.fromJson(
                event.toJson(),
                room,
              ).redactEvent(reason: reason);
            }
          } else {
            await event.cancelSend();
          }
        }
      },
    );
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
  }

  List<Client?> get currentRoomBundle {
    final clients = Matrix.of(context).currentBundle!;
    clients.removeWhere((c) => c!.getRoomById(roomId) == null);
    return clients;
  }

  bool get canRedactSelectedEvents {
    if (isArchived) return false;
    final clients = Matrix.of(context).currentBundle;
    for (final event in selectedEvents) {
      if (!event.status.isSent) return false;
      if (event.canRedact == false &&
          !(clients!.any((cl) => event.senderId == cl!.userID))) {
        return false;
      }
    }
    return true;
  }

  bool get canPinSelectedEvents {
    if (isArchived ||
        !room.canChangeStateEvent(EventTypes.RoomPinnedEvents) ||
        selectedEvents.length != 1 ||
        !selectedEvents.single.status.isSent ||
        activeThreadId != null) {
      return false;
    }
    return true;
  }

  bool get canEditSelectedEvents {
    if (isArchived ||
        selectedEvents.length != 1 ||
        !selectedEvents.first.status.isSent) {
      return false;
    }
    return currentRoomBundle.any(
      (cl) => selectedEvents.first.senderId == cl!.userID,
    );
  }

  Future<void> forwardEventsAction() async {
    if (selectedEvents.isEmpty) return;
    final timeline = this.timeline;
    if (timeline == null) return;

    final forwardEvents = List<Event>.from(
      selectedEvents,
    ).map((event) => event.getDisplayEvent(timeline)).toList();

    await showScaffoldDialog(
      context: context,
      builder: (context) => ShareScaffoldDialog(
        items: forwardEvents
            .map((event) => ContentShareItem(event.content.copy()))
            .toList(),
      ),
    );
    if (!mounted) return;
    setState(() => selectedEvents.clear());
  }

  void sendAgainAction() {
    final event = selectedEvents.first;
    if (event.status.isError) {
      event.sendAgain();
    }
    final allEditEvents = event
        .aggregatedEvents(timeline!, RelationshipTypes.edit)
        .where((e) => e.status.isError);
    for (final e in allEditEvents) {
      e.sendAgain();
    }
    setState(() => selectedEvents.clear());
  }

  void replyAction({Event? replyTo}) {
    setState(() {
      replyEvent = replyTo ?? selectedEvents.first;
      selectedEvents.clear();
    });
    inputFocus.requestFocus();
  }

  /// T40.3a: the in-chat search panel open flag. chat_view.dart renders the
  /// panel in the appbar's bottom slot, Telegram-style: the field row replaces
  /// the header title area and the list overlays the timeline.
  bool chatSearchOpen = false;

  void toggleChatSearch() {
    chatSearchOpen = !chatSearchOpen;
    setState(() {});
  }

  Future<void> scrollToEventId(
    String eventId, {
    bool highlightEvent = true,
    bool timelineReloaded = false,
  }) async {
    final foundEvent = timeline!.events.firstWhereOrNull(
      (event) => event.eventId == eventId,
    );

    final threadRootId =
        foundEvent?.relationshipType == RelationshipTypes.thread
        ? foundEvent?.relationshipEventId
        : null;
    if (activeThreadId == null && threadRootId != null) {
      return scrollToEventId(threadRootId, highlightEvent: highlightEvent);
    }

    final visibleEvents = timeline!.events.filterByVisibleInGui(
      exceptionEventId: eventId,
      threadId: activeThreadId,
    );
    final eventIndex = foundEvent == null
        ? -1
        : visibleEvents.indexOf(foundEvent);

    if (eventIndex == -1) {
      if (foundEvent != null || timelineReloaded) return;
      setState(() {
        timeline = null;
        _scrolledUp = false;
        loadTimelineFuture = _getTimeline(eventContextId: eventId).onError(
          ErrorReporter(
            context,
            'Unable to load timeline after scroll to ID',
          ).onErrorCallback,
        );
      });
      await loadTimelineFuture;
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        scrollToEventId(
          eventId,
          highlightEvent: highlightEvent,
          timelineReloaded: true,
        );
      });
      return;
    }
    if (highlightEvent) {
      setState(() {
        scrollToEventIdMarker = eventId;
        scrollToEventIdMarkerToken++;
      });
      _jumpHighlightTimer?.cancel();
      _jumpHighlightTimer = Timer(const Duration(milliseconds: 1000), () {
        if (mounted) setState(() => scrollToEventIdMarker = null);
      });
    }
    // A photo that draws inside an album has no row of its own: the run's
    // anchor row draws its mosaic (roadmap T7). Ask the cluster which row
    // actually draws this event, so a jump to a hidden member lands on the
    // album instead of on that member's empty slot. Selection mode draws every
    // event on its own row, so there the index stays as it is.
    final scrollIndex = telegramAlbumGridEnabled && selectedEvents.isEmpty
        ? TelegramAlbumCluster.of(visibleEvents).scrollTargetIndexAt(eventIndex)
        : eventIndex;
    // Owner phone pass on build 49 (2026-10-28): "when scrolling to a message,
    // make it smoother". Telegram's jump scroller runs at a fixed speed and
    // decelerates into the centred target over a 400 ms base per screenful
    // (`LinearSmoothScrollerCustom.java:73`, `DecelerateInterpolator(1.5f)`,
    // via `ChatActivity.java:6627-6631`). The `scroll_to_index` package runs
    // its seek hops at `Curves.ease` with no curve parameter (its
    // `scrollToIndex` takes only `duration` and `preferPosition` - checked in
    // `scroll_to_index-3.0.1/lib/scroll_to_index.dart:75-90,243`), so the
    // lever here is the duration: 250 -> 350 ms slows every hop, most of all
    // the final decelerating one.
    await scrollController.scrollToIndex(
      scrollIndex + 1,
      duration: const Duration(milliseconds: 350),
      preferPosition: AutoScrollPosition.middle,
    );
    _updateScrollController();
  }

  Future<void> scrollDown() async {
    if (!timeline!.allowNewEvent) {
      setState(() {
        timeline = null;
        _scrolledUp = false;
        loadTimelineFuture = _getTimeline().onError(
          ErrorReporter(
            context,
            'Unable to load timeline after scroll down',
          ).onErrorCallback,
        );
      });
      await loadTimelineFuture;
    }
    // Owner phone pass on build 49 (2026-10-28): the scroll-to-bottom button
    // must "animate it in the same way, and make it smooth" - this was a
    // `jumpTo`, an instant teleport. Telegram's list scrollers run at a fixed
    // speed (~400 ms per screenful on a user's Pixel, `0.37 ms/px`,
    // `LinearSmoothScrollerCustom.java:73`), so the duration is proportional
    // to the distance travelled - the exact figure here, since the bottom
    // distance is `offset` - clamped to [250, 750] ms, decelerating into the
    // end like the jump above.
    final distance = scrollController.hasClients
        ? scrollController.offset
        : 0.0;
    if (distance <= 1.0) return;
    scrollController.animateTo(
      0,
      duration: Duration(
        milliseconds: (distance * 0.37).clamp(250.0, 750.0).round(),
      ),
      curve: Curves.easeOutCubic,
    );
  }

  void onEmojiSelected(_, Emoji? emoji) {
    typeEmoji(emoji);
    onInputBarChanged(sendController.text);
  }

  void typeEmoji(Emoji? emoji) {
    if (emoji == null) return;
    final text = sendController.text;
    final selection = sendController.selection;
    final start = selection.baseOffset == -1 ? 0 : selection.baseOffset;
    final newText = sendController.text.isEmpty
        ? emoji.emoji
        : text.replaceRange(selection.start, selection.end, emoji.emoji);
    sendController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        // don't forget an UTF-8 combined emoji might have a length > 1
        offset: start + emoji.emoji.length,
      ),
    );
  }

  void emojiPickerBackspace() {
    sendController
      ..text = sendController.text.characters.skipLast(1).toString()
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: sendController.text.length),
      );
  }

  void clearSelectedEvents() => setState(() {
    selectedEvents.clear();
    showEmojiPicker = false;
  });

  void clearSingleSelectedEvent() {
    if (selectedEvents.length <= 1) {
      clearSelectedEvents();
    }
  }

  void _startEditingEvent(Event event, {bool clearSelection = false}) {
    final timeline = this.timeline;
    if (timeline == null) return;

    final client = currentRoomBundle.firstWhere(
      (c) => c?.userID == event.senderId,
      orElse: () => null,
    );
    if (client == null) return;

    setSendingClient(client);
    setState(() {
      pendingText = sendController.text;
      editEvent = event;
      sendController.text = event
          .getDisplayEvent(timeline)
          .calcLocalizedBodyFallback(
            MatrixLocals(L10n.of(context)),
            withSenderNamePrefix: false,
            hideReply: true,
          );
      if (clearSelection) selectedEvents.clear();
    });
    inputFocus.requestFocus();
  }

  void editSelectedEventAction() {
    _startEditingEvent(selectedEvents.first, clearSelection: true);
  }

  void _editLastSentMessage() {
    final timeline = this.timeline;
    if (timeline == null) return;

    final events = timeline.events.filterByVisibleInGui(
      threadId: activeThreadId,
    );

    final lastOwnMessage = events.firstWhereOrNull(
      (e) =>
          e.type == EventTypes.Message &&
          e.messageType == MessageTypes.Text &&
          e.status.isSent &&
          !e.redacted &&
          currentRoomBundle.any((c) => c?.userID == e.senderId),
    );

    if (lastOwnMessage == null) return;

    _startEditingEvent(lastOwnMessage);
  }

  Future<void> goToNewRoomAction() async {
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final users = await room.requestParticipants(
          [Membership.join, Membership.leave],
          true,
          false,
        );
        users.sort((a, b) => a.powerLevel.level.compareTo(b.powerLevel.level));
        final via = users
            .map((user) => user.id.domain)
            .whereType<String>()
            .toSet()
            .take(10)
            .toList();
        return room.client.joinRoom(
          room
              .getState(EventTypes.RoomTombstone)!
              .parsedTombstoneContent
              .replacementRoom,
          via: via,
        );
      },
    );
    if (result.error != null) return;
    if (!mounted) return;
    context.go('/rooms/${result.result!}');

    await showFutureLoadingDialog(context: context, future: room.leave);
  }

  void onSelectMessage(Event event) {
    if (!event.redacted) {
      if (selectedEvents.contains(event)) {
        setState(() => selectedEvents.remove(event));
      } else {
        setState(() => selectedEvents.add(event));
      }
      selectedEvents.sort(
        (a, b) => a.originServerTs.compareTo(b.originServerTs),
      );
    }
  }

  int? findChildIndexCallback(Key key, Map<String, int> thisEventsKeyMap) {
    // this method is called very often. As such, it has to be optimized for speed.
    if (key is! ValueKey) {
      return null;
    }
    final eventId = key.value;
    if (eventId is! String) {
      return null;
    }
    // first fetch the last index the event was at
    final index = thisEventsKeyMap[eventId];
    if (index == null) {
      return null;
    }
    // we need to +1 as 0 is the typing thing at the bottom
    return index + 1;
  }

  void onInputBarSubmitted(String _) {
    send();
    FocusScope.of(context).requestFocus(inputFocus);
  }

  void onAddPopupMenuButtonSelected(AddPopupMenuActions choice) {
    room.client.getConfig();

    switch (choice) {
      case AddPopupMenuActions.file:
        sendFileAction();
        return;
      case AddPopupMenuActions.image:
        sendFileAction(type: FileType.image);
        return;
      case AddPopupMenuActions.video:
        sendFileAction(type: FileType.video);
        return;
      case AddPopupMenuActions.poll:
        showAdaptiveBottomSheet(
          context: context,
          builder: (context) => StartPollBottomSheet(room: room),
        );
        return;
      case AddPopupMenuActions.photoCamera:
        openCameraAction();
        return;
      case AddPopupMenuActions.videoCamera:
        openVideoCameraAction();
        return;
      case AddPopupMenuActions.location:
        sendLocationAction();
        return;
    }
  }

  Future<void> unpinEvent(String eventId) async {
    final response = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).unpin,
      message: L10n.of(context).confirmEventUnpin,
      okLabel: L10n.of(context).unpin,
      cancelLabel: L10n.of(context).cancel,
    );
    if (!mounted) return;
    if (response == OkCancelResult.ok) {
      final events = room.pinnedEventIds
        ..removeWhere((oldEvent) => oldEvent == eventId);
      showFutureLoadingDialog(
        context: context,
        future: () => room.setPinnedEvents(events),
      );
    }
  }

  void pinEvent() {
    final pinnedEventIds = room.pinnedEventIds;
    final selectedEventIds = selectedEvents.map((e) => e.eventId).toSet();
    final unpin =
        selectedEventIds.length == 1 &&
        pinnedEventIds.contains(selectedEventIds.single);
    if (unpin) {
      pinnedEventIds.removeWhere(selectedEventIds.contains);
    } else {
      pinnedEventIds.addAll(selectedEventIds);
    }
    showFutureLoadingDialog(
      context: context,
      future: () => room.setPinnedEvents(pinnedEventIds),
    );
  }

  Timer? _storeInputTimeoutTimer;
  static const Duration _storeInputTimeout = Duration(milliseconds: 500);

  double? inputBarHeight;

  void updateInputBarHeight() {
    RenderBox? renderBox;
    if (inputBarKey.currentContext?.findRenderObject() != null) {
      renderBox = inputBarKey.currentContext!.findRenderObject() as RenderBox;
    }

    final height = renderBox?.size.height ?? 72.0;
    if (height != inputBarHeight) {
      setState(() {
        inputBarHeight = height;
      });
    }
  }

  void onInputBarChanged(String text) {
    if (_inputTextIsEmpty != text.isEmpty) {
      setState(() {
        _inputTextIsEmpty = text.isEmpty;
      });
    }

    _storeInputTimeoutTimer?.cancel();
    _storeInputTimeoutTimer = Timer(_storeInputTimeout, () async {
      final prefs = Matrix.of(context).store;
      await prefs.setString('draft_$roomId', text);
    });
    if (text.endsWith(' ') && Matrix.of(context).hasComplexBundles) {
      final clients = currentRoomBundle;
      for (final client in clients) {
        final prefix = client!.sendPrefix;
        if ((prefix.isNotEmpty) &&
            text.toLowerCase() == '${prefix.toLowerCase()} ') {
          setSendingClient(client);
          setState(() {
            sendController.clear();
          });
          return;
        }
      }
    }
    if (AppSettings.sendTypingNotifications.value) {
      typingCoolDown?.cancel();
      typingCoolDown = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        typingCoolDown = null;
        currentlyTyping = false;
        room.setTyping(false);
      });
      typingTimeout ??= Timer(const Duration(seconds: 30), () {
        typingTimeout = null;
        currentlyTyping = false;
      });
      if (!currentlyTyping) {
        currentlyTyping = true;
        room.setTyping(
          true,
          timeout: const Duration(seconds: 30).inMilliseconds,
        );
      }
    }
  }

  bool _inputTextIsEmpty = true;

  bool get isArchived =>
      {Membership.leave, Membership.ban}.contains(room.membership);

  void showEventInfo([Event? event]) =>
      (event ?? selectedEvents.single).showInfoDialog(context);

  void cancelReplyEventAction() => setState(() {
    if (editEvent != null) {
      sendController.text = pendingText;
      pendingText = '';
    }
    replyEvent = null;
    editEvent = null;
  });

  void startOrJoinVideoCall() {
    Matrix.of(context).activeCallRoomId.value = room.id;
  }

  bool supportLiveKitCalls = false;

  Future<void> _cancelEditWithConfirmation() async {
    final originalText = editEvent!
        .getDisplayEvent(timeline!)
        .calcLocalizedBodyFallback(
          MatrixLocals(L10n.of(context)),
          withSenderNamePrefix: false,
          hideReply: true,
        );

    if (sendController.text != originalText) {
      final result = await showOkCancelAlertDialog(
        context: context,
        title: L10n.of(context).areYouSure,
        message: L10n.of(context).discardEdits,
        okLabel: L10n.of(context).ok,
        cancelLabel: L10n.of(context).cancel,
      );
      if (result == OkCancelResult.cancel) return;
    }

    cancelReplyEventAction();
  }

  late final ValueNotifier<bool> _displayChatDetailsColumn;

  Future<void> toggleDisplayChatDetailsColumn() async {
    await AppSettings.displayChatDetailsColumn.setItem(
      !_displayChatDetailsColumn.value,
    );
    _displayChatDetailsColumn.value = !_displayChatDetailsColumn.value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Actions(
      actions: kIsWeb
          ? {}
          : <Type, Action<Intent>>{
              PasteTextIntent: CallbackAction<PasteTextIntent>(
                onInvoke: (PasteTextIntent intent) =>
                    _handleClipboardImagePaste(),
              ),
            },
      child: Row(
        children: [
          Expanded(child: ChatView(this)),
          ValueListenableBuilder(
            valueListenable: _displayChatDetailsColumn,
            builder: (context, displayChatDetailsColumn, _) =>
                !FluffyThemes.isThreeColumnMode(context) ||
                    room.membership != Membership.join ||
                    !displayChatDetailsColumn
                ? const SizedBox(height: double.infinity, width: 0)
                : Container(
                    width: FluffyThemes.columnWidth,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(width: 1, color: theme.dividerColor),
                      ),
                    ),
                    child: ChatDetails(
                      roomId: roomId,
                      embeddedCloseButton: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: toggleDisplayChatDetailsColumn,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

enum AddPopupMenuActions {
  image,
  video,
  file,
  poll,
  photoCamera,
  videoCamera,
  location,
}
