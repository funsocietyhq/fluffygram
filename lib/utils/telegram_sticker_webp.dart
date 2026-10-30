// SPDX-FileCopyrightText: 2026-Present FluffyGram fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';

// Re-encodes a picked image as a sticker, so the send dialog can offer
// "Send as sticker" (T142, user, 2026-10-30: "can we do the same thing we did
// for gifs with stickers? ... Then they'd show up in the sticker drawer").
//
// Telegram's own form is the target: **a static sticker is a WebP whose width
// or height is 512 px, and transparency is supported**
// (core.telegram.org/api/stickers, "Static stickers", read 2026-10-30). Matrix
// agrees on the size from the other side - MSC2545: "Stickers SHOULD be at
// least 512x512 pixels". Upstream's sticker-pack path declares 256 px
// (`settings_emotes.dart:334`, "normalize width / height to 256, required for
// stickers"), which is half of both numbers, so the fork resizes to 512.
//
// **Alpha stays on.** T123.1 measured that Flutter's Skia refuses to animate a
// WebP carrying an alpha plane (`Could not getPixels for frame N`), which is
// why `telegram_gif_webp.dart` flattens every frame. A sticker is the opposite
// case on both halves: it is static, so the animation bug cannot fire, and its
// transparency is the picture - every sticker pack this app already draws is a
// WebP with alpha. So this file strips nothing.
//
// An **animated** pick becomes its first frame: an alpha-bearing animated WebP
// sticker would hit the T123.1 wall in this engine, and Telegram's own animated
// forms (Lottie `.tgs`, WebM) are not Matrix stickers at all.
//
// Returns `null` when the pick cannot be converted - the caller then sends it
// as a plain image. Like `telegramGifToWebp`, this never throws into a send.

/// Telegram's static sticker canvas: one side exactly 512 px, the other side in
/// proportion. Larger picks are capped to it; smaller ones are never blown up.
const int _stickerMaxSide = 512;

/// `encodeWebP` defaults to `lossless: true`, where `quality` and `method` do
/// nothing (`image-4.12.0/lib/src/formats/formats.dart:485-540`). Lossy is what
/// makes a 512 px photo sticker a few tens of KB, so the mode is explicit.
const bool _webpLossless = false;

/// Quality 90, not the GIF path's 75: a sticker sits in the timeline and in the
/// drawer for its whole life, and at 512 px the byte cost of 90 over 75 is small
/// against Telegram's own ceiling (below). Method 4 for the same reason the GIF
/// path picks it - method 6 buys ~5 % for ~2x the encode time.
const int _webpQuality = 90;
const int _webpMethod = 4;

/// Telegram's static sticker class of file ("the perfect sticker" guide caps a
/// static sticker at 100 KB). Over it the file re-encodes once at
/// [_stickerFallbackQuality] rather than shipping a fat sticker: a sticker is
/// drawn at 128 dp on the phone (`message_content.dart:76` caps a sticker row at
/// 128.0), so the 512 px canvas is already 4x the display size and a drop to 70
/// is invisible there while it halves the bytes.
const int _maxStickerBytes = 100 * 1000;
const int _stickerFallbackQuality = 70;

/// Converts [pick] to a 512 px WebP sticker. Runs on an isolate: the decode and
/// the encode are the same 100-500 ms class of work as the GIF conversion, and
/// this runs inside the send dialog on a phone.
Future<MatrixImageFile?> telegramImageToSticker(MatrixImageFile pick) async {
  try {
    return await Isolate.run(
      () => _toSticker(pick.bytes, pick.name, pick.mimeType),
    );
  } catch (e) {
    // A conversion must never break a send. Whatever failed, send the image.
    Logs().i('[StickerWebp] conversion skipped: $e');
    return null;
  }
}

/// Runs on the isolate: takes only bytes, a name and a mime type, and touches no
/// Flutter binding.
MatrixImageFile? _toSticker(Uint8List bytes, String name, String? mimeType) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  // An animated pick becomes its first frame. The frame list is a trap here,
  // measured on this version: `decoded.frames.first` **is** `decoded`
  // (`identical()` answers true), and a `copyCrop` or `convert` of it keeps all
  // 34 frames - so encoding "the first frame" of a user's Giphy clip
  // shipped an ANIMATED WebP (1,016,068 B, `webpmux -info` reads
  // `Features present: animation`). `frames` is a plain mutable `List<Image>`
  // (`image-4.12.0/lib/src/image/image.dart:76`), so the still is that object
  // with its tail cut off: 27,710 B, no animation feature in the container.
  if (decoded.frames.length > 1) {
    decoded.frames.removeRange(1, decoded.frames.length);
  }
  final first = decoded;
  final longSide = first.width >= first.height ? first.width : first.height;

  // A pick that is already a WebP inside the sticker canvas keeps its bytes:
  // re-encoding a lossless sticker or an already-crisp 512 px WebP only loses
  // quality (a user's standing rule from T131: keep the source when the
  // transform cannot improve it).
  if (mimeType == 'image/webp' && longSide <= _stickerMaxSide) {
    return MatrixImageFile(
      bytes: bytes,
      name: _webpName(name),
      mimeType: 'image/webp',
      width: first.width,
      height: first.height,
    );
  }

  var source = first;

  // `copyResize` silently falls back to nearest-neighbour for a palette source
  // no matter which interpolation is passed (`copy_resize.dart:24,30`), and a
  // picked GIF arrives paletted. De-palette first so `average` is real -
  // measured +11 dB over nearest on a video frame (the measurement log).
  if (source.hasPalette) source = source.convert();

  var image = source;
  if (longSide > _stickerMaxSide) {
    // One dimension only, so the aspect ratio survives; `copyResize` with both
    // null throws `ImageException: Invalid size`.
    image = first.width >= first.height
        ? img.copyResize(
            source,
            width: _stickerMaxSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            source,
            height: _stickerMaxSide,
            interpolation: img.Interpolation.average,
          );
  }

  var webp = img.encodeWebP(
    image,
    lossless: _webpLossless,
    quality: _webpQuality,
    method: _webpMethod,
  );

  // Measured at 512 px, none of the real picks come close: a 593x762 photo
  // 12,964 B, a 900x700 transparent PNG 11,246 B, the first frame of a Giphy
  // clip 27,710 B. If one does (a heavily dithered, noisy frame), it re-encodes
  // once at 70 and ships whatever that costs - a fat sticker is not worth a
  // search loop, and a homeserver upload limit is megabytes away.
  if (webp.length > _maxStickerBytes) {
    webp = img.encodeWebP(
      image,
      lossless: _webpLossless,
      quality: _stickerFallbackQuality,
      method: _webpMethod,
    );
  }

  return MatrixImageFile(
    bytes: webp,
    name: _webpName(name),
    mimeType: 'image/webp',
    width: image.width,
    height: image.height,
  );
}

String _webpName(String name) {
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  return '$base.webp';
}
