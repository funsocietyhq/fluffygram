// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// Telegram's "recently used stickers" row.
///
/// The last [cap] sticker `mxc://` URIs, most recent first, kept on this
/// device in `AppSettings.recentStickers` as a JSON list - the same shape
/// T5B's chat background map uses. Nothing here is protocol state: the
/// sticker send events are unchanged, only this local preference is written.
/// The notification seam of a recents store (T56.2.2). The tray's recents row
/// listens to it, so a sticker sent while the tray is open enters the row
/// without a close-and-reopen. `ChangeNotifier.notifyListeners()` is
/// `@protected`, so a store fires through this subclass instead of from
/// outside the class.
class RecentStickersNotifier extends ChangeNotifier {
  /// Tell the listeners - the tray's recents row - that the list changed.
  void changed() => notifyListeners();
}

abstract final class RecentStickers {
  /// Telegram pins about twenty stickers in the tray.
  static const int cap = 20;

  /// T56.2.2: the tray's recents row listens to this. `record()` is the only
  /// writer and fires it after the new value is stored.
  static final RecentStickersNotifier notifier = RecentStickersNotifier();

  /// The stored URIs, most recent first. A damaged value reads as empty.
  static List<String> get uris {
    final stored = AppSettings.recentStickers.value;
    if (stored.isEmpty) return const [];
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! List) return const [];
      return decoded
          .whereType<String>()
          .where((uri) => uri.startsWith('mxc://'))
          .toList(growable: false);
    } on FormatException catch (e) {
      Logs().v('RecentStickers: dropping damaged value', e);
      return const [];
    }
  }

  /// Move [url] to the front of the list, dropping the duplicate and the
  /// oldest entry past [cap].
  static Future<void> record(Uri url) async {
    final uri = url.toString();
    final next = <String>[uri, ...uris.where((stored) => stored != uri)];
    if (next.length > cap) next.removeRange(cap, next.length);
    await AppSettings.recentStickers.setItem(jsonEncode(next));
    notifier.changed();
  }

  /// T56.2.1: the tray's long-press menu takes one tile out of the row.
  /// Drops [url] from the list and notifies the open row. Device-local,
  /// store-only - nothing is un-sent. Removing an absent uri writes nothing
  /// and notifies nothing.
  static Future<void> remove(Uri url) async {
    final uri = url.toString();
    final current = uris;
    final next = current.where((stored) => stored != uri).toList();
    if (next.length == current.length) return;
    await AppSettings.recentStickers.setItem(jsonEncode(next));
    notifier.changed();
  }

  /// The mxc url of the sticker an event carries. A Matrix sticker is a plain
  /// `mxc://` reference (`content['url']`) - never the encrypted-attachment
  /// shape a photo uses, where the url sits inside `content['file']`
  /// (`matrix-14.1.0/lib/src/room.dart:1120-1138`) - and both shapes are read
  /// here so a hand-made sticker event works too. Null for the url-less
  /// placeholder `Room.sendEvent()` inserts while the send is in flight.
  static String? urlOf(Event event) {
    final file = event.content['file'];
    final url = (file is Map ? file['url'] : null) ?? event.content['url'];
    return url is String && url.startsWith('mxc://') ? url : null;
  }

  /// True when this row's sticker is in the drawer right now - the test that
  /// makes the context menu read "Remove from stickers" instead of "Add to
  /// stickers" (T142, the T125 rule for GIF rows).
  static bool holds(Event event) {
    final url = urlOf(event);
    return url != null && uris.contains(url);
  }

  /// T142 (user, 2026-10-30: "'add to stickers' etc? Then they'd show up in the
  /// sticker drawer"): put the sticker of **any** sticker row - mine or a
  /// friend's - into the drawer by hand. Reads only what the event carries; no
  /// download, no re-encode, no `im.ponies` pack write (a pack is a shared
  /// account-data object; the recents row is the device-local list Telegram's
  /// drawer shows first).
  static Future<void> addFromEvent(Event event) async {
    final url = urlOf(event);
    if (url == null) return;
    await record(Uri.parse(url));
  }

  /// Take this row's sticker out of the drawer. Device-local: nothing is
  /// un-sent, and the same sticker sent again enters the row again - Telegram
  /// behaves the same way, and unlike the GIF tray this store keeps no
  /// tombstone, because a sticker list of 20 urls is cheap to re-add.
  static Future<void> removeForEvent(Event event) async {
    final url = urlOf(event);
    if (url == null) return;
    await remove(Uri.parse(url));
  }
}
