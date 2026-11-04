// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';

import '../config/setting_keys.dart';

/// Link previews on the outgoing side - ROADMAP T159.
///
/// Three decisions live here, and each has a reason:
///
/// 1. **The Worker fetches the page, not the phone.** The endpoint is one route
///    on the push gateway (`push-gateway/worker/preview.js`, T158). A member
///    pasting a link must not make their own device contact that site: Telegram
///    generates previews on its servers for the same reason. The app sends the
///    URL to a host we run and reads back six fields.
/// 2. **The thumbnail is re-hosted as an `mxc://` asset.** The linked site's
///    image URL is never put in the message, so a recipient's client loads the
///    picture from their own homeserver. A plain `<img src="https://…">` in
///    `formatted_body` would hand every reader's IP and user agent to the
///    linked site - that is a tracking pixel, and Matrix clients are not
///    allowed to do that to their users.
/// 3. **The field names are MSC3860's**, the Matrix extension Element Web and
///    Element Android already read (`org.matrix.msc3860.url_previews`), so a
///    FluffyGram preview displays in those clients unchanged. Nothing here is a
///    protocol change: it is ordinary `m.text` content with one extra key.
///
/// Previews attach to **plain-text** sends only - see
/// [telegramPlainLinkMessage]. matrix-dart builds the markdown answer inside
/// `Room.sendTextEvent` (`matrix-14.1.0/lib/src/room.dart:693-778`) and does not
/// export it, and this fork does not import `package:matrix/src/**`, so a
/// formatted message keeps going through `sendTextEvent` exactly as before and
/// simply gets no preview.
///
/// Every failure here is a silent downgrade to a plain link: a preview is a
/// decoration, and no preview problem may ever block or mangle a send.

/// The first http(s) link in a message body, the one Telegram previews (it
/// shows one preview, for the first link). Null when the body carries none.
Uri? telegramFirstLink(String text) {
  for (final match in RegExp(r'''https?://[^\s<>"']+''').allMatches(text)) {
    final raw = match.group(0)!;
    // Trailing punctuation is prose, not part of a URL: "see https://x.example/a."
    final trimmed = raw.replaceFirst(RegExp(r'''[.,;:!?)\]}'"]+$'''), '');
    if (trimmed.length < 12) continue; // "https://a" is not a link
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) continue;
    if (uri.scheme != 'http' && uri.scheme != 'https') continue;
    final host = uri.host;
    if (!host.contains('.') || host.length < 4) continue;
    return uri;
  }
  return null;
}

/// True when [text] can be sent as a plain `body` with no formatting pass, so
/// the preview path is allowed to build the event content itself. Any markdown
/// marker, mention or command takes the message back to
/// `Room.sendTextEvent`'s normal path.
bool telegramPlainLinkMessage(String text) {
  final trimmed = text.trim();
  if (trimmed.startsWith('/')) return false; // a slash command
  if (trimmed.contains('@')) return false; // mentions build m.mentions
  const markers = ['*', '_', '~', '`', '[', ']', '>', '#', '<', '&'];
  if (markers.any(trimmed.contains)) return false;
  return true;
}

/// One link preview, ready to put on an event.
class TelegramLinkPreview {
  final String url;
  final String siteName;
  final String title;
  final String description;
  final String authorName;

  /// The page's own `og:type` (`link`, `article`, `photo`, `video`).
  final String type;
  final Uri? imageMxc;
  final int? imageWidth;
  final int? imageHeight;
  final int? imageSize;
  final String? imageMime;

  const TelegramLinkPreview({
    required this.url,
    this.siteName = '',
    this.title = '',
    this.description = '',
    this.authorName = '',
    this.type = 'link',
    this.imageMxc,
    this.imageWidth,
    this.imageHeight,
    this.imageSize,
    this.imageMime,
  });

  bool get hasText =>
      siteName.isNotEmpty || title.isNotEmpty || description.isNotEmpty;

  /// MSC3860's content key. An array, as the extension defines it.
  static const contentKey = 'org.matrix.msc3860.url_previews';

  Map<String, Object?> toContent() => {
    'url': url,
    if (siteName.isNotEmpty) 'site_name': siteName,
    if (title.isNotEmpty) 'title': title,
    if (description.isNotEmpty) 'description': description,
    if (authorName.isNotEmpty) 'author_name': authorName,
    'type': 'm.link',
    if (type.isNotEmpty) 'og:type': type,
    // The picture, as MSC3860's ImageInfo. `thumbnail_url` is the pre-spec key
    // older Element Web builds read; it costs 30 bytes and buys backwards
    // compatibility for a group that mixes clients.
    if (imageMxc case final Uri mxc) ...{
      'org.matrix.msc3860/image': {
        'url': mxc.toString(),
        if (imageWidth != null) 'w': imageWidth,
        if (imageHeight != null) 'h': imageHeight,
        if (imageSize != null) 'size': imageSize,
        if (imageMime != null) 'mimetype': imageMime,
      },
      'thumbnail_url': mxc.toString(),
    },
  };
}

