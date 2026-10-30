// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Telegram's message context menu (ROADMAP T40.1).
///
/// A long press on a timeline row opens this menu, anchored on the touch point.
/// Telegram's own contract is `ChatMessageCell.java:557` `ChatMessageCellDelegate`
/// -> `didLongPress(View view, int x, int y, int position)`: the cell hands the
/// row view AND the touch point to `ChatActivity`, which opens the menu there.
/// A long press never enters selection mode - "Select" is one item in the menu.
///
/// The public `reference/telegram-android` tree carries no context-menu item
/// list and no menu geometry (`the measurement log`, "What the reference
/// tree answers, and what it cannot"). The item set below is read from the
/// a user's app, and every number in [TelegramContextMenuGeometry] is
/// PROVISIONAL: a user judges the menu in the web demo, and the three
/// captures ROADMAP T40.1 names retune the geometry class in one edit.
// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

library;

import 'package:fluffychat/config/telegram_palette.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/telegram_gif.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The one place the menu's dp values live, so one capture retunes the menu in
/// one edit. All values are PROVISIONAL (2026-10-27): they are not measured,
/// the tree states none of them, and a user's eye is the gate.
abstract final class TelegramContextMenuGeometry {
  /// PROVISIONAL. Menu row height, 44 dp.
  static const double itemHeight = 44;

  /// PROVISIONAL. The leading icon column, 20 dp.
  static const double iconSize = 20;

  /// PROVISIONAL. The item label, 16 sp.
  static const double labelFontSize = 16;

  /// PROVISIONAL. Item horizontal padding, 16 dp.
  static const double itemHorizontalPadding = 16;

  /// PROVISIONAL. Gap between the icon and the label, 16 dp.
  static const double iconLabelGap = 16;

  /// PROVISIONAL. The menu's own corner radius, 8 dp.
  static const double cornerRadius = 8;

  /// PROVISIONAL. How far the menu's anchor corner sits from the touch point,
  /// 8 dp. `showMenu`'s `position` is the cut-out rect the menu avoids.
  static const double touchOffset = 8;

  /// PROVISIONAL. Narrowest the menu may be, 196 dp.
  static const double minMenuWidth = 196;

  /// The menu fill. Night: the palette's raised popup surface (its doc names
  /// the attheme key `message_action_sheet_bg`). Day: the theme's own popup
  /// surface. No new hex - `verification/palette_contract.sh` stays green.
  static Color menuFill(Brightness brightness, ColorScheme scheme) =>
      brightness == Brightness.dark
      ? TelegramPalette.surfaceRaised
      : scheme.surfaceContainerHighest;

  /// Item label ink. Night is Telegram's `context_menu_text` (the palette
  /// constant [TelegramPalette.textPrimary] documents that attheme key).
  static Color labelInk(Brightness brightness, ColorScheme scheme) =>
      brightness == Brightness.dark
      ? TelegramPalette.textPrimary
      : scheme.onSurface;

  /// Item icon ink - Telegram's `context_menu_icon` at night
  /// ([TelegramPalette.textSecondary]).
  static Color iconInk(Brightness brightness, ColorScheme scheme) =>
      brightness == Brightness.dark
      ? TelegramPalette.textSecondary
      : scheme.onSurfaceVariant;
}

/// One item of the menu. Declaration order IS Telegram's draw order
/// (ROADMAP T40.1): Reply, Quote, Copy, Forward, Select, Pin/Unpin, then the
/// row-specific block, then Edit, then Delete.
///
/// Deliberately absent, each with the Matrix reason at its branch in
/// [telegramContextActionsFor]: "via @bot" and the views counter (no Matrix
/// field), "Mark as unread" at message level (Matrix is room-level only),
/// custom emoji, Translate (no server), "Send silently" / "Schedule message"
/// (ROADMAP T40.5), "Convert to audio file" / "Save to music" (product
/// features), "Copy text" / "Copy caption" (one payload in Matrix:
/// `event.body` is the whole text), "Add to stickers" (the `im.ponies` pack
/// write lives in `lib/pages/settings_emotes/`, no row-level API today), and
/// Report (it stays in the selection action bar, `chat_view.dart:156-230`).
enum TelegramContextAction {
  reply,
  quote,
  copy,
  forward,
  select,
  pin,
  save,
  // T125 (user, 2026-10-30: "'Add to gifs' should be an option on gifs and
  // animated webps"): one item, two verbs - it adds the row's GIF to the tray
  // or takes it out, and the label follows the current membership. Telegram
  // has the same pair on a GIF row ("Add to GIFs"); the fork's tray is the
  // local `RecentGifs` store, so the write is device-local.
  gifs,
  copyLink,
  info,
  edit,
  delete;

