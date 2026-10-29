// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:fluffychat/pages/image_viewer/telegram_progress_ring.dart';
import 'package:fluffychat/pages/image_viewer/telegram_video_controls.dart';
import 'package:fluffychat/utils/attachments/telegram_media_cache.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
// The whole-file download this page owns (T53.1 half 2). The stream session the
// same file exports is unreferenced since a user decision of 2026-10-29.
import 'package:fluffychat/utils/streaming/telegram_attachment_stream_client.dart';
import 'package:fluffychat/utils/telegram_gif.dart';
import 'package:fluffychat/widgets/blur_hash.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../utils/error_reporter.dart';
import '../../widgets/mxc_image.dart';

class EventVideoPlayer extends StatefulWidget {
  final Event event;

  /// This player's page in the viewer, so it can tell "am I the page in
  /// view" from the page the viewer shows (`image_viewer_view.dart`'s page
  /// builder passes its own `index`).
  final int index;

  /// The viewer's current page, read live on every page change. An
  /// `int Function()` beats an `int` field: the value must be current at
  /// the moment the page changes, and a rebuild of this (neighbour) page is
  /// not guaranteed (`ImageViewerController.currentIndex`).
  final int Function() currentIndex;

  /// The viewer's page controller - the notification a page change already
  /// sends. `ExtendedImageGesturePageView` scrolls it while the user swipes
  /// and while the page settles, and `ImageViewerController.onPageChanged`
  /// (the callback the page view itself calls) flips what [currentIndex]
  /// reads.
  final Listenable pageController;

  const EventVideoPlayer(
    this.event, {
    required this.index,
    required this.currentIndex,
    required this.pageController,
    super.key,
  });

  @override
  EventVideoPlayerState createState() => EventVideoPlayerState();
}

class EventVideoPlayerState extends State<EventVideoPlayer> {
  ChewieController? _chewieController;
  VideoPlayerController? _videoPlayerController;

  // The streaming path (ROADMAP T55-T79: decrypt as it downloads, serve the
  // plaintext on loopback, let the player start before the last byte) is off
  // the video path since a user's decision of 2026-10-29: a group video is
  // downloaded whole and played from the file, Element X's model. The classes
  // stay in `lib/utils/streaming/`, unreferenced. The reason is the seek side
  // of the old path - T75 (a swipe-to-seek crash) and T79 (media3 refuses a
  // 13.4 s forward seek over HTTP) - neither of which a local file has.

  /// The text last logged out of the player's own error field, so one failure
  /// writes one line. `VideoPlayerValue.hasError` was read by nobody in this
  /// widget, so a video that died mid-playback - a user's a build report,
  /// "it started playing but the player crashed with some error" - left no
  /// trace in any logcat the fork could read (the measurement log).
  Timer? _playerErrorWatch;
  String? _watchedPlayerError;

  /// T103: whether the player has proved that a decoded frame is on screen.
  /// Until it has, the poster stays painted over the played stage - that
  /// surface is black until Android delivers frame 1 (see `_watchPlayerErrors`
  /// and `build`). Cleared with the player, so a replay starts covered again.
  bool _firstFramePainted = false;

  double? _downloadProgress;

  /// The whole-file fetch this State owns (T53.1 half 2): closing the viewer
  /// under a still-loading video cancels it in `dispose`. Null on web, on
  /// shapes the fork path cannot serve, and once `run` handed its file over.
  TelegramAttachmentDownload? _download;

  // The video_player package only doesn't support Windows and Linux.
  final _supportsVideoPlayer =
      !PlatformInfos.isWindows && !PlatformInfos.isLinux;

  /// T63.2: Telegram plays a viewer video at the panel's high refresh rate
  /// (`RefreshRateController.java:227` picks the mode with the highest
  /// `getRefreshRate()` out of `Display.getSupportedModes()`), so the motion
  /// in our viewer looks stiff next to it while the panel idles at 60 Hz
  /// (user finding, Pixel, build 45). The request is per-window
  /// (`WindowManager.LayoutParams.preferredDisplayModeId`), so this page asks
  /// on open and releases on close. Android only, and
  /// `MissingPluginException` is swallowed: web, desktop and `flutter test`
  /// answer with no channel.
  static const MethodChannel _displayChannel = MethodChannel(
    'app.fluffygram/display',
  );

