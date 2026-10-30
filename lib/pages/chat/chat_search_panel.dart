// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// T40.3a: Telegram's in-chat search. The header's title row turns into a
// query field, a tab row picks the content type, and a list of result rows
// overlays the timeline under the header. Measured geometry:
// the measurement log `## T40.3` (ChatActivity.java:7605-7638, 7832-7838;
// ChatSearchTabs.java; ChatActivitySearchContainer.java). Constants marked
// PROVISIONAL have no number in the reference tree (the tree's tab strip is
// the hashtag flow; the content-type tab labels are a fork design decision).

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'dart:async';

import 'package:fluffychat/config/telegram_palette.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Geometry for [TelegramChatSearchPanel].
class TelegramSearchPanel {
  /// Tab row height. Measured: ChatActivity.java:7838 (`50`).
  static const double tabRowHeight = 50;

  /// Tab row vertical padding. Measured: ChatActivity.java:7833 (`dp(7.66f)`).
  static const double tabRowVerticalPadding = 7.66;

  /// Tab pill corner radius. Measured: ChatActivity.java:7836 (`dp(18)`).
  static const double tabPillRadius = 18;

  /// Tab strip background padding. Measured: ChatActivity.java:7836
  /// (`setPadding(dp(7f))`).
  static const double tabPillPadding = 7;

  /// Panel fade zone. Measured: ChatActivitySearchContainer.java
  /// (`setFadeHeightTop(dp(48))`). PROVISIONAL: the fork clips the list
  /// instead of drawing a gradient fade.
  static const double fadeHeight = 48;

  /// Query field row height. PROVISIONAL.
  static const double fieldRowHeight = 56;

  /// Horizontal margin of the field row and the tab row. PROVISIONAL.
  static const double rowHorizontalMargin = 8;

  /// Result row vertical padding. PROVISIONAL.
  static const double resultRowVerticalPadding = 8;

  /// Sender name font size. PROVISIONAL.
  static const double senderFontSize = 14;

  /// Result body font size. PROVISIONAL.
  static const double bodyFontSize = 15;

  /// Result time font size. PROVISIONAL.
  static const double timeFontSize = 12;

  /// Panel height as a fraction of the screen. PROVISIONAL (the reference
  /// panel is MATCH_PARENT over the timeline; the fork leaves the composer
  /// visible).
  static const double panelHeightFactor = 0.6;

  /// Max results per query. PROVISIONAL (RoomEventsCriteria has no limit
  /// field in matrix-14.1.0; the cap is client-side, in _search).
  static const int resultLimit = 50;

  /// Query debounce. Telegram searches live; the brief pins 300 ms.
  static const Duration debounce = Duration(milliseconds: 300);
}

/// One content-type tab. `msgTypes == null` accepts every msgtype; `links`
/// filters on the body client-side (Matrix search has no link filter).
class TelegramSearchTab {
  const TelegramSearchTab(this.name, {this.msgTypes, this.links = false});

  /// Stable identity of the tab. The pill label is a translated string: see
  /// [label].
  final String name;
  final Set<String>? msgTypes;
  final bool links;

  /// Telegram's own words for these sections: `FilterAllChatsShort`
  /// (strings.xml:3052) "All", `MediaTab` (6180) "Media", `Files` (6181)
  /// "Files", `SharedLinks` (2054) "Links", `SharedVoiceTab2` (3176)
  /// "Voice" - see the measurement log `## T42`.
  String label(L10n l10n) => switch (name) {
    'All' => l10n.searchTabAll,
    'Media' => l10n.searchTabMedia,
    'Files' => l10n.searchTabFiles,
    'Links' => l10n.searchTabLinks,
    _ => l10n.searchTabVoice,
  };
}

/// The shipped tab row (fork design decision, see the measurement log
/// `## T40.3`): labels All / Media / Files / Links / Voice.
const List<TelegramSearchTab> kTelegramSearchTabs = [
  TelegramSearchTab('All'),
  TelegramSearchTab('Media', msgTypes: {'m.image', 'm.video', 'm.sticker'}),
  TelegramSearchTab('Files', msgTypes: {'m.file'}),
  TelegramSearchTab('Links', links: true),
  TelegramSearchTab('Voice', msgTypes: {'m.audio'}),
];

/// The in-chat search panel: field row, tab row, result list. Rendered by
/// chat_view.dart in the appbar's bottom slot; hidden while [open] is false.
class TelegramChatSearchPanel extends StatefulWidget {
  const TelegramChatSearchPanel({
    required this.controller,
    required this.onClose,
    required this.open,
    super.key,
  });

