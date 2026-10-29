// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'dart:math';

import 'package:fluffychat/config/recent_gifs.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/poll.dart';
import 'package:fluffychat/pages/chat/events/video_player.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer.dart';
import 'package:fluffychat/utils/media_viewer_hero.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../../config/app_config.dart';
import '../../../utils/event_checkbox_extension.dart';
import '../../../utils/platform_infos.dart';
import '../../../utils/telegram_gif.dart';
import '../../../utils/url_launcher.dart';
import 'album_grid.dart';
import 'audio_player.dart';
import 'bubble_shape.dart';
import 'cute_events.dart';
import 'html_message.dart';
import 'image_bubble.dart';
import 'map_bubble.dart';
import 'message_download_content.dart';

class MessageContent extends StatelessWidget {
  final Event event;
  final Color textColor;
  final Color linkColor;
  final void Function(Event)? onInfoTab;
  final BorderRadius borderRadius;
  final Timeline timeline;
  final bool selected;
  final Set<String> bigEmojis;

  /// Telegram's timestamp + tick glyphs, drawn inline on the last line of the
  /// text inside the bubble (`HtmlMessage.inlineMeta`).
  final Widget? inlineMeta;

  /// The box that meta takes at the end of the text, so the text wraps around
  /// it and it sits in the bubble's bottom-right corner
  /// (`HtmlMessage.inlineMetaReserve`).
  final Size? inlineMetaReserve;

  /// The media run this event anchors, drawn as one Telegram album instead of
  /// this single photo/video (`album_grid.dart`). Null when it draws alone.
  final List<Event>? albumRun;

  /// Long-press on one tile of that album: selection of the tile's own event.
  final void Function(Event)? onAlbumTileLongPress;

  const MessageContent(
    this.event, {
    this.onInfoTab,
    super.key,
    required this.timeline,
    required this.textColor,
    required this.linkColor,
    required this.borderRadius,
    required this.selected,
    required this.bigEmojis,
    this.inlineMeta,
    this.inlineMetaReserve,
    this.albumRun,
    this.onAlbumTileLongPress,
  });

