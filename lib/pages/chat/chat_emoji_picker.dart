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
import 'dart:ui' show ImageFilter;

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/config/recent_gifs.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/telegram_palette.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/sticker_picker_dialog.dart';
import 'package:fluffychat/pages/chat/trust_user_key_dialog.dart';
import 'package:fluffychat/utils/telegram_gif_file.dart';
import 'package:fluffychat/utils/telegram_gif_grid.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'chat.dart';

/// Telegram's emoji cell on a phone - 60 dp on a tablet, and the fork has no
/// tablet layout. Telegram EmojiView.java:3013
const double _emojiCellDp = 45;

/// The tray tab strip's band: `bottomTabContainer` is `MATCH_PARENT x dp(48)`
/// at `Gravity.BOTTOM` and `typeTabs` goes into it `WRAP_CONTENT x dp(48)`,
/// `Gravity.CENTER_HORIZONTAL | Gravity.BOTTOM` - bottom-centred, over the grid.
/// Telegram EmojiView.java:2676, :2703
const double _stripBandDp = 48;

/// The dark capsule behind the three labels. A user's capture measures
/// 94 px at 2.625 px/dp = **35.8 dp** tall, so a 36 dp pill, radius 18 dp.
/// Telegram paints it with its glass blur - this fork draws a `BackdropFilter`
/// stand-in, see `_TelegramTabStrip`.
const double _capsuleHeightDp = 36;
const double _capsuleRadiusDp = 18;

/// The selected-tab marker is a CAPSULE, not a line:
/// `rectTmp.set(lineLeft - dp(11), getPaddingTop(), lineRight + dp(11),
/// height - getPaddingBottom())` then `drawRoundRect(..., height / 2, ...)`.
/// Telegram PagerSlidingTabStrip.java:296-300 with EmojiView.java:2698-2702.
const double _markerHeightDp = 26;
const double _markerRadiusDp = 13;
const double _markerExtendDp = 11;

/// The tab label is 14 dp and bold. Telegram PagerSlidingTabStrip.java:179-180
const double _tabLabelFontSizeDp = 14;

/// The strip's own `setPadding(dp(4), dp(11), dp(4), dp(11))` side term, and
/// the adapter's per-tab `getTabPadding(position) = dp(position == 1 ? 12 : 18)`.
/// Telegram EmojiView.java:2702 and :8619-8621
const double _stripPaddingDp = 4;
const List<double> _tabPaddingDp = [18, 12, 18];

/// Telegram's tray grid padding: dp(6) at the sides, dp(48) at the bottom.
/// Telegram ChatAttachAlertEmojiLayout.java:172
const double _gridSidePaddingDp = 6;
const double _gridBottomPaddingDp = 48;

/// T115: the GIF tray grid has **no** side padding and `dp(44)` at the bottom
/// - `gifGridView.setPadding(0, searchFieldHeight, 0, dp(44) + bottomInset)`,
/// Telegram EmojiView.java:2057. Its top is 0 because a user chose no
/// search field, so nothing sits above the tiles.
const double _gifGridBottomPaddingDp = 44;

/// T145 (user, 2026-10-31, capture `the reference capture`: "Gif tray
/// isn't really similar"): the tray panel is as tall as **the soft keyboard it
/// replaces**. Telegram keeps one measured IME height and hands it to every
/// panel that takes the keyboard's place (`ChatActivityEnterView.java:12561,
/// :12717, :13620`). Measured on that capture - 1080 px wide at 2.625 px/dp, a
/// 2424 px (923 dp) screen - the panel's top, the GIF search row, sits at
/// y=1543 px, so the panel is 881 px = **336 dp**, 36 % of the screen, and the
/// grid under it is 283 dp: under three rows of ~100 dp tiles.
///
/// The share this file used to apply, `availableHeight * 3/5 + 16 dp` from the
/// **old** attach alert (`ChatAttachAlertEmojiLayout.java:155-173`), gives 520
/// dp on that screen: 184 dp too tall, five tile rows where Telegram shows
/// under three. Measurement: `the measurement log`.
const double _telegramPanelShare = 336 / 923;

