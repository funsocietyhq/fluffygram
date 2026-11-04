// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/telegram_palette.dart';
import 'package:fluffychat/pages/chat/events/bubble_shape.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/media_viewer_hero.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../../widgets/blur_hash.dart';

class ImageBubble extends StatelessWidget {
  final Event event;
  final bool tapToView;
  final BoxFit fit;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? linkColor;
  final bool thumbnailOnly;
  final bool animated;
  final double width;
  final double height;
  final void Function()? onTap;
  final BorderRadius? borderRadius;
  final Timeline? timeline;

  const ImageBubble(
    this.event, {
    this.tapToView = true,
    this.backgroundColor,
    this.fit = BoxFit.contain,
    this.thumbnailOnly = true,
    this.width = 400,
    this.height = 300,
    this.animated = false,
    this.onTap,
    this.borderRadius,
    this.timeline,
    this.textColor,
    this.linkColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var borderRadius =
        this.borderRadius ?? BorderRadius.circular(AppConfig.borderRadius);

    final fileDescription = event.fileDescription;
    final textColor = this.textColor;

    if (fileDescription != null) {
      borderRadius = borderRadius.copyWith(
        bottomLeft: Radius.zero,
        bottomRight: Radius.zero,
      );
    }

    return Column(
      mainAxisSize: .min,
      spacing: 8,
      children: [
        // T165 (user, 2026-11-05: "now gifs and images have no chat bubble
        // border? that's wrong too") puts the outline back and narrows T162.
        // Telegram DOES outline a media bubble: measured on
        // `the reference capture` at 2.75 px/dp, the GIF's left edge
        // runs black to x 128, `#4c5268` at x 129..132, media from x 133; the
        // right edge runs media to x 1044, `#4c5268` at x 1045..1049, black from
        // x 1050 - a 4-5 px = 1.5 dp line. T162's "no stroke" reading came from
        // a luminance probe across the TOP edge, which sees only the
        // anti-aliasing ramp of a dark picture. What T162 correctly killed was
        // the DOUBLE line: upstream stroked the media box while the bubble box
        // was larger. Since T163 the two boxes are one, so this stroke is the
        // bubble's only outline.
        Material(
          color: Colors.transparent,
          clipBehavior: Clip.hardEdge,
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: BorderSide(
              color: Theme.of(context).brightness == Brightness.dark
                  ? TelegramPalette.mediaBubbleBorder
                  : Theme.of(context).dividerColor,
              width: TelegramBubbleGeometry.mediaBorderWidth,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: borderRadius,
            child: Stack(
              alignment: Alignment.center,
              children: [
                telegramBubbleHero(
                  eventId: event.eventId,
                  child: AppSettings.showThumbnailsInTimeline.value
                      ? MxcImage(
                          cacheKey: event.transactionId ?? event.eventId,
                          cacheName: event.room.id,
                          event: event,
                          width: width,
                          height: height,
                          fit: fit,
                          animated: animated,
                          isThumbnail: thumbnailOnly,
                          placeholder: event.messageType == MessageTypes.Sticker
                              ? null
                              : (_) => _ImageBubblePlaceholder(
                                  event: event,
                                  width: width,
                                  height: height,
                                  fit: fit,
                                ),
                        )
                      : _ImageBubblePlaceholder(
                          event: event,
                          width: width,
                          height: height,
                          fit: fit,
                        ),
                ),
              ],
            ),
          ),
        ),
        if (fileDescription != null && textColor != null)
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

class _ImageBubblePlaceholder extends StatelessWidget {
  final Event event;
  final double width, height;
  final BoxFit fit;

  const _ImageBubblePlaceholder({
    required this.event,
    required this.width,
    required this.height,
    required this.fit,
  });

  @override
  Widget build(BuildContext context) {
    final blurHashString =
        event.infoMap.tryGet<String>('xyz.amorgan.blurhash') ??
        'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
    return SizedBox(
      width: width,
      height: height,
      child: BlurHash(
        blurhash: blurHashString,
        width: width,
        height: height,
        fit: fit,
      ),
    );
  }
}
