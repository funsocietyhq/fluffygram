// SPDX-FileCopyrightText: 2026-Present FluffyGram fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';

/// Re-encodes an animated GIF as an animated WebP so a GIF upload ships
/// smaller. Owned by T123 (user, 2026-10-30: "The main goal is smaller gifs.
/// Gifs currently are large.").
///
/// This needs no new dependency: `image: ^4.12.0` (`pubspec.yaml:58`) already
/// writes the animated container - `ANIM` at `webp_encoder.dart:141`, one
/// `ANMF` per frame at `:150`, each with its `frameDuration`, whole frames and
/// no delta frames. `decodeWebP` reads `ANMF` back at `webp_decoder.dart:330`,
/// and a round trip in the probe kept every one of the 149 frames.
///
/// Returns `null` when the GIF must keep its bytes, which happens in six
/// cases: undecodable, a single frame (today's path is then unchanged), over
/// the memory budget, transparent enough that flattening would change how it
/// looks, or **when the WebP came out bigger than the GIF**. That
/// last gate is not optional. Measured (`the measurement log`, "Animated
/// WebP instead of GIF: measured, and it goes both ways"): a photo-like clip,
/// 400 x 400 x 50 frames, went 144,106 B -> 30,832 B, **4.7x smaller**; a flat
/// clip of text, 249 x 46 x 149 frames, went 65,324 B -> 224,528 B, **3.4x
/// BIGGER**, because this encoder stores whole frames with no inter-frame
/// prediction while GIF's LZW plus a 256-entry palette is very good at flat
/// graphics. The caller keeps the GIF whenever this returns null.
const int _webpQuality = 75;
const int _webpMethod = 4;

/// `encodeWebP` defaults to `lossless: true`, and in that mode `quality` and
/// `method` do nothing at all (`image-4.12.0/lib/src/formats/formats.dart:485-
/// 540`). The lossy mode is the whole point of this file, so it is explicit.
const bool _webpLossless = false;

/// Decode ceiling in pixel-frames: width x height x frame count. Decoding puts
/// every frame in RGBA, so 4 bytes each. 20,000,000 pixel-frames is about 80 MB
/// of RGBA, which is the same wall T120 hit from the other side
/// (`PaintingBinding.maximumSizeBytes`, 100 MB): a 720p, 100-frame GIF would be
/// ~900 MB and would kill the phone in the send dialog. Over the budget the GIF
/// ships as it is.
const int _maxPixelFrames = 20000000;

/// Every frame is encoded **without an alpha plane** (see
/// [_stripAlpha]). Flutter cannot play an animated WebP that carries one:
/// measured 2026-10-30 on a user's Giphy clip, the engine stepped 13 frames
/// and then threw `Could not getPixels for frame 13`, which is the first frame
/// `webpmux -info` marks `alpha yes`; the identical failure lands on the alpha
/// frame of an animated WebP built by Google's own `img2webp`, so the container
/// is legal (Chrome, Element and libwebp all play it) and only the Skia build
/// Flutter ships refuses it. Flattening is therefore mandatory, not an
/// optimisation.
///
/// Flattening is a lie when the GIF really is transparent, so a GIF above this
/// share of transparent pixels keeps its GIF bytes. Measured with
/// `notes/`-side probes: a photo clip (the case WebP wins 7x on) carries 869
/// transparent pixels of 5,907,840, 0.08 % on its worst frame; a flat text
/// overlay clip carries 24.88 % on a frame, and there the transparency is the
/// picture. 2 % sits 25x above the first case and 12x below the second.
const double _maxTransparentFraction = 0.02;

/// The transparency count samples every 4th pixel of every 4th row (1/16 of the
/// canvas) because it runs in the send dialog on a phone; a 2 % threshold
/// cannot be crossed by accident at that sampling density.
const int _alphaSampleStep = 4;

