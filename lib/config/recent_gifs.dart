// SPDX-FileCopyrightText: 2026 FluffyGram fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/telegram_gif.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// The GIF tray's own collection: the GIFs this user has sent, newest first.
///
/// Telegram's GIF panel opens on the user's own collection and the send path
/// is what grows it (`the measurement log` T56; a user's instruction
/// "just sending a GIF adds it to your gifs"). Telegram's provider half -
/// Giphy search and categories - is out of scope for this fork (AGENTS.md
/// rule 8), so the collection is the only content the panel has.
///
/// This is the same shape as `RecentStickers`, over its own key
/// (`AppSettings.recentGifs`): the last [cap] GIFs this user sent as a JSON
/// list of [RecentGif] entries on this device (one key holds every chat's
/// rows; T112 gives each row the room it came from, and since T117 the tray
/// shows **all** of them - one account-wide list, Telegram's own shape - with
/// [RecentGifs.gifsFor] kept for the per-chat scan guard) (T56.3.3: an entry is a url
/// plus the size the GIF had when it was sent, so a tile replayed from the
/// grid draws at its true shape). Device-local, not account data - the sticker decision of
/// 2026-10-27 (ROADMAP **Decisions**) applies unchanged: a recents list is a
/// per-device convenience, and account data would put a `Client` in a static
/// read path plus a `/sync` round between a send and the grid repainting.
/// Stickers and GIFs are different media, so they keep separate keys.
/// One GIF grid entry (T56.3.3): the stored `mxc://` url plus the size the
/// GIF had when it was sent. `w`/`h` are 0 when the size is unknown - a grid
/// stored by build 32/33, a first-run seed from history, a send that carried
/// no size - and the send then omits the size and behaves as T56.3 did.
///
/// T112 adds the two fields that make an encrypted send replayable:
/// * `room` - the id of the room the GIF was sent in. The tray is scoped per
///   chat (ROADMAP **Decisions**, "Media references are re-sent, and the tray
///   is per chat", user 2026-10-29): Synapse >=1.117 grants a media download
///   to a member who can read *an event referencing that media id*, so a tile
///   re-sent into another room would hand that room bytes it never got.
///   `''` means an entry written before T112, which no room's grid shows.
/// * `file` - the whole encrypted-file reference of the source event
///   (`{url, mimetype, v: 'v2', key, iv, hashes}`, SDK `room.dart:1120-1138`).
///   A send that carries it needs no second upload: 313 bytes of content
///   instead of the file (`the measurement log`, "POC (2026-10-29)").
///   `null` for a plain (unencrypted) send and for an older entry.
///
/// T117 (user, 2026-10-30: "SHA the gifs to avoid duplicates and store group
/// and URL per gif") adds `sha`, the plaintext content hash that collapses one
/// GIF sent into two chats down to one tile, and `groupName`, the name of the
/// chat the row came from - the readable half of the source a user asked to
/// keep beside the url.
final class RecentGif {
  final String url;
  final int w;
  final int h;
  final String room;
  final Map<String, Object?>? file;

  /// T116 (user capture 2026-10-30: the GIF tab drew one broken-image glyph):
  /// the id of the event the GIF was read from. A bare `mxc://` download in an
  /// encrypted room hands back the encrypted bytes, so the tile can only draw
  /// through the event - `Client.downloadMxcCached()` then `Image.memory()`
  /// fails and `mxc_image.dart:163-180` paints the glyph, while the event path
  /// `event.downloadAndDecryptAttachment()` (SDK `event.dart:813`) decrypts
  /// first. `''` is a row written by a build <= 74: it draws no picture. T125
  /// (2026-10-30) deleted the on-open history scan that used to refill it, so
  /// the explicit "Add to gifs" is what turns such a row into a playable one.
  final String eventId;

  /// T114 :
  /// Telegram's tray is `MediaDataController.getRecentGifs()` - the GIFs **I**
  /// sent, one account-wide list (`ui/Components/EmojiView.java:6292`). A row
  /// written by this fork's own writers always carries the marker; an entry
  /// stored by an older build reads `mine == false` and shows in no grid, which
  /// is what retires the other-member tiles build 72 seeded.
  final bool mine;

