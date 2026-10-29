// SPDX-FileCopyrightText: 2026-Present Contributors to FluffyGram
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'telegram_loopback_media_server.dart';

/// The loopback byte server: a tiny HTTP/1.1 responder on 127.0.0.1 that
/// answers `Range` requests for one file out of a `slice` callback.
///
/// Nothing here is a general web server: it binds the loopback interface on an
/// ephemeral port, serves exactly one path token, and answers GET and HEAD
/// only. It exists because ExoPlayer and AVPlayer will not stream a video they
/// cannot seek in, and the Matrix attachment endpoint gives them nothing to
/// seek in.
class _LoopbackServer implements TelegramLoopbackMediaServer {
  _LoopbackServer(this._server, this._token, this._contentLength);

  final HttpServer _server;
  final String _token;
  final int _contentLength;
  int _servedBytes = 0;

  @override
  Uri get url => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: _server.port,
    pathSegments: <String>[_token],
  );

  @override
  int get servedBytes => _servedBytes;

  @override
  Future<void> close() => _server.close(force: true);

  Future<void> _serve(
    HttpRequest request,
    String contentType,
    Future<Uint8List> Function(int start, int end) slice,
  ) async {
    final response = request.response;
    if (request.uri.pathSegments.length != 1 ||
        request.uri.pathSegments.first != _token) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    response.headers.set('content-disposition', 'inline; filename="$_token"');

    final range = _parseRange(request.headers.value('range'), _contentLength);
    // One line per player request: a seek shows up here as a new span, and the
    // absence of a request the player should have made is the other half of the
    // diagnosis. A user's a build video started, played, then died with a
    // player error nothing in the app could see (ROADMAP T55).
    //
    // `debugPrint`, never `dart:developer log`: a user's release logcat carries
    // every `debugPrint` as `I flutter : ...` and carried **no** `fg_media` line at all,
    // which is why the request that produced build 46's `Response code: 416` could not be
    // read from any artifact (ROADMAP T64, the measurement log).
    debugPrint(
      '[TelegramLoopback] req method=${request.method}'
      ' range=${request.headers.value('range')} total=$_contentLength'
      ' served=$_servedBytes port=${_server.port}',
    );
    if (range == null) {
      // Whole file.
      response.contentLength = _contentLength;
      await _write(response, slice, 0, _contentLength);
      return;
    }
    if (range.$1 >= range.$2) {
      // T64: a span with nothing in it is still a player read. media3's
      // `InvalidResponseCodeException` turns any status other than 200/206 into a fatal
      // `Playback error / Source error`, which is what killed a user's a build video 10
      // seconds in (`Caused by: I0.s: Response code: 416`) and sent the viewer to the
      // whole-file path. RFC 7233 asks for 416; a byte server whose only client is a media
      // player answers end-of-data instead - a 206 with an empty body reads as EOF.
      response.statusCode = HttpStatus.partialContent;
      response.contentLength = 0;
      response.headers.set('content-range', 'bytes */$_contentLength');
      debugPrint(
        '[TelegramLoopback] eof range=${request.headers.value('range')}'
        ' start=${range.$1} total=$_contentLength served=$_servedBytes',
      );
      await response.close();
      return;
    }
    response.statusCode = HttpStatus.partialContent;
    response.contentLength = range.$2 - range.$1;
    response.headers.set(
      'content-range',
      'bytes ${range.$1}-${range.$2 - 1}/$_contentLength',
    );
    await _write(response, slice, range.$1, range.$2);
  }

  Future<void> _write(
    HttpResponse response,
    Future<Uint8List> Function(int start, int end) slice,
    int start,
    int end,
  ) async {
    // In single-request mode (T59b) these spans cost the homeserver nothing: a
    // slice there waits for the one response to reach the byte and answers from
    // the resident plaintext. The player keeps sending its own range requests,
    // and this is where they stop.
    //
    // Ask the homeserver for 4 MiB at a time. The 256 KiB this used to request
    // made one 22,548,864-byte video 86 `Range` GETs, and the media endpoint
    // answered 429 M_LIMIT_EXCEEDED - the a build crash (the measurement log,
    // 2026-10-28). The socket still sees 256 KiB writes, so a seek costs at most
    // one span and the player keeps getting bytes at a responsive cadence.
    const fetchSpan = 1 << 22;
    const writeChunk = 1 << 18;
    var written = 0;
    try {
      for (var at = start; at < end; at += fetchSpan) {
        final spanEnd = at + fetchSpan > end ? end : at + fetchSpan;
        final bytes = await slice(at, spanEnd);
        _servedBytes += bytes.length;
        for (var off = 0; off < bytes.length; off += writeChunk) {
          final to = off + writeChunk > bytes.length
              ? bytes.length
              : off + writeChunk;
          response.add(bytes.sublist(off, to));
          written += to - off;
          await response.flush();
        }
      }
      debugPrint(
        '[TelegramLoopback] write-complete span=$start..$end bytes=$written',
      );
      await response.close();
    } catch (e) {
      // The player went away mid-write (it seeks, it stops, the page pops).
      // A truncated response is a real event, not noise: the player reads it as
      // "the source ended", and that is how a byte-service bug becomes a crash
      // on a user's phone with no trace in the app's own log.
      debugPrint(
        '[TelegramLoopback] write-aborted span=$start..$end bytes=$written'
        ' of=${end - start} served=$_servedBytes err=${e.runtimeType}',
      );
      try {
        await response.close();
      } catch (_) {}
    }
  }
}

/// `bytes=a-b`, `bytes=a-`, `bytes=-n` (the last n bytes), null for no range or
/// a range we cannot use. Returns the half-open `[start, end)` span.
(int, int)? _parseRange(String? header, int contentLength) {
  if (header == null || !header.startsWith('bytes=')) return null;
  final spec = header.substring('bytes='.length).split(',').first.trim();
  final dash = spec.indexOf('-');
  if (dash < 0 || contentLength <= 0) return null;
  final rawStart = spec.substring(0, dash).trim();
  final rawEnd = spec.substring(dash + 1).trim();
  int start;
  int end; // exclusive
  if (rawStart.isEmpty) {
    final n = int.tryParse(rawEnd);
    if (n == null || n <= 0) return null;
    start = contentLength - n < 0 ? 0 : contentLength - n;
    end = contentLength;
  } else {
    final s = int.tryParse(rawStart);
    // An empty span. `_serve` answers it as end-of-data, never as 416 (T64).
    if (s == null || s < 0 || s >= contentLength) return (0, 0);
    start = s;
    end = rawEnd.isEmpty
        ? contentLength
        : (int.tryParse(rawEnd) ?? contentLength - 1) + 1;
    if (end > contentLength) end = contentLength;
    if (start >= end) return (0, 0);
  }
  return (start, end);
}

Future<TelegramLoopbackMediaServer?> start({
  required int contentLength,
  required String contentType,
  required Future<Uint8List> Function(int start, int end) slice,
  required String fileName,
  String pathToken = 'media',
}) async {
  if (contentLength <= 0) return null;
  HttpServer server;
  try {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  } catch (e) {
    return null;
  }
  final instance = _LoopbackServer(server, pathToken, contentLength);
  server.listen(
    (request) => instance._serve(request, contentType, slice),
    onError: (Object e) {},
  );
  return instance;
}