  @override
  Widget build(BuildContext context) {
    const fontSize = AppConfig.messageFontSize;
    final buttonTextColor = textColor;
    switch (event.type) {
      case EventTypes.Message:
      case EventTypes.Encrypted:
      case EventTypes.Sticker:
        // A burst of photos/videos from one sender draws as one album mosaic.
        if (albumRun case final List<Event> run
            when run.length > 1 && run.first.eventId == event.eventId) {
          return telegramMediaInset(
            TelegramAlbumGrid(
              events: run,
              timeline: timeline,
              textColor: textColor,
              linkColor: linkColor,
              onLongPressSelect: onAlbumTileLongPress,
            ),
          );
        }
        switch (event.messageType) {
          case MessageTypes.Image:
          case MessageTypes.Sticker:
            if (event.redacted) continue textmessage;
            final maxSize = event.messageType == MessageTypes.Sticker
                ? 128.0
                : TelegramAlbumGeometry.gridMaxWidthForWindow(
                    MediaQuery.sizeOf(context).width,
                  );
            final w = event.content
                .tryGetMap<String, Object?>('info')
                ?.tryGet<int>('w');
            final h = event.content
                .tryGetMap<String, Object?>('info')
                ?.tryGet<int>('h');
            var width = maxSize;
            var height = maxSize;
            var fit = event.messageType == MessageTypes.Sticker
                ? BoxFit.contain
                : BoxFit.cover;
            if (w != null && h != null) {
              fit = BoxFit.contain;
              if (w > h) {
                width = maxSize;
                height = max(32, maxSize * (h / w));
              } else {
                height = maxSize;
                width = max(32, maxSize * (w / h));
              }
            }
            // A GIF is fetched as the animated original and drawn moving: the
            // Matrix thumbnail of a GIF is a static JPEG, so `thumbnailOnly`
            // must go false for one, and `animated` is the flag that asks the
            // server for the animated file. Telegram loops a GIF in the cell
            // (VideoPlayer.java:1636 `setLooping`).
            final isGif = telegramEventIsGif(event);
            // T113 :
            // this row is where an own GIF send first has its real content -
            // `Room.sendFileEvent()` inserts a placeholder with no url first
            // (`room.dart:868-897`) and the finished event replaces it without
            // a new timeline insert, so the insert hook alone never recorded a
            // GIF sent from this phone. Own sender only: Telegram's tray holds
            // the GIFs *I* sent, not the group's. Idempotent, and the seen-set
            // in the store keeps a rebuilding row from writing twice.
            if (isGif && event.senderId == event.room.client.userID) {
              RecentGifs.recordFromEvent(event);
            }
            final media = ImageBubble(
              event,
              width: width,
              height: height,
              fit: fit,
              animated: isGif,
              thumbnailOnly: !isGif,
              borderRadius: borderRadius,
              timeline: timeline,
              textColor: textColor,
              onTap: () =>
                  Navigator.of(
                    // T91 : the root Navigator, so the viewer
                    // lands on the router's own stack. GoRouter 18.1.1 keeps its
                    // `Navigator` inside a `Builder` whose elements find this
                    // `Navigator` first (go_router-18.1.1/lib/src/router.dart:281,
                    // routing.dart:65-68), so a route pushed here is invisible to
                    // the delegate: `canPop()` reports false (delegate.dart:134-138)
                    // and `Router` answers the Android back button with
                    // `SystemNavigator.pop()` (delegate.dart:82-97) - the app quit
                    // with the photo still on screen. The root Navigator is the one
                    // GoRouter pushes its own pages onto (router.dart:297), and the
                    // viewer's `PopScope` takes the pop from there.
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
                  ),
            );
            // A sticker row keeps Telegram's box-less surface: no container, so
            // no inset strip around it.
            return event.messageType == MessageTypes.Sticker
                ? media
                : telegramMediaInset(media);
          case CuteEventContent.eventType:
            return CuteContent(event);
          case MessageTypes.Audio:
            if (PlatformInfos.isMobile ||
                PlatformInfos.isMacOS ||
                PlatformInfos.isWeb ||
                PlatformInfos.isLinux) {
              return AudioPlayerWidget(
                event,
                color: textColor,
                linkColor: linkColor,
                fontSize: fontSize,
              );
            }
            return MessageDownloadContent(
              event,
              textColor: textColor,
              linkColor: linkColor,
            );
          case MessageTypes.Video:
            return telegramMediaInset(
              EventVideoPlayer(
                event,
                textColor: textColor,
                linkColor: linkColor,
                timeline: timeline,
                // T135: the media carries the bubble's corners, like ImageBubble
                // above - a uniform AppConfig.borderRadius left a round corner
                // where the bubble outline is tight.
                borderRadius: borderRadius,
              ),
            );
          case MessageTypes.File:
            return MessageDownloadContent(
              event,
              textColor: textColor,
              linkColor: linkColor,
            );
          case MessageTypes.Location:
            final geoUri = Uri.tryParse(
              event.content.tryGet<String>('geo_uri')!,
            );
            if (geoUri != null && geoUri.scheme == 'geo') {
              final latlong = geoUri.path
                  .split(';')
                  .first
                  .split(',')
                  .map(double.tryParse)
                  .toList();
              if (latlong.length == 2 &&
                  latlong.first != null &&
                  latlong.last != null) {
                return MapBubble(
                  onTap: () =>
                      UrlLauncher(context, geoUri.toString()).launchUrl(),
                  latitude: latlong.first!,
                  longitude: latlong.last!,
                );
              }
            }
            continue textmessage;
          case MessageTypes.Text:
          case MessageTypes.Notice:
          case MessageTypes.Emote:
          case MessageTypes.None:
          textmessage:
          default:
            if (event.redacted) {
              return RedactionWidget(
                event: event,
                buttonTextColor: buttonTextColor,
                onInfoTab: onInfoTab,
                fontSize: fontSize,
              );
            }
            var html = AppSettings.renderHtml.value && event.isRichMessage
                ? event.formattedText
                : event.body.replaceAll('<', '&lt;').replaceAll('>', '&gt;');
            if (event.messageType == MessageTypes.Emote) {
              html = '* $html';
            }

            final bigEmotes =
                !event.isRichMessage && bigEmojis.contains(event.body);

            return Padding(
              // Telegram bubble inner padding: 12dp x 7dp.
              padding: const EdgeInsets.symmetric(
                horizontal: TelegramBubbleGeometry.paddingH,
                vertical: TelegramBubbleGeometry.paddingV,
              ),
              child: HtmlMessage(
                html: html,
                textColor: textColor,
                room: event.room,
                inlineMeta: inlineMeta,
                inlineMetaReserve: inlineMetaReserve,
                fontSize: AppConfig.messageFontSize * (bigEmotes ? 5 : 1),
                linkStyle: TextStyle(
                  color: linkColor,
                  fontSize: AppConfig.messageFontSize,
                  decoration: TextDecoration.underline,
                  decorationColor: linkColor,
                ),
                onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
                eventId: event.eventId,
                checkboxCheckedEvents: event.aggregatedEvents(
                  timeline,
                  EventCheckboxRoomExtension.relationshipType,
                ),
              ),
            );
        }
      case PollEventContent.startType:
        if (event.redacted) {
          return RedactionWidget(
            event: event,
            buttonTextColor: buttonTextColor,
            onInfoTab: onInfoTab,
            fontSize: fontSize,
          );
        }
        return PollWidget(
          event: event,
          timeline: timeline,
          textColor: textColor,
          linkColor: linkColor,
        );
      case EventTypes.CallInvite:
        return FutureBuilder<User?>(
          future: event.fetchSenderUser(),
          builder: (context, snapshot) {
            return _ButtonContent(
              label: L10n.of(context).startedACall(
                snapshot.data?.calcDisplayname() ??
                    event.senderFromMemoryOrFallback.calcDisplayname(),
              ),
              icon: '📞',
              textColor: buttonTextColor,
              onPressed: () => onInfoTab!(event),
              fontSize: fontSize,
            );
          },
        );
      default:
        return FutureBuilder<User?>(
          future: event.fetchSenderUser(),
          builder: (context, snapshot) {
            return _ButtonContent(
              label: L10n.of(context).userSentUnknownEvent(
                snapshot.data?.calcDisplayname() ??
                    event.senderFromMemoryOrFallback.calcDisplayname(),
                event.type,
              ),
              icon: 'ℹ️',
              textColor: buttonTextColor,
              onPressed: () => onInfoTab!(event),
              fontSize: fontSize,
            );
          },
        );
    }
  }
}

