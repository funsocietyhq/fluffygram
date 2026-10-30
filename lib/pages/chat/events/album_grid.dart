// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pages/chat/events/bubble_shape.dart';
import 'package:fluffychat/pages/chat/events/date_divider.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/media_viewer_hero.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// One-line switch for the album grid (roadmap T7). Set it to `false` and the
/// timeline renders every photo and video as its own bubble again, exactly as
/// before this feature.
///
/// **It is `false` by user decision (2026-10-29): "disable collapsing image
/// messages in the conversation screen, and just have one image per message
/// like fluffychat had originally" (roadmap T95).** The mosaic is worth what it
/// costs only while it is cheaper than the single-image row, and a user's
/// phone said the opposite: a gallery message repaints up to 10 clip-path tiles
/// per frame while the open/close Hero flight runs (ROADMAP T76/T77 geometry
/// per tile), and a user's report was "return animation still feels janky,
/// especially in a gallery message". One image per message keeps the bubble
/// container, the inset strip and the Hero flight, and drops the run detection,
/// the hidden-member rows, the mosaic clip paths and the shared image axis.
/// Every algorithm in this file stays - flipping this one line back to `true`
/// restores the album, and `test/telegram_fidelity/album_cluster_test.dart`
/// keeps the clustering logic gated either way.
///
/// Matrix has no album event: MSC3382 (Inline message Attachments - all the
/// media of one send in one event) is an open proposal, and Matrix 1.10 merged
/// media *captions* only. So an album is built here, in the widget tree, from
/// the events that are already on the wire - the same way WhatsApp clients
/// cluster the one-image-per-message sends of a burst. Nothing in this file
/// writes: no event-content key, no relation, no edit, no state event. Other
/// clients cannot see that this fork grouped anything.
const bool telegramAlbumGridEnabled = false;

/// Album grid geometry (dp). Every number is named here.
abstract final class TelegramAlbumGeometry {
  /// A run needs at least this many media events to become an album.
  static const int minRunLength = 2;

  /// Telegram's mosaic caps one album at 10 items; a longer burst starts a new
  /// album.
  static const int maxRunLength = 10;

  /// The events of a run must be this close in time (seconds between an event
  /// and the one before it). Telegram sends a burst in one action, so the gap
  /// is a few seconds; 60 leaves room for a slow homeserver.
  static const int maxGapSeconds = 60;

  /// The gap between two tiles. Measured 2026-10-25 on a user's
  /// `the reference capture` (1080px wide, 2.625px per dp): the fill run
  /// between two photo columns is x 621-624, so 4px = 1.5dp, read in 92 of the
  /// 125 rows that cross it. The old 2dp came from an analogy with a sender
  /// run's bubble group gap, never from a capture. See `the measurement log`,
  /// "Album inset and leftover placement (measured 2026-10-25)".
  static const double tileGap = 1.5;

  /// The strip of container fill Telegram leaves between a media container edge
  /// and the media inside it. Measured 2026-10-25 on `shots/measure/
  /// a measurement crop` (unscaled crop of a user's `the reference capture of 
  /// the reference capture`, 1080px wide): the container runs x 156-921 and the first photo
  /// pixel column is x 160, so 4px of fill = 1.5dp at 2.625px per dp. 123 of the
  /// 146 sampled rows read exactly 4px. Our render put the media at 0dp (commit
  /// 4a38666), which is why an album looked pasted onto its own box.
  /// See `the measurement log`, "Album inset and leftover placement
  /// (measured 2026-10-25)". Applied to image and video containers only; a
  /// sticker row stays box-less and keeps no inset.
  static const double containerInset = 1.5;

  /// Widest mosaic. A single photo bubble is capped at 256dp by
  /// `message_content.dart`; the album keeps that width.
  // T14b U3: the bubble cap moved 280 -> 284 dp; this number does not ride it.
  // A photo bubble is capped at 256dp by `message_content.dart` and that media
  // cap is measured on its own, so the mosaic keeps it. The album does consume
  // the bubble corner set (`TelegramBubbleShape.borderRadius`), which already
  // reads TelegramBubbleGeometry.cornerRadius (15dp at a user's setting).
  static const double gridMaxWidth = 256;