  /// T117 : hex SHA-256
  /// of the **decrypted** file, the content identity of the tile. The
  /// `file.hashes.sha256` a Matrix event carries is the hash of the
  /// **encrypted** bytes, and every send re-encrypts with a fresh key and iv,
  /// so two copies of one GIF never share it - plaintext hashing is the only
  /// test that finds a duplicate. `''` means not hashed yet; the tray fills it
  /// the first time it has the bytes ([RecentGifs.setSha]) and drops the rows
  /// that then share a hash.
  final String sha;

  /// T117 : the **name** of
  /// the chat the row came from, taken at record time. [room] is the room id,
  /// which is what a re-send and a delete need but is unreadable in a label;
  /// this string is what a "Sent in …" line prints, and it survives the chat
  /// being left or renamed later. Written by every row writer, `''` for an
  /// entry from an older build.
  final String groupName;

  /// T125 (user, 2026-10-30: "'Add to gifs' should be an option on gifs and
  /// animated webps"): this row went into the tray **by hand**, from the
  /// message long-press menu, so it draws whatever its sender is. A friend's
  /// GIF reads `mine == false, added == true` and still shows; the auto-record
  /// of my own send reads `added == false`, which is also what every entry
  /// written before T125 reads, so an existing store is unchanged.
  final bool added;

  /// T133 : the
  /// row is a **Convert to gif clip**, an `m.video` this fork marked with
  /// `org.fluffygram.gif`. Its bytes are an mp4, so the tile paints a poster and
  /// a replay sends `m.video` plus the marker - never an `m.image`.
  final bool video;

  const RecentGif(
    this.url, {
    this.w = 0,
    this.h = 0,
    this.room = '',
    this.file,
    this.eventId = '',
    this.mine = true,
    this.sha = '',
    this.groupName = '',
    this.added = false,
    this.video = false,
  });

  Map<String, Object?> toJson() => {
    'url': url,
    'w': w,
    'h': h,
    if (room.isNotEmpty) 'room': room,
    if (file != null) 'file': file,
    if (eventId.isNotEmpty) 'event': eventId,
    if (sha.isNotEmpty) 'sha': sha,
    if (groupName.isNotEmpty) 'from': groupName,
    if (mine) 'me': 1,
    if (added) 'added': 1,
    if (video) 'video': 1,
  };

  /// The tolerant reader (T56.3.3): a map entry reads its fields, a bare
  /// string - the entry shape build 32/33 wrote - reads as the url with
  /// `w == h == 0` so an existing grid survives the upgrade, and anything
  /// else (or a non-mxc url) reads as null.
  static RecentGif? fromJson(Object? raw) {
    if (raw is String) {
      // A bare string is a build 32/33 row: no `me` marker, so it is not one
      // of my GIFs and shows in no grid (T114).
      return raw.startsWith('mxc://') ? RecentGif(raw, mine: false) : null;
    }
    if (raw is! Map) return null;
    final url = raw['url'];
    if (url is! String || !url.startsWith('mxc://')) return null;
    final w = raw['w'];
    final h = raw['h'];
    final room = raw['room'];
    final file = raw['file'];
    final eventId = raw['event'];
    final sha = raw['sha'];
    final from = raw['from'];
    return RecentGif(
      url,
      mine: raw['me'] == 1,
      video: raw['video'] == 1,
      // T125: an entry written before T125 carries no `added` marker and
      // reads as an auto-recorded row.
      added: raw['added'] == 1,
      eventId: eventId is String ? eventId : '',
      sha: sha is String ? sha : '',
      groupName: from is String ? from : '',
      w: w is num ? w.toInt() : 0,
      h: h is num ? h.toInt() : 0,
      room: room is String ? room : '',
      file: file is Map ? Map<String, Object?>.from(file) : null,
    );
  }