/// The measured strip of container fill between a media container edge and the
/// media inside it (`TelegramAlbumGeometry.containerInset`, 1.5 dp, measured on
/// `a measurement crop`: container x 156-921, first photo pixel
/// column x 160). Used for image and video content only. The tiles, their size
/// and their gaps are untouched, and a sticker row never passes through here.
Widget telegramMediaInset(Widget child) => Padding(
  padding: const EdgeInsets.all(TelegramAlbumGeometry.containerInset),
  child: child,
);

class RedactionWidget extends StatelessWidget {
  const RedactionWidget({
    super.key,
    required this.event,
    required this.buttonTextColor,
    required this.onInfoTab,
    required this.fontSize,
  });

  final Event event;
  final Color buttonTextColor;
  final void Function(Event p1)? onInfoTab;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User?>(
      future: event.redactedBecause?.fetchSenderUser(),
      builder: (context, snapshot) {
        final reason = event.redactedBecause?.content.tryGet<String>('reason');
        final redactedBy =
            snapshot.data?.calcDisplayname() ??
            event.redactedBecause?.senderId.localpart ??
            L10n.of(context).user;
        return _ButtonContent(
          label: reason == null
              ? L10n.of(context).redactedBy(redactedBy)
              : L10n.of(context).redactedByBecause(redactedBy, reason),
          icon: '🗑️',
          textColor: buttonTextColor.withAlpha(128),
          onPressed: () => onInfoTab!(event),
          fontSize: fontSize,
        );
      },
    );
  }
}

class _ButtonContent extends StatelessWidget {
  final void Function() onPressed;
  final String label;
  final String icon;
  final Color? textColor;
  final double fontSize;

  const _ButtonContent({
    required this.label,
    required this.icon,
    required this.textColor,
    required this.onPressed,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TelegramBubbleGeometry.paddingH,
        vertical: TelegramBubbleGeometry.paddingV,
      ),
      child: InkWell(
        onTap: onPressed,
        child: Text(
          '$icon  $label',
          style: TextStyle(color: textColor, fontSize: fontSize),
        ),
      ),
    );
  }
}