  /// The mosaic's width on a window of [windowWidth]: the measured 256 dp up
  /// to phone width, then growing in step with the bubble cap so an album in
  /// a wide window keeps Telegram's proportion to the text column instead of
  /// freezing at mobile width (user rule 2026-10-26, finding 24). Never
  /// wider than the column it sits in.
  static double gridMaxWidthForWindow(double windowWidth) {
    // Below the wide-window break the mosaic is the measured 256 dp block: a
    // phone's album never grows, and Telegram's own album cap
    // (`DialogsObject.getMaxParentWidthForMediaLayout()`) is a fixed dp number.
    if (windowWidth < TelegramBubbleGeometry.wideWindowStartDp) {
      return gridMaxWidth;
    }
    // Incoming is the narrower of Telegram's two column formulas, so the
    // mosaic is measured against the side that has less room.
    final cap = TelegramBubbleGeometry.maxBubbleWidthForWindow(
      windowWidth,
      outgoing: false,
    );
    if (cap <= TelegramBubbleGeometry.maxBubbleWidth) return gridMaxWidth;
    final grown = gridMaxWidth * cap / TelegramBubbleGeometry.maxBubbleWidth;
    final room = windowWidth - TelegramBubbleGeometry.bubbleColumnChrome;
    return grown > room ? room : grown;
  }

  /// Tiles per row for a burst of five or more (Telegram's 3-column mosaic).
  static const int wideRunColumns = 3;

  /// Columns of the square mosaic of a run of `count` photos.
  ///
  /// A run of four is a 2x2 grid; every wider run (5 to 10) goes to
  /// [wideRunColumns] and Telegram fills the last row from the left, leaving
  /// the holes at the right. Runs of 2 and 3 have their own, non-uniform
  /// layouts (two halves, one big tile and two stacked) and are not mosaic
  /// grids at all, so they never reach this.
  static int mosaicColumns(int count) => count == 4 ? 2 : wideRunColumns;

  /// Rows of the square mosaic of a run of `count` photos: 4 gives 2, 9 gives
  /// 3, 10 gives 4 (3 + 3 + 3 + 1).
  static int mosaicRows(int count) => (count / mosaicColumns(count)).ceil();

  /// Size of the play glyph on a video tile.
  static const double playGlyphSize = 32;

  /// Caption geometry inside the album container, measured 2026-10-26 on the
  /// a user's album capture `the reference capture` (crop
  /// `a measurement crop`, column scan at x = 500). All three
  /// numbers read from the CONTAINER edge outward, at 2.625 px per dp; the build
  /// subtracts `containerInset`, because the mosaic already stands 1.5 dp off
  /// every container edge.
  ///
  /// Gap from the mosaic's bottom edge to the run's one caption line: grid
  /// bottom y = 2042, first caption glyph top y = 2074 -> 32 px = 12 dp
  /// (`the measurement log`, "Album grid geometry" table).
  static const double captionGapAboveTiles = 12;

  /// Left inset of the caption text: glyphs start at x = 181 against the
  /// container edge x = 156 -> 25 px = 10 dp (same table).
  static const double captionTextInset = 10;

  /// Room under the last caption line before the container's bottom edge: last
  /// line top y = 2121, glyph block ends y = 2151, container edge y = 2175 ->
  /// 24 px = 9 dp. Telegram spends part of that room on the clock it prints on
  /// the caption's last line; this fork prints a media row's time below the
  /// bubble (T11 finding 8), so the whole room is the caption's own.
  static const double captionRoomBelow = 9;
}

/// The render-time clustering of one timeline page.
///
/// Built from the list the timeline already renders (newest event first, the
/// order `ChatEventList` walks). It answers three questions about a timeline
/// index: is it the anchor that draws the mosaic, is it hidden inside that
/// mosaic, and which events does the mosaic show.
class TelegramAlbumCluster {
  const TelegramAlbumCluster(this._anchorOf, this._runsByAnchor);

