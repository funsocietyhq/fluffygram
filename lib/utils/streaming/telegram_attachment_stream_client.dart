// SPDX-FileCopyrightText: 2026-Present Contributors to FluffyGram
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'telegram_attachment_stream.dart';
import 'telegram_loopback_media_server.dart';

/// An encrypted attachment that plays while it downloads: the stream plus the
/// loopback byte server in front of it (ROADMAP T55).
///
/// [open] is the whole decision. It returns null - "use the old path" - for
/// every case this cannot serve: a web build (no loopback socket), an
/// attachment that is not encrypted, an MP4 whose index sits at the end of the
/// file and whose server will not give byte ranges, a container we cannot
/// probe, a file bigger than [maxStreamBytes] (the plaintext is held in
/// memory), a homeserver that refuses `Range` requests. The caller then does
/// exactly what it did before: `downloadAndDecryptAttachment()` to a temp file.
class TelegramAttachmentStreamSession {
  TelegramAttachmentStreamSession._({
    required this.stream,
    required this.server,
    required this.contentLength,
    this.indexServedByTailFetch = false,
  });

  /// Null for a plain (unencrypted-room) session: the byte service is the
  /// homeserver's own range endpoint, so there is no crypto stream to own.
  final TelegramAttachmentStream? stream;
  final TelegramLoopbackMediaServer server;

  /// Total bytes the player will be served (ciphertext for an encrypted
  /// attachment, the file itself for a plain one).
  final int contentLength;

  /// The URL to hand `VideoPlayerController.networkUrl`.
  Uri get url => server.url;

  /// Whether a player that starts at byte 0 can reach the MP4 sample index
  /// without waiting for the download. False means it cannot: the file keeps its
  /// index in its last ~20 KB (user a build logcat a log id asks
  /// `bytes=31625342-` of 31,645,902 and `bytes=22526129-` of 22,548,864 while
  /// only 4,194,304 bytes are here), and a byte service that answers in file
  /// order cannot serve it, so the caller must finish the download before a
  /// player sees these bytes (T76). True covers a front-loaded `moov` and the
  /// chunked mode, where a range fetch already pulled the tail. Null while the
  /// layout is unknown or not a walkable container: the caller keeps progressive
  /// playback.
  bool? get containerIndexReachable =>
      indexServedByTailFetch ? true : stream?.containerIndexInHead;

  /// Set by the chunked mode when it pulled the range that holds the index.
  final bool indexServedByTailFetch;

  int get byteLength => stream?.byteLength ?? contentLength;

  int get downloadedBytes => stream?.filledBytes ?? contentLength;

  /// True once the whole ciphertext has arrived and matched the attachment's
  /// own SHA-256. A plain session has no hash to match, so it is true from
  /// the start - the homeserver connection carries its own TLS integrity.
  bool get integrityOk => stream?.integrityOk ?? true;

  /// Why streaming gave up, null while healthy.
  Object? get failure => stream?.failure;

  Future<void> dispose() async {
    await stream?.stop();
    await server.close();
  }

  /// Writes the bytes this session already downloaded into [file] once they are
  /// all here, and returns that file. Null when the stream gave up first: this
  /// media was fetched exactly once, so nothing here starts a second request -
  /// a user's a build log paid for a 31,645,902-byte video twice after the
  /// player died at its tail seek (T76). Callers dispose the session after the
  /// write: the plaintext buffer is the session's to free.
  Future<File?> writeDownloadedFile(File file) async {
    final stream = this.stream;
    if (stream == null) return null;
    if (!await stream.awaitComplete()) {
      debugPrint(
        '[TelegramStream] download stopped before the last byte: $failure',
      );
      return null;
    }
    final plain = stream.plainBytesWhenComplete;
    if (plain == null) return null;
    await file.writeAsBytes(plain);
    debugPrint(
      '[TelegramStream] whole file landed: ${plain.length} bytes at $file '
      '(written by the one stream, no second fetch)',
    );
    return file;
  }

  /// Largest attachment we will stream: the decrypted bytes are held in memory
  /// so the player can seek backwards into them.
  static const int maxStreamBytes = 256 << 20; // 256 MiB

