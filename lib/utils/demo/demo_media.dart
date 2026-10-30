// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Demo media, added 2026-10-24 for the `FLUFFYGRAM_DEMO` build flag.
//
// Two things live here:
//
//  * the MXC -> asset mapping (`demoAssetKeyForMxc`), the one place that knows
//    where the fake chat files sit in the bundle, and
//  * `DemoHttpClient`, the `httpClient` given to the demo `Client`. It answers
//    every request the SDK makes from the bundle or from a canned body, so a
//    demo build sends zero network requests: nothing is ever opened to
//    `https://fluffygram.local`, which is not a real host.
//
// Media therefore reaches the widgets through the normal SDK download path
// (`MxcImage` -> `downloadMxcCached`, `AudioPlayerWidget` / the video viewer ->
// `Event.downloadAndDecryptAttachment`). No widget is patched, and no
// `kIsWeb` branch is needed for the URI shape: the audio and video players turn
// the returned bytes into a `Uri.dataFromBytes` source on web and into a temp
// file on Android by themselves.

import 'dart:convert';
import 'dart:typed_data';

import 'package:fluffychat/config/demo_mode.dart';
import 'package:fluffychat/utils/demo/demo_seed.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

/// Root directory of the bundled demo files, as registered in `pubspec.yaml`.
const String kFluffyGramDemoAssetDir = 'assets/demo';

/// The bundle key of a demo file, e.g. `assets/demo/photo/photo_01_cat.jpg`.
///
/// `mxc://fluffygram.local/photo/photo_01_cat.jpg` ->
/// `assets/demo/photo/photo_01_cat.jpg`: the MXC path under the fake server
/// name is the path under `assets/demo/`. Null for any other MXC URI, so a
/// demo build cannot accidentally claim a real room's media.
///
/// Flutter web serves a registered asset directory under the doubled
/// `assets/assets/...` prefix of the built site. `rootBundle` takes the logical
/// key returned here and adds that prefix itself, which is why this function
/// has no platform branch: the same key is correct on web, Android and desktop.
String? demoAssetKeyForMxc(Uri mxc) {
  if (mxc.scheme != 'mxc' || mxc.host != kFluffyGramDemoServerName) {
    return null;
  }
  final name = mxc.pathSegments.join('/');
  return name.isEmpty ? null : '$kFluffyGramDemoAssetDir/$name';
}

/// The bundle key behind a media request of the fake homeserver, e.g.
/// `https://fluffygram.local/_matrix/client/v1/media/thumbnail/
///  fluffygram.local/thumb/photo_01_cat.jpg?width=240...` ->
/// `assets/demo/thumb/photo_01_cat.jpg`. Null when the path is not a media
/// download, which is how `DemoHttpClient` tells media from API calls.
String? demoAssetKeyForMediaRequest(Uri url) {
  if (url.host != kFluffyGramDemoServerName) return null;
  final segments = url.pathSegments;
  final marker = segments.indexWhere(
    (s) => s == 'download' || s == 'thumbnail',
  );
  // `<api>/media/<download|thumbnail>/<mxc server name>/<name...>`
  if (marker == -1 || marker + 2 >= segments.length) return null;
  final name = segments.sublist(marker + 2).join('/');
  return name.isEmpty ? null : '$kFluffyGramDemoAssetDir/$name';
}