/// Rewrites every frame of [image] as a 3-channel RGB image, so
/// `encodeWebP` never writes an `ALPH` sub-chunk inside an `ANMF` frame.
/// `frames` is a plain `List<Image>` (`image-4.12.0/lib/src/image/image.dart:76`)
/// so the frames are replaced in place; building a fresh canvas and calling
/// `addFrame` instead would prepend a blank base frame (measured: 35 frames for
/// a 34-frame GIF). `convert` carries `frameDuration` across, which the frame
/// durations in `webpmux -info` confirm.
void _stripAlpha(img.Image image) {
  for (var i = 0; i < image.frames.length; i++) {
    image.frames[i] = image.frames[i].convert(numChannels: 3);
  }
}

/// True when no frame has more than [_maxTransparentFraction] transparent
/// pixels, i.e. when flattening cannot be seen.
bool _transparencyIsASpeck(img.Image image) {
  const step = _alphaSampleStep;
  final sampleArea = (image.width / step).ceil() * (image.height / step).ceil();
  for (final frame in image.frames) {
    var transparent = 0;
    for (var y = 0; y < frame.height; y += step) {
      for (var x = 0; x < frame.width; x += step) {
        if (frame.getPixel(x, y).a < 255) transparent++;
      }
    }
    if (transparent / sampleArea > _maxTransparentFraction) return false;
  }
  return true;
}

/// Encodes with method 4, not 6 or 0: the package's own docs say method 0-1 run
/// ~4x faster for ~20 % more bytes and method 6 saves ~5 % for ~2x the time,
/// and the encode already costs 125-493 ms on a desktop CPU (358 ms and 660 ms
/// in the two measured clips) - more on a phone. Quality 75 is the measured
/// setting; above 90 the size grows steeply.
Future<MatrixImageFile?> telegramGifToWebp(
  MatrixImageFile gif, {
  int maxDimension = 1600,
}) async {
  try {
    // Off the UI thread: the encode is 125-493 ms on a desktop and slower on a
    // phone, and it runs inside the send dialog.
    return await Isolate.run(() => _convert(gif.bytes, gif.name, maxDimension));
  } catch (e) {
    // A conversion must never break a send. Whatever failed, send the GIF.
    Logs().i('[GifWebp] conversion skipped: $e');
    return null;
  }
}

/// Runs on the isolate. Everything it needs is passed in, and it touches no
/// Flutter binding, so it is safe away from the UI thread.
MatrixImageFile? _convert(Uint8List bytes, String name, int maxDimension) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  // `Image` has no `frameCount` getter; `frames` is the frame list.
  final frameCount = decoded.frames.length;
  if (frameCount < 2) return null; // a still GIF keeps today's path

  if (decoded.width * decoded.height * frameCount > _maxPixelFrames) {
    return null; // would need more RGBA than the phone can hold
  }

  // Cap the longer side, exactly what matrix-dart's own resize path does for a
  // still when the Compress toggle is on (`matrix_file.dart:229-253`).
  // `copyResize` resizes EVERY frame when the interpolation allows a byte-level
  // resize (`image-4.12.0/lib/src/transform/copy_resize.dart:19,41,111`), so
  // this caps the clip and does not flatten it.
  // Transparency is read off the decoded frames, before any resize, and it
  // gates the whole conversion: flattening a genuinely transparent GIF would
  // paint its holes with the canvas background and change the picture.
  if (!_transparencyIsASpeck(decoded)) return null;

  var image = decoded;
  if (decoded.width > maxDimension || decoded.height > maxDimension) {
    // One dimension only, so `copyResize` keeps the aspect ratio - the same
    // shape as matrix-dart's own resize path (`matrix_file.dart:229-253`).
    // The `if` is not decoration: `copyResize` with both dimensions null
    // throws `ImageException: Invalid size`, measured in the probe.
    image = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: maxDimension)
        : img.copyResize(decoded, height: maxDimension);
  }

  // Mandatory, not a size tweak: an alpha-bearing frame stops Flutter's
  // animated-WebP codec part way through the clip (see _maxTransparentFraction).
  _stripAlpha(image);

  final webp = img.encodeWebP(
    image,
    lossless: _webpLossless,
    quality: _webpQuality,
    method: _webpMethod,
  );

  // The flat-clip case: keep the GIF when WebP did not actually win.
  if (webp.length >= bytes.length) return null;

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