  /// At or below this size a video is fetched with **one** `GET` and **no**
  /// `Range` header (ROADMAP T59b: 1 request for a user's 22,548,864-byte
  /// video, where build 41 made 86 and build 42 made 6, and remote-hosted
  /// media answers `Range:` with 500). Above it the chunked path stays exactly
  /// as build 42 shipped it: 512 KiB crypto chunks, 4 MiB byte-server spans.
  ///
  /// The line is the resident-memory budget of one playback. A whole-file
  /// request publishes through one resident plaintext buffer (the file size)
  /// plus one 512 KiB working block, the response itself streams, so a 22 MB
  /// video costs ~23 MiB and 48 MiB is the most a phone should hold for one
  /// clip while the viewer, the room and the media cache are alive. Two more
  /// costs grow with the file and stop being worth it past this line: a whole
  /// file request that dies restarts from byte 0 (a range path resumes at the
  /// fill cursor), and the `429` retry loop re-sends the whole request.
  static const int maxSingleStreamBytes = 48 << 20; // 48 MiB

  /// How much of the head we read to find the MP4 index.
  static const int probeBytes = 2 << 20; // 2 MiB

  /// How much of the tail we read when the index is at the end.
  static const int tailBytes = 4 << 20; // 4 MiB

  static final Random _random = Random.secure();