  /// Empty cluster: every event renders on its own. Used when the album grid
  /// is switched off.
  const TelegramAlbumCluster.disabled()
    : _anchorOf = const [],
      _runsByAnchor = const {};

  /// For every timeline index, the index of the run's anchor, or -1 when the
  /// event renders alone. The anchor is the run's oldest event: the reversed
  /// list puts it topmost on screen, so the mosaic reads in send order.
  final List<int> _anchorOf;

  /// Anchor index -> the run's events in send order (oldest first).
  final Map<int, List<Event>> _runsByAnchor;

  /// Group [events] (newest first) into Telegram albums.
  ///
  /// A run is a maximal stretch of adjacent events that are all
  /// `m.image`/`m.video`, all from one sender, none of them a reply, each one
  /// within `maxGapSeconds` of the previous, of length `minRunLength` ..
  /// `maxRunLength`.
  factory TelegramAlbumCluster.of(List<Event> events) {
    final anchorOf = List<int>.filled(events.length, -1);
    final runsByAnchor = <int, List<Event>>{};
    var start = 0;
    for (var i = 0; i <= events.length; i++) {
      final breaks =
          i == events.length ||
          !_clustersAlone(events[i]) ||
          i > start && !_continuesRun(events[i - 1], events[i]);
      if (!breaks) continue;
      final runLength = i - start;
      if (runLength >= TelegramAlbumGeometry.minRunLength) {
        // A stretch longer than `maxRunLength` becomes several albums, oldest
        // first - Telegram caps one mosaic at 10 tiles. The list is newest
        // first, so the oldest stretch sits at the high indices and the anchor
        // of a chunk is its last index (`chunkEnd - 1`), the event on screen
        // above the rest of its chunk. A leftover of a single event (a burst of
        // 11 = 10 + 1) is under `minRunLength`: it keeps its own bubble.
        var chunkEnd = i;
        while (chunkEnd > start) {
          final chunkLength = min(
            chunkEnd - start,
            TelegramAlbumGeometry.maxRunLength,
          );
          final chunkStart = chunkEnd - chunkLength;
          if (chunkLength >= TelegramAlbumGeometry.minRunLength) {
            final anchor = chunkEnd - 1;
            for (var j = chunkStart; j < chunkEnd; j++) {
              anchorOf[j] = anchor;
            }
            runsByAnchor[anchor] = [
              for (var j = anchor; j >= chunkStart; j--) events[j],
            ];
          }
          chunkEnd = chunkStart;
        }
      }
      start = i;
      // Skip the events that cannot start a run (text, replies, other senders).
      while (i < events.length && !_clustersAlone(events[i])) {
        i++;
      }
      start = i;
    }
    return TelegramAlbumCluster(anchorOf, runsByAnchor);
  }

  /// The event itself is a media event that may join a run: a photo or a
  /// video, not redacted, and not a reply (a reply quote keeps its own bubble).
  static bool _clustersAlone(Event event) =>
      !event.redacted &&
      event.inReplyToEventId() == null &&
      (event.messageType == MessageTypes.Image ||
          event.messageType == MessageTypes.Video);

  /// Does [event] continue the run that ends with [previous]?
  static bool _continuesRun(Event previous, Event event) =>
      _clustersAlone(event) &&
      _clustersAlone(previous) &&
      event.senderId == previous.senderId &&
      event.inReplyToEventId() == null &&
      previous.inReplyToEventId() == null &&
      event.originServerTs
              .difference(previous.originServerTs)
              .inSeconds
              .abs() <=
          TelegramAlbumGeometry.maxGapSeconds &&
      event.room.id == previous.room.id;

  /// The anchor that draws the mosaic for [index], or null when [index] is not
  /// part of a run. `_anchorOf` stores -1 for "in no run", and that sentinel is
  /// NOT a valid answer here: returning -1 makes `isHiddenAt` true for every
  /// event outside an album, because -1 is non-null and never equals an index.
  /// Measured on a phone: the timeline then draws `SizedBox.shrink()` in place
  /// of every plain message, so a chat shows no messages at all.
  int? anchorOf(int index) {
    if (index < 0 || index >= _anchorOf.length) return null;
    final anchor = _anchorOf[index];
    return anchor < 0 ? null : anchor;
  }