  /// T124 (user, build 80, 2026-10-30): the mimetype this GIF was sent with.
  /// The row's own `file` map is the truth - a GIF the Compress toggle turned
  /// into an animated WebP reads `image/webp` there. `image/gif` is the
  /// fallback for a row that carries no `file` map (an unencrypted send, a row
  /// from a build older than T112). A tray re-send used to pin
  /// `info['mimetype']` to `image/gif`, which produced an event whose `info`
  /// said gif while its `file` said webp; other Matrix clients label the
  /// bubble from `info` and showed the wrong thing. This fork hid the
  /// mismatch because it sniffs magic bytes. T123 made `image/webp` on an
  /// `m.image` a recognised GIF, which is why this value needs no pin.
  String get mimeType {
    final mimetype = file?['mimetype'];
    if (mimetype is String && mimetype.isNotEmpty) return mimetype;
    // A clip sent into an unencrypted room carries no `file` map, so the
    // `image/gif` fallback would replay an mp4 as a picture.
    return video ? 'video/mp4' : 'image/gif';
  }

  /// The file name extension that matches [mimeType]. matrix-dart picks an
  /// image encoder from the file name in its resize path
  /// (`matrix_file.dart:229-253`, `encodeNamedImage(fileName)`), so a replay
  /// of WebP bytes must not be named `.gif`.
  String get fileExtension => switch (mimeType) {
    'image/webp' => 'webp',
    'video/mp4' => 'mp4',
    _ => 'gif',
  };
}

abstract final class RecentGifs {
  /// A GIF row holds more than a sticker row, so the cap is higher than
  /// `RecentStickers.cap` (20). One constant, named.
  static const int cap = 60;

  /// T56.2.2: the tray's GIF grid listens to this. The timeline insert hook of
  /// T56.3.2 is the only writer and fires it after the new value is stored.
  static final RecentGifsNotifier notifier = RecentGifsNotifier();

  /// T125 (user, 2026-10-30: "Even if I remove something from my gif tray, it
  /// comes back when I restart the app. The tray should be persistent storage,
  /// not calculated when I open the app"): the mxc urls a user took out of
  /// the tray by hand, `|`-joined, **newest last**, capped at [removedCap]. The
  /// key holds the **bare url**, not `room|url`: a removal is a fact about
  /// that media id, so it hides the GIF in every chat's tray. Every writer
  /// that builds a row out of an event ([record], [recordFromEvent],
  /// [seedFrom]) refuses a tombstoned url, so a timeline row that repaints -
  /// and the same history read again after a restart - cannot bring it back.
  /// Only a user's explicit "Add to gifs" lifts a tombstone, through
  /// [addFromEvent] and [clearRemoved].
  static const int removedCap = 500;

  static List<String> _removedUrls() => AppSettings.recentGifsRemoved.value
      .split('|')
      .where((url) => url.isNotEmpty)
      .toList(growable: false);

  static bool _isRemoved(String mxcUri) =>
      mxcUri.isNotEmpty && _removedUrls().contains(mxcUri);

  /// Remember that a user removed [mxcUri] (newest last, [removedCap]).
  static Future<void> _addRemoved(String mxcUri) async {
    if (!mxcUri.startsWith('mxc://')) return;
    final current = _removedUrls();
    if (current.contains(mxcUri)) return;
    final next = [...current.where((url) => url != mxcUri), mxcUri];
    // Newest last, so trimming the front keeps the freshest removals.
    if (next.length > removedCap) next.removeRange(0, next.length - removedCap);
    await AppSettings.recentGifsRemoved.setItem(next.join('|'));
  }

  /// Forget that [mxcUri] was removed, so its rows may be written again. The
  /// explicit "Add to gifs" calls this: a user asked for that GIF again,
  /// which outranks the earlier removal.
  static Future<void> clearRemoved(String mxcUri) async {
    final current = _removedUrls();
    if (!current.contains(mxcUri)) return;
    await AppSettings.recentGifsRemoved.setItem(
      current.where((url) => url != mxcUri).join('|'),
    );
  }