  /// Prepares a stream for [event]'s video attachment. Null means "not
  /// streamable, take the whole-file path".
  static Future<TelegramAttachmentStreamSession?> open(
    Event event, {
    String? fileName,
  }) async {
    if (kIsWeb) return null; // the web player streams from a blob of its own
    final client = event.room.client;
    final mxc = event.attachmentMxcUrl;
    if (mxc == null) {
      debugPrint('[TelegramStream] fallback: no mxc url');
      return null;
    }
    final file = TelegramEncryptedFileKey.fromFileMap(
      event.content['file'] is Map
          ? Map<Object?, Object?>.from(event.content['file'] as Map)
          : null,
      // The spec's EncryptedFile carries no size; content.info.size does.
      plaintextSize: event.content
          .tryGetMap<String, Object?>('info')
          ?.tryGet<int>('size'),
    );
    if (file == null) {
      // No usable key/iv/sha256 + size here, so there is nothing to decrypt
      // with - the homeserver's own range endpoint is already a byte-range
      // media source, and the same loopback server serves it through with no
      // crypto layer at all. Two shapes reach this branch: a genuinely plain
      // attachment (a sender whose crypto was not ready, a non-encrypting
      // integration, media copied out of an unencrypted room), and a
      // well-formed encrypted attachment whose `file` object lacks `size`
      // while `info.size` is also absent. Both stream the same way.
      return _openPlain(event, mxc: mxc, fileName: fileName);
    }
    if (file.encryptedSize > maxStreamBytes) {
      debugPrint(
        '[TelegramStream] fallback: ${(file.encryptedSize >> 20)} MiB exceeds '
        'the ${maxStreamBytes >> 20} MiB stream ceiling',
      );
      return null;
    }
    final contentType = _videoMimeOf(event) ?? _mimeFromUri(mxc);
    if (contentType == null) {
      debugPrint('[TelegramStream] fallback: no video mime on ${event.body}');
      return null;
    }

    final Uri downloadUri;
    try {
      downloadUri = await mxc.getDownloadUri(client);
    } catch (e) {
      debugPrint('[TelegramStream] fallback: download uri failed $e');
      return null;
    }
    final accessToken = client.accessToken;
    if (accessToken == null) {
      debugPrint('[TelegramStream] fallback: no access token');
      return null;
    }

    final TelegramAttachmentStream stream;
    var servedTailIndex = false;
    // One `Range` GET of `[start, end)` cipher bytes: the closure both modes take.
    Future<Uint8List> rangeFetch(int start, int end) =>
        _fetchRange(client, downloadUri, accessToken, start, end);
    if (file.encryptedSize <= maxSingleStreamBytes) {
      // ONE request for the whole ciphertext, no `Range` header (T59b). The
      // player still sends its own range requests; the loopback byte server
      // answers them out of the decrypted bytes, at zero homeserver cost.
      final Stream<List<int>> body;
      try {
        body = await _fetchWhole(
          client,
          downloadUri,
          accessToken,
          expectedBytes: file.encryptedSize,
        );
      } catch (e) {
        debugPrint(
          '[TelegramStream] fallback: single-request fetch refused $e',
        );
        return null;
      }
      debugPrint(
        '[TelegramStream] single-request ${file.encryptedSize} bytes from '
        '$downloadUri',
      );
      // T76 read this mode as fetching no ranges at all, so a file whose index sits
      // at the file end could never answer the player's tail seek - measured in the
      // a user's a build logcat (a log id): the ask landed 20,560 bytes before
      // EOF while 4,194,304 bytes had arrived, media3 waited 8.12 s, then died with
      // `Loading finished before preparation is complete {contentIsMalformed=true}`
      // and the whole file started again at byte 0. T77 gave this mode its out-of-order
      // ranged GET (`rangeFallback` below), which is what a tail seek costs now: one
      // 206 request, 550 ms measured. The layout verdict itself is unchanged: the box
      // walk runs on the head
      // as it lands, so the layout verdict is in hand before the URL goes to a player.
      // T78: a tail index is fetched out of order right here, so no video waits for
      // its download. `slice()` over the last `tailBytes` is exactly the ask the player
      // would make - one call, 8 crypto chunks fetched at once (T77's out-of-order
      // ranged GET) - and the byte service then answers the seek from resident bytes.
      // T76's finish-then-play survives only when that ask is refused, i.e. a server
      // that answers `Range:` with 200 and raises [TelegramRangeNotSupportedException].
      stream = TelegramAttachmentStream.singleStream(
        file: file,
        cipherStream: body,
        rangeFallback: rangeFetch,
      )..start();
      final layout = await stream.awaitContainerLayout();
      var indexReachedBeforeTheEnd = layout != false;
      if (layout == false) {
        try {
          await stream.slice(
            max(0, file.encryptedSize - tailBytes),
            file.encryptedSize,
          );
          indexReachedBeforeTheEnd = true;
          // Tells `containerIndexReachable` that the index is resident, whatever the
          // head walk said about where the file keeps it.
          servedTailIndex = true;
        } catch (e) {
          debugPrint(
            '[TelegramStream] tail index not fetchable out of order ($e): '
            'this video plays from its finished download (T76)',
          );
        }
      }
      debugPrint(
        '[TelegramStream] mp4 index '
        '${layout == true
            ? 'in the head'
            : layout == false
            ? 'at the file end'
            : 'unknown'} '
        'for ${file.encryptedSize} bytes: '
        '${indexReachedBeforeTheEnd ? 'progressive' : 'finish the download, then play'}',
      );
    } else {
      stream = TelegramAttachmentStream(file: file, fetchRange: rangeFetch)
        ..start();

      // Find the MP4 index before handing anything to a player: a player given
      // a file whose `moov` is at the end will read the head, find no index,
      // stall at 0% and show nothing.
      try {
        final head = await stream.slice(0, min(probeBytes, file.encryptedSize));
        switch (probeTelegramMp4Layout(head)) {
          case TelegramMp4Layout.frontLoaded:
            break;
          case TelegramMp4Layout.moovAfterMdat:
            // Pull the tail too, so a seek to the end of our byte service
            // finds the index. The sequential pass fetches these bytes again
            // for the hash - the plaintext is kept, the ciphertext is not.
            await stream.slice(
              max(0, file.encryptedSize - tailBytes),
              file.encryptedSize,
            );
            servedTailIndex = true;
          case TelegramMp4Layout.unknown:
            await stream.stop();
            debugPrint(
              '[TelegramStream] fallback: the head is not a parsable mp4 '
              '(${file.encryptedSize} bytes ciphertext)',
            );
            return null;
        }
      } catch (e) {
        await stream.stop();
        // A TelegramRangeNotSupportedException here means the homeserver
        // answered 200 to `Range:` - the answer ROADMAP T55.1 asks for.
        debugPrint('[TelegramStream] fallback: range/layout probe failed $e');
        return null;
      }
    }
    if (stream.failure != null) {
      debugPrint('[TelegramStream] fallback: stream failure ${stream.failure}');
      return null;
    }

