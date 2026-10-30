// SPDX-FileCopyrightText: 2026-Present Contributors to FluffyGram
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

/// The fork's own media cache: a decrypted attachment kept under the app's
/// cache folder, keyed by its `mxc://` id, so the next open of the same video
/// plays from disk with no request (ROADMAP T84).
///
/// Element X's shape, and the shape the whole-file video path (T82) needed:
/// download once, play from the file, keep what fits. Before this class the
/// video page wrote its decrypted bytes into the OS temp folder under the
/// `mxc` name and nobody read that folder back: every viewer open of the same
/// clip was a fresh download, and finished files stayed there unbounded.
///
/// Three limits, a user's numbers (2026-10-29):
///
/// * one file is kept when it is at most [maxCachedFileBytes]; a bigger clip
///   plays from the temp folder and is not kept, which is the "up to a certain
///   size" rule they asked for;
/// * the whole folder is kept under [maxCacheBytes], least-recently-used
///   first out;
/// * an entry older than [keepMediaFor] is dropped on the next adopt. It is
///   the SDK's own window - `deleteFilesAfterDuration`, 30 days, at
///   `flutter_matrix_dart_sdk_database/builder.dart:127-129`. It was seven
///   days, and that is what made a user's GIF tray "still takes a while" on
///   build 76: a gif older than a week was decrypted again on the next open
///   (T117.1, user 2026-10-30). Telegram's own cache maths (`MediaStorage`) is
///   not in the vendored sparse clone, so no Telegram number backs it either.
///
/// The folder is `getTemporaryDirectory()/matrix-media`: the app cache folder
/// a user picked, so Android may clear it under storage pressure and
/// Settings -> Apps -> Clear cache wipes it. A cleared cache costs a
/// re-download and nothing else.
class TelegramMediaCache {
  static const int maxCachedFileBytes = 250 * 1024 * 1024;
  static const int maxCacheBytes = 1024 * 1024 * 1024;
  static const Duration keepMediaFor = Duration(days: 30);

  static const String _dirName = 'matrix-media';

  /// The cached plaintext file for this event, or null when there is no usable
  /// entry. A hit means: the id matches, the entry is younger than
  /// [keepMediaFor] and inside [maxCachedFileBytes], and - when the event
  /// declares its plaintext length - the file length equals it. A hit touches
  /// the entry, so "least recently used" counts plays, not the day it was
  /// downloaded.
  static Future<File?> cached(Event event) async {
    final expected = _plainSize(event);
    final safe = _safeId(event);
    if (safe == null) return null;
    final dir = await _dir();
    final key = _key(safe, expected);
    final file = File('${dir.path}/$key');
    if (file.existsSync()) return _accept(file, expected, key);
    if (expected != null) return null;
    // T122 stage 2 (user, 2026-10-30: "gallery mode is re downloading the gif
    // each time instead of using the cache ... black screen and then loading
    // like 10 seconds later"). The GIF the tray re-sends by reference declares
    // no `info.size` - `lib/pages/chat/chat.dart` `_sendGifByReference` (T112)
    // writes `mimetype` and `w`/`h` only - and matrix-dart calls an attachment
    // with no declared size non-storeable (`event.dart:843-851`). So its exact
    // key is `<id>.unknown` while the very same bytes sit under the original
    // event's `<id>.<size>`: a guaranteed miss on the row that must hit, and a
    // fresh 4 MB fetch on every open. One media id names exactly one byte
    // string, so when this event declares no length an entry named
    // `<id>.`anything IS these bytes.
    return _byIdPrefix(dir, safe);
  }

