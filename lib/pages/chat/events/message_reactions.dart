// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:collection/collection.dart' show IterableExtension;
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

// T48 - the reaction pill, from Telegram's in-bubble reaction row
// `ui/Components/Reactions/ReactionsLayoutInBubble.java`. The pill is a 26 dp
// capsule: radius = height / 2 (`float rad = height / 2f;`, :998, :1111).
const double reactionPillHeight =
    26; // ReactionsLayoutInBubble.java:360, :381, :429
const double reactionPillSpacing = 4; // ReactionsLayoutInBubble.java:387, :393
const double reactionCounterFontSize = 12; // ReactionsLayoutInBubble.java:85
const FontWeight reactionCounterFontWeight =
    FontWeight.bold; // ReactionsLayoutInBubble.java:86

class MessageReactions extends StatelessWidget {
  final Event event;
  final Timeline timeline;

  const MessageReactions(this.event, this.timeline, {super.key});

  @override
  Widget build(BuildContext context) {
    final allReactionEvents = event.aggregatedEvents(
      timeline,
      RelationshipTypes.reaction,
    );
    final reactionMap = <String, _ReactionEntry>{};
    final client = Matrix.of(context).client;

    for (final e in allReactionEvents) {
      final key = e.content
          .tryGetMap<String, Object?>('m.relates_to')
          ?.tryGet<String>('key');
      if (key != null) {
        if (!reactionMap.containsKey(key)) {
          reactionMap[key] = _ReactionEntry(
            key: key,
            count: 0,
            reacted: false,
            reactors: [],
          );
        }
        reactionMap[key]!.count++;
        reactionMap[key]!.reactors!.add(e.senderFromMemoryOrFallback);
        reactionMap[key]!.reacted |= e.senderId == e.room.client.userID;
      }
    }

    final reactionList = reactionMap.values.toList();
    reactionList.sort((a, b) => b.count - a.count > 0 ? 1 : -1);
    final ownMessage = event.senderId == event.room.client.userID;
    return Wrap(
      spacing: reactionPillSpacing,
      runSpacing: reactionPillSpacing,
      alignment: ownMessage ? WrapAlignment.end : WrapAlignment.start,
      children: [
        ...reactionList.map(
          (r) => _Reaction(
            reactionKey: r.key,
            count: r.count,
            onTap: () {
              if (r.reacted) {
                final evt = allReactionEvents.firstWhereOrNull(
                  (e) =>
                      e.senderId == e.room.client.userID &&
                      e.content.tryGetMap('m.relates_to')?['key'] == r.key,
                );
                if (evt != null) {
                  showFutureLoadingDialog(
                    context: context,
                    future: evt.redactEvent,
                  );
                }
              } else {
                event.room.sendReaction(event.eventId, r.key);
              }
            },
            onLongPress: () async => await _AdaptableReactorsDialog(
              client: client,
              reactionEntry: r,
            ).show(context),
          ),
        ),
      ],
    );
  }
}

class _Reaction extends StatelessWidget {
  final String reactionKey;
  final int count;
  final void Function()? onTap;
  final void Function()? onLongPress;

  const _Reaction({
    required this.reactionKey,
    required this.count,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget content;
    if (reactionKey.startsWith('mxc://')) {
      content = MxcImage(
        uri: Uri.parse(reactionKey),
        width: 20,
        height: 20,
        animated: false,
        isThumbnail: false,
      );
    } else {
      var renderKey = Characters(reactionKey);
      if (renderKey.length > 10) {
        renderKey = renderKey.getRange(0, 9) + Characters('…');
      }
      content = Text(renderKey.toString(), style: TextStyle(fontSize: 14));
    }
    return Badge(
      isLabelVisible: count > 1,
      // Telegram's counter is dp(12) bold (ReactionsLayoutInBubble.java:85-86).
      label: Text(
        count.toString(),
        style: const TextStyle(
          fontSize: reactionCounterFontSize,
          fontWeight: reactionCounterFontWeight,
        ),
      ),
      textColor: theme.colorScheme.onPrimary,
      backgroundColor: theme.colorScheme.primary.withAlpha(200),
      child: InkWell(
        onTap: () => onTap != null ? onTap!() : null,
        onLongPress: () => onLongPress != null ? onLongPress!() : null,
        borderRadius: BorderRadius.circular(reactionPillHeight / 2),
        child: Container(
          // Telegram fills the pill and draws no outline (`drawRoundRect(..., paint)`
          // at ReactionsLayoutInBubble.java:1138; no STROKE on the pill path), so
          // the reacted ring is gone: Telegram marks reacted with a colour pair the
          // local theme files lack (see the measurement log T48).
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(reactionPillHeight / 2),
          ),
          height: reactionPillHeight,
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: content,
        ),
      ),
    );
  }
}

class _ReactionEntry {
  String key;
  int count;
  bool reacted;
  List<User>? reactors;

  _ReactionEntry({
    required this.key,
    required this.count,
    required this.reacted,
    this.reactors,
  });
}

class _AdaptableReactorsDialog extends StatelessWidget {
  final Client? client;
  final _ReactionEntry? reactionEntry;

  const _AdaptableReactorsDialog({this.client, this.reactionEntry});

  Future<bool?> show(BuildContext context) => showDialog(
    context: context,
    builder: (context) => this,
    barrierDismissible: true,
    useRootNavigator: false,
  );

  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(
      child: Wrap(
        spacing: 8.0,
        runSpacing: 4.0,
        alignment: WrapAlignment.center,
        children: <Widget>[
          for (final reactor in reactionEntry!.reactors!)
            Chip(
              avatar: Avatar(
                mxContent: reactor.avatarUrl,
                name: reactor.displayName,
                client: client,
                presenceUserId: reactor.stateKey,
              ),
              label: Text(reactor.displayName!),
            ),
        ],
      ),
    );

    final title = Center(child: Text(reactionEntry!.key));

    return AlertDialog(title: title, content: body);
  }
}