  /// True when the event at [index] draws inside the mosaic at [anchor].
  bool isHiddenAt(int index) {
    final anchor = anchorOf(index);
    return anchor != null && anchor != index;
  }

  /// The events of the run anchored at [index], in send order, or null when
  /// [index] does not anchor a run.
  List<Event>? runAt(int index) => _runsByAnchor[index];

  /// The timeline index `AutoScrollController.scrollToIndex` should be given for
  /// the event at [index]: the index of the row that draws it. A run's anchor
  /// draws the mosaic; a member below the anchor draws no tiles, so its own
  /// index is an empty slot and a jump to it lands on nothing. An event in no
  /// run maps to itself, which keeps every plain-message jump unchanged.
  int scrollTargetIndexAt(int index) => anchorOf(index) ?? index;

  /// The timeline index whose row must print the day pill for a day change at
  /// [index]. Telegram's pill names the day of the group under it and an album
  /// run is ONE group, so a day change that sits on a hidden member belongs to
  /// the row that draws the container - the run's anchor. An event in no run
  /// answers with its own index, so every plain message pill stays where it
  /// was. Roadmap T27.
  int datePillAnchorAt(int index) => anchorOf(index) ?? index;

  /// Does the row at [index] print the day pill? [events] is the newest-first
  /// list the timeline walks - the same list [of] clustered.
  ///
  /// A hidden member never prints one: a pill on its own zero-height row sits
  /// between the container's tiles, and Telegram has no divider there. The row
  /// anchoring a run prints the pill when the day changes at its own older
  /// boundary or anywhere inside its span - ONE pill for the run, above the
  /// mosaic. A plain message asks the plain question: its own day against its
  /// older neighbour's.
  bool datePillAt(int index, List<Event> events) {
    if (index < 0 || index >= events.length) return false;
    if (isHiddenAt(index)) return false;
    if (anchorOf(index) == null) {
      return startsTelegramDateGroup(
        events[index],
        index + 1 < events.length ? events[index + 1] : null,
      );
    }
    // The anchor of a run owns the pill of the whole run. The anchor is the
    // run's oldest event, so its members sit at the lower indices: walk down
    // until `anchorOf` stops answering this anchor - that is the run's edge.
    for (var j = index; anchorOf(j) == index; j--) {
      if (startsTelegramDateGroup(
        events[j],
        j + 1 < events.length ? events[j + 1] : null,
      )) {
        return true;
      }
    }
    return false;
  }
}

/// Telegram's album tile: one bubble that holds a whole burst of photos and
/// videos as a mosaic. Each tile keeps its own tap (opens the viewer on that
/// event), its own long-press (selection on that event). The run draws ONE
/// caption line under the mosaic - Telegram's rule, measured in the same
/// capture: "one caption for the whole cluster", not one per photo. Reactions,
/// the read marker and the tick row stay on the anchor event.
class TelegramAlbumGrid extends StatelessWidget {
  const TelegramAlbumGrid({
    required this.events,
    required this.timeline,
    required this.textColor,
    required this.linkColor,
    this.onLongPressSelect,
    super.key,
  });

  /// The run's events, oldest first.
  final List<Event> events;
  final Timeline timeline;
  final Color textColor;
  final Color linkColor;
  final void Function(Event event)? onLongPressSelect;