/// The tallest keyboard inset this app run has shown, in logical pixels. The
/// live one is `MediaQuery.viewInsets.bottom`; Telegram measures its keyboard
/// once and caches it, so the tray holds one height across chats instead of
/// following whatever keyboard was up last.
double? _imeInsetDp;

/// The tray panel height: the keyboard height Telegram's panel equals, or the
/// measured 36 % share while this run has not opened a keyboard yet.
double _telegramPanelHeight(BuildContext context) =>
    _imeInsetDp ?? MediaQuery.sizeOf(context).height * _telegramPanelShare;

/// T146 (user, 2026-10-31: "The gap between the text bar and the gif tray isn't
/// there either"): Telegram leaves **chat background** between the composer pill
/// and the tray panel. Measured on `the reference capture`: the pill's
/// bottom edge sits at y=1520 px and the panel's fill starts at y=1543 px, so the
/// band is 23 px = **8.8 dp** at 2.625 px/dp, and it reads `srgb(0,0,0)` - the
/// chat background, not the panel's `srgb(23,23,23)` fill. The fork's composer
/// row ends at the pill's own bottom, so without this band the panel butts
/// against the text bar.
const double _trayGapDp = 9;

/// The tray panel fill. Measured on the same capture: the panel and the composer
/// card carry the **same** fill, `srgb(23,23,23)` = #171717 = `composerPill`, on
/// a `srgb(0,0,0)` chat background. Telegram's night attheme states
/// `chat_emojiPanelBackground = #1E1E1F` (`night.attheme`), 4 levels lighter than
/// its own capture; the capture wins, as it did for the composer card.
/// `colorScheme.onInverseSurface` - what this file used - is Material 3's seeded
/// inverse surface (about #2B2926 here): too light, and tinted.