  IconData icon({required bool isPinned}) => switch (this) {
    TelegramContextAction.reply => Icons.reply,
    TelegramContextAction.quote => Icons.format_quote,
    TelegramContextAction.copy => Icons.copy_outlined,
    TelegramContextAction.forward => Icons.forward,
    TelegramContextAction.select => Icons.check_circle_outline,
    TelegramContextAction.pin =>
      isPinned ? Icons.push_pin : Icons.push_pin_outlined,
    TelegramContextAction.save => Icons.download_outlined,
    TelegramContextAction.gifs => Icons.gif_outlined,
    TelegramContextAction.copyLink => Icons.link,
    TelegramContextAction.info => Icons.info_outlined,
    TelegramContextAction.edit => Icons.edit_outlined,
    TelegramContextAction.delete => Icons.delete_outline,
  };

  /// The label. Every item carries a key in `lib/l10n/intl_en.arb`; the last
  /// two (`quote`, `copyLink`) landed with T42. [inGifTray] is the one fact the
  /// caller has to hand in for the `gifs` item (T125): it says whether this
  /// row's GIF is in the tray right now, which picks "Remove from gifs" or
  /// "Add to gifs". Every other label ignores it.
  String labelOf(
    BuildContext context, {
    required bool isPinned,
    bool inGifTray = false,
  }) {
    final l10n = L10n.of(context);
    return switch (this) {
      TelegramContextAction.reply => l10n.reply,
      // "Quote" = Telegram R.string.Quote (res/values/strings.xml:326;
      // ChatActivity.java:10944). ARB key `quote` (T42).
      TelegramContextAction.quote => l10n.quote,
      TelegramContextAction.copy => l10n.copy,
      TelegramContextAction.forward => l10n.forward,
      TelegramContextAction.select => l10n.select,
      TelegramContextAction.pin => isPinned ? l10n.unpin : l10n.pinMessage,
      // Telegram says "Save to Downloads" / "Save to gallery"; the fork uses
      // its existing key (the selection bar's download verb) for one term.
      TelegramContextAction.save => l10n.downloadFile,
      // T125: ARB keys `addToGifs` / `removeFromGifs`. One term for one verb,
      // shared with the tray tile's own long-press menu.
      TelegramContextAction.gifs =>
        inGifTray ? l10n.removeFromGifs : l10n.addToGifs,
      // Telegram's menu label is R.string.CopyLink "Copy Link"
      // (res/values/strings.xml:1970); the fork ships "Copy link" (the T40.1
      // row label; casing kept on purpose, the measurement log T42).
      // ARB key `copyLink` (T42).
      TelegramContextAction.copyLink => l10n.copyLink,
      TelegramContextAction.info => l10n.messageInfo,
      TelegramContextAction.edit => l10n.edit,
      TelegramContextAction.delete => l10n.delete,
    };
  }
}

/// The first `http(s)://` link in a message body, trimmed of trailing
/// sentence punctuation. Null when the row carries no link.
String? telegramEventLink(String body) => RegExp(
  r'https?://\S+',
).firstMatch(body)?.group(0)?.replaceAll(RegExp(r'[.,;:!?)\]]+$'), '');