  Future<void> _askDisplay(String method) async {
    if (!PlatformInfos.isAndroid) return;
    try {
      await _displayChannel.invokeMethod<void>(method);
    } on MissingPluginException {
      // No channel on this platform: the panel keeps its default rate.
    }
  }

  Future<void> _downloadAction() async {
    if (!_supportsVideoPlayer) {
      widget.event.saveFile(context);
      return;
    }

    try {
      // One whole-file fetch, then play from the file (user decision
      // 2026-10-29). One request per video, and the server's own rate limit is
      // the only throttle: the 12-back-to-back-ranged-GET burst the streaming
      // path could produce is gone (the measurement log, the media API
      // range budget).

      final fileSize = widget.event.content
          .tryGetMap<String, Object?>('info')
          ?.tryGet<int>('size');

      // The whole-file fetch is cancellable (T53.1 half 2): `dispose`
      // cancels the download this branch starts, so a viewer closed under a
      // still-loading video stops pulling bytes - Telegram cancels the load
      // with the screen. The fork path (`TelegramAttachmentDownload`)
      // serves the shapes the SDK call served; the SDK call itself stays
      // where the fork path cannot (web: no temp file) and keeps its old
      // behaviour.
      late VideoPlayerController videoPlayerController;
      if (kIsWeb) {
        final videoFile = await widget.event.downloadAndDecryptAttachment(
          onDownloadProgress: fileSize == null
              ? null
              : (progress) => _setDownloadProgress(progress / fileSize),
        );

        // The viewer can be gone before the download ends. An unmounted
        // State may not start a player - nothing would ever dispose it, and
        // its audio keeps playing over the chat (user report 2026-10-27:
        // swiping away while a video loaded left it running, ROADMAP T53).
        if (!mounted) return;
        videoPlayerController = VideoPlayerController.networkUrl(
          Uri.dataFromBytes(videoFile.bytes, mimeType: videoFile.mimeType),
        );
      } else {
        // T84: one download per attachment. An entry in the app's media cache
        // whose length equals the plaintext size the event declares plays at
        // once - no request, no progress ring (the Element X replay a user
        // asked for on 2026-10-29: "can't we cache videos up to a certain size
        // locally", caps 250 MB per file and 1 GB in total).
        final cached = await TelegramMediaCache.cached(widget.event);
        if (!mounted) return;
        var playFile = cached;
        final tempDir = await getTemporaryDirectory();
        final fileNameStr =
            widget.event.attachmentMxcUrl?.pathSegments.last ??
            widget.event.body;
        final fileName = Uri.encodeComponent(fileNameStr);
        final download = playFile == null
            ? await TelegramAttachmentDownload.open(widget.event)
            : null;
        if (playFile == null && download == null) {
          // No fork path for this shape (no usable key, no download uri, no
          // access token): the SDK call exactly as before - uncancellable,
          // exactly as before.
          final videoFile = await widget.event.downloadAndDecryptAttachment(
            onDownloadProgress: fileSize == null
                ? null
                : (progress) => _setDownloadProgress(progress / fileSize),
          );
          if (!mounted) return;
          final file = File('${tempDir.path}/${fileName}_${videoFile.name}');
          if (await file.exists() == false) {
            await file.writeAsBytes(videoFile.bytes);
          }
          playFile =
              await TelegramMediaCache.adopt(file: file, event: widget.event) ??
              file;
        } else if (playFile == null && download != null) {
          _download = download;
          if (!mounted) {
            // `dispose` ran while `open` derived the uri: kill the download
            // before it asks for its first byte.
            download.cancel();
            return;
          }
          final file = File('${tempDir.path}/${fileName}_${widget.event.body}');
          final landed = await download.run(
            file,
            onProgress: (received, total) =>
                _setDownloadProgress(received / total),
          );
          // A `dispose` under the fetch cancels it inside `run`, deletes the
          // temp file and reports the cancel, which this dead State
          // swallows silently below.
          if (!mounted) return;
          _download = null;
          // The cache takes the file the download wrote and hands back the
          // path to play - the same bytes, under `matrix-media/`, with the
          // `mxc` id and plaintext size as their name. A clip over the
          // per-file cap is not kept and plays from the temp path.
          playFile =
              await TelegramMediaCache.adopt(
                file: landed,
                event: widget.event,
              ) ??
              landed;
        }
        // A clip this fork marks as a GIF (`org.fluffygram.gif`) is silent
        // everywhere, not only in the timeline row, and it never asks the phone
        // for audio focus: `mixWithOthers: true` is what stops ExoPlayer from
        // taking focus and pausing whatever a user was already listening to
        // (video_player_android `VideoPlayer.java:99-102` passes
        // `handleAudioFocus = !mixWithOthers`). An ordinary video keeps the
        // plugin default, so its sound still behaves normally in the viewer.
        // The option is held in one shared object by the Android plugin
        // (`VideoPlayerPlugin.java:190-192` sets `sharedOptions`), so this call
        // states it explicitly for both cases instead of inheriting what the
        // last timeline loop left there.
        videoPlayerController = VideoPlayerController.file(
          playFile!,
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: telegramEventIsMp4Gif(widget.event),
          ),
        );
      }

      // Dispose the controllers if we already have them.
      _disposeControllers();
      _videoPlayerController = videoPlayerController;

      await videoPlayerController.initialize();
      if (!mounted) {
        _videoPlayerController?.dispose();
        _videoPlayerController = null;
        return;
      }
      // T138: a marked GIF clip carries no sound into the viewer. An mp4 sent
      // as a GIF can hold an audio track (the container allows it); the fork
      // treats it as a GIF, so the track stays in the file and never reaches
      // the speaker .
      if (telegramEventIsMp4Gif(widget.event)) {
        await videoPlayerController.setVolume(0);
      }
      _watchPlayerErrors(videoPlayerController);

      // Create a ChewieController on top.
      setState(() {
        _chewieController = ChewieController(
          videoPlayerController: videoPlayerController,
          // Telegram draws its own chrome, and T80 mounts it in this page's own
          // box: Chewie draws no chrome (its `player_with_controls.dart:106-124`
          // layout is what put the band off the picture) and no dim layer.
          customControls: const SizedBox.shrink(),
          showControlsOnInitialize: false,
          // Telegram plays only the page in view (`the measurement log`,
          // T53): a cached neighbour page must not start sound when its own
          // download lands.
          autoPlay: widget.currentIndex() == widget.index,
          autoInitialize: true,
          looping: true,
          aspectRatio: _videoPlayerController?.value.aspectRatio,
        );
      });
    } on TelegramAttachmentDownloadCancelled {
      // The viewer closed under the whole-file fetch (`dispose` cancelled
      // it): the temp file is already deleted, no half file reached a
      // player, and a dead State has nothing to show - one line, no banner.
      debugPrint('[TelegramStream] whole-file download cancelled');
      return;
    } on MatrixException catch (e) {
      // A `429 M_LIMIT_EXCEEDED` ("Rate Limited") is a server answer, not a
      // bug: build 41 fell through to the generic catch below and filed a
      // crash report over a video that had been playing, for a homeserver
      // saying "slow down" (a user's logcat, 2026-10-28).
      // `toLocalizedString` maps M_LIMIT_EXCEEDED to its own sentence.
      developer.log(
        'download-refused ${e.errcode} retryAfterMs=${e.retryAfterMs}',
        name: 'fg_media',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    } on IOException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    } catch (e, s) {
      if (!mounted) return;
      ErrorReporter(context, 'Unable to play video').onErrorCallback(e, s);
    }
  }

  /// The spinner fraction of the whole-file path (T53): the SDK call and
  /// the fork download report the same number, and a dead State stays dead
  /// - no `setState` after `dispose`.
  void _setDownloadProgress(double progressPercentage) {
    if (!mounted) return;
    setState(() {
      _downloadProgress = progressPercentage < 1 ? progressPercentage : null;
    });
  }

  /// Logs what the player says about itself when playback dies. The
  /// `video_player` package reports a mid-playback failure by setting
  /// `value.hasError` and an `errorDescription`, and nothing here read them:
  /// the state went to `error` with no text in any capture, on every path.
  void _watchPlayerErrors(VideoPlayerController controller) {
    // T80: every player start in this State runs through here, and the `Chewie`
    // widget that used to keep the screen awake is no longer mounted (it took
    // the lock inside its own fullscreen route, `chewie_player.dart:267,296`).
    // The page holds it for as long as a player lives here; `dispose` drops it.
    unawaited(WakelockPlus.enable());
    _playerErrorWatch?.cancel();
    _playerErrorWatch = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final value = controller.value;
      // T103: this watch doubles as the first-frame detector. `video_player
      // 2.14.1` exposes no first-frame flag (a grep of its lib/ for
      // `firstFrameAvailable` is empty), and its `VideoPlayer` builds a bare
      // `Container()` until `playerId` lands, then the Android surface, which
      // paints black until frame 1 is decoded (`lib/video_player.dart:1208-
      // 1216`). A position that has advanced is the cheapest proof that a frame
      // is on screen, and 250 ms of poster is invisible next to a black flash.
      if (!_firstFramePainted && value.position > Duration.zero) {
        if (!mounted) return;
        setState(() => _firstFramePainted = true);
      }
      if (!value.hasError) return;
      final message = value.errorDescription ?? 'unknown';
      if (message == _watchedPlayerError) return;
      _watchedPlayerError = message;
      developer.log('player-error msg=$message', name: 'fg_media');
    });
  }

  void _disposeControllers() {
    _playerErrorWatch?.cancel();
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    _chewieController = null;
    _videoPlayerController = null;
    _firstFramePainted = false;
  }

  /// Telegram plays a video only while its cell is the visible one:
  /// "Telegram pauses a video whose cell is not the visible one
  /// (`PhotoViewCell` / `VideoFileWrapper` detach rules)" -
  /// `the measurement log`, T53 section. `ExtendedImageGesturePageView
  /// .builder` keeps this page's neighbours mounted in the viewport cache,
  /// so a player here pauses itself whenever the viewer shows another page.
  /// Pause only, never dispose (Telegram resumes the cell when you swipe
  /// back); and never resume on becoming current again - a video the user
  /// paused stays paused.
  void _pauseIfNotCurrentPage() {
    if (widget.currentIndex() == widget.index) return;
    final controller = _videoPlayerController;
    if (controller != null && controller.value.isPlaying) {
      controller.pause();
    }
  }

  @override
  void dispose() {
    widget.pageController.removeListener(_pauseIfNotCurrentPage);
    _disposeControllers();
    // T53.1 half 2: the whole-file fetch nobody will watch anymore stops
    // here - Telegram cancels the load with the screen. `cancel` closes the
    // download's own client, so the in-flight body read dies, and `run`
    // deletes the half-written temp file before it reports the cancel,
    // which the dead State swallows silently.
    _download?.cancel();
    _download = null;
    unawaited(WakelockPlus.disable());
    unawaited(_askDisplay('reset'));
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // The page change arrives as a scroll notification on the viewer's page
    // controller. The listener reads the getter, so the pause lands the
    // moment the page in view changes even when this neighbour page is
    // never rebuilt (`onPageChanged` -> `setState` -> `didUpdateWidget`
    // below is the second, rebuild-driven path).
    widget.pageController.addListener(_pauseIfNotCurrentPage);
    unawaited(_askDisplay('high'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _downloadAction();
    });
  }

  @override
  void didUpdateWidget(EventVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pauseIfNotCurrentPage();
  }

  static const String fallbackBlurHash = 'L5H2EC=PM+yV0g-mq.wG9c010J}I';

  @override
  Widget build(BuildContext context) {
    final hasThumbnail = widget.event.hasThumbnail;
    final blurHash =
        (widget.event.infoMap as Map<String, dynamic>).tryGet<String>(
          'xyz.amorgan.blurhash',
        ) ??
        fallbackBlurHash;
    final infoMap = widget.event.content.tryGetMap<String, Object?>('info');
    final videoWidth = infoMap?.tryGet<int>('w') ?? 400;
    final videoHeight = infoMap?.tryGet<int>('h') ?? 300;

    final chewieController = _chewieController;

    // T80: the page sizes the box, and mounts the picture and the chrome in it.
    // `Chewie` is not mounted any more: `player_with_controls.dart:106-124`
    // wraps its picture AND its `customControls` in
    // `AspectRatio(calculateAspectRatio(context))`, and that helper (:16-23)
    // returns the SCREEN's max/min ratio - 923.4 / 411.4 = 2.245 on a user's
    // Pixel - as a width/height ratio. The box holding the picture and the band
    // therefore came out 403.2 x 179.6 dp in an 871.4 dp page: the picture
    // filled ~40 % of the page height centred, and the 44 dp band sat ~187 dp
    // below its bottom edge, over black (user capture
    // `the reference capture`, crop `a measurement crop`).
    // Chewie keeps the engine: `ChewieController` initializes, autoplays and
    // loops by itself (`chewie_player.dart:476`, `:1129-1141`), and the provider
    // below is what `ChewieController.of` needs.
    final page = MediaQuery.sizeOf(context);
    // The viewer reserves 52 dp at the top: `image_viewer_view.dart:196-206`
    // puts this widget in `Padding(top: 52)` inside a `Center`.
    final pageHeight = page.height - 52;
    final playerAspect =
        chewieController?.videoPlayerController.value.aspectRatio ?? 0;
    final aspect = playerAspect > 0 ? playerAspect : videoWidth / videoHeight;
    // T97: the pre-play picture (the thumbnail, or the BlurHash, with the T83
    // download ring over it) sits in THIS box - not in the old aspect-fill of the
    // page height. The old box was `height = page.height - 52` by
    // `width = videoWidth * height / videoHeight`: for a 1080x1920 phone video on
    // a user's 411.4 x 923.4 dp window that is 490.2 x 871.4 dp, 78.8 dp wider
    // than the screen, and `BoxFit.cover` cut 39.4 dp from each side (16.1 % of the
    // picture; 73.4 % for a 1920x1080 video). The played stage below already used
    // this contain box, so one video was drawn at two rects - a user's "videos
    // ... zoom in" (capture `the reference capture`, build 65, download
    // ring visible = the pre-play stage).
    var boxWidth = page.width;
    var boxHeight = boxWidth / aspect;
    if (boxHeight > pageHeight) {
      boxHeight = pageHeight;
      boxWidth = boxHeight * aspect;
    }

    // T103: ONE still, mounted by both stages. It used to exist only in the
    // `chewieController == null` stage, so the picture a user was looking at
    // disappeared at the exact moment the player's surface went up, and that
    // surface is black until Android decodes frame 1. Two things followed: the
    // black flash, and a dropped `Hero` flight, because the `Hero` left the tree
    // at the swap (`the measurement log`, "T103 - the video open flash").
    // Telegram keeps the still frame under the video until the first decoded
    // frame arrives, so here the poster is the layer the played stage paints
    // over, inside the same box - one rect for picture, poster and player.
    final still = Hero(
      tag: widget.event.eventId,
      child: hasThumbnail
          ? MxcImage(
              event: widget.event,
              isThumbnail: true,
              width: boxWidth,
              height: boxHeight,
              fit: BoxFit.contain,
              placeholder: (context) => BlurHash(
                blurhash: blurHash,
                width: boxWidth,
                height: boxHeight,
              ),
            )
          : BlurHash(blurhash: blurHash, width: boxWidth, height: boxHeight),
    );

    return chewieController != null
        ? Center(
            child: SizedBox(
              width: boxWidth,
              height: boxHeight,
              child: ChewieControllerProvider(
                controller: chewieController,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: VideoPlayer(
                        chewieController.videoPlayerController,
                      ),
                    ),
                    if (!_firstFramePainted) Positioned.fill(child: still),
                    const TelegramVideoControls(),
                  ],
                ),
              ),
            ),
          )
        : Stack(
            children: [
              Center(child: still),
              Center(
                // Telegram puts its own ring over the media while the file is
                // still arriving: 54 dp box, 3 dp white arc (`RadialProgressView.java:71`,
                // `PhotoViewer.java:6140-6143`). T83.
                child: TelegramProgressRing(progress: _downloadProgress),
              ),
            ],
          );
  }
}
