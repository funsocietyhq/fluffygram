// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/recent_stickers.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/avatar.dart';

/// Telegram's sticker cell: the grid span count is the tray width divided by
/// `dp(72)`. Telegram EmojiView.java:6827, applied :7087
const double kTelegramStickerCellDp = 72;

/// Telegram's tray grid padding: dp(6) at the sides, dp(48) at the bottom.
/// Telegram ChatAttachAlertEmojiLayout.java:172
const double _gridSidePaddingDp = 6;
const double _gridBottomPaddingDp = 48;

/// Telegram's sticker recents row: one row of **52 dp** cells at the top of the
/// sticker list - a row of the same list, not a separate header view. The 72 dp
/// cell above belongs to the pack grid; the recents row is its own size.
/// Telegram EmojiView.java:6945
const double kTelegramStickerRecentsCellDp = 52;

/// Telegram's sticker span count: the tray width divided by the 72 dp cell.
/// Telegram EmojiView.java:6827
int telegramStickerSpanCount(double width) =>
    (width / kTelegramStickerCellDp).floor().clamp(1, 1 << 16);

class StickerPickerDialog extends StatefulWidget {
  final Room room;
  final ImagePackUsage usage;
  final void Function(ImagePackImageContent) onSelected;

  const StickerPickerDialog({
    required this.onSelected,
    required this.room,
    this.usage = ImagePackUsage.sticker,
    super.key,
  });

  @override
  StickerPickerDialogState createState() => StickerPickerDialogState();
}

class StickerPickerDialogState extends State<StickerPickerDialog> {
  String? searchFilter;