    final server = await startTelegramLoopbackMediaServer(
      contentLength: file.encryptedSize,
      contentType: contentType,
      slice: stream.slice,
      fileName: fileName ?? event.body,
      pathToken: _token(),
    );
    if (server == null) {
      await stream.stop();
      debugPrint(
        '[TelegramStream] fallback: the loopback server did not start',
      );
      return null;
    }
    debugPrint(
      '[TelegramStream] streaming ${file.encryptedSize} bytes from '
      '${server.url}',
    );
    return TelegramAttachmentStreamSession._(
      stream: stream,
      server: server,
      contentLength: file.encryptedSize,
      indexServedByTailFetch: servedTailIndex,
    );
  }

  /// Streaming for a video in a room that is **not** encrypted: the event
  /// carries a plain `url`, so the byte service is the homeserver's media
  /// endpoint with a `Range:` header and nothing is decrypted.
  ///
  /// Same contract as the encrypted path: the mp4 index is probed before the
  /// player sees a single byte, and a homeserver that answers `200` to a
  /// `Range:` request (ROADMAP T55.1) throws out of the first probe and falls
  /// back to the whole-file download.
  static Future<TelegramAttachmentStreamSession?> _openPlain(
    Event event, {
    required Uri mxc,
    String? fileName,
  }) async {
    final client = event.room.client;
    final size = event.content
        .tryGetMap<String, Object?>('info')
        ?.tryGet<int>('size');
    if (size == null || size <= 0 || size > maxStreamBytes) {
      debugPrint(
        '[TelegramStream] plain fallback: size ${size ?? "unknown"} is not '
        'streamable',
      );
      return null;
    }
    final contentType = _videoMimeOf(event) ?? _mimeFromUri(mxc);
    if (contentType == null) {
      debugPrint('[TelegramStream] plain fallback: no video mime');
      return null;
    }
    final Uri downloadUri;
    try {
      downloadUri = await mxc.getDownloadUri(client);
    } catch (e) {
      debugPrint('[TelegramStream] plain fallback: download uri failed $e');
      return null;
    }
    final accessToken = client.accessToken;
    if (accessToken == null) {
      debugPrint('[TelegramStream] plain fallback: no access token');
      return null;
    }
    final Future<Uint8List> Function(int start, int end) slice;
    if (size <= maxSingleStreamBytes) {
      // ONE request for the whole file, no `Range` header (T59b). This is the
      // path a plain room video was missing: for media the homeserver does not
      // host, the probe below answered `Range fetch answered 500`, so the
      // attachment never streamed and the whole 22 MB went to the temp file.
      final Stream<List<int>> body;
      try {
        body = await _fetchWhole(
          client,
          downloadUri,
          accessToken,
          expectedBytes: size,
        );
      } catch (e) {
        debugPrint(
          '[TelegramStream] plain fallback: single-request fetch refused $e',
        );
        return null;
      }
      debugPrint(
        '[TelegramStream] single-request $size plain bytes from $downloadUri',
      );
      // No layout probe here either, for the same reason as the encrypted
      // branch: the head is the first thing the one request delivers.
      final source = _PlainWholeFileBytes(size);
      source.consume(body);
      slice = source.slice;
    } else {
      Future<Uint8List> plainSlice(int start, int end) {
        final s = start.clamp(0, size);
        final e = end.clamp(s, size);
        if (e == s) return Future.value(Uint8List(0));
        return _fetchRange(client, downloadUri, accessToken, s, e);
      }

      try {
        final head = await plainSlice(0, min(probeBytes, size));
        switch (probeTelegramMp4Layout(head)) {
          case TelegramMp4Layout.frontLoaded:
            break;
          case TelegramMp4Layout.moovAfterMdat:
            // The index sits at the tail: hand the player its tail too, so a
            // seek to the end finds it.
            await plainSlice(max(0, size - tailBytes), size);
          case TelegramMp4Layout.unknown:
            debugPrint('[TelegramStream] plain fallback: unparsable mp4 head');
            return null;
        }
      } catch (e) {
        debugPrint('[TelegramStream] plain fallback: range probe failed $e');
        return null;
      }
      slice = plainSlice;
    }
    final server = await startTelegramLoopbackMediaServer(
      contentLength: size,
      contentType: contentType,
      slice: slice,
      fileName: fileName ?? event.body,
      pathToken: _token(),
    );
    if (server == null) {
      debugPrint('[TelegramStream] plain fallback: no loopback server');
      return null;
    }
    debugPrint(
      '[TelegramStream] streaming $size plain bytes from ${server.url}',
    );
    return TelegramAttachmentStreamSession._(
      stream: null,
      server: server,
      contentLength: size,
    );
  }

  /// `Range` GET of `[start, end)` ciphertext. A server that answers 200 to a
  /// range request is a server that will not give ranges: streaming a video it
  /// serves cannot seek, so that is an error, not a fallback - the caller
  /// takes the whole-file path.
  static Future<Uint8List> _fetchRange(
    Client client,
    Uri uri,
    String accessToken,
    int start,
    int end,
  ) async {
    for (var attempt = 0; ; attempt++) {
      final request = http.Request('GET', uri)
        ..headers['authorization'] = 'Bearer $accessToken'
        ..headers['range'] = 'bytes=$start-${end - 1}';
      final response = await client.httpClient.send(request);
      final status = response.statusCode;
      if (status == 429 && attempt < _rateLimitAttempts) {
        // A 429 on a media endpoint is the server asking us to slow down, and a
        // byte-range video is a burst of requests by construction. The body
        // names the wait; when it does not, 2 s is the answer Synapse's own
        // `retry_after_ms` values are usually under. Falling through here is
        // what turned a user's a build playback into a crash report.
        final body = await response.stream.toBytes();
        final wait =
            retryAfterOf(_jsonBody(body)) ?? const Duration(seconds: 2);
        developer.log(
          'range-fetch-rate-limited span=$start..$end attempt=$attempt'
          ' waiting=${wait.inMilliseconds}ms',
          name: 'fg_media',
        );
        await Future<void>.delayed(wait);
        continue;
      }
      return _rangeResult(response, uri, start, end);
    }
  }

  /// ONE `GET` of the whole attachment with **no `Range` header**, answered as
  /// a byte stream (ROADMAP T59b). The request count is the whole point: 86
  /// range GETs bought a `429 M_LIMIT_EXCEEDED`, 6 bought a video that played,
  /// (the measurement log, a user's a build and a build captures), so one
  /// request per video stays the primary path. What build 42 measured beside it -
  /// `Range fetch answered 500` - was that media's answer on the server that hosts
  /// it, not a rule: on the group's own media id `the group homeserver` answers `Range:`
  /// with 206 + Content-Range (measured 2026-10-28). The whole GET still carries the
  /// body; the out-of-order ranged GETs T77 added answer only a span the player
  /// seeks to before the sequential pass reaches it.
  ///
  /// The body comes back unconsumed: the caller streams it into the crypto pass
  /// (or into the plain buffer), so the file is never held twice.
  static Future<Stream<List<int>>> _fetchWhole(
    Client client,
    Uri uri,
    String accessToken, {
    required int expectedBytes,
    http.Client? httpClient,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final request = http.Request('GET', uri)
        ..headers['authorization'] = 'Bearer $accessToken';
      final response = await (httpClient ?? client.httpClient).send(request);
      final status = response.statusCode;
      if (status == 429 && attempt < _rateLimitAttempts) {
        // The same helpers the range path uses, now over the one request that
        // carries the video: sleep the server's own `retry_after_ms`, capped.
        final body = await response.stream.toBytes();
        final wait =
            retryAfterOf(_jsonBody(body)) ?? const Duration(seconds: 2);
        developer.log(
          'whole-fetch-rate-limited total=$expectedBytes attempt=$attempt'
          ' waiting=${wait.inMilliseconds}ms',
          name: 'fg_media',
        );
        await Future<void>.delayed(wait);
        continue;
      }
      if (status == 404) {
        throw const TelegramAttachmentMissingException();
      }
      if (status != 200) {
        throw http.ClientException(
          'Whole fetch answered $status for $uri',
          uri,
        );
      }
      final declared = response.contentLength;
      if (declared != null && declared >= 0) {
        // T67.1 (2026-10-28): the declared length is the BODY, and an
        // Element-encrypted body is larger than the plaintext - the base64
        // JSON header on top and kTelegramElementMacBytes behind each
        // kTelegramElementChunkBytes chunk (a user's 10,000,000-byte file
        // is served as 10,000,211). Demanding equality with the attachment's
        // plaintext size sent every Element video from a server that DOES
        // send Content-Length into the whole-file fallback (the T67 fix
        // 458ec78c1, open point 8; a user's own server answers chunked,
        // which is why their file streamed). The stream picks the format off
        // the body's header signature, so this guard now rejects only the
        // real failures: a body shorter than the plaintext (truncation), and
        // a body too big for any wrapper the stream parses - one header
        // probe window (256 bytes) plus one MAC slot per chunk, +1 for a
        // header-inflated chunk count.
        final chunks =
            (expectedBytes + kTelegramElementChunkBytes - 1) ~/
            kTelegramElementChunkBytes;
        final maxWrapped =
            expectedBytes + 256 + kTelegramElementMacBytes * (chunks + 1);
        if (declared < expectedBytes || declared > maxWrapped) {
          // The attachment object and the bytes disagree. Streaming a file of
          // a length we cannot trust puts a truncated video in front of the
          // user, so this is a stop and the whole-file path decides.
          throw http.ClientException(
            'Whole fetch declared $declared of $expectedBytes bytes for $uri',
            uri,
          );
        }
      }
      return response.stream;
    }
  }

  static const _rateLimitAttempts = 3;
  static const _rateLimitCap = Duration(seconds: 10);

  /// How long a `429` body asks us to wait, capped: a server that names an hour
  // is not a video we should sit on. Null when the body does not say.
  ///
  /// Matrix Client-Server spec, "Standard error codes": `M_LIMIT_EXCEEDED`
  /// carries `retry_after_ms`.
  static Duration? retryAfterOf(Map<String, Object?> body) {
    final ms = body['retry_after_ms'];
    if (ms is! int || ms <= 0) return null;
    final wait = Duration(milliseconds: ms);
    return wait > _rateLimitCap ? _rateLimitCap : wait;
  }

  static Map<String, Object?> _jsonBody(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map<String, Object?> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  static Future<Uint8List> _rangeResult(
    http.StreamedResponse response,
    Uri uri,
    int start,
    int end,
  ) async {
    final status = response.statusCode;
    if (status == 404) {
      throw const TelegramAttachmentMissingException();
    }
    if (status == 200) {
      // The server ignored the Range header. A video player that cannot seek
      // cannot stream, so this is a stop, not a fallback: the caller's layout
      // probe fails and the whole-file path takes over.
      throw const TelegramRangeNotSupportedException();
    }
    if (status != 206) {
      throw http.ClientException('Range fetch answered $status for $uri', uri);
    }
    final bytes = await response.stream.toBytes();
    if (bytes.length < end - start) {
      throw http.ClientException(
        'Range fetch returned ${bytes.length} of ${end - start} bytes',
        uri,
      );
    }
    return bytes;
  }

  /// `video/mp4` or `video/quicktime` - the containers this probe understands.
  static String? _videoMimeOf(Event event) {
    final info = event.content['info'];
    final mime = info is Map ? info['mimetype'] : null;
    if (mime is! String) return null;
    final lower = mime.toLowerCase();
    if (lower == 'video/mp4' || lower == 'video/quicktime') return lower;
    return null;
  }

  static String? _mimeFromUri(Uri mxc) {
    final last = mxc.pathSegments.isEmpty ? '' : mxc.pathSegments.last;
    final dot = last.lastIndexOf('.');
    if (dot < 0) return null;
    switch (last.substring(dot + 1).toLowerCase()) {
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
    }
    return null;
  }

  static String _token() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(
      24,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();
  }
}