class ChatEmojiPicker extends StatelessWidget {
  final ChatController controller;
  const ChatEmojiPicker(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // T145: this widget is in the tree whenever the chat page is - an
    // `AnimatedContainer` of height 0 while the tray is shut - so a keyboard
    // frame is a sample of the inset the panel will want. The 100 dp floor
    // ignores a navigation-bar inset, which is not a keyboard.
    final imeInset = MediaQuery.viewInsetsOf(context).bottom;
    if (imeInset > 100 && imeInset > (_imeInsetDp ?? 0)) _imeInsetDp = imeInset;
    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      height: controller.showEmojiPicker
          ? _telegramPanelHeight(context) + _trayGapDp
          : 0,
      child: controller.showEmojiPicker
          ? DefaultTabController(
              length: 3,
              // T118 (user, 2026-10-30: "the drawer must remember the last tab
              // picked, so I do not tap GIF every time"). Without this the
              // controller is rebuilt with index 0 every time the chat page is
              // rebuilt. Telegram stores no tray tab, so this is a fork
              // convenience - see the measurement log.
              initialIndex: AppSettings.chatEmojiPickerTab.value,
              // T119: a Stack, not a Column. Telegram's strip draws **over**
              // the pages - `typeTabs` sits in a 48 dp band pinned to the
              // panel bottom and the grid scrolls behind it
              // (EmojiView.java:2676, :2703).
              child: Stack(
                children: [
                  // T146: the pages start 9 dp below the top of the panel, so a
                  // band of chat background sits between the composer pill and
                  // the tray. The strip stays pinned to the panel bottom.
                  Positioned.fill(
                    top: _trayGapDp,
                    child: TabBarView(
                      children: [
                        EmojiPicker(
                          onEmojiSelected: controller.onEmojiSelected,
                          onBackspacePressed: controller.emojiPickerBackspace,
                          config: Config(
                            locale: Localizations.localeOf(context),
                            emojiViewConfig: EmojiViewConfig(
                              noRecents: const NoRecent(),
                              backgroundColor: TelegramPalette.composerPill,
                              // Telegram's emoji cell is 45 dp on a phone and
                              // the grid is one column per cell.
                              // Telegram EmojiView.java:3013
                              columns:
                                  (MediaQuery.sizeOf(context).width /
                                          _emojiCellDp)
                                      .floor(),
                              emojiSizeMax: _emojiCellDp,
                              // Telegram's grid padding: dp(6) sides, dp(48)
                              // at the bottom.
                              // Telegram ChatAttachAlertEmojiLayout.java:172
                              gridPadding: const EdgeInsets.fromLTRB(
                                _gridSidePaddingDp,
                                0,
                                _gridSidePaddingDp,
                                _gridBottomPaddingDp,
                              ),
                            ),
                            bottomActionBarConfig: const BottomActionBarConfig(
                              enabled: false,
                            ),
                            categoryViewConfig: CategoryViewConfig(
                              backspaceColor: theme.colorScheme.primary,
                              iconColor: theme.colorScheme.primary.withAlpha(
                                128,
                              ),
                              iconColorSelected: theme.colorScheme.primary,
                              indicatorColor: theme.colorScheme.primary,
                              backgroundColor: theme.colorScheme.surface,
                            ),
                            skinToneConfig: SkinToneConfig(
                              dialogBackgroundColor: Color.lerp(
                                theme.colorScheme.surface,
                                theme.colorScheme.primaryContainer,
                                0.75,
                              )!,
                              indicatorColor: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        // T119: Telegram's tab order is its `allTabs` insertion
                        // order - emoji, gifs, stickers (EmojiView.java:1642,
                        // :1990, :2328), and `getPageTitle`'s 0/1/2 switch
                        // agrees (:8605-8610). Nothing outside this file sets
                        // the tab index, so the pages swap with the labels.
                        // Same rule for a GIF tile: the send path owns the
                        // store write, in ChatController.sendGif().
                        GifPickerView(controller: controller),
                        StickerPickerDialog(
                          room: controller.room,
                          onSelected: (sticker) async {
                            final proceed = await showTrustUserInRoomDialog(
                              context,
                              controller.room,
                            );
                            if (!proceed) return;
                            // The send path owns the recents write: the tray
                            // records the sticker when the send completes, in
                            // ChatController.sendSticker().
                            await controller.sendSticker(sticker);
                            controller.hideEmojiPicker();
                          },
                        ),
                      ],
                    ),
                  ),
                  // The grids keep their own bottom padding (48 dp emoji,
                  // 44 dp GIF), so tiles scroll under the strip as they do in
                  // Telegram.
                  _TelegramTabStrip(
                    // `getPageTitle` -> `R.string.Emoji`, `R.string.AccDescrGIFs`,
                    // `R.string.AccDescrStickers`; `getPageIconDrawable` returns
                    // null, so there are no icons (EmojiView.java:8599-8612).
                    // English is hard-coded: the fork's precedent in this tray.
                    labels: const ['Emoji', 'GIFs', 'Stickers'],
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

/// Telegram's tray tab strip: three bold 14 dp words in a dark capsule at the
/// bottom centre of the panel, the chosen word sitting on a soft 26 dp capsule.
/// Telegram's `typeTabs` is a `PagerSlidingTabStrip` in a 48 dp band at the
/// panel bottom (EmojiView.java:2695, :2676, :2703); its labels are text
/// (`getPageTitle`, :8604-8612) and `getPageIconDrawable` returns null
/// (:8599-8601).
///
/// The 30 dp icon numbers this class used to carry came from the **wrong**
/// view: `EmojiTabsStrip.java:196, :211, :216` is Telegram's emoji *category*
/// row, which `EmojiView.java:1955-1956` feeds the emoji packs - not this
/// three-tab picker strip (T119, the measurement log).
///
/// NAMED DEVIATION: the dark capsule behind the labels. Telegram paints it
/// with its glass blur, which this fork has no equivalent of, so the stand-in
/// is a blurred backdrop plus a surface tint at alpha 200. The size is the
/// a user's capture measurement (35.8 dp).
class _TelegramTabStrip extends StatefulWidget {
  const _TelegramTabStrip({required this.labels});

  /// One label per tab, in Telegram's `allTabs` order - Emoji, GIFs, Stickers
  /// (EmojiView.java:1642, :1990, :2328).
  final List<String> labels;

  @override
  State<_TelegramTabStrip> createState() => _TelegramTabStripState();
}

class _TelegramTabStripState extends State<_TelegramTabStrip> {
  /// The controller this State listens to, so `dispose` can detach the listener
  /// even if the enclosing `DefaultTabController` is replaced under us.
  TabController? _watched;

  /// The tab currently held down. Telegram runs `ScaleStateListAnimator.apply(
  /// tab, .025f, 1.2f)` on each tab - the pressed label scales by 1.025
  /// (PagerSlidingTabStrip.java:188).
  int _pressedTab = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = DefaultTabController.of(context);
    if (controller == _watched) return;
    _watched?.removeListener(_storeIndex);
    _watched = controller;
    // T118: the write sits on the controller, not on the tap handler, because a
    // sideways swipe over the pages changes the tab too and must be remembered
    // the same way.
    controller.addListener(_storeIndex);
  }

  void _storeIndex() {
    final controller = _watched;
    if (controller == null) return;
    AppSettings.chatEmojiPickerTab.setItem(controller.index);
  }

  @override
  void dispose() {
    _watched?.removeListener(_storeIndex);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabController = DefaultTabController.of(context);
    final labels = widget.labels;
    return Align(
      // Bottom-centred over the pages, inside the 48 dp band.
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: _stripBandDp,
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_capsuleRadiusDp),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: _capsuleHeightDp,
                color: theme.colorScheme.surface.withAlpha(200),
                // `setPadding(dp(4), dp(11), dp(4), dp(11))` - EmojiView.java:
                // :2702. The 11 dp top/bottom is inside the 26 dp marker height.
                padding: const EdgeInsets.symmetric(
                  horizontal: _stripPaddingDp,
                ),
                child: AnimatedBuilder(
                  animation: tabController,
                  builder: (context, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < labels.length; i++)
                        InkWell(
                          onTap: () => tabController.index = i,
                          onTapDown: (_) => setState(() => _pressedTab = i),
                          onTapUp: (_) => setState(() => _pressedTab = -1),
                          onTapCancel: () => setState(() => _pressedTab = -1),
                          borderRadius: BorderRadius.circular(_markerRadiusDp),
                          // Per-tab horizontal padding 18 / 12 / 18 dp -
                          // EmojiView.java:8619-8621.
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: _tabPaddingDp[i],
                            ),
                            child: Container(
                              // The selected marker: 26 dp tall, radius 13 dp,
                              // 11 dp past the label box each side
                              // (PagerSlidingTabStrip.java:296-300). The colour
                              // is alpha 20 of `chat_emojiPanelIconSelected`
                              // (EmojiView.java:2699); `setUnderlineHeight(0)`
                              // (:2700) means no underline is drawn at all.
                              height: _markerHeightDp,
                              padding: const EdgeInsets.symmetric(
                                horizontal: _markerExtendDp,
                              ),
                              alignment: Alignment.center,
                              decoration: tabController.index == i
                                  ? BoxDecoration(
                                      color: theme.colorScheme.onSurface
                                          .withAlpha(20),
                                      borderRadius: BorderRadius.circular(
                                        _markerRadiusDp,
                                      ),
                                    )
                                  : null,
                              child: AnimatedScale(
                                scale: _pressedTab == i ? 1.025 : 1.0,
                                duration: const Duration(milliseconds: 100),
                                child: Text(
                                  labels[i],
                                  // 14 dp bold - PagerSlidingTabStrip.java:179-180.
                                  // Ink = `glass_defaultIcon` at 0.6 unselected
                                  // and 0.8 selected (:181, :463) = alpha 153
                                  // and 204, on one theme token.
                                  style: TextStyle(
                                    fontSize: _tabLabelFontSizeDp,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withAlpha(
                                          tabController.index == i ? 204 : 153,
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tray's `GIFs` tab: the GIFs this user has sent, newest first, in
/// Telegram's sticker cell (**72 dp**, span count = width / 72, grid inset
/// dp(6) at the sides with dp(48) below the last row).
/// Telegram EmojiView.java:6827, padding ChatAttachAlertEmojiLayout.java:172
///
/// Telegram's GIF panel is backed by a provider (Giphy search and categories).
/// This fork ships no provider and no search (AGENTS.md rule 8), so the panel
/// is the device's own collection - `RecentGifs` - and the send path is what
/// grows it, which is the behaviour a user asked for.
///
/// T125  replaced T56.3.1's per-chat history seed scan: the
/// store is the only authority, a hand add comes from the message long-press
/// menu, and a hand removal is tombstoned so it never comes back.
class GifPickerView extends StatefulWidget {
  const GifPickerView({required this.controller, super.key});

  final ChatController controller;

  @override
  State<GifPickerView> createState() => _GifPickerViewState();
}

class _GifPickerViewState extends State<GifPickerView> {
  // T125 (user, 2026-10-30: "Even if I remove something from my gif tray, it
  // comes back when I restart the app. The tray should be persistent storage,
  // not calculated when I open the app"): this state used to scan the open
  // room's whole GIF history on the first tray open of every chat (the `v3`
  // marker, `_seedRunning`, `_gifRow()` and `_seedFromRoom()`, all gone here).
  // That scan is why a removal came back: the store is device-local, but so is
  // the in-memory seen-set that kept a timeline row from re-writing it, and a
  // scan (or a repaint after a restart) wrote the deleted GIF back from its
  // event. The store is now the only authority - the send path records my own
  // GIFs, the message long-press menu adds any GIF by hand
  // (`RecentGifs.addFromEvent`), and a removal is tombstoned in
  // `AppSettings.recentGifsRemoved`. `RecentGifs.seedFrom()` itself stays for
  // the gate test; the picker simply never calls it.

  /// Open Telegram's one-item remove menu for a GIF tile, at the touch
  /// point - the same `showMenu` shape as the timeline's long-press menu
  /// (event_context_menu.dart:256, fed from `LongPressStartDetails
  /// .globalPosition`). "Delete" is the existing l10n key; the removal
  /// touches only the local store and the tray stays open.
  Future<void> _showGifDeleteMenu(Offset position, RecentGif gif) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'delete',
          // T125: one term for one verb - the same label the message
          // long-press menu uses for the same action on a GIF row.
          child: Text(L10n.of(context).removeFromGifs),
        ),
      ],
    );
    if (action != 'delete') return;
    // The row, not the url: the tray is one list across every chat (T117), and
    // a url can sit in two chats' rows until the content hash collapses them.
    await RecentGifs.remove(gif.url, room: gif.room);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      // T146: Telegram's tray fill, measured #171717 - the composer card's own
      // fill, not Material 3's inverse surface.
      color: TelegramPalette.composerPill,
      child: SafeArea(
        top: false,
        // T56.2.2: the grid is an `AnimatedBuilder` on the store and reads it
        // in its builder, so a GIF sent with the tray open enters the grid in
        // place - no close-and-reopen. Telegram's recents row redraws the
        // same list the same way.
        child: AnimatedBuilder(
          animation: RecentGifs.notifier,
          builder: (context, _) {
            // T117 : one list across every
            // chat, newest first - Telegram's own tray is one account-wide list
            // (`MediaDataController.getRecentGifs()`, EmojiView.java:6292). A
            // row keeps the chat it came from, and a send into another chat
            // pulls the file and uploads it there (`ChatController.sendGif`).
            final gifs = RecentGifs.gifs;
            return gifs.isEmpty
                // One line of grey text: the store is empty until the user
                // sends their first GIF. No button, no add flow.
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        // T125: names both ways in - the send path and the
                        // long-press menu's "Add to gifs" on any GIF, mine or
                        // a friend's.
                        'No GIFs yet. Send a GIF, or hold one in a chat and choose Add to gifs.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : LayoutBuilder(
                    // T115: Telegram's GIF tray is not a square grid. It cuts
                    // the grid into 100 spans, gives each gif the spans its own
                    // aspect ratio needs against a 100 dp row, shares the
                    // leftover spans out so a row fills the width, and puts
                    // dp(2) between the cells (`telegram_gif_grid.dart`, port of
                    // ExtendedGridLayoutManager.java:51-157 + EmojiView.java:
                    // 2050-2051). Its padding is `padding(0, searchFieldHeight,
                    // 0, dp(44))` (EmojiView.java:2057): no side padding, 44 dp
                    // at the bottom. No search field here - a user chose no
                    // search box on 2026-10-30, so nothing sits above the grid.
                    builder: (context, constraints) {
                      final gridRows = TelegramGifGrid.rows([
                        for (final gif in gifs)
                          TelegramGifGrid.aspectOf(gif.w, gif.h),
                      ], constraints.maxWidth);
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          0,
                          0,
                          0,
                          _gifGridBottomPaddingDp,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var r = 0; r < gridRows.length; r++)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: r == 0 ? 0 : TelegramGifGrid.gutterDp,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (
                                      var c = 0;
                                      c < gridRows[r].length;
                                      c++
                                    ) ...[
                                      if (c > 0)
                                        SizedBox(
                                          width: TelegramGifGrid.gutterDp,
                                        ),
                                      _gifCell(
                                        context,
                                        gifs[gridRows[r][c].index],
                                        gridRows[r][c],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
          },
        ),
      ),
    );
  }

  /// One tray tile: the gif at its Telegram cell box, cropped to fill, with
  /// the tap that sends it and the long press that removes it.
  Widget _gifCell(BuildContext context, RecentGif gif, TelegramGifCell cell) {
    final mxcUri = gif.url;
    return SizedBox(
      width: cell.w,
      height: cell.h,
      child: GestureDetector(
        // Telegram's tray has no long-press menu on a recent gif, but our
        // store is local, so this is the only way to drop a tile. Kept as a
        // deliberate deviation (ROADMAP T115).
        onLongPressStart: (d) => _showGifDeleteMenu(d.globalPosition, gif),
        child: InkWell(
          key: ValueKey(mxcUri),
          onTap: () async {
            final proceed = await showTrustUserInRoomDialog(
              context,
              widget.controller.room,
            );
            if (!proceed) return;
            // The send path owns the store write, so a GIF whose send failed
            // never enters the grid.
            await widget.controller.sendGif(gif);
            widget.controller.hideEmojiPicker();
          },
          child: ClipRect(
            child: AbsorbPointer(
              absorbing: true,
              // T116: the tile draws through its **event**, never its url. In
              // an encrypted room a bare `mxc://` GET returns the encrypted
              // bytes, `Image.memory` fails, and MxcImage's own fallback is the
              // broken-image glyph a user captured (see the measurement in
              // `the measurement log`); the event path decrypts first, and
              // `animated: true` still asks for the animated original (T56.4).
              child: _gifTileImage(gif, cell),
            ),
          ),
        ),
      ),
    );
  }

  /// The picture of one tile: its decrypted animated gif from the fork's media
  /// cache, or an empty box while it is not on disk. A tray never shows
  /// MxcImage's broken-image glyph - Telegram's tray draws a cached file or
  /// nothing.
  Widget _gifTileImage(RecentGif gif, TelegramGifCell cell) => _TelegramGifTile(
    key: ValueKey(gif.url),
    gif: gif,
    cell: cell,
    client: widget.controller.sendingClient,
  );
}

/// One tray picture, read from the fork's decrypted media cache (T117). The
/// first open of a gif downloads and decrypts it once and keeps the file; every
/// open after that is a file open plus a hit in Flutter's image cache, which is
/// the "cached in the tray" a user asked for. While the file is not there the
/// tile is an empty box - no spinner, no glyph (T116).
class _TelegramGifTile extends StatefulWidget {
  const _TelegramGifTile({
    required this.gif,
    required this.cell,
    required this.client,
    super.key,
  });

  final RecentGif gif;
  final TelegramGifCell cell;
  final Client client;

  @override
  State<_TelegramGifTile> createState() => _TelegramGifTileState();
}

class _TelegramGifTileState extends State<_TelegramGifTile> {
  File? _file;
  Event? _poster;
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _TelegramGifTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gif.url == widget.gif.url &&
        oldWidget.gif.eventId == widget.gif.eventId) {
      return;
    }
    _file = null;
    _tried = false;
    _load();
  }

  Future<void> _load() async {
    if (_tried) return;
    _tried = true;
    if (widget.gif.video) {
      // T133: a Convert to gif clip is an mp4, and `Image` cannot decode one -
      // the tile would be an empty box. Its picture is the **poster** the
      // timeline row also paints before its first frame: the event's own
      // thumbnail, through the same event path T116 chose so an encrypted room
      // decrypts first. No clip bytes are fetched for a tile.
      _poster = await TelegramGifFile.sourceEvent(widget.gif, widget.client);
      if (!mounted) return;
      setState(() {});
      return;
    }
    final file = await TelegramGifFile.file(widget.gif, client: widget.client);
    if (file == null) return;
    // The content hash of a row the store does not have yet: one pass over a
    // file the tray just read, and the row it duplicates leaves the tray.
    if (widget.gif.sha.isEmpty) unawaited(_fingerprint(file));
    if (!mounted) return;
    setState(() => _file = file);
  }

  Future<void> _fingerprint(File file) async {
    try {
      await RecentGifs.setSha(
        widget.gif.url,
        await TelegramGifFile.sha256Of(file),
      );
    } on Object catch (e) {
      debugPrint('[TelegramGif] hash failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final poster = _poster;
    if (poster != null) {
      // A failed poster fetch paints the placeholder - an empty box - not
      // MxcImage's decode glyph, which no tray may show (T116).
      return MxcImage(
        event: poster,
        isThumbnail: true,
        cacheKey: poster.transactionId ?? poster.eventId,
        cacheName: poster.room.id,
        width: widget.cell.w,
        height: widget.cell.h,
        fit: BoxFit.cover,
        placeholder: (_) => const SizedBox.shrink(),
      );
    }
    return _file == null
        ? const SizedBox.shrink()
        : Image(
            image: _tileImage(context),
            width: widget.cell.w,
            height: widget.cell.h,
            fit: BoxFit.cover,
            // A file that leaves the cache (evicted while the tray is open) is
            // not a reason to paint a glyph: keep the last frame's box.
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          );
  }

  /// The tile's picture, **decoded inside the tile's own pixel box**. An
  /// animated gif decodes frame by frame into the image cache: one 400 x 400
  /// gif with 50 frames is about 24 MB of RGBA, so nine visible tiles want some
  /// 216 MB against Flutter's 100 MB image budget (`PaintingBinding.
  /// maximumSizeBytes`), tiles evict each other, and scrolling re-decodes the
  /// grid. That is the part of a user's "still takes a while" no file cache
  /// can touch (T117.1, 2026-10-30).
  ///
  /// `ResizeImagePolicy.fit` keeps the source aspect and caps both edges at the
  /// tile's pixels; `ResizeImage` clamps to the intrinsic size, so a small gif
  /// is never upscaled. The GPU still stretches the small bitmap to cover the
  /// tile, which is free next to a decode. Telegram's tray tile carries the
  /// document **thumbnail** rather than the file for the same reason
  /// (`ui/Cells/ContextLinkCell.java:562-588`); Flutter offers no `ui.Image`
  /// encoder here, so the saving is taken at decode time instead.
  ResizeImage _tileImage(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ResizeImage(
      FileImage(_file!),
      width: (widget.cell.w * dpr).round(),
      height: (widget.cell.h * dpr).round(),
      policy: ResizeImagePolicy.fit,
    );
  }
}

class NoRecent extends StatelessWidget {
  const NoRecent({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          L10n.of(context).emoteKeyboardNoRecents,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
