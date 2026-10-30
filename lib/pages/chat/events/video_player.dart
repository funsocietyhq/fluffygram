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
import 'dart:io';
import 'dart:math';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/attachments/telegram_media_cache.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/media_viewer_hero.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/streaming/telegram_attachment_stream_client.dart';
import 'package:fluffychat/utils/telegram_gif.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/blur_hash.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../../image_viewer/image_viewer.dart';

class EventVideoPlayer extends StatelessWidget {
  final Event event;
  final Timeline? timeline;
  final Color? textColor;
  final Color? linkColor;

  /// The corners of the bubble this video sits in. `MessageContent` passes the
  /// same set it passes `ImageBubble`, so the media carries the bubble's shape
  /// instead of inventing its own (T135).
  final BorderRadius? borderRadius;

  const EventVideoPlayer(
    this.event, {
    this.timeline,
    this.textColor,
    this.linkColor,
    this.borderRadius,
    super.key,
  });

  static const String fallbackBlurHash = 'L5H2EC=PM+yV0g-mq.wG9c010J}I';

  @override
  Widget build(BuildContext context) {
    final supportsVideoPlayer = PlatformInfos.supportsVideoPlayer;
    final theme = Theme.of(context);

    final blurHash =
        (event.infoMap as Map<String, dynamic>).tryGet<String>(
          'xyz.amorgan.blurhash',
        ) ??
        fallbackBlurHash;
    final fileDescription = event.fileDescription;
    const maxDimension = 300.0;
    final infoMap = event.content.tryGetMap<String, Object?>('info');
    final videoWidth = infoMap?.tryGet<int>('w') ?? maxDimension;
    final videoHeight = infoMap?.tryGet<int>('h') ?? maxDimension;

    final modifier = max(videoWidth, videoHeight) / maxDimension;
    final width = videoWidth / modifier;
    final height = videoHeight / modifier;

    final durationInt = infoMap?.tryGet<int>('duration');
    final duration = durationInt == null
        ? null
        : Duration(milliseconds: durationInt);

    // T131 : a Convert to gif clip is an mp4 that this fork
    // marked as a GIF, and Telegram plays those inline, muted and looping -
    // no play circle, no time badge (`MessageObject.java:6984-7003` is the
    // classification; `VideoPlayer.java:1636` `setLooping` is the loop).
    final isGif = telegramEventIsMp4Gif(event);

    // T135 (user, 2026-10-30: "Corners are missing the border for some
    // reason"): a media row is drawn by `ImageBubble` with the bubble's own
    // corner set and a 1 dp outline in `theme.dividerColor`
    // (`image_bubble.dart:70-80`). This row used a uniform
    // `AppConfig.borderRadius` and no outline, so a GIF bubble lost the line
    // the picture bubbles keep, and its outer bottom corner was round where the
    // bubble is tight (`TelegramBubbleGeometry.tailSideCornerRadius`, 3 dp).
    var mediaRadius =
        borderRadius ?? BorderRadius.circular(AppConfig.borderRadius);
    if (fileDescription != null) {
      // A caption hangs under the media, so the media's bottom corners go flat -
      // the same rule `ImageBubble` applies.
      mediaRadius = mediaRadius.copyWith(
        bottomLeft: Radius.zero,
        bottomRight: Radius.zero,
      );
    }

    return Column(
      mainAxisSize: .min,
      spacing: 8,
      children: [
        Material(
          color: Colors.black,
          clipBehavior: Clip.hardEdge,
          shape: RoundedRectangleBorder(
            borderRadius: mediaRadius,
            side: BorderSide(color: theme.dividerColor),
          ),
          child: InkWell(
            onTap: () => supportsVideoPlayer
                ? Navigator.of(
                    // T91: the root Navigator, so the router's delegate can pop
                    // the viewer - the full reason is at message_content.dart.
                    context,
                    rootNavigator: true,
                  ).push(
                    FadeThroughBlackPageRoute(
                      builder: (_) => ImageViewer(
                        event,
                        timeline: timeline,
                        outerContext: context,
                      ),
                    ),
                  )
                : event.saveFile(context),
            borderRadius: mediaRadius,
            child: SizedBox(
              width: width,
              height: height,
              child: telegramHero(
                tag: event.eventId,
                child: Stack(
                  children: [
                    if (event.hasThumbnail &&
                        AppSettings.showThumbnailsInTimeline.value)
                      MxcImage(
                        event: event,
                        cacheKey: event.transactionId ?? event.eventId,
                        cacheName: event.room.id,
                        isThumbnail: true,
                        width: width,
                        height: height,
                        fit: BoxFit.cover,
                        placeholder: (context) => BlurHash(
                          blurhash: blurHash,
                          width: width,
                          height: height,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      BlurHash(
                        blurhash: blurHash,
                        width: width,
                        height: height,
                        fit: BoxFit.cover,
                      ),
                    if (isGif && supportsVideoPlayer)
                      _GifLoopSurface(
                        event: event,
                        width: width,
                        height: height,
                        borderRadius: mediaRadius,
                      )
                    else
                      Center(
                        child: CircleAvatar(
                          child: supportsVideoPlayer
                              ? const Icon(Icons.play_arrow_outlined)
                              : const Icon(Icons.file_download_outlined),
                        ),
                      ),
                    if (duration != null && !isGif)
                      Positioned(
                        bottom: 8,
                        left: 16,
                        child: Text(
                          '${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: Colors.white,
                            backgroundColor: Colors.black.withAlpha(32),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (fileDescription != null && textColor != null && linkColor != null)
          SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Linkify(
                text: fileDescription,
                textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
                style: TextStyle(
                  color: textColor,
                  fontSize: AppConfig.messageFontSize,
                ),
                options: const LinkifyOptions(humanize: false),
                linkStyle: TextStyle(
                  color: linkColor,
                  fontSize: AppConfig.messageFontSize,
                  decoration: TextDecoration.underline,
                  decorationColor: linkColor,
                ),
                onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
              ),
            ),
          ),
      ],
    );
  }
}

/// The inline loop of a GIF-marked mp4 (T131, user 2026-10-30). Telegram
/// autostarts a GIF in the chat cell - muted, looping, no play circle - and the
/// sound is only in the viewer. The bytes come from the same
/// `TelegramMediaCache` + `TelegramAttachmentDownload` pair the viewer uses, and
/// a row that cannot get them keeps painting exactly what it painted before: the
/// thumbnail with the play circle.
class _GifLoopSurface extends StatefulWidget {
  final Event event;
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const _GifLoopSurface({
    required this.event,
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  @override
  State<_GifLoopSurface> createState() => _GifLoopSurfaceState();
}

class _GifLoopSurfaceState extends State<_GifLoopSurface> {
  VideoPlayerController? _controller;
  TelegramAttachmentDownload? _download;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final playFile = await _playFile();
      if (playFile == null || !mounted) return;
      // `mixWithOthers` is why this row is quiet about audio at all: the Android
      // side calls `exoPlayer.setAudioAttributes(attrs, /* handleAudioFocus = */
      // !mixWithOthers)` (video_player_android `VideoPlayer.java:99-102`), so
      // the plugin default of `false` makes ExoPlayer REQUEST audio focus the
      // moment the loop starts. Two user findings from build 88 follow from
      // that one call: the phone's own music player is paused by a bubble that
      // plays no sound (`setVolume(0)` does not stop the focus request), and a
      // second loop on screen takes the focus the first holds, which pauses the
      // first - the reason two GIF bubbles did not both play.
      final controller = VideoPlayerController.file(
        playFile,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      // Muted and looping, like Telegram's cell
      // (`ui/Components/VideoPlayer.java:1636` `setLooping`). A clip marked as a
      // GIF is a GIF, and a GIF has no sound in this app: the volume stays at 0
      // whatever the container carries, so an mp4 with an audio track sent as a
      // GIF cannot make noise on this device .
      await controller.setVolume(0);
      await controller.setLooping(true);
      unawaited(controller.play());
      setState(() => _controller = controller);
      debugPrint('[Mp4Gif] loop started ${playFile.path}');
    } on TelegramAttachmentDownloadCancelled {
      // The row scrolled away or the send was redacted mid-fetch.
    } catch (e, s) {
      // T134 : this
      // line is what names the cause on the phone - `adb logcat -s flutter
      // | grep Mp4Gif`. Without it a row that stayed a poster said nothing.
      if (mounted) Logs().w('[Mp4Gif] loop failed: $_step', e, s);
    }
  }

  /// Last step reached, for the failure line above.
  String _step = 'open';

  /// Cache first, whole file second - the viewer's own order (T84), kept simple
  /// on purpose: a GIF clip is short, so this row never asks for byte ranges.
  Future<File?> _playFile() async {
    _step = 'cache';
    final cached = await TelegramMediaCache.cached(widget.event);
    if (cached != null) return cached;
    if (widget.event.attachmentMxcUrl == null) {
      // Still uploading (the placeholder event has no url yet), or a shape this
      // fork cannot fetch. The poster stays and the tap still opens the viewer.
      return null;
    }
    _step = 'download';
    final download = await TelegramAttachmentDownload.open(widget.event);
    if (download == null) return null;
    _download = download;
    final tempDir = await getTemporaryDirectory();
    // T134: named by **event**, not by media id. Two bubbles of the same clip
    // (`m.video` with the same bytes, sent twice) share one media id, so an
    // mxc-named scratch file was one file written by two rows at once, and the
    // first row's `adopt()` renamed it out from under the second - the second
    // row then had no bytes to play and said nothing about it.
    final name = Uri.encodeComponent(widget.event.eventId);
    final landed = await download.run(File('${tempDir.path}/${name}_gif'));
    _download = null;
    // The cache takes the bytes and hands back the path to play, so the next
    // build of this row - you scroll back - starts from disk with no request.
    _step = 'adopt';
    final kept = await TelegramMediaCache.adopt(
      file: landed,
      event: widget.event,
    );
    if (kept != null) return kept;
    // The scratch file is gone (the cache moved it, or another row of the same
    // media took it): fall back to whatever the cache holds for this event.
    if (await landed.exists()) return landed;
    _step = 'cache after adopt';
    return await TelegramMediaCache.cached(widget.event);
  }

  @override
  void dispose() {
    // A row that goes away under a fetch stops pulling bytes (viewer rule,
    // T53.1), and its player goes with it.
    _download?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: widget.height,
    child: _controller == null
        ? null
        : ClipRRect(
            borderRadius: widget.borderRadius,
            child: VideoPlayer(_controller!),
          ),
  );
}