/// The plain-room form of one request per video (ROADMAP T59b): the body of a
/// single `GET` of the whole file, drained into one resident buffer. Same shape
/// as [TelegramAttachmentStream.singleStream] with no crypto layer - `slice`
/// waits for the fill cursor and issues no range fetch, so the homeserver
/// serves the video exactly once.
class _PlainWholeFileBytes {
  _PlainWholeFileBytes(this._size) : _bytes = Uint8List(_size);

  final int _size;
  final Uint8List _bytes;
  int _filled = 0;
  Object? _failure;

  /// Drains the response in the background; the byte server reads [slice] while
  /// this fills, which is what lets the player start before the last byte.
  Future<void> consume(Stream<List<int>> body) async {
    try {
      await for (final part in body) {
        final end = min(_filled + part.length, _size);
        _bytes.setRange(_filled, end, part);
        _filled = end;
        if (_filled >= _size) break;
      }
      if (_filled < _size) {
        _failure = http.ClientException(
          'Whole fetch delivered $_filled of $_size bytes',
        );
      }
    } catch (e) {
      _failure = e;
    }
  }

  Future<Uint8List> slice(int start, int end) async {
    final from = max(0, start);
    final to = min(end, _size);
    if (to <= from) return Uint8List(0);
    while (_filled < to) {
      final failure = _failure;
      if (failure != null) throw failure;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return Uint8List.sublistView(_bytes, from, to);
  }
}

/// The whole-file fallback download of one encrypted video attachment
/// (ROADMAP T53.1 half 2). `Event.downloadAndDecryptAttachment` exposes no
/// cancel, so closing the viewer while a big non-streamable video was still
/// fetching kept pulling bytes: bandwidth, battery, and a half temp file
/// nobody would ever play. Telegram cancels the load with the screen
/// (`FileLoader.cancel` from the viewer's detach, `the measurement log`
/// T53); this class is that cancel for the one path the stream cannot
/// serve.
///
/// Same fetch as the stream's single-request mode (one `GET`, no `Range`
/// header, the `429` retry loop of `_fetchWhole`) and the same
/// decrypt-and-verify ([TelegramAttachmentStream.singleStream]: one
/// sequential AES-CTR pass, SHA-256 over the whole ciphertext before the
/// file is handed over) - but over an `http.Client` this object owns, so
/// closing it dies with the viewer instead of draining to the last byte
/// (measured on this sandbox: `ClientException: Connection closed while
/// receiving data`, 1.7 s into a 4 s body).
class TelegramAttachmentDownload {
  TelegramAttachmentDownload._(
    this._event,
    this._file,
    this._downloadUri,
    this._accessToken,
  );