/// The ceiling on a thumbnail we are willing to fetch and re-upload. An
/// `og:image` is normally 20-200 KB; a site that answers with 50 MB is a
/// reason to skip the picture, not to fill the phone.
const int _maxPreviewImageBytes = 4 * 1024 * 1024;

/// T161 - the warm answers, keyed by link. A Send tap may not wait on the
/// network: the fetch is what made a first tap sit for half a second with the
/// composer text still in place, so a second tap sent a second message. The
/// prefetch fills this map while you type, one in-flight fetch per link stops
/// the duplicate work, and a Send tap that finds nothing warm gives up on its
/// own budget and sends the plain link. Ten minutes and twenty links is a
/// conversation's worth; the Worker's own KV cache lives a day behind this.
final Map<String, TelegramLinkPreview> _warm = {};
final Map<String, DateTime> _warmAt = {};
final Map<String, Future<TelegramLinkPreview?>> _inFlight = {};
const Duration _warmTtl = Duration(minutes: 10);
const int _warmMax = 20;

/// The warm answer for the first link in [body]; null when nothing is cached
/// for it. Cheap enough to call on every send.
TelegramLinkPreview? telegramCachedPreview(String body) {
  final link = telegramFirstLink(body);
  if (link == null) return null;
  final key = link.toString();
  final at = _warmAt[key];
  if (at == null) return null;
  if (DateTime.now().difference(at) > _warmTtl) {
    _warm.remove(key);
    _warmAt.remove(key);
    return null;
  }
  return _warm[key];
}

void _storeWarm(String key, TelegramLinkPreview preview) {
  _warm[key] = preview;
  _warmAt[key] = DateTime.now();
  if (_warm.length <= _warmMax) return;
  final oldest = _warmAt.entries
      .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
      .key;
  _warm.remove(oldest);
  _warmAt.remove(oldest);
}

/// Ask the endpoint about the first link in [body] in the background, so the
/// answer is warm by the time Send is tapped. Every failure is swallowed: the
/// prefetch decides nothing, the send path asks the same question and gets the
/// plain-link answer if this one came back empty.
Future<void> telegramPrefetchLinkPreview(Client client, String body) async {
  try {
    await telegramLinkPreviewFor(client, body);
  } catch (e) {
    // ignore: avoid_print
    print('[LinkPreview] prefetch failed: $e');
  }
}

/// Ask the preview endpoint about the first link in [body] and re-host its
/// picture. Null means "send a plain link": no endpoint baked into this build,
/// no link in the body, no warm answer inside [budget], or any failure at all.
Future<TelegramLinkPreview?> telegramLinkPreviewFor(
  Client client,
  String body, {
  Duration? budget,
}) async {
  final base = AppSettings.linkPreviewUrl.value.trim();
  if (base.isEmpty) return null;
  final link = telegramFirstLink(body);
  if (link == null) return null;
  final key = link.toString();

  final warm = telegramCachedPreview(body);
  if (warm != null) return warm;

  // One fetch per link: a Send tap joins the prefetch already running for the
  // same url, on the tap's own clock. A tap that runs out of budget sends the
  // plain link and the fetch keeps going, so the next message is warm.
  final joined = _inFlight[key];
  if (joined != null) {
    return budget == null
        ? await joined
        : await joined.timeout(budget, onTimeout: () => null);
  }

  final running = _fetchPreview(client, link, base);
  _inFlight[key] = running;
  try {
    final result = budget == null
        ? await running
        : await running.timeout(budget, onTimeout: () => null);
    if (result != null) _storeWarm(key, result);
    return result;
  } finally {
    _inFlight.remove(key);
  }
}

