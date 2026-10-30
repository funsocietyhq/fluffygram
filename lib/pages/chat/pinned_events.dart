// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/pinned_message_bar.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Value prefix that turns an entry of the pinned-messages sheet into an unpin
/// action instead of a jump. Telegram's own sheet does the same thing: each row
/// can be opened or unpinned.
const _unpinActionPrefix = 'unpin:';

class PinnedEvents extends StatelessWidget {
  final ChatController controller;

  const PinnedEvents(this.controller, {super.key});

  String _preview(BuildContext context, Event? event) =>
      event
          ?.calcLocalizedBodyFallback(
            MatrixLocals(L10n.of(context)),
            withSenderNamePrefix: true,
            hideReply: true,
          )
          .replaceAll('\n', ' ') ??
      L10n.of(context).loadingPleaseWait;

  Future<void> _displayPinnedEventsDialog(BuildContext context) async {
    final l10n = L10n.of(context);
    final eventsResult = await showFutureLoadingDialog(
      context: context,
      future: () => Future.wait(
        controller.room.pinnedEventIds.map(
          (eventId) => controller.room.getEventById(eventId),
        ),
      ),
    );
    final events = eventsResult.result;
    if (events == null) return;
    if (!context.mounted) return;

    // Telegram's pinned-messages sheet: one row jumps, one row unpins. An id
    // arrives from the jump rows, an `unpin:` value from the unpin rows.
    final canPin = controller.room.canSendEvent(EventTypes.RoomPinnedEvents);
    final action = await showModalActionPopup<String>(
      context: context,
      title: l10n.pin,
      cancelLabel: l10n.cancel,
      actions: [
        for (final event in events)
          AdaptiveModalAction(
            value: event?.eventId ?? '',
            icon: const Icon(Icons.push_pin_outlined),
            label: _preview(context, event),
          ),
        if (canPin)
          for (final event in events)
            if (event != null)
              AdaptiveModalAction(
                value: '$_unpinActionPrefix${event.eventId}',
                icon: const Icon(Icons.push_pin),
                label: '${l10n.unpin} ${_preview(context, event)}',
                isDestructive: true,
              ),
      ],
    );

    if (action == null) return;
    if (action.startsWith(_unpinActionPrefix)) {
      await controller.unpinEvent(action.substring(_unpinActionPrefix.length));
      return;
    }
    controller.scrollToEventId(action);
  }

  @override
  Widget build(BuildContext context) {
    final pinnedEventIds = controller.room.pinnedEventIds;

    if (pinnedEventIds.isEmpty || controller.activeThreadId != null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<Event?>(
      future: controller.room.getEventById(pinnedEventIds.last),
      builder: (context, snapshot) {
        final event = snapshot.data;
        return PinnedMessageBar(
          leading: FutureBuilder<User?>(
            // Telegram's leading element is the avatar of the sender of the
            // pinned message, not a pin glyph.
            future: event?.fetchSenderUser(),
            initialData: event?.senderFromMemoryOrFallback,
            builder: (context, snapshot) {
              final user = snapshot.data ?? event?.senderFromMemoryOrFallback;
              return Avatar(
                mxContent: user?.avatarUrl,
                name: user?.calcDisplayname() ?? '',
                size: PinnedMessageBar.avatarSize,
              );
            },
          ),
          label: L10n.of(context).pinnedMessage,
          preview: _preview(context, event),
          pinCount: pinnedEventIds.length,
          onTap: () => _displayPinnedEventsDialog(context),
          onOpenPinList: () => _displayPinnedEventsDialog(context),
        );
      },
    );
  }
}