  /// Decides a found entry for both lookup paths of [cached]: the length check
  /// the event's declaration allows, the byte cap, the 30-day window, then the
  /// touch that makes LRU count plays.
  static File? _accept(File file, int? expectedSize, String key) {
    final bytes = file.lengthSync();
    if (expectedSize != null && bytes != expectedSize) {
      // Not the same bytes - a partial write, or an id reused. Refuse it and
      // let the caller fetch, rather than hand a player a file nobody verified.
      debugPrint(
        '[TelegramCache] stale entry for $key: $bytes bytes, event declares '
        '$expectedSize',
      );
      return null;
    }
    if (bytes > maxCachedFileBytes) {
      debugPrint(
        '[TelegramCache] $key is $bytes bytes, over the $maxCachedFileBytes '
        'cap: refusing it',
      );
      return null;
    }
    if (_isExpired(file)) return null;
    file.setLastModifiedSync(DateTime.now());
    if (expectedSize == null) {
      // A size-unknown entry: id, age and the cap decide, which is already all
      // the byte cap and the LRU pass use.
      debugPrint(
        '[TelegramCache] hit $key, size not declared ($bytes bytes on disk)',
      );
    } else {
      debugPrint('[TelegramCache] hit $key ($bytes bytes)');
    }
    return file;
  }