  @override
  Widget build(BuildContext context) {
    const gap = TelegramAlbumGeometry.tileGap;
    final caption = runCaption;
    // The caption's padding is measured from the container edge, and the mosaic
    // already stands `containerInset` off that edge, so the block's own padding
    // is the measured value minus that strip.
    const sideInset =
        TelegramAlbumGeometry.captionTextInset -
        TelegramAlbumGeometry.containerInset;
    const bottomInset =
        TelegramAlbumGeometry.captionRoomBelow -
        TelegramAlbumGeometry.containerInset;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final cap = TelegramAlbumGeometry.gridMaxWidthForWindow(
              MediaQuery.sizeOf(context).width,
            );
            final side = min(box.maxWidth.isFinite ? box.maxWidth : cap, cap);
            return SizedBox(width: side, child: _mosaic(context, side, gap));
          },
        ),
        // Telegram shows ONE caption for the whole cluster, under the tiles and
        // inside the same container (`the measurement log`, "Album grid
        // geometry" rule 3; `a measurement crop`). Matrix puts a
        // `body` on every event of the run, so the run's caption is the first
        // member in send order that carries one; the other members draw nothing.
        if (caption case final String captionText)
          // Keep the caption inside the mosaic's own width, so a long caption
          // wraps at the tile block's edge and not past it.
          SizedBox(
            width: TelegramAlbumGeometry.gridMaxWidthForWindow(
              MediaQuery.sizeOf(context).width,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                sideInset,
                TelegramAlbumGeometry.captionGapAboveTiles,
                sideInset,
                bottomInset,
              ),
              child: Linkify(
                text: captionText,
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

  /// The run's one caption: the first member, in send order, that carries a
  /// body the widget reads as a caption (`Event.fileDescription`). Null when no
  /// member of the run has one.
  String? get runCaption {
    for (final event in events) {
      if (event.fileDescription case final String description) {
        return description;
      }
    }
    return null;
  }

  Widget _mosaic(BuildContext context, double side, double gap) {
    final count = events.length;
    if (count == 2) {
      final tile = (side - gap) / 2;
      return Row(
        children: [
          _tile(context, events[0], tile, tile),
          SizedBox(width: gap),
          _tile(context, events[1], tile, tile),
        ],
      );
    }
    if (count == 3) {
      // Telegram: one big tile left, two stacked right.
      final small = (side - 2 * gap) / 3;
      final big = side - small - gap;
      return Row(
        children: [
          _tile(context, events[0], big, big),
          SizedBox(width: gap),
          Column(
            children: [
              _tile(context, events[1], small, small),
              SizedBox(height: gap),
              _tile(context, events[2], small, small),
            ],
          ),
        ],
      );
    }
    final columns = TelegramAlbumGeometry.mosaicColumns(count);
    final tile = (side - gap * (columns - 1)) / columns;
    final rows = <Widget>[];
    for (var row = 0; row * columns < count; row++) {
      final cells = <Widget>[];
      for (var column = 0; column < columns; column++) {
        final index = row * columns + column;
        cells.add(
          index < count
              ? _tile(context, events[index], tile, tile)
              : SizedBox(width: tile),
        );
        if (column < columns - 1) cells.add(SizedBox(width: gap));
      }
      rows.add(
        Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            if (row > 0) SizedBox(height: gap),
            Row(children: cells),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: rows,
    );
  }

  Widget _tile(BuildContext context, Event event, double width, double height) {
    return GestureDetector(
      // Flat ink, no ripple: the bubble surface stays flat.
      // A full-screen route, not a dialog barrier: Flutter 3.47 gives neither
      // `showDialog` nor `MaterialPageRoute` a transition slot, so the fade and
      // its 220 ms duration live on the route itself (ROADMAP T12.1), matched
      // to the Hero flight below.
      onTap: () =>
          Navigator.of(
            // T91: the root Navigator, so the Android back button pops the viewer
            // instead of quitting the app - full reason at message_content.dart.
            context,
            rootNavigator: true,
          ).push(
            FadeThroughBlackPageRoute(
              builder: (_) =>
                  ImageViewer(event, timeline: timeline, outerContext: context),
            ),
          ),
      onLongPress: onLongPressSelect == null
          ? null
          : () => onLongPressSelect!(event),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            telegramHero(
              tag: event.eventId,
              child: MxcImage(
                key: ValueKey(event.eventId),
                cacheKey: event.transactionId ?? event.eventId,
                cacheName: event.room.id,
                event: event,
                width: width,
                height: height,
                fit: BoxFit.cover,
                isThumbnail: true,
              ),
            ),
            if (event.messageType == MessageTypes.Video)
              Center(
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: TelegramAlbumGeometry.playGlyphSize,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