Future<TelegramLinkPreview?> _fetchPreview(
  Client client,
  Uri link,
  String base,
) async {
  Map<String, Object?> answer;
  try {
    final request = Uri.parse(
      '$base${base.contains('?') ? '&' : '?'}url=${Uri.encodeComponent(link.toString())}',
    );
    final response = await http
        .get(request, headers: const {'accept': 'application/json'})
        .timeout(const Duration(seconds: 9));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) return null;
    answer = decoded.cast<String, Object?>();
  } catch (e) {
    // The endpoint is a decoration. Logs() is not reachable from here without
    // a client, and debugPrint is the release-invisible channel this fork uses
    // for media paths (see telegram_mp4_gif.dart).
    // ignore: avoid_print
    print('[LinkPreview] endpoint failed: $e');
    return null;
  }

  String field(String key) {
    final value = answer[key];
    return value is String ? value.trim() : '';
  }

  var imageMxc = Uri.tryParse(field('image_url'));
  int? width;
  int? height;
  int? size;
  String? mime;
  if (imageMxc != null &&
      (imageMxc.scheme == 'http' || imageMxc.scheme == 'https')) {
    final picture = await _fetchAndUploadPicture(client, imageMxc);
    imageMxc = picture?.mxc;
    width = picture?.width;
    height = picture?.height;
    size = picture?.size;
    mime = picture?.mime;
  } else {
    imageMxc = null;
  }

  final preview = TelegramLinkPreview(
    url: field('url').isEmpty ? link.toString() : field('url'),
    siteName: field('site_name'),
    title: field('title'),
    description: field('description'),
    authorName: field('author_name'),
    type: field('type'),
    imageMxc: imageMxc,
    imageWidth: width,
    imageHeight: height,
    imageSize: size,
    imageMime: mime,
  );
  if (!preview.hasText && preview.imageMxc == null) return null;
  return preview;
}

class _UploadedPicture {
  final Uri mxc;
  final int? width;
  final int? height;
  final int? size;
  final String? mime;
  const _UploadedPicture(
    this.mxc,
    this.width,
    this.height,
    this.size,
    this.mime,
  );
}

/// Download one `og:image`, read its pixel size, upload it to this client's
/// homeserver. Null on any problem, including an oversized or non-image answer.
Future<_UploadedPicture?> _fetchAndUploadPicture(
  Client client,
  Uri imageUri,
) async {
  try {
    final response = await http
        .get(imageUri)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;
    final declared = int.tryParse(response.headers['content-length'] ?? '');
    if (declared != null && declared > _maxPreviewImageBytes) return null;
    final bytes = response.bodyBytes;
    if (bytes.isEmpty || bytes.length > _maxPreviewImageBytes) return null;
    final mime = (response.headers['content-type'] ?? '')
        .split(';')
        .first
        .trim();
    if (!mime.startsWith('image/')) return null;

    // The pixel size goes into the event so the card can lay the picture out
    // before it decodes, and so `org.matrix.msc3860/image` carries real
    // ImageInfo. Header decode only: a full decode of a 1200x800 og:image is
    // 3.8 MB of RGBA on a phone for a number we can read from the header.
    int? width;
    int? height;
    final decoder = img.findDecoderForData(bytes);
    if (decoder != null) {
      final info = decoder.startDecode(bytes);
      if (info != null && info.width > 0 && info.height > 0) {
        width = info.width;
        height = info.height;
      }
    }

    final mxc = await client
        .uploadContent(bytes, filename: 'preview', contentType: mime)
        .timeout(const Duration(seconds: 30));
    return _UploadedPicture(mxc, width, height, bytes.length, mime);
  } catch (e) {
    // ignore: avoid_print
    print('[LinkPreview] picture skipped: $e');
    return null;
  }
}

/// The `m.room.message` content for a plain-text send that carries [preview].
///
/// Field parity with what `Room.sendTextEvent` builds for a plain body
/// (`matrix-14.1.0/lib/src/room.dart:693-778`): `msgtype`, `body`, and the
/// replied-to user in `m.mentions`. No `format`/`formatted_body`: a plain body
/// gets none from matrix-dart either, once its markdown answer equals the body.
Map<String, Object?> telegramTextPreviewContent({
  required String body,
  required TelegramLinkPreview preview,
  Event? inReplyTo,
}) => {
  'msgtype': 'm.text',
  'body': body,
  if (inReplyTo != null)
    'm.mentions': {
      'user_ids': [inReplyTo.senderId],
    },
  TelegramLinkPreview.contentKey: [preview.toContent()],
};

/// The preview object of an event, in the shape [LinkPreview] draws. Null when
/// the event carries none. Accepts a bare object as well as the spec's array,
/// because a hand-made event on a server we do not run is a real thing in a
/// friend group.
Map<String, Object?>? telegramEventLinkPreview(Event event) {
  final raw = event.content[TelegramLinkPreview.contentKey];
  final map = switch (raw) {
    final List<Object?> list when list.isNotEmpty =>
      (list.first as Map?)?.cast<Object?, Object?>(),
    final Map<Object?, Object?> map => map,
    _ => null,
  };
  return map?.cast<String, Object?>();
}
