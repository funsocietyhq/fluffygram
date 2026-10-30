// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart' show MatrixImageFile;
import 'package:media_kit/media_kit.dart';

/// T128 : turn a picked mp4 into an **animated WebP** at
/// send time, behind the explicit "Convert to gif" switch in the send dialog.
///
/// Why a WebP and not Telegram's form: Telegram keeps the mp4 and marks it
/// animated (`messenger/MessageObject.java:6916-6926`, `isNewGifDocument`, gate
/// w <= 1280 && h <= 1280). **Matrix has no animated attribute**, so an mp4
/// never loops in a client that does not know the flag. An image loops in
/// every client, which is the whole point of the feature (ROADMAP T128,
/// Decisions: "the only way a clip loops in every client is to ship it as an
/// image"). T123's `telegramEventIsGif` already counts `image/webp` on an
/// `m.image` as a GIF, so the row loops, enters the GIF tray and replays.
///
/// Every rejection and every failure returns `null`, and the caller then sends
/// the video exactly as it does today. A Convert-to-gif attempt can never
/// break a send.
///
/// The pixel path is media_kit's `Player.screenshot()` - mpv behind FFI, no
/// Kotlin (ground rule 2). The dependency is already committed: `media_kit
/// 1.2.6` (`pubspec.yaml:71`) plus the new `media_kit_libs_android_video`
/// 1.3.8 natives.
///
/// WebP encoding reuses the T123 rules, including the alpha rule in
/// [_prepareFrame].

/// Ceiling for the longer side, and it is Telegram's own: `isNewGifDocument`
/// accepts an animated document only while `w <= 1280 && h <= 1280`
/// (`messenger/MessageObject.java:6916-6926`). A phone clip at 720p or 1080p is
/// the only thing this scales; anything smaller keeps its pixels (T131, user
/// 2026-10-29: "I just want to maintain quality with the original mp4").
const int _defaultMaxSide = 1280;

/// Frame-rate ceiling when sampling the clip at its own rate. A 60 fps phone
/// clip holds no more visible motion at 25 fps, and every extra frame costs a
/// seek, a grab and RGBA in memory. The ANMF `duration` field is milliseconds
/// (WebP container spec, and `webp_encoder.dart:156` writes `f.frameDuration`
/// straight into it), so `frameDuration` is 1000/fps ms.
const double _maxFps = 25;

/// Used when mpv gives no `container-fps` (a raw stream in a bare container).
/// 25 is what a phone camera clip records at, so guessing 25 costs nothing real.
const double _fallbackFps = 25;

/// Wall-clock ceiling on the grab loop, in frames. One frame costs a seek plus a
/// screenshot, measured at 101 ms for the seek route and 76 ms for mpv's
/// sequential `frame-step` (`NativePlayer.command`, real.dart:1359) at 720x1280 -
/// PNG encode/decode dominates, so the sampling route is not what to optimize.
/// 150 frames therefore keeps the send-dialog wait near 15 s on Linux (a phone
/// is slower), and a clip longer than that drops its SAMPLE RATE rather than
/// making the sender wait: 8 s -> 18 fps, 15 s -> 10 fps.
const int _maxFrames = 150;

/// Longer clips are videos, not GIFs. At the 150-frame ceiling a 15 s clip is
/// sampled at 10 fps.
const Duration _defaultMaxDuration = Duration(seconds: 15);

/// Output ceiling in BYTES. Frames are encoded one at a time and assembled
/// straight into the WebP container (T131), so the sender never holds a list of
/// RGBA frames and memory stopped being the limit - the upload size is. A
/// 921,600 px frame at quality 90 measures 36 KB encoded, so a 150-frame clip at
/// 720p lands near 5.4 MB, and 12 MB still refuses a clip the group could not
/// download.
///
/// Holding every frame was the old design's wall (30 M pixel-frames ~ 120 MB of
/// RGBA). The receiving side never paid it: Flutter's own decoder
/// (`ui.instantiateImageCodec`) walked a 1280x720 x 60-frame file - 55 M
/// pixel-frames - in 897 ms and moved process RSS by +23 MB, because it decodes
/// one frame at a time. The sender now does the same.
const int _maxOutputBytes = 12 * 1024 * 1024;