  final ChatController controller;
  final VoidCallback onClose;
  final bool open;

  @override
  State<TelegramChatSearchPanel> createState() =>
      _TelegramChatSearchPanelState();
}

class _TelegramChatSearchPanelState extends State<TelegramChatSearchPanel> {
  final TextEditingController _field = TextEditingController();
  Timer? _debounce;
  int _requestSeq = 0;
  int _tabIndex = 0;
  bool _loading = false;
  List<Event> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(TelegramSearchPanel.debounce, () => _search(query));
  }

  Future<void> _search(String query) async {
    final seq = ++_requestSeq;
    if (query.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _loading = true);
    var found = const <Event>[];
    try {
      // matrix-14.1.0 MatrixApi.search posts /_matrix/client/v3/search
      // (matrix_api_lite/generated/api.dart:5236). Matrix search is global;
      // the room filter is client-side (decision, the measurement log
      // T40.3).
      final response = await widget.controller.room.client.search(
        Categories(roomEvents: RoomEventsCriteria(searchTerm: query)),
      );
      final room = widget.controller.room;
      found = (response.searchCategories.roomEvents?.results ?? [])
          .map((r) => r.result!)
          .where((j) => j.roomId == room.id)
          .take(TelegramSearchPanel.resultLimit)
          .map((j) => Event.fromJson(j.toJson(), room))
          .toList();
    } catch (_) {
      found = const [];
    }
    if (seq != _requestSeq) return;
    // Stale answer: a newer query is in flight.
    if (mounted) setState(() => _results = found);
  }

  List<Event> get _visibleResults {
    final tab = kTelegramSearchTabs[_tabIndex];
    return _results.where((e) {
      if (tab.links) {
        final body = e.body;
        return body.contains('http://') || body.contains('https://');
      }
      final types = tab.msgTypes;
      if (types == null) return true;
      return types.contains(e.content['msgtype'] as String?);
    }).toList();
  }

  void _openResult(Event event) {
    widget.onClose();
    widget.controller.scrollToEventId(event.eventId);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final results = _visibleResults;
    return SizedBox(
      height:
          MediaQuery.sizeOf(context).height *
          TelegramSearchPanel.panelHeightFactor,
      child: Material(
        color: TelegramPalette.surfaceRaised,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: TelegramSearchPanel.fieldRowHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TelegramSearchPanel.rowHorizontalMargin,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      size: 20,
                      color: TelegramPalette.textTertiary,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _field,
                        autofocus: true,
                        style: const TextStyle(fontSize: 16),
                        decoration: InputDecoration(
                          hintText: L10n.of(context).search,
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: _onQueryChanged,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: L10n.of(context).close,
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: TelegramSearchPanel.tabRowHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  vertical: TelegramSearchPanel.tabRowVerticalPadding,
                  horizontal: TelegramSearchPanel.rowHorizontalMargin,
                ),
                children: [
                  for (var i = 0; i < kTelegramSearchTabs.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: i == _tabIndex
                              ? theme.colorScheme.primary
                              : TelegramPalette.searchFieldBackground,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(TelegramSearchPanel.tabPillRadius),
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: const BorderRadius.all(
                              Radius.circular(
                                TelegramSearchPanel.tabPillRadius,
                              ),
                            ),
                            onTap: () => setState(() => _tabIndex = i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: TelegramSearchPanel.tabPillPadding,
                              ),
                              child: Center(
                                child: Text(
                                  kTelegramSearchTabs[i].label(l10n),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: i == _tabIndex
                                        ? theme.colorScheme.onPrimary
                                        : TelegramPalette.textTertiary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : results.isEmpty
                  ? Center(
                      child: Text(
                        L10n.of(context).noResults,
                        style: TextStyle(
                          color: TelegramPalette.textTertiary,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, index) =>
                          _resultRow(theme, results[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultRow(ThemeData theme, Event event) {
    final sender = event.senderFromMemoryOrFallback;
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(event.originServerTs));
    return InkWell(
      onTap: () => _openResult(event),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TelegramSearchPanel.rowHorizontalMargin,
          vertical: TelegramSearchPanel.resultRowVerticalPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    sender.displayName ?? event.senderId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: TelegramSearchPanel.senderFontSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  time,
                  style: TextStyle(
                    color: TelegramPalette.textTertiary,
                    fontSize: TelegramSearchPanel.timeFontSize,
                  ),
                ),
              ],
            ),
            Text(
              event.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TelegramSearchPanel.bodyFontSize,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