/// Bytes of a bundled demo file, read once and kept for the process.
Future<Uint8List> demoAssetBytes(String assetKey) async {
  final data = await rootBundle.load(assetKey);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// `Content-Type` for a bundled demo file, by extension.
String demoContentType(String assetKey) {
  if (assetKey.endsWith('.png')) return 'image/png';
  if (assetKey.endsWith('.jpg') || assetKey.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (assetKey.endsWith('.mp4')) return 'video/mp4';
  if (assetKey.endsWith('.wav')) return 'audio/wav';
  if (assetKey.endsWith('.ogg') || assetKey.endsWith('.oga')) {
    return 'audio/ogg';
  }
  return 'application/octet-stream';
}

/// A `http.Client` that answers the demo client's requests in-process.
///
/// Requests for demo media return the bundled bytes. API calls (`/sync`,
/// `/versions`, `/keys/*`, `/filter`, receipts, typing, read markers) get a
/// small canned body so the SDK is happy. Any request aimed at a host other
/// than the fake one throws: a demo build cannot reach the network.
class DemoHttpClient extends http.BaseClient {
  final Map<String, Future<Uint8List>> _assetCache = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;
    if (uri.host != kFluffyGramDemoServerName) {
      throw http.ClientException(
        'FluffyGram demo mode: the network is off, request to ${uri.host} '
        'refused',
        uri,
      );
    }
    Logs().v('DemoHttpClient: answered locally', uri.path);
    if (request.method == 'GET' || request.method == 'HEAD') {
      final assetKey = demoAssetKeyForMediaRequest(uri);
      if (assetKey != null) return _bytes(await _asset(assetKey), assetKey);
    }
    final body = request is http.Request
        ? utf8.decode(request.bodyBytes, allowMalformed: true)
        : null;
    return _json(uri, _cannedBody(uri, body), request.method);
  }

  /// How many one-time keys a `/keys/upload` body carries, so the answer can
  /// accept exactly that number. 0 for a device-keys-only upload, which the
  /// SDK does not compare in that call.
  static int _oneTimeKeyCount(String? body) {
    if (body == null || body.isEmpty) return 0;
    try {
      final json = jsonDecode(body);
      final keys = json is Map ? json['one_time_keys'] : null;
      return keys is Map ? keys.length : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<Uint8List> _asset(String assetKey) =>
      _assetCache.putIfAbsent(assetKey, () => demoAssetBytes(assetKey));

  /// The canned answer for one API path. An unknown path gets `{}`: the SDK's
  /// `fromJson` models treat every field as optional, so an empty object is a
  /// valid "nothing happened" for reads and a plain acknowledgement for writes.
  Object? _cannedBody(Uri uri, String? body) {
    final path = uri.path;
    if (path.endsWith('/versions') || path == '/versions') {
      // v1.11 makes `authenticatedMediaSupported()` true, so media requests
      // take the `/_matrix/client/v1/media/...` form mapped above.
      return {
        'versions': ['v1.1', 'v1.11'],
        'unstable_features': <String, bool>{},
      };
    }
    if (path.endsWith('/sync')) {
      // An empty sync. `next_batch` equals the stored prev batch on the second
      // loop, so the sync loop has nothing to process.
      return {
        'next_batch': 'demo-batch',
        'rooms': <String, Object?>{},
        'presence': <String, Object?>{},
        'account_data': <String, Object?>{
          // The seeded `Weekend Trip` room is muted. `Room.pushRuleState` reads the
          // client's `m.push_rules` ACCOUNT DATA (matrix-14.1.0
          // client.dart:1693, room.dart:2495), which arrives in this first
          // /sync round - the `/pushrules` endpoint is not what the getter
          // consults. The rule form the getter matches: an override rule whose
          // `rule_id` is the room id and whose actions are empty once
          // `dont_notify` and `coalesce` are stripped. The `/pushrules` answer
          // carries the same rule so both paths agree.
          'events': <Object?>[
            {
              'type': 'm.push_rules',
              'content': <String, Object?>{
                'global': <String, Object?>{
                  'override': <Object?>[
                    {
                      'rule_id': '!trip:fluffygram.local',
                      'default': false,
                      'enabled': true,
                      'actions': <Object?>['dont_notify'],
                    },
                  ],
                  'content': <Object?>[],
                  'room': <Object?>[],
                  'underride': <Object?>[],
                },
              },
            },
          ],
        },
        'to_device': <Object?>[],
        'device_lists': <String, Object?>{},
        'device_one_time_keys_count': <String, int>{},
      };
    }
    if (path.endsWith('/filter')) return {'filter_id': 'demo-filter'};
    if (path.endsWith('/keys/upload')) {
      // `OlmManager.uploadKeys()` compares the number of one-time keys it sent
      // with `response['signed_curve25519']` and calls the upload failed on a
      // mismatch, and `Client.init()` clears the session when publishing the
      // keys of a new olm account fails (matrix-14.1.0 olm_manager.dart:
      // 264-270). An empty count map therefore produces a demo build that
      // never paints. The stub echoes back what the request carried.
      final uploaded = _oneTimeKeyCount(body);
      return {
        'one_time_key_counts': <String, int>{
          'signed_curve25519': uploaded,
          'curve25519': uploaded,
        },
      };
    }
    if (path.endsWith('/keys/query')) {
      return {
        'device_keys': <String, Object?>{},
        'failures': <String, Object?>{},
      };
    }
    if (path.endsWith('/keys/changes')) {
      return {'changed': <String>[], 'left': <String>[]};
    }
    if (path.endsWith('/whoami')) {
      return {'user_id': '@alice:fluffygram.local', 'device_id': 'DEMOGRAM01'};
    }
    if (path.endsWith('/capabilities')) {
      return {'capabilities': <String, Object?>{}};
    }
    if (path.endsWith('/pushers')) return {'pushers': <Object?>[]};
    if (path.endsWith('/pushrules')) {
      return {
        'global': <String, Object?>{
          'override': <Object?>[
            // The seeded `Weekend Trip` room is muted, so a demo build can show what
            // a muted chat looks like: the mute glyph inside the chat title
            // (T11 finding 15) and the grey unread bubble. `Room.pushRuleState`
            // (matrix-14.1.0 lib/src/room.dart:2495) matches an override rule
            // whose `rule_id` is the room id and whose actions are empty once
            // `dont_notify` and `coalesce` are stripped - conditions are not
            // read, so the rule id form is the one that works.
            {
              'rule_id': '!trip:fluffygram.local',
              'default': false,
              'enabled': true,
              'actions': <Object?>['dont_notify'],
            },
          ],
          'content': <Object?>[],
          'room': <Object?>[],
          'underride': <Object?>[],
        },
      };
    }
    if (uri.pathSegments.contains('send')) {
      // A send in a demo build is answered locally, so the composer behaves as
      // it does against a server: the SDK puts the event into the local
      // timeline with this id. No event leaves the device.
      return {
        'event_id':
            '\$demo-local:$kFluffyGramDemoServerName[$demoLocalEventCounter()]',
      };
    }
    if (path.endsWith('/search')) return _searchAnswer(body);
    if (path.endsWith('/joined_members')) {
      return {'joined': <String, Object?>{}};
    }
    if (path.endsWith('/members')) return {'chunk': <Object?>[]};
    if (path.endsWith('/messages')) return {'chunk': <Object?>[]};
    if (path.endsWith('/state')) return {'chunk': <Object?>[]};
    if (path.endsWith('/relations') || path.endsWith('/event')) {
      return {'chunk': <Object?>[]};
    }
    return <String, Object?>{'demo': true};
  }

  /// T40.3a: answers `POST /_matrix/client/v3/search` from
  /// [demoSeedTextEvents] (the seeded plain-text messages), so the in-chat
  /// search panel finds real seeded text in the web demo.
  static Object? _searchAnswer(String? body) {
    var term = '';
    try {
      final decoded = jsonDecode(body ?? '{}');
      term =
          (((decoded['search_categories'] as Map)['room_events']
                          as Map)['search_term']
                      as String? ??
                  '')
              .toLowerCase();
    } catch (_) {}
    final results = <Object?>[
      for (final event in demoSeedTextEvents)
        if (term.isEmpty ||
            (((event['content'] as Map?)?['body'] as String? ?? '')
                .toLowerCase()
                .contains(term)))
          {'rank': 1.0, 'result': event},
    ];
    return <String, Object?>{
      'search_categories': <String, Object?>{
        'room_events': <String, Object?>{
          'count': results.length,
          'results': results,
          'highlights': <String>[],
        },
      },
    };
  }

  http.StreamedResponse _json(Uri uri, Object? body, String method) {
    final bytes = utf8.encode(jsonEncode(body));
    return http.StreamedResponse(
      Stream.value(bytes),
      200,
      contentLength: bytes.length,
      headers: const {'content-type': 'application/json'},
      request: http.Request(method, uri),
    );
  }

  http.StreamedResponse _bytes(Uint8List bytes, String assetKey) =>
      http.StreamedResponse(
        Stream.value(bytes),
        200,
        contentLength: bytes.length,
        headers: {
          'content-type': demoContentType(assetKey),
          'content-length': '${bytes.length}',
        },
        request: http.Request(
          'GET',
          Uri.parse('https://$kFluffyGramDemoServerName/'),
        ),
      );

  @override
  void close() => _assetCache.clear();
}

/// Unique local ids for messages sent inside a demo build.
int demoLocalEventCounter() => ++_demoLocalEventId;

int _demoLocalEventId = 0;