/// Quality 90 / method 3 / lossy. T131 raised the quality from T123's 75: the
/// a user's finding was that a converted clip looked worse than the mp4 it came
/// from, and the measurements put that loss in the resize filter first
/// (nearest-neighbour 25.61 dB vs area-average 36.64 dB against the same
/// reference) with the codec second; 75 -> 90 measured +0.2 dB at 480x270.
/// Method went 4 -> 3 for the same reason in reverse: at 1280x720 it measures
/// 111 ms against method 4's 213 ms with the output within noise (35.24 dB vs
/// 35.23 dB, 36,160 B vs 36,382 B) - the encode is what the phone spends its
/// seconds on, and method 2 (40 ms, 35.22 dB, +5 % bytes) is the next stop if it
/// is still too slow.
/// `encodeWebP` is lossless by default, and in that mode `quality` and `method`
/// do nothing (`image-4.12.0/lib/src/formats/formats.dart:525-538`), so all
/// three stay explicit.
const int _webpQuality = 90;
const int _webpMethod = 3;
const bool _webpLossless = false;

/// mpv takes a moment to build its internals, and longer to load the first
/// frame of a file. Over either timeout the conversion is abandoned and the
/// clip sends as a video.
const Duration _initTimeout = Duration(seconds: 10);
const Duration _metadataTimeout = Duration(seconds: 10);

/// A seek lands asynchronously, and a screenshot taken before it lands repeats
/// the previous frame. This is how long one seek is allowed to take.
const Duration _seekSettleTimeout = Duration(milliseconds: 400);

/// Hard wall-clock budget for the whole seek+screenshot loop. 181 seeks on a
/// phone can be slow; rather than hold the send dialog forever the loop stops
/// and whatever frames it collected get encoded (2 is the minimum).
const Duration _grabBudget = Duration(seconds: 90);

/// How many of mpv's own log lines reach logcat through `stream.log`. Enough to
/// name why an open or a screenshot failed, few enough not to flood a release
/// log. (T128.1: build 85 had zero diagnostics because media_kit never prints
/// these itself.)
const int _maxMpvLogLines = 12;

/// mpv's own load-time options that this conversion needs, written before
/// `open()`. `NativePlayer.setProperty` takes strings and applies them to the
/// option pool, so a load-time option set here is live at the next load
/// (media_kit `native/player/real.dart:1223`, `setProperty`; the comment at
/// `:2321` is media_kit's own note that some options must exist before
/// `mpv_initialize`).
///
/// - **`vid = auto`** is the fix for build 86's failure. A `Player` with no
///   `VideoController` attached is headless by media_kit's definition, and a
///   headless player gets `vid = no`: real.dart:2325-2333 sets
///   `hasNoUi = videoControllerCount == 0 && audioControllerCount == 0` and
///   `if (!test) 'vid': 'no'` at `:2432`, which tells mpv to select NO video
///   track. That is exactly what mpv said on a user's phone: `fatal:
///   No video or audio streams selected`, after which every seek failed
///   (`error running command _command(seek, ...)`) and no frame could ever be
///   grabbed. `auto` selects the video track without needing a widget: the
///   a user's logcat and the local Linux run both then report real dimensions,
///   a moving `position`, and a non-null screenshot.
/// - **`cache-on-disk = no`** stops `error: Failed to create file cache.`.
///   media_kit sets `cache = yes` and `cache-on-disk = yes` unconditionally
///   (real.dart:2400-2401) and never sets `demuxer-cache-dir`, and mpv's
///   on-disk cache wants a temp dir Android does not give it. Measured locally
///   with media_kit's own option pair: the error appears with
///   `cache-on-disk=yes` and is gone with `no` or with `cache=no` (mpv 0.41 CLI
///   A/B, `the measurement log` "T128.2"). A RAM cache is the right shape
///   for a clip this function caps at 15 s.
const List<(String, String)> _mpvLoadOptions = [
  ('vid', 'auto'),
  ('cache-on-disk', 'no'),
];

/// `[Mp4Gif]` diagnostics go through `print`, not `debugPrint`, so this file
/// stays free of `package:flutter` and a plain `dart run` on Linux can call the
/// shipped function directly (user instruction 2026-10-29: test locally before
/// shipping). A `print` from the isolate still reaches logcat as `I flutter :`.
void _log(String message) {
  // ignore: avoid_print
  print(message);
}