  /// The stored entries, most recent first. A damaged value reads as empty;
  /// bare-string entries from build 32/33 read through [RecentGif.fromJson].
  static List<RecentGif> get gifs {
    final stored = AppSettings.recentGifs.value;
    if (stored.isEmpty) return const [];
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! List) return const [];
      return decoded
          .map(RecentGif.fromJson)
          // T114: an entry with no `me` marker came from a build that recorded
          // the whole room's GIFs, so it reads as absent from every grid.
          // T125 widens the test with `added`: a row a user put in the tray
          // by hand - a friend's GIF included - draws even though it is not
          // one of my sends. A pre-T125 entry carries neither marker and
          // reads exactly as it did before.
          .whereType<RecentGif>()
          .where((gif) => gif.mine || gif.added)
          .toList(growable: false);
    } on FormatException catch (e) {
      Logs().v('RecentGifs: dropping damaged value', e);
      return const [];
    }
  }

  /// The stored urls only, most recent first - for callers that need just
  /// the urls (the seed guard, the gate).
  static List<String> get uris =>
      gifs.map((gif) => gif.url).toList(growable: false);

  /// T112: this room's rows only, most recent first. One store key still
  /// holds every room's rows (no per-room keys) and the flat [cap] is shared,
  /// so a busy chat can push another chat's oldest row out - accepted, the
  /// cap is a convenience bound, not a per-room quota. Entries written before
  /// T112 carry `room == ''` and so show in no grid: they hold no `file` map,
  /// which in an encrypted room is a tile that cannot be read.
  static List<RecentGif> gifsFor(String roomId) =>
      gifs.where((gif) => gif.room == roomId).toList(growable: false);

  /// T117 : write the content hash of a row, and collapse
  /// the rows that share it. The tray is one list across every chat, so the
  /// same GIF sent in two chats used to be two tiles; once both are hashed,
  /// the newest one stays and the older copy leaves. Called from the tray the
  /// first time it holds the decrypted bytes - hashing costs one pass over a
  /// file the tray just read, and only for a row that has no hash yet. Writes
  /// nothing when the hash is already stored.
  static Future<void> setSha(String mxcUri, String sha) async {
    if (!mxcUri.startsWith('mxc://') || sha.isEmpty) return;
    final current = gifs;
    if (!current.any((gif) => gif.url == mxcUri && gif.sha != sha)) return;
    final next = <RecentGif>[];
    var shaSeen = false;
    for (final gif in current) {
      final filled = gif.url == mxcUri ? _withSha(gif, sha) : gif;
      if (filled.sha.isNotEmpty && filled.sha == sha) {
        if (shaSeen) continue; // the same GIF under another url, older - out
        shaSeen = true;
      }
      next.add(filled);
    }
    if (next.length > cap) next.removeRange(cap, next.length);
    await AppSettings.recentGifs.setItem(
      jsonEncode([for (final gif in next) gif.toJson()]),
    );
    notifier.changed();
  }

  static RecentGif _withSha(RecentGif gif, String sha) => RecentGif(
    gif.url,
    w: gif.w,
    h: gif.h,
    room: gif.room,
    file: gif.file,
    eventId: gif.eventId,
    mine: gif.mine,
    sha: sha,
    groupName: gif.groupName,
    added: gif.added,
  );

  /// Move [mxcUri] to the front of the list with its sent size [w]/[h]
  /// (T56.3.3; 0 when the sent event carried no size), its room [room] and
  /// its file reference [file] (T112), dropping the duplicate and the oldest
  /// entry past [cap] - a re-send with a size updates the head entry's size,
  /// it does not add a second tile. Called only after a send completed, so a
  /// failed send never enters the grid. The duplicate test is url **and**
  /// room: the same GIF sent in two chats is two tiles, one per grid.
  static Future<void> record(
    String mxcUri, {
    int w = 0,
    int h = 0,
    String room = '',
    Map<String, Object?>? file,
    String eventId = '',
    bool mine = true,
    bool added = false,
    String groupName = '',
    bool video = false,
  }) async {
    if (!mxcUri.startsWith('mxc://')) return;
    // T125: a user removed this GIF by hand, so no writer may put it back.
    // The explicit add lifts the tombstone first ([addFromEvent]).
    if (_isRemoved(mxcUri)) return;
    final next = <RecentGif>[
      RecentGif(
        mxcUri,
        w: w,
        h: h,
        room: room,
        file: file,
        eventId: eventId,
        mine: mine,
        groupName: groupName,
        added: added,
        video: video,
      ),
      ...gifs.where((gif) => gif.url != mxcUri || gif.room != room),
    ];
    if (next.length > cap) next.removeRange(cap, next.length);
    await AppSettings.recentGifs.setItem(
      jsonEncode([for (final gif in next) gif.toJson()]),
    );
    notifier.changed();
  }

  /// T56.2.1: the tray's long-press menu takes one tile out of the grid.
  /// Drops [mxcUri] from [room]'s rows and notifies the open grid. Device-local,
  /// store-only - nothing is un-sent. Removing an absent uri writes nothing
  /// and notifies nothing.
  static Future<void> remove(
    String mxcUri, {
    String room = '',
    bool tombstone = true,
  }) async {
    // T126 (user, 2026-10-30: "I only see remove from gifs for gif I already
    // removed"). The delete matches the **media id alone**, in every chat. It
    // used to match `(url, room)`, which left a second row of the same GIF
    // alive when that GIF had also been sent in another chat - the tile in the
    // chat they tapped vanished, the row somewhere else stayed, and the
    // long-press menu (which asks `holds()`, a url match across the whole list)
    // still read "Remove from gifs". One tile per media id means one removal per
    // media id. `room` stays in the signature for the callers that name where
    // the tap happened; it no longer scopes the delete.
    final current = gifs;
    final next = current.where((gif) => gif.url != mxcUri).toList();
    if (next.length == current.length) return;
    await AppSettings.recentGifs.setItem(
      jsonEncode([for (final gif in next) gif.toJson()]),
    );
    // T125: the removal is remembered, not just applied. The tombstone is the
    // bare url, so that GIF stays out of **every** chat's tray from here on -
    // which is the same reach the rows themselves have (the grid is one global
    // list, `chat_emoji_picker.dart:452`). `tombstone: false` is
    // for a drop the app makes because it cannot read the file
    // (`ChatController.sendGif`): that is not a user saying "I do not want
    // this GIF", so it must not silence the row's source event forever.
    if (tombstone) await _addRemoved(mxcUri);
    notifier.changed();
  }

  /// T125: the long-press menu's "Remove from gifs". Drops **every** row that
  /// carries this event's GIF url - the menu sits on one row, a user's
  /// intent covers the whole tray - and tombstones the url.
  static Future<void> removeForEvent(Event event) async {
    final url = urlOf(event);
    if (url == null) return;
    // T126: one path, one rule - the media id leaves the store wherever it was
    // recorded, and the tombstone keeps it out.
    await remove(url, room: event.room.id);
  }

  /// The encrypted-file reference of an event, or null (a plain send, and the
  /// upload placeholder of T113, carry none).
  static Map<String, Object?>? _fileOf(Event event) {
    final raw = event.content['file'];
    return raw is Map ? raw.map((k, v) => MapEntry(k.toString(), v)) : null;
  }

  /// The mxc url of the GIF an event carries, in either shape: an encrypted
  /// send keeps it **inside** `content['file']` (SDK `room.dart:1120-1138`), a
  /// plain send has it at `content['url']`. Null when the row carries none.
  static String? urlOf(Event event) {
    final url = _fileOf(event)?['url'] ?? event.content['url'];
    return url is String && url.startsWith('mxc://') ? url : null;
  }

  /// True when this event's GIF is in the tray right now - the test that makes
  /// the long-press menu read "Remove from gifs" instead of "Add to gifs".
  static bool holds(Event event) {
    final url = urlOf(event);
    return url != null && gifs.any((gif) => gif.url == url);
  }

  /// T125 (user, 2026-10-30: "'Add to gifs' should be an option on gifs and
  /// animated webps"): put the GIF of **any** GIF event - mine or another
  /// member's - into the tray by hand. Lifts any tombstone first, so the
  /// explicit add outranks an earlier removal, and marks the row
  /// [RecentGif.added] so it draws with `mine == false`. Reads only what the
  /// event already carries (url, `info` size, `file` reference, event id,
  /// room name): nothing is downloaded, re-encoded or re-uploaded here. A row
  /// whose bytes this chat never saw is pulled when a user taps the tile,
  /// by `TelegramGifFile.file()` inside `ChatController.sendGif`.
  static Future<void> addFromEvent(Event event) async {
    final file = _fileOf(event);
    final url = file?['url'] ?? event.content['url'];
    if (url is! String) return;
    final info = event.content['info'];
    final w = info is Map ? info['w'] : null;
    final h = info is Map ? info['h'] : null;
    await clearRemoved(url);
    await record(
      url,
      w: w is num ? w.toInt() : 0,
      h: h is num ? h.toInt() : 0,
      room: event.room.id,
      file: file,
      eventId: event.eventId,
      mine: event.senderId == event.room.client.userID,
      added: true,
      groupName: event.room.name,
      video: telegramEventIsMp4Gif(event),
    );
  }

  /// `room|mxc` of every row this process wrote from an event **whose id was a
  /// real event id**, so a timeline row that rebuilds on every frame does not
  /// write the store again. T124: a write that carried only a transaction id is
  /// not settled, so it stays out of this set and the sent event for the same
  /// media id is free to upgrade the row.
  static final Set<String> _recordedFromEvents = {};

  /// T113 : record the
  /// GIF of a **displayed** event. The timeline insert hook cannot be the only
  /// writer: `Room.sendFileEvent()` puts a **placeholder** event in the
  /// timeline first, whose content is `msgtype`/`body`/`filename`/`info` and
  /// **no url at all** (`room.dart:868-897`, "a fake Event object as a
  /// placeholder for the uploading file"), and the finished event *replaces*
  /// that placeholder without a new insert. So an own send was tested against a
  /// content map that could never carry a url - the tray stayed empty in every
  /// room, encrypted or not, while the seed scan and other clients' sends worked.
  /// The row that plays the GIF is the first place it is visible with its real
  /// content, and it is the same `telegramEventIsGif()` test a user just saw
  /// pass. Idempotent through [_recordedFromEvents].
  ///
  /// T124 (user, 2026-10-30: "when I first upload, the tray isn't showing the
  /// new gif until I restart the app. It shows a slot for it, but no image"):
  /// that placeholder is now refused outright, and a row whose stored event id
  /// is not a real one may be upgraded. The tile draws through the **source
  /// event** ([RecentGif.eventId]), and `Room.getEventById()` resolves only a
  /// `$`-prefixed event id - a matrix-dart transaction id is not one - so a row
  /// recorded from the placeholder paints an empty slot until the history scan
  /// rewrites it, which is what made a restart look like the fix.
  static Future<void> recordFromEvent(Event event) async {
    // T124: an event that is not sent has a transaction id and no final
    // content, so it can only ever record an unusable row.
    if (!event.status.isSent) return;
    // T125, T114's rule stated at the writer: auto-record is mine-only -
    // Telegram's tray holds the GIFs **I** sent (`MediaDataController
    // .getRecentGifs()`, EmojiView.java:6292). Until now the rule was only
    // implicit: this writer passed `mine: true` for every event it read, so a
    // friend's GIF shown in the timeline entered the store as if it were my
    // send. A friend's GIF gets in through the explicit [addFromEvent], which
    // marks the row [RecentGif.added] instead.
    if (event.senderId != event.room.client.userID) return;
    // T133: a Convert to gif clip (`m.video` + `org.fluffygram.gif`) belongs in
    // the tray exactly like an animated picture - Telegram's tray holds the GIFs
    // I sent, and its "send as GIF" path produces the same kind of row.
    final isMp4Gif = telegramEventIsMp4Gif(event);
    if (!isMp4Gif && !telegramEventIsGif(event)) return;
    final content = event.content;
    final file = _fileOf(event);
    final url = file?['url'] ?? content['url'];
    if (url is! String) return;
    // T125: a user removed this GIF. A row that repaints, and the same
    // media id read again after a restart, must not undo that.
    if (_isRemoved(url)) return;
    final roomId = event.room.id;
    // T124: a real event id starts with `$`. One settled row per `room|mxc` is
    // written once and then left alone; an id that is empty or a transaction id
    // (a row build <= 80 left behind) is not settled, so the seen-set does not
    // hold it and the first sent event for that media id upgrades the row.
    // The merge itself is `record()`'s - the new row goes to the front and the
    // matching `room|mxc` row drops out, so there is one writer for both cases.
    final settled = event.eventId.startsWith(r'$');
    if (settled) {
      if (_recordedFromEvents.contains('$roomId|$url')) return;
      _recordedFromEvents.add('$roomId|$url');
    }
    final info = content['info'];
    final w = info is Map ? info['w'] : null;
    final h = info is Map ? info['h'] : null;
    await record(
      url,
      w: w is num ? w.toInt() : 0,
      h: h is num ? h.toInt() : 0,
      room: roomId,
      file: file,
      eventId: event.eventId,
      groupName: event.room.name,
      video: isMp4Gif,
    );
  }

  /// T56.3.1: fill the store from the room's own GIF history on a fresh
  /// install, so the tray's `GIFs` tab is not empty on day one. [entries] come
  /// newest first, built from the history events - T112: each one carries the
  /// room id it was read in and the `file` reference when the event had one,
  /// so a seeded tile replays with zero uploads instead of posting an
  /// unreadable bubble. Writes only a store that is currently empty - a
  /// member's own grid always wins - dedupes keeping the newest occurrence,
  /// trims to [cap], and fires [notifier] once for the whole batch.
  static Future<void> seedFrom(List<RecentGif> entries) async {
    if (entries.isEmpty) return;
    // T113: the guard is per chat - a device that already filled one chat's
    // tray still fills the next one. A chat that has rows is never touched. An
    // entry with no room id (a pre-T112 caller) keeps the old device-wide rule.
    final seedRoom = entries.first.room;
    if (seedRoom.isEmpty) {
      if (RecentGifs.gifs.isNotEmpty) return;
    } else if (RecentGifs.gifsFor(seedRoom).isNotEmpty) {
      return;
    }
    final next = <RecentGif>[];
    for (final gif in entries) {
      // T125: a tombstoned url is refused here too - a scan over a room's
      // history was the widest route back in for a GIF a user deleted.
      if (!(gif.mine || gif.added) ||
          !gif.url.startsWith('mxc://') ||
          _isRemoved(gif.url) ||
          next.any((other) => other.url == gif.url && other.room == gif.room)) {
        continue;
      }
      next.add(gif);
      if (next.length == cap) break;
    }
    if (next.isEmpty) return;
    // T116: one store key holds **every** chat's rows and the scan runs per
    // chat, so writing only `next` erased the chats scanned before it - the `v3`
    // re-arm would have made that visible (chat B's scan wiped chat A's tray,
    // and chat A's marker then kept it empty for good). This chat's fresh rows
    // go in front, every other chat's rows follow, and the flat [cap] still
    // trims.
    final merged = <RecentGif>[
      ...next,
      ...gifs.where((gif) => gif.room != seedRoom),
    ];
    if (merged.length > cap) merged.removeRange(cap, merged.length);
    await AppSettings.recentGifs.setItem(
      jsonEncode([for (final gif in merged) gif.toJson()]),
    );
    notifier.changed();
  }
}

/// The notification seam of the GIF store (T56.2.2), for the same reason as
/// `RecentStickersNotifier`: `ChangeNotifier.notifyListeners()` is
/// `@protected`, so the store fires through this subclass.
class RecentGifsNotifier extends ChangeNotifier {
  /// Tell the listeners - the tray's GIF grid - that the collection changed.
  void changed() => notifyListeners();
}