  final Event _event;
  final TelegramEncryptedFileKey _file;
  final Uri _downloadUri;
  final String _accessToken;

  /// This download's own client - never the Matrix client's, which carries
  /// sync and room state. Closing it is the cancel.
  http.Client? _httpClient;
  bool _cancelled = false;
  bool _finished = false;

  /// Prepares a cancelable whole-file download for [event]. Null when the
  /// fork path cannot serve the shape - no mxc url, no usable key, no
  /// download uri, no access token - and the caller keeps the SDK call it
  /// had, uncancellable, exactly as before.
  static Future<TelegramAttachmentDownload?> open(Event event) async {
    final mxc = event.attachmentMxcUrl;
    if (mxc == null) {
      debugPrint('[TelegramStream] whole-file fallback: no mxc url');
      return null;
    }
    final file = TelegramEncryptedFileKey.fromFileMap(
      event.content['file'] is Map
          ? Map<Object?, Object?>.from(event.content['file'] as Map)
          : null,
      // The spec's EncryptedFile carries no size; content.info.size does.
      plaintextSize: event.content
          .tryGetMap<String, Object?>('info')
          ?.tryGet<int>('size'),
    );
    if (file == null) {
      debugPrint('[TelegramStream] whole-file fallback: no usable key');
      return null;
    }
    final client = event.room.client;
    final Uri downloadUri;
    try {
      downloadUri = await mxc.getDownloadUri(client);
    } catch (e) {
      debugPrint('[TelegramStream] whole-file fallback: no download uri: $e');
      return null;
    }
    final accessToken = client.accessToken;
    if (accessToken == null) {
      debugPrint('[TelegramStream] whole-file fallback: no access token');
      return null;
    }
    return TelegramAttachmentDownload._(event, file, downloadUri, accessToken);
  }

