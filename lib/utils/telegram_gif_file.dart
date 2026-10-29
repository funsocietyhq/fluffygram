// SPDX-FileCopyrightText: 2026-Present Contributors to FluffyGram
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

// Transitive (the SDK's own dependency): the analyzer's `depend_on_referenced_
// packages` info notes it, which `--no-fatal-infos` tolerates. Adding it to
// pubspec.yaml is an user decision (AGENTS.md ground rule 8), and re-hashing
// by hand is not worth 60 lines.
import 'package:crypto/crypto.dart';
import 'package:fluffychat/config/recent_gifs.dart';
import 'package:fluffychat/utils/attachments/telegram_media_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// The file behind one GIF tray row (ROADMAP T117, user 2026-10-30: "i want
/// gifs cached. In the tray. Decrypting is taking too long").
///
/// What the tray used to do per open: every visible tile called
/// `Event.downloadAndDecryptAttachment()` (SDK `event.dart:813`), which reads
/// the **encrypted** bytes back out of the SDK's own media store and runs
/// AES-CTR again. That store is capped at 10 MB per file and pruned after 30
/// days (`maxFileSize` / `deleteFilesAfterDuration`, this fork's SDK database
/// at `flutter_matrix_dart_sdk_database/builder.dart:127-129`), so a bigger
/// gif was fetched from the server again, and with 60 rows in one grid the
/// tiles all fetched at once.
///
/// So the tray reads [file]: a hit in [TelegramMediaCache] - the fork's own
/// folder of **decrypted** files keyed by mxc id and plaintext size - is a
/// plain file open, and the miss downloads and decrypts **once**, into a
/// single in-flight slot, and is kept. `FileImage` then hands the decoded
/// frames to Flutter's image cache, which is what makes re-opening the tray
/// instant.
abstract final class TelegramGifFile {
  /// The decrypted gif of [gif] as a file, or null when it cannot be had: no
  /// source event (a row written by a build that stored no event id, a chat
  /// that was left), or the download failed. A tray tile draws an empty box in
  /// that case and never a glyph - Telegram's tray draws a cached file or
  /// nothing.
  static Future<File?> file(RecentGif gif, {required Client client}) async {
    final event = await sourceEvent(gif, client);
    if (event == null) return null;
    final started = DateTime.now();
    final cached = await TelegramMediaCache.cached(event);
    if (cached != null) {
      // A user's phone answers the "is the file too big?" question with
      // these two numbers (T117.1): a hit costs milliseconds and says how many
      // bytes the gif actually is.
      debugPrint(
        '[TelegramGif] cache hit ${DateTime.now().difference(started).inMilliseconds} ms '
        '${cached.lengthSync()} bytes',
      );
      return cached;
    }
    final file = await _fetch(event);
    debugPrint(
      '[TelegramGif] cache miss ${DateTime.now().difference(started).inMilliseconds} ms '
      '${file == null ? '-' : '${file.lengthSync()} bytes'}',
    );
    return file;
  }

  /// The event the row was recorded from, read through the room the row came
  /// from, so the tray is one list across every chat (T117).
  /// `Room.getEventById()` reads the local database and sends no request (SDK
  /// `room.dart:2225`).
  static Future<Event?> sourceEvent(RecentGif gif, Client client) async {
    if (gif.eventId.isEmpty) return null;
    final room = client.getRoomById(gif.room);
    if (room == null) return null;
    return await room.getEventById(gif.eventId);
  }

  /// One fetch at a time. A grid of 60 tiles used to start 60 downloads and
  /// hold 60 decrypted gifs in memory at once; one slot keeps the peak at a
  /// single file, and every fetch after the first is a cache hit anyway.
  static Future<void> _tail = Future<void>.value();

  static Future<File?> _fetch(Event event) {
    final next = _tail.then((_) => _fetchNow(event));
    // The tail never carries an error, so one failed fetch cannot poison the
    // ones queued behind it.
    _tail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  /// One fetch: [TelegramMediaCache.fileFor] - a cache hit, or one download and
  /// decrypt that is kept (the body this class grew in T117.1, moved into the
  /// cache in T120 because the timeline media row needs it too). Its
  /// `download failed` / `temp write failed` lines now print under the
  /// `[TelegramCache]` tag.
  static Future<File?> _fetchNow(Event event) =>
      TelegramMediaCache.fileFor(event);

  /// Hex SHA-256 of the decrypted bytes - the content identity the tray
  /// dedupes on . One
  /// pass over a file the tray already read, and only for a row with no hash.
  static Future<String> sha256Of(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}