  /// Open Telegram's one-item remove menu for a recents tile, at the touch
  /// point - the same `showMenu` shape as the timeline's long-press menu
  /// (event_context_menu.dart:256, fed from `LongPressStartDetails
  /// .globalPosition`). "Delete" is the existing l10n key; the removal
  /// touches only the local store and the tray stays open.
  Future<void> _showRecentsDeleteMenu(Offset position, Uri url) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(value: 'delete', child: Text(L10n.of(context).delete)),
      ],
    );
    if (action != 'delete') return;
    await RecentStickers.remove(url);
  }

  /// One tray tile: the sticker image with the tray's ink splash.
  /// [onLongPress] is set only by the recents row - T56.2.1 makes recents
  /// tiles removable; a pack-grid sticker is not deletable.
  Widget _tile({
    required Uri url,
    required String tooltip,
    required VoidCallback? onTap,
    void Function(Offset position)? onLongPress,
  }) => Tooltip(
    message: tooltip,
    // InkWell has no onLongPressStart (that is GestureDetector's API), so a
    // parent recognizer carries the touch point. It competes only for the
    // long-press - InkWell has none of its own - and the tap falls through.
    child: GestureDetector(
      onLongPressStart: onLongPress == null
          ? null
          : (d) => onLongPress(d.globalPosition),
      child: InkWell(
        radius: AppConfig.borderRadius,
        key: ValueKey(url.toString()),
        onTap: onTap,
        child: AbsorbPointer(
          absorbing: true,
          child: MxcImage(
            uri: url,
            fit: BoxFit.contain,
            width: 128,
            height: 128,
            animated: true,
            isThumbnail: false,
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // T56.2.2: the store is read on every build - the row below rebuilds
    // itself from the store when the store notifies.
    final recentStickers = RecentStickers.uris;
    final stickerPacks = widget.room.getImagePacks(widget.usage);
    final packSlugs = stickerPacks.keys.toList();

    return Material(
      color: theme.colorScheme.onInverseSurface,
      child: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverAppBar(
              floating: true,
              primary: false,
              toolbarHeight: 72,
              scrolledUnderElevation: 0,
              backgroundColor: Colors.transparent,
              automaticallyImplyLeading: false,
              title: TextField(
                autofocus: false,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: theme.colorScheme.secondaryContainer,
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  contentPadding: EdgeInsets.zero,
                  hintText: L10n.of(context).search,
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.normal,
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  prefixIcon: const Icon(Icons.search_outlined),
                ),
                onChanged: (s) => setState(() => searchFilter = s),
              ),
            ),
            // Telegram's recents row: one horizontal row of 52 dp cells above
            // the pack grid, inside the tray's own scroll view, inset dp(6) at
            // the sides like the pack grid. A tap sends, as in the pack grid.
            // Telegram EmojiView.java:6945, padding
            // ChatAttachAlertEmojiLayout.java:172
            //
            // T56.2.2: the row is an `AnimatedBuilder` on the store, so a
            // sticker sent with the tray open enters the row in place; the row
            // is absent while the store is empty. Telegram's row redraws the
            // same list the same way.
            AnimatedBuilder(
              animation: RecentStickers.notifier,
              builder: (context, _) {
                final recentStickers = RecentStickers.uris;
                if (recentStickers.isEmpty) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _gridSidePaddingDp,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: SizedBox(
                      height: kTelegramStickerRecentsCellDp,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.zero,
                        itemCount: recentStickers.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: _gridSidePaddingDp),
                        itemBuilder: (context, i) {
                          final url = Uri.parse(recentStickers[i]);
                          return SizedBox(
                            width: kTelegramStickerRecentsCellDp,
                            child: _tile(
                              url: url,
                              tooltip: url.pathSegments.last,
                              onTap: () => widget.onSelected(
                                ImagePackImageContent(
                                  url: url,
                                  body: url.pathSegments.last,
                                ),
                              ),
                              onLongPress: (p) =>
                                  _showRecentsDeleteMenu(p, url),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            if (packSlugs.isEmpty && recentStickers.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: .min,
                    children: [
                      Text(L10n.of(context).noEmotesFound),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => UrlLauncher(
                          context,
                          AppConfig.howDoIGetStickersTutorial,
                        ).launchUrl(),
                        icon: const Icon(Icons.explore_outlined),
                        label: Text(L10n.of(context).discover),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: packSlugs.length,
                itemBuilder: (BuildContext context, int packIndex) {
                  final pack = stickerPacks[packSlugs[packIndex]]!;
                  final filteredImagePackImageEntried = pack.images.entries
                      .toList();
                  if (searchFilter?.isNotEmpty ?? false) {
                    filteredImagePackImageEntried.removeWhere(
                      (e) =>
                          !(e.key.toLowerCase().contains(
                                searchFilter!.toLowerCase(),
                              ) ||
                              (e.value.body?.toLowerCase().contains(
                                    searchFilter!.toLowerCase(),
                                  ) ??
                                  false)),
                    );
                  }
                  final imageKeys = filteredImagePackImageEntried
                      .map((e) => e.key)
                      .toList();
                  if (imageKeys.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final packName =
                      pack.pack.displayName ?? packSlugs[packIndex];
                  return Column(
                    children: <Widget>[
                      if (packIndex != 0) const SizedBox(height: 20),
                      if (packName != 'user')
                        ListTile(
                          leading: Avatar(
                            mxContent: pack.pack.avatarUrl,
                            name: packName,
                            client: widget.room.client,
                          ),
                          title: Text(packName),
                        ),
                      const SizedBox(height: 6),
                      LayoutBuilder(
                        builder: (context, constraints) => GridView.builder(
                          // Telegram's tray grid: dp(6) at the sides.
                          // Telegram ChatAttachAlertEmojiLayout.java:172
                          padding: const EdgeInsets.symmetric(
                            horizontal: _gridSidePaddingDp,
                          ),
                          itemCount: imageKeys.length,
                          // Telegram's sticker cell is 72 dp and the span count is
                          // the width divided by it.
                          // Telegram EmojiView.java:6827, applied :7087
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: telegramStickerSpanCount(
                                  constraints.maxWidth,
                                ),
                                mainAxisSpacing: 8.0,
                                crossAxisSpacing: 8.0,
                              ),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemBuilder: (BuildContext context, int imageIndex) {
                            final image = pack.images[imageKeys[imageIndex]]!;
                            return _tile(
                              url: image.url,
                              tooltip: image.body ?? imageKeys[imageIndex],
                              onTap: () {
                                // copy the image
                                final imageCopy =
                                    ImagePackImageContent.fromJson(
                                      image.toJson().copy(),
                                    );
                                // set the body, if it doesn't exist, to the key
                                imageCopy.body ??= imageKeys[imageIndex];
                                widget.onSelected(imageCopy);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            // Telegram's tray grid carries dp(48) below the last row.
            // Telegram ChatAttachAlertEmojiLayout.java:172
            const SliverToBoxAdapter(
              child: SizedBox(height: _gridBottomPaddingDp),
            ),
          ],
        ),
      ),
    );
  }
}
