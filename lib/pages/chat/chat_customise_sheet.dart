// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/widgets/chat_background_picker_sheet.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Telegram's chat-header "Customise" sheet: Background / Notifications /
/// Permissions. Background opens the picker scoped to this chat; the other two
/// rows open screens this fork already ships - the chat details page carries
/// this room's mute control, the permissions page its power levels. The room id
/// is all the sheet reads, and the background pick is device-local: no row here
/// writes room state.
Future<void> showChatCustomiseSheet(BuildContext context, Room room) async {
  final roomId = room.id;
  await showAdaptiveBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.wallpaper_outlined),
            title: Text(L10n.of(sheetContext).background),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showChatBackgroundPicker(context: context, roomId: roomId);
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(L10n.of(sheetContext).notifications),
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.go('/rooms/$roomId/details');
            },
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text(L10n.of(sheetContext).chatPermissions),
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.go('/rooms/$roomId/details/permissions');
            },
          ),
        ],
      ),
    ),
  );
}