/// The ordered item set for one row. Pure: it reads the event's own properties
/// and the four flags the caller has already computed, and touches no widget,
/// no controller and no network. This is the part the gate test asserts.
///
/// [canEdit], [canPin] and [canRedact] mirror `ChatController`'s
/// `canEditSelectedEvents` / `canPinSelectedEvents` / `Event.canRedact` for a
/// single row; they are flags rather than lookups so the function stays
/// testable over a fixture room.
List<TelegramContextAction> telegramContextActionsFor({
  required Event event,
  required bool ownMessage,
  required bool canEdit,
  required bool isPinned,
  bool canPin = true,
  bool canRedact = true,
}) {
  final type = event.messageType;
  final body = event.body;
  final sent = event.status.isSent;
  final isMedia = const {
    MessageTypes.Image,
    MessageTypes.Video,
    MessageTypes.Audio,
    MessageTypes.File,
    MessageTypes.Sticker,
  }.contains(type);

  // Telegram's redacted row keeps almost nothing: it can be selected (to see
  // the row) and its info dialog opens.
  if (event.redacted) {
    return const [TelegramContextAction.select, TelegramContextAction.info];
  }

  final actions = <TelegramContextAction>[
    // Reply: the composer takes the reply relation, so a row in a chat the
    // member cannot write to is the caller's (composer's) problem, not the
    // item's - the fork's `replyAction` is always available.
    TelegramContextAction.reply,
  ];
  // Quote = quote-and-reply (ROADMAP T40.13): it cuts a quote block out of the
  // row's text, so it needs text. A media row's caption is not quotable here.
  if (type == MessageTypes.Text && body.isNotEmpty) {
    actions.add(TelegramContextAction.quote);
  }
  // Copy: "Copy text" and "Copy caption" are excluded - in Matrix the whole
  // payload is `event.body`, so one Copy item covers every row that has one.
  if (body.isNotEmpty) actions.add(TelegramContextAction.copy);
  // A local echo (sending, or failed) cannot be forwarded.
  if (sent) actions.add(TelegramContextAction.forward);
  actions.add(TelegramContextAction.select);
  // Pin / Unpin - one item, one verb: ChatController.pinEvent() unpins when
  // the single selected row is already pinned.
  if (canPin && sent) actions.add(TelegramContextAction.pin);

  // ---- the row-specific block ----
  // Save to Downloads: photo, video, file, audio and voice. A Matrix voice
  // message is MessageTypes.Audio with info."org.matrix.msc3245.voice", so
  // this one item is Telegram's voice "Save" as well as its media "Save".
  // "Save as..." / "Save to gallery" (the picker variant) is the same verb
  // behind the fork's `Event.saveFile`.
  if (isMedia) actions.add(TelegramContextAction.save);
  // T125: "Add to gifs" / "Remove from gifs" on every GIF row - a GIF the
  // Compress toggle turned into an animated WebP counts, `telegramEventIsGif()`
  // is the same predicate the timeline's loop and the T121 badge read. Mine or
  // a friend's: the tray writes the row either way, marked `added`.
  // T133 : a
  // Convert to gif clip - `m.video` carrying `org.fluffygram.gif` - is a GIF to
  // this fork, so the same item appears on its row.
  if (telegramEventIsGif(event) || telegramEventIsMp4Gif(event)) {
    actions.add(TelegramContextAction.gifs);
  }
  // "Add to stickers" is excluded: the sticker pack write (`im.ponies`) lives
  // in lib/pages/settings_emotes/, and no row-level API for it exists today.
  // Copy link: Telegram shows it on a row whose text carries a link.
  if (type == MessageTypes.Text && telegramEventLink(body) != null) {
    actions.add(TelegramContextAction.copyLink);
  }
  // "Mark as unread" is excluded: Matrix marks the ROOM read (a
  // `m.fully_read` marker), never one message.
  // "View message info" is on every row.
  actions.add(TelegramContextAction.info);
  // ---- end row-specific block ----

  // Edit: own text/media rows only, and only a sent one - an edit event
  // replaces a sent event, a local echo has nothing to replace.
  if (ownMessage && canEdit && sent && (type == MessageTypes.Text || isMedia)) {
    actions.add(TelegramContextAction.edit);
  }
  // Delete: Telegram's "Delete for everyone" is a Matrix redaction
  // (`event.canRedact`); a row still local to this device deletes locally.
  if (sent ? canRedact : ownMessage) actions.add(TelegramContextAction.delete);
  return actions;
}

/// Open the menu at [position] (global/stage coordinates, from
/// `LongPressStartDetails.globalPosition`) and return the item the user
/// picked, or null. The caller wires the item to its verbs - this file draws
/// the list and nothing else.
Future<TelegramContextAction?> showTelegramEventContextMenu(
  BuildContext context, {
  required Offset position,
  required List<TelegramContextAction> actions,
  required bool isPinned,
  bool inGifTray = false,
}) {
  final theme = Theme.of(context);
  final brightness = theme.brightness;
  final scheme = theme.colorScheme;
  final anchor =
      position +
      const Offset(
        TelegramContextMenuGeometry.touchOffset,
        TelegramContextMenuGeometry.touchOffset,
      );
  return showMenu<TelegramContextAction>(
    context: context,
    // The cut-out rect the menu lays itself out against: a point at the touch.
    position: RelativeRect.fromLTRB(anchor.dx, anchor.dy, anchor.dx, anchor.dy),
    color: TelegramContextMenuGeometry.menuFill(brightness, scheme),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(
        TelegramContextMenuGeometry.cornerRadius,
      ),
    ),
    constraints: const BoxConstraints(
      minWidth: TelegramContextMenuGeometry.minMenuWidth,
    ),
    items: [
      for (final action in actions)
        PopupMenuItem<TelegramContextAction>(
          value: action,
          height: TelegramContextMenuGeometry.itemHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: TelegramContextMenuGeometry.itemHorizontalPadding,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                action.icon(isPinned: isPinned),
                size: TelegramContextMenuGeometry.iconSize,
                color: TelegramContextMenuGeometry.iconInk(brightness, scheme),
              ),
              const SizedBox(width: TelegramContextMenuGeometry.iconLabelGap),
              Text(
                action.labelOf(
                  context,
                  isPinned: isPinned,
                  inGifTray: inGifTray,
                ),
                style: TextStyle(
                  fontSize: TelegramContextMenuGeometry.labelFontSize,
                  color: action == TelegramContextAction.delete
                      ? scheme.error
                      : TelegramContextMenuGeometry.labelInk(
                          brightness,
                          scheme,
                        ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