  /// Kills the fetch: closes this download's own client, so an in-flight
  /// body read dies instead of draining to its natural end. The `Future`
  /// [run] returned then deletes the half-written temp file and throws
  /// [TelegramAttachmentDownloadCancelled]. No-op after [run] handed a
  /// complete, hash-verified file over.
  void cancel() {
    if (_finished || _cancelled) return;
    _cancelled = true;
    _httpClient?.close();
  }

  /// Streams the whole ciphertext through
  /// [TelegramAttachmentStream.singleStream] - the same sequential AES-CTR
  /// decrypt and whole-ciphertext SHA-256 the stream plays under - and
  /// writes the plaintext into [tempFile] as it arrives. Returns that file
  /// once every byte landed and the hash matched.
  Future<File> run(
    File tempFile, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (_cancelled) throw const TelegramAttachmentDownloadCancelled();
    final total = _file.encryptedSize;
    IOSink? sink;
    try {
      final cipher = await TelegramAttachmentStreamSession._fetchWhole(
        _event.room.client,
        _downloadUri,
        _accessToken,
        expectedBytes: total,
        httpClient: _httpClient ??= http.Client(),
      );
      final stream = TelegramAttachmentStream.singleStream(
        file: _file,
        cipherStream: cipher,
      )..start();
      sink = tempFile.openWrite();
      final written = await writeStreamedPlainText(
        stream,
        sink,
        total: total,
        onProgress: onProgress,
        cancelled: () => _cancelled,
      );
      if (!stream.complete) {
        // The loop only leaves early on cancel; everything else threw.
        throw const TelegramAttachmentDownloadCancelled();
      }
      await sink.flush();
      await sink.close();
      // The count on disk is the only number a player can read, so it is the
      // number this method vouches for. A file short of the declared length
      // is what ExoPlayer answers with `java.io.EOFException` and
      // `Source error`.
      final landed = await tempFile.length();
      if (landed != written) {
        throw StateError(
          'the whole-file write stopped short: $landed of $written bytes on '
          'disk at ${tempFile.path}',
        );
      }
      _finished = true;
      debugPrint(
        '[TelegramStream] whole file landed: $landed bytes at '
        '${tempFile.path}',
      );
      return tempFile;
    } catch (e) {
      // A download that did not land leaves no half temp file behind: no
      // player ever saw it, and the OS temp cleaner should not be its
      // undertaker.
      await _discardTemp(tempFile, sink);
      if (_cancelled) {
        // Silent by contract: the viewer is gone, the socket is dead, the
        // half file is deleted. The caller logs one line and stops.
        throw const TelegramAttachmentDownloadCancelled();
      }
      if (e is TelegramAttachmentMissingException) {
        // The server's "gone" answer, in the SDK's own words: the
        // whole-file path this class replaces answered a localized
        // M_NOT_FOUND snackbar, and that stays the answer.
        throw MatrixException.fromJson(<String, Object?>{
          'errcode': 'M_NOT_FOUND',
          'error': 'Not found',
        });
      }
      rethrow;
    }
  }

