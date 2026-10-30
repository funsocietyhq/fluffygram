// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/telegram_palette.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_geometry.dart';
import 'package:fluffychat/pages/chat_list/client_chooser_button.dart';
import 'package:fluffychat/utils/sync_status_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';

class ChatListHeader extends StatelessWidget implements PreferredSizeWidget {
  final ChatListController controller;
  final bool globalSearch;

  const ChatListHeader({
    super.key,
    required this.controller,
    this.globalSearch = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final isColumnMode = FluffyThemes.isColumnMode(context);

    return SliverAppBar(
      floating: true,
      toolbarHeight: 72,
      pinned: isColumnMode,
      scrolledUnderElevation: 0,
      shape: isColumnMode
          ? Border(bottom: BorderSide(color: theme.dividerColor, width: 1))
          : null,
      backgroundColor: isColumnMode
          ? FluffyThemes.chatListField(context).withAlpha(240)
          : Colors.transparent,
      automaticallyImplyLeading: false,
      title: StreamBuilder(
        stream: client.onSyncStatus.stream,
        builder: (context, snapshot) {
          final status =
              client.onSyncStatus.value ??
              const SyncStatusUpdate(SyncStatus.waitingForResponse);
          final hide =
              client.onSync.value != null &&
              status.status != SyncStatus.error &&
              client.prevBatch != null;
          return TextField(
            controller: controller.searchController,
            focusNode: controller.searchFocusNode,
            textInputAction: TextInputAction.search,
            onChanged: (text) =>
                controller.onSearchEnter(text, globalSearch: globalSearch),
            decoration: InputDecoration(
              filled: true,
              // Telegram's search field is a #282828 stadium 39.6 dp tall with the
              // text inset 11.4 dp, measured on a user's chat-list capture. The
              // day theme has no capture, so it keeps the theme's own container.
              fillColor: theme.brightness == Brightness.light
                  ? theme.colorScheme.secondaryContainer
                  : TelegramPalette.searchFieldBackground,
              isDense: true,
              constraints: BoxConstraints(
                minHeight: ChatListGeometry.searchFieldHeight,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: ChatListGeometry.searchFieldInset,
                vertical: ChatListGeometry.searchFieldVerticalPadding,
              ),
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(
                  ChatListGeometry.searchFieldRadius,
                ),
              ),
              hintText: hide
                  ? L10n.of(context).searchChatsRooms
                  : status.calcLocalizedString(context),
              hintStyle: TextStyle(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.normal,
              ),

              prefixIcon: hide
                  ? controller.isSearchMode
                        ? IconButton(
                            tooltip: L10n.of(context).cancel,
                            constraints: BoxConstraints.tightFor(
                              height: ChatListGeometry.searchFieldHeight,
                            ),
                            icon: const Icon(Icons.close_outlined),
                            onPressed: controller.cancelSearch,
                            color: theme.colorScheme.onPrimaryContainer,
                          )
                        : isColumnMode ||
                              (controller.spaces.isEmpty &&
                                  !AppSettings.displayNavigationRail.value)
                        ? IconButton(
                            tooltip: L10n.of(context).search,
                            constraints: BoxConstraints.tightFor(
                              height: ChatListGeometry.searchFieldHeight,
                            ),
                            onPressed: controller.startSearch,
                            icon: Icon(
                              Icons.search_outlined,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          )
                        : IconButton(
                            tooltip: L10n.of(context).displayNavigationRail,
                            constraints: BoxConstraints.tightFor(
                              height: ChatListGeometry.searchFieldHeight,
                            ),
                            onPressed: controller.openNavrail,
                            icon: Icon(
                              Icons.menu,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          )
                  : SizedBox(
                      width: 8,
                      height: 8,
                      child: Center(
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                          value: status.progress,
                        ),
                      ),
                    ),
              suffixIcon: controller.isSearchMode && globalSearch
                  ? controller.isSearching
                        ? const Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: 10.0,
                              horizontal: 12,
                            ),
                            child: SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : TextButton.icon(
                            onPressed: controller.setServer,
                            style: TextButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(99),
                              ),
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: Text(
                              controller.searchServer ??
                                  Matrix.of(context).client.homeserver!.host,
                              maxLines: 2,
                            ),
                          )
                  : SizedBox(width: 0, child: ClientChooserButton(controller)),
            ),
          );
        },
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