/// Converts the mp4 at [path] into an animated WebP `MatrixImageFile`.
///
/// Returns `null` - and leaves the caller's video send untouched - when the
/// clip is shorter than 2 frames, longer than [maxDuration], bigger than
/// [maxOutputBytes] encoded, or when anything at all fails (no native mpv, a
/// refused seek, an undecodable screenshot).
///
/// mpv itself is never wrapped in `Isolate.run` - it is a native handle behind
/// FFI, and media_kit already runs the screenshot in a worker isolate
/// (`media_kit/lib/src/player/native/player/real.dart:1188`, `compute`). The
/// pixel work this file adds (PNG decode, resize, WebP encode) DOES run in a
/// fresh isolate per frame, because at source resolution that is 100 ms+ of
/// pure-Dart CPU per frame and it would freeze the send dialog.
Future<MatrixImageFile?> telegramMp4ToGif(
  String path, {
  int maxSide = _defaultMaxSide,
  double? fps,
  Duration maxDuration = _defaultMaxDuration,
  int maxOutputBytes = _maxOutputBytes,
}) async {
  Player? player;
  StreamSubscription<PlayerLog>? logSub;
  try {
    MediaKit.ensureInitialized(); // media_kit/lib/src/media_kit.dart:23
    final initialized = Completer<void>();
    player = Player(
      // media_kit/lib/src/player/player.dart:103
      configuration: PlayerConfiguration(
        muted: true, // platform_player.dart:475 - no audio for a GIF
        // T128.1 (user logcat, build 85, 2026-10-29 14:54:05: "[Mp4Gif]
        // skipped: no media metadata within 0:00:10"). mpv's default video
        // output on Android is `gpu`, which needs a window we never attach, so
        // the video track stays disabled and mpv never emits `video-params`.
        // `'null'` is mpv's window-less output - the classic frame-extraction
        // recipe (`mpv --vo=null --seek=<t> --frames=1 <file>`) - and
        // media_kit exposes it as `PlayerConfiguration.vo` (String?,
        // platform_player.dart:5), applied at native/player/real.dart:2427.
        vo: 'null',
        // platform_player.dart:470; fired by NativePlayer once mpv is up
        // (native/player/real.dart:82).
        ready: () {
          if (!initialized.isCompleted) initialized.complete();
        },
      ),
    );
    await initialized.future.timeout(_initTimeout);
    // mpv says why an open or a grab fails, and media_kit puts those words on
    // `stream.log` (models/player_stream.dart:97) without printing them -
    // build 85's logcat was silent for that reason. Bounded, so a chatty demuxer
    // cannot flood the log.
    var mpvLogLines = 0;
    logSub = player.stream.log.listen((l) {
      if (mpvLogLines++ < _maxMpvLogLines) {
        _log('[Mp4Gif] mpv ${l.level}: ${l.text}');
      }
    });

    // T128.2: mpv must be told to select a video track, and must not be asked
    // to cache that track to disk. See [_mpvLoadOptions].
    final native = player.platform;
    if (native is NativePlayer) {
      for (final (key, value) in _mpvLoadOptions) {
        await native.setProperty(key, value); // real.dart:1223
      }
    } else {
      _log(
        '[Mp4Gif] note: player platform is ${native.runtimeType}, '
        'mpv load options not applied',
      );
    }

    // player.dart:160. `Media` takes a plain path and resolves an Android
    // `content://` pick to `fd://<fd>` (models/media/media_native.dart:146-160).
    // The resolved uri goes in the log, so a failed open names the file mpv was
    // actually handed.
    final media = Media(path);
    _log('[Mp4Gif] opening ${media.uri}');
    await player.open(media, play: false);

    // T128.1: the gate waits for the DURATION only. `duration` comes from the
    // demuxer and needs no decoder (models/player_state.dart:36), while
    // `width/height` come from mpv's `video-params`, which needs a decoded
    // frame - build 85 waited on all three and timed out on the two that a
    // window-less player leaves null. The grabbed frames carry their own size,
    // and the pixel budget moves to the first one.
    final metadataDeadline = DateTime.now().add(_metadataTimeout);
    while (player.state.duration == Duration.zero) {
      if (DateTime.now().isAfter(metadataDeadline)) {
        _log(
          '[Mp4Gif] skipped: no duration within $_metadataTimeout '
          '(w=${player.state.width} h=${player.state.height} '
          'position=${player.state.position} completed=${player.state.completed})',
        );
        return null;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final duration = player.state.duration;
    if (duration > maxDuration) {
      _log(
        '[Mp4Gif] skipped: $duration over the ${maxDuration.inSeconds} s ceiling',
      );
      return null;
    }

    // The clip's OWN frame rate, capped at `_maxFps` (T131: sampling 12 fps out
    // of a 25 fps clip was half the motion quality of the mp4 it came from).
    // mpv names the container rate `container_fps` (`getProperty`,
    // native/player/real.dart:1255).
    final fpsProperty = await _mpvProperty(native, 'container-fps');
    final containerFps = fpsProperty == null
        ? null
        : double.tryParse(fpsProperty);
    var sampleFps = (fps ?? (containerFps ?? _fallbackFps)).clamp(1.0, _maxFps);
    final rateForFrameCap = _maxFrames * 1000.0 / duration.inMilliseconds;
    if (sampleFps > rateForFrameCap) {
      sampleFps = rateForFrameCap.clamp(1.0, _maxFps);
      _log(
        '[Mp4Gif] $duration at ${containerFps ?? _fallbackFps} fps would pass '
        '$_maxFrames frames -> sampling at $sampleFps fps',
      );
    }
    // One frame per 1/sampleFps, starting at t = 0, last one at or before
    // duration.
    _log('[Mp4Gif] container fps $containerFps -> sampling $sampleFps fps');
    final stepMs = (1000 / sampleFps).round().clamp(1, 10000);
    final frameCount = duration.inMilliseconds ~/ stepMs + 1;
    if (frameCount < 2) return null;

    // Grab frame 0 BEFORE choosing an output size: the screenshot's own
    // dimensions are the truth about the picture (mpv's `video-params` can
    // disagree with it through a sample aspect ratio), and the plan below has to
    // match the frames the loop actually holds.
    final firstBytes = await _grab(player, Duration.zero);
    if (firstBytes == null) {
      _log('[Mp4Gif] skipped: no frame at t = 0');
      return null;
    }
    final firstFrame = img.decodeImage(firstBytes);
    if (firstFrame == null) {
      _log('[Mp4Gif] skipped: the frame at t = 0 did not decode');
      return null;
    }
    final out = _planOutput(firstFrame.width, firstFrame.height, maxSide);
    if (out == null) return null;
    final outW = out.$1;
    final outH = out.$2;

    // One frame at a time, all the way through: the pixel stage returns a
    // single-frame WebP, its bitstream goes into an ANMF chunk, and the sender
    // holds ONE RGBA frame instead of a list (T131 - that is what lets the
    // output keep the source size).
    final anmf = <Uint8List>[];
    var encodedBytes = 0;
    var overflow = false;
    void addStill(Uint8List still) {
      if (still.isEmpty || overflow) return; // a bad frame is skipped, not fatal
      encodedBytes += still.length;
      if (encodedBytes > maxOutputBytes) {
        overflow = true;
        return;
      }
      anmf.add(_anmfPayload(outW, outH, stepMs, _webpFrameChunks(still)));
    }

    addStill(_encodeStill(firstFrame, outW, outH));
    final grabDeadline = DateTime.now().add(_grabBudget);
    // The encode of frame i-1 runs while mpv seeks and screenshots frame i: one
    // side is native, the other an isolate, so the loop costs the grab (~110 ms)
    // instead of grab plus encode (~220 ms measured at 1280x720).
    Future<Uint8List>? inFlight;
    for (var i = 1; i < frameCount; i++) {
      if (DateTime.now().isAfter(grabDeadline)) {
        _log('[Mp4Gif] grab budget used, ${anmf.length} of $frameCount frames');
        break;
      }
      final grabbed = await _grab(player, Duration(milliseconds: i * stepMs));
      if (grabbed == null) continue;
      // A plain copy, not the buffer media_kit hands back: its `Uint8List` is
      // backed by native memory, and a native-backed list is NOT sendable to an
      // isolate (`Illegal argument in isolate message: object is unsendable`,
      // measured - the copy costs ~1 ms and is what makes the worker usable).
      final shot = Uint8List.fromList(grabbed);
      final previous = inFlight;
      inFlight = _encodeOffThread(shot, outW, outH);
      if (previous != null) addStill(await previous);
      if (overflow) break;
    }
    if (inFlight != null) addStill(await inFlight);
    if (overflow) {
      _log('[Mp4Gif] skipped: $encodedBytes bytes over $maxOutputBytes');
      return null;
    }
    if (anmf.length < 2) return null;

    final webp = _riffAnimation(outW, outH, anmf);
    _log('[Mp4Gif] $outW x $outH x ${anmf.length} frames, ${webp.length} B');
    return MatrixImageFile(
      bytes: webp,
      name: '${_nameStem(path)}.webp',
      mimeType: 'image/webp',
      width: outW,
      height: outH,
    );
  } catch (e) {
    // A conversion attempt must never break a send - the caller keeps the video.
    _log('[Mp4Gif] skipped: $e');
    return null;
  } finally {
    try {
      await logSub?.cancel();
    } catch (_) {}
    try {
      await player?.dispose(); // player.dart:138
    } catch (_) {}
  }
}

/// mpv's own property read, null-safe on a platform that is not the native
/// player and on a property this mpv build does not have (`getProperty`,
/// native/player/real.dart:1255).
Future<String?> _mpvProperty(Object? platform, String name) async {
  if (platform is! NativePlayer) return null;
  try {
    return await platform.getProperty(name);
  } catch (_) {
    return null;
  }
}

/// Seeks to [at], waits for mpv's `position` to land, and screenshots. Null when
/// either step fails. PNG, not JPEG: the screenshot stays lossless on the way
/// into `package:image`, and `image/png` is one of the two formats the native
/// backend accepts (native/player/real.dart:1170-1174; player.dart:321).
Future<Uint8List?> _grab(Player player, Duration at) async {
  await player.seek(at); // player.dart:222
  await _awaitSeek(player, at);
  return player.screenshot(format: 'image/png');
}

/// The hop that keeps the send dialog alive: a fresh isolate per frame for the
/// pixel work.
///
/// It has to be a SEPARATE sync function, not the closure written inline in
/// `telegramMp4ToGif`: a closure created inside that async function shares its
/// context, which holds the async machinery, and the spawn dies with
/// `Illegal argument in isolate message: object is unsendable - Class:
/// _AsyncCompleter` (measured). A plain copy of the screenshot bytes goes in,
/// because media_kit's own `Uint8List` is native-backed and equally unsendable.
Future<Uint8List> _encodeOffThread(Uint8List shot, int outW, int outH) =>
    Isolate.run(() => _encodeShot(shot, outW, outH));

/// PNG screenshot bytes in, single-frame lossy WebP out: decode, resize, strip
/// alpha, encode. This is what runs in a fresh isolate for every frame after the
/// first, so converting a 100-frame clip leaves the send dialog responsive. An
/// empty result means "skip this frame" and the caller keeps looping.
Uint8List _encodeShot(Uint8List shot, int outW, int outH) {
  final decoded = img.decodeImage(shot);
  if (decoded == null) return Uint8List(0);
  return _encodeStill(decoded, outW, outH);
}

Uint8List _encodeStill(img.Image decoded, int outW, int outH) {
  final frame = _prepareFrame(decoded, outW, outH);
  if (frame == null) return Uint8List(0);
  return img.encodeWebP(
    frame,
    lossless: _webpLossless,
    quality: _webpQuality,
    method: _webpMethod,
  );
}

/// The parts of a single-frame WebP that belong inside an ANMF chunk: the
/// bitstream (`VP8 ` lossy, `VP8L` lossless) plus any `ALPH` plane, in file
/// order, each kept with its own tag, size **and pad byte**. A single-frame file
/// is `RIFF`, a size, `WEBP`, then chunks of tag + 32-bit LE size + payload + a
/// pad byte when the payload length is odd (`webp/webp_container.dart:16-31`).
///
/// The pad byte has to come along, and dropping it was a real defect (found
/// 2026-10-30, `scratch/gifq/`): an ANMF payload is itself a chunk stream, so
/// its sub-chunks follow the same even-padding rule. Copying only
/// `8 + size` bytes left every frame whose bitstream had an ODD length one byte
/// short of what the ANMF size field announces, and Google's own tools then
/// could not open the file at all - `webpmux -info` printed `Failed to create
/// mux object from file ...` for all 26 frames of a 1 s test clip, 12 of them
/// odd-length. Adding the pad byte inside the ANMF payload made the same file
/// read `Canvas size ... Features present: animation`. Flutter's Skia codec
/// never minded the missing pad, so this bug was invisible to the phone and
/// fatal to every other client - the opposite half of the T123.1 lesson, and
/// the reason `webpmux -info` is now part of this task's gate.
List<Uint8List> _webpFrameChunks(Uint8List still) {
  final out = <Uint8List>[];
  var i = 12;
  while (i + 8 <= still.length) {
    final tag = String.fromCharCodes(Uint8List.sublistView(still, i, i + 4));
    final size =
        still[i + 4] |
        (still[i + 5] << 8) |
        (still[i + 6] << 16) |
        (still[i + 7] << 24);
    if (tag == 'VP8 ' || tag == 'VP8L' || tag == 'ALPH') {
      // Through the pad byte, not up to it: the ANMF payload is a chunk stream
      // and its sub-chunks must be even-padded like any other WebP chunk.
      out.add(
        Uint8List.sublistView(still, i, i + 8 + size + (size.isOdd ? 1 : 0)),
      );
    }
    i += 8 + size + (size.isOdd ? 1 : 0);
  }
  return out;
}

/// One ANMF chunk payload, byte-for-byte the layout `package:image` writes and
/// webpmux plus Flutter already accept (`webp/webp_container.dart:93-117`):
/// x>>1, y>>1, width-1, height-1 and the duration in ms, each 24-bit LE, then one
/// flags byte, then the frame's own chunks. Flags 3 = dispose to the background
/// and do not blend, which is what a whole-canvas frame wants.
Uint8List _anmfPayload(
  int width,
  int height,
  int durationMs,
  List<Uint8List> frameChunks,
) {
  final b = BytesBuilder(copy: true);
  void u24(int v) {
    b.addByte(v & 0xff);
    b.addByte((v >> 8) & 0xff);
    b.addByte((v >> 16) & 0xff);
  }

  u24(0);
  u24(0);
  u24(width - 1);
  u24(height - 1);
  u24(durationMs.clamp(0, 0xffffff));
  b.addByte(3);
  for (final c in frameChunks) {
    b.add(c);
  }
  return b.takeBytes();
}

/// VP8X + ANIM + one ANMF per frame, wrapped in RIFF.
///
/// VP8X `flags` is **0x02 - animation only, the alpha bit stays clear** - and
/// that is a correctness fix, not a size tweak. The alpha bit (0x10) promises
/// the file carries an `ALPH` plane somewhere; every frame this writer emits is
/// alpha-free (T123.1 - Flutter cannot animate a WebP that has an ALPH frame),
/// so setting it describes a plane that does not exist, and Google's own
/// tooling rejects such a file: `webpmux -info` printed `Failed to create mux
/// object from file ...` on this writer's 151-frame output while the SAME
/// frames through `package:image`'s own encoder opened fine (measured
/// 2026-10-30, `scratch/gifq/`). `webp_container.dart:34-45` computes that byte
/// from `hasAlphaChunk || _hasTransparency(image)` plus the animation bit,
/// which is how the reference encoder lands on 0x02 for alpha-free frames.
/// Flutter's Skia codec tolerated the wrong flag and walked all 151 frames, but
/// Element, Chrome and every other client may not, and the whole point of this
/// route is that other clients play these clips.
///
/// Canvas background 0 (transparent) and loop count 0 (forever), as
/// `animChunkData` writes it (`webp_container.dart:74-84`).
Uint8List _riffAnimation(int width, int height, List<Uint8List> anmfPayloads) {
  Uint8List tag(String s) => Uint8List.fromList(s.codeUnits);
  Uint8List le32(int v) => Uint8List.fromList([
    v & 0xff,
    (v >> 8) & 0xff,
    (v >> 16) & 0xff,
    (v >> 24) & 0xff,
  ]);
  Uint8List chunk(String name, Uint8List data) {
    final b = BytesBuilder(copy: true)
      ..add(tag(name))
      ..add(le32(data.length))
      ..add(data);
    if (data.length.isOdd) b.addByte(0); // pad, not counted in the size field
    return b.takeBytes();
  }

  final vp8x = BytesBuilder(copy: true)
    ..addByte(0x02) // hasAnimation, and deliberately NOT hasAlpha (see above)
    ..add([0, 0, 0]); // reserved
  void u24(int v) {
    vp8x.addByte(v & 0xff);
    vp8x.addByte((v >> 8) & 0xff);
    vp8x.addByte((v >> 16) & 0xff);
  }

  u24(width - 1);
  u24(height - 1);

  final body = BytesBuilder(copy: false)
    ..add(tag('WEBP'))
    ..add(chunk('VP8X', vp8x.takeBytes()))
    // background colour (BGRA) then the loop count: all zero, so a transparent
    // canvas and unlimited looping (`animChunkData`, webp_container.dart:74-84)
    ..add(chunk('ANIM', Uint8List(6)));
  for (final p in anmfPayloads) {
    body.add(chunk('ANMF', p));
  }
  // `bytes` already carries the 'WEBP' tag, and the RIFF size field counts
  // exactly what follows it - 'WEBP' plus the chunks (`buildRiff`,
  // webp_container.dart:112-119 sums 4 + the chunk sizes). Adding 4 again makes
  // a file Skia still walks but webpmux refuses (`Failed to create mux object`).
  final bytes = body.takeBytes();
  return (BytesBuilder(copy: false)
        ..add(tag('RIFF'))
        ..add(le32(bytes.length))
        ..add(bytes))
      .takeBytes();
}

/// The output size for a source of [w] x [h]: the source, never enlarged, and
/// scaled only when its longer side passes [maxSide] - Telegram's own animated
/// document gate of 1280 px (`MessageObject.java:6916-6926`). The memory cap that
/// used to shrink clips further is gone: the encode streams frame by frame, so
/// the only ceiling left is the file the group has to download.
(int, int)? _planOutput(int w, int h, int maxSide) {
  var outW = w;
  var outH = h;
  final long = math.max(outW, outH);
  if (long > maxSide) {
    final f = maxSide / long;
    outW = (outW * f).round();
    outH = (outH * f).round();
    _log('[Mp4Gif] source $w x $h -> $outW x $outH, over the $maxSide px gate');
  } else {
    _log('[Mp4Gif] source $w x $h kept');
  }
  return (outW, outH);
}

/// Waits (bounded) for mpv's `position` to reach [at] after a seek, so the next
/// screenshot carries the frame at that time instead of the previous one.
Future<void> _awaitSeek(Player player, Duration at) async {
  final deadline = DateTime.now().add(_seekSettleTimeout);
  while (player.state.position < at && DateTime.now().isBefore(deadline)) {
    await Future.delayed(const Duration(milliseconds: 20));
  }
}

/// Resizes one decoded screenshot to the planned size and strips the alpha
/// plane. No resize at all when the frame is already that size.
///
/// The filter is `Interpolation.average`, and that is the finding behind this
/// whole change: `copyResize` defaults to `Interpolation.nearest`
/// (`image-4.12.0/lib/src/transform/copy_resize.dart:24`), so build 87 dropped 8
/// of every 9 pixels with no filter when it shrank a clip. Measured on 8 real
/// frames of a 1280x720 clip against a filtered reference (`the measurement log`
/// T131): nearest 25.61 dB and an aliasing energy of 11.20 against the
/// reference's 7.95, linear 29.63, cubic 29.15, average **36.64 dB / 8.76** -
/// and 18 % SMALLER once WebP-encoded, because it stops inventing high-frequency
/// noise for the codec to spend bits on. `average` costs 3.45 ms per frame at
/// this scale against nearest's 0.80 ms, which the seek loop already dwarves.
///
/// `convert(numChannels: 3)` is mandatory, not a size tweak (T123.1, ROADMAP
/// Decisions): Flutter cannot animate an animated WebP whose frames carry an
/// `ALPH` sub-chunk - the engine stops at the first alpha frame with
/// `Could not getPixels for frame N`. Flattening a video frame is always safe:
/// a decoded video has no transparency to lose.
img.Image? _prepareFrame(img.Image decoded, int outW, int outH) {
  var frame = decoded;
  if (decoded.width != outW || decoded.height != outH) {
    frame = img.copyResize(
      decoded,
      width: outW,
      height: outH,
      interpolation: img.Interpolation.average,
    );
  }
  return frame.convert(numChannels: 3);
}

/// `report_2026-01-01.mp4` -> `report_2026-01-01`.
String _nameStem(String path) {
  final slash = path.lastIndexOf('/');
  final base = slash >= 0 ? path.substring(slash + 1) : path;
  final dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}