  /// Closes [sink] (best effort - a cancelled socket has nothing more to
  /// flush) and deletes the half-written [file].
  Future<void> _discardTemp(File file, IOSink? sink) async {
    try {
      await sink?.close();
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[TelegramStream] whole-file cleanup failed: $e');
    }
  }
}

/// Copies plaintext from [stream] into [sink] in file order and answers the
/// byte count handed to the sink.
///
/// The drain runs **before** the completion test. A loop that tests
/// `stream.complete` at the top exits with the last chunk still unsliced, and
/// `complete` flips in the same 20 ms sleep that carries that chunk. Measured
/// in a user's log 80d38f23aa14 (build 60, the group's 22,548,864-byte
/// video): the stream verified every byte, the file on disk held 22,544,384 =
/// 1,376 whole 16 KiB chunks, the 4,480-byte tail chunk never reached the
/// sink, and the player died on the hole with `java.io.EOFException` ->
/// `PlatformException(VideoError, ... Source error ...)`.
Future<int> writeStreamedPlainText(
  TelegramAttachmentStream stream,
  IOSink sink, {
  required int total,
  void Function(int received, int total)? onProgress,
  bool Function()? cancelled,
}) async {
  var written = 0;
  while (true) {
    if (cancelled?.call() == true) return written;
    final failure = stream.failure;
    if (failure != null) throw failure;
    final filled = stream.filledBytes;
    if (filled > written) {
      // A view, not a copy: every plaintext byte below `filled` is
      // final, written once in file order.
      sink.add(await stream.slice(written, filled));
      written = filled;
      onProgress?.call(written, total);
    }
    // Drained first: the tail chunk is on its way to the sink now.
    if (stream.complete) return written;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// `dispose` cancelled a [TelegramAttachmentDownload]: the viewer is gone,
/// the fetch died with it and the half-written temp file was deleted. Not
/// an error - the caller swallows it and stops quietly.
class TelegramAttachmentDownloadCancelled implements Exception {
  const TelegramAttachmentDownloadCancelled();

  @override
  String toString() => 'The viewer closed while the whole file downloaded';
}

/// The attachment is not on the server.
class TelegramAttachmentMissingException implements Exception {
  const TelegramAttachmentMissingException();

  @override
  String toString() => 'Attachment not found on the homeserver';
}

/// The homeserver answered a `Range` request with the whole file, so it will not
/// give byte ranges and a player cannot seek in the video. The class lives in
/// `telegram_attachment_stream.dart`, where single-request mode catches it and
/// stops asking for ranges (T77).