  /// The entry of an event that declares no plaintext size: the newest file in
  /// the folder named `<id>.`anything. [cached] reaches this only after its
  /// exact `<id>.unknown` key missed, and one media id names one byte string,
  /// so `<id>.<size>` - written by the original send of that media - is it.
  static File? _byIdPrefix(Directory dir, String safeId) {
    File? found;
    try {
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.startsWith('$safeId.')) continue;
        if (
          found == null ||
          entity.statSync().modified.isAfter(found.statSync().modified)
        ) {
          found = entity;
        }
      }
    } on Object catch (e) {
      debugPrint('[TelegramCache] id scan failed: $e');
      return null;
    }
    final entry = found;
    if (entry == null) return null;
    return _accept(entry, null, entry.uri.pathSegments.last);
  }

  /// The decrypted file of [event]: a [cached] hit when there is one, otherwise
  /// **one** download + decrypt that is kept, so the next open is a file read.
  /// This is the body `TelegramGifFile._fetchNow` grew for the GIF tray
  /// (T117.1), pulled here because the chat timeline row needs the same thing
  /// (T120, user 2026-10-30: "The timeline view needs cache or something:").
  static Future<File?> fileFor(Event event) async {
    final hit = await cached(event);
    if (hit != null) return hit;
    final MatrixFile decrypted;
    try {
      decrypted = await event.downloadAndDecryptAttachment();
    } on Object catch (e) {
      debugPrint('[TelegramCache] download failed: $e');
      return null;
    }
    return keep(event, decrypted.bytes);
  }

  /// Keeps bytes the caller **already decrypted** in the cache: a temp file in
  /// `getTemporaryDirectory()`, then [adopt]. A caller that paid the decrypt to
  /// paint once (the timeline media row, T120) hands the bytes over instead of
  /// calling [fileFor], which would download and decrypt a second time.
  static Future<File?> keep(Event event, Uint8List bytes) async {
    final File tempFile;
    try {
      final temp = await getTemporaryDirectory();
      tempFile = File(
        '${temp.path}/media-${DateTime.now().microsecondsSinceEpoch}',
      );
      await tempFile.writeAsBytes(bytes);
    } on Object catch (e) {
      debugPrint('[TelegramCache] temp write failed: $e');
      return null;
    }
    // `adopt` moves the file into the cache under the event's key, or returns
    // null when it is over [maxCachedFileBytes]; the temp file then stays the
    // caller's, exactly as before this cache existed.
    return await adopt(file: tempFile, event: event) ?? tempFile;
  }

  /// Moves [file] into the cache and returns its new path, or null when the
  /// file is too big to keep - the caller then keeps playing the path it
  /// already holds. Adoption is the eviction point: one download can only push
  /// the folder over its cap at the moment it lands.
  static Future<File?> adopt({required File file, required Event event}) async {
    final expected = _plainSize(event);
    final safe = _safeId(event);
    if (safe == null) return null;
    final key = _key(safe, expected);
    final bytes = file.lengthSync();
    if (expected == null) {
      debugPrint(
        '[TelegramCache] $key carries no declared plaintext size: kept anyway, '
        'so the next open does not decrypt it again',
      );
    }
    if (bytes > maxCachedFileBytes) {
      debugPrint(
        '[TelegramCache] $key is $bytes bytes, over the '
        '$maxCachedFileBytes byte cap: played from the temp folder, not kept',
      );
      return null;
    }
    final dir = await _dir();
    final target = File('${dir.path}/$key');
    try {
      if (await target.exists()) await target.delete();
      await file.rename(target.path);
    } on Object catch (e) {
      // Cross-device rename (a mounted SD card, a web shell) throws: the copy
      // is the fallback, and a cache that refused to fill is the better
      // failure than a video that never played.
      debugPrint('[TelegramCache] rename failed ($e), copying');
      try {
        await file.copy(target.path);
        await file.delete();
      } on Object catch (e) {
        debugPrint('[TelegramCache] adopt failed: $e');
        return null;
      }
    }
    unawaited(_evict(dir));
    debugPrint('[TelegramCache] kept $key ($bytes bytes)');
    return target;
  }

  /// Drops entries older than [keepMediaFor], then the oldest entries until
  /// the folder is back under [maxCacheBytes].
  /// T139: the pass carries one stat per entry instead of re-asking for it.
  /// `statSync()` blocks the isolate that painted the row that just asked for
  /// these bytes, and a sort comparator that calls it pays again for the same
  /// file on every one of the ~2 n log n comparisons. Measured on this box
  /// (`the measurement log`, 2026-10-30): one pass over 20 / 100 / 400 /
  /// 1200 entries cost 2.0 / 4.4 / 14.4 / 50.7 ms as shipped, and 0.13 / 0.40 /
  /// 1.44 / 4.2 ms with the value remembered. `adopt()` runs this after every
  /// media download, so a fling through not-yet-cached media paid it once a row.
  static Future<void> _evict(Directory dir) async {
    final entries = <({File file, int bytes, DateTime touched})>[];
    var total = 0;
    final now = DateTime.now();
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final int bytes;
      final DateTime touched;
      try {
        final stat = entity.statSync();
        bytes = stat.size;
        touched = stat.modified;
      } on Object catch (_) {
        continue;
      }
      // `lastModified` is the play time, refreshed by [cached].
      if (now.difference(touched) > keepMediaFor) {
        await _delete(entity);
        continue;
      }
      total += bytes;
      entries.add((file: entity, bytes: bytes, touched: touched));
    }
    if (total <= maxCacheBytes) return;
    // Oldest touch first out.
    entries.sort((a, b) => a.touched.compareTo(b.touched));
    for (final entry in entries) {
      if (total <= maxCacheBytes) break;
      if (await _delete(entry.file)) total -= entry.bytes;
    }
  }

  static Future<bool> _delete(File file) async {
    try {
      await file.delete();
      debugPrint('[TelegramCache] evicted ${file.path.split('/').last}');
      return true;
    } on Object catch (e) {
      // A file a player still holds open refuses to go; the next adopt tries
      // again.
      debugPrint('[TelegramCache] delete refused: $e');
      return false;
    }
  }

  static bool _isExpired(File file) {
    final age = DateTime.now().difference(file.statSync().modified);
    if (age <= keepMediaFor) return false;
    debugPrint(
      '[TelegramCache] ${file.path.split('/').last} is $age old: drop',
    );
    return true;
  }

  /// The plaintext size the event declares (`info.size` - Matrix stores the
  /// decrypted length). FluffyChat writes it on its own sends; other clients
  /// and a re-sent media reference are not bound to, so it can be absent and
  /// [cached] then checks the entry by id and age alone (T117.1).
  static int? _plainSize(Event event) =>
      event.content.tryGetMap<String, Object?>('info')?.tryGet<int>('size');

  static String? _safeId(Event event) {
    final mxc = event.attachmentMxcUrl?.pathSegments.last;
    if (mxc == null || mxc.isEmpty) return null;
    return mxc.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  static String _key(String safeId, int? expectedSize) {
    // The size is in the name, so an id that comes back with different bytes
    // is a different entry, never a length mismatch to reject at read time.
    // `unknown` is the entry of an event that declares no size: before T117.1
    // such an event got **no entry at all**, and its tray tile paid a fresh
    // decrypt on every open. [cached] answers a size-less lookup that misses
    // here by the media id alone (T122 stage 2), so `<id>.unknown` and
    // `<id>.<size>` see each other.
    return '$safeId.${expectedSize ?? 'unknown'}';
  }

  static Future<Directory> _dir() async {
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/$_dirName');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }
}
