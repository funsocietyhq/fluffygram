// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The text draft the chat page keeps for one chat under the
/// `draft_<room id>` key of `Matrix.of(context).store` (see
/// `lib/pages/chat/chat.dart`). The chat list shows it as Telegram does -
/// "Draft:" plus the saved text, in place of the last-event preview - so this
/// widget reads the stored string and hands it to [builder].
///
/// The store answers from its in-memory copy, so one read is cheap: it runs in
/// [initState] and on every row rebuild (a send, an incoming event, a draft
/// write on leaving the chat).
class ChatListDraft extends StatefulWidget {
  const ChatListDraft({required this.room, required this.builder, super.key});

  final Room room;

  /// The draft body Telegram shows in the chat-list preview is cut at 150
  /// characters before the row's own ellipsis: `DialogCell.java:1635`
  /// (`mess.length() > 150 -> mess.subSequence(0, 150)`).
  static const int maxDraftBodyChars = 150;

  /// Called with the saved draft on one line, or null when the chat has none.
  final Widget Function(BuildContext context, String? draft) builder;

  @override
  State<ChatListDraft> createState() => _ChatListDraftState();
}

class _ChatListDraftState extends State<ChatListDraft> {
  String? _draft;

  /// The store answers from its in-memory copy, so one read is cheap.
  String? _readDraft() {
    final stored = Matrix.of(
      context,
    ).store.getString('draft_${widget.room.id}');
    final draft = stored?.trim().replaceAll('\n', ' ');
    if (draft == null || draft.isEmpty) return null;
    if (draft.length > ChatListDraft.maxDraftBodyChars) {
      return draft.substring(0, ChatListDraft.maxDraftBodyChars);
    }
    return draft;
  }

  @override
  void initState() {
    super.initState();
    _draft = _readDraft();
  }

  @override
  void didUpdateWidget(ChatListDraft oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      _draft = _readDraft();
      return;
    }
    // The row rebuilds on every room update, which is also when the chat page
    // writes a draft (on leaving) and when a send clears one (on sending).
    final draft = _readDraft();
    if (draft != _draft) setState(() => _draft = draft);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _draft);
}
