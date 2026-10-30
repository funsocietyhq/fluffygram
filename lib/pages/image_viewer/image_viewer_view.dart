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
import 'dart:convert' show base64Decode;

import 'package:extended_image/extended_image.dart';
import 'package:fluffychat/config/telegram_palette.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/image_viewer/video_player.dart';
import 'package:fluffychat/utils/attachments/telegram_media_cache.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/media_viewer_hero.dart';
import 'package:fluffychat/utils/telegram_pager_physics.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'image_viewer.dart';

/// A 1x1 fully transparent PNG. A media page draws with it when the event
/// carries neither the full media nor a thumbnail, so the page is pan-able,
/// zoom-able, page-able and dismiss-able from its very first frame. A page that
/// has a thumbnail draws that instead (T105), which is what stops the flash.
final Uint8List pendingMediaBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAEAAAYAAf6MZ8gAAAAASUVORK5CYII=',
);

/// Telegram rule 9: how many lines of caption fit under the media.
const int viewerCaptionMaxLines = 3;

/// Key of the widget that translates the media during a drag-out. The fidelity
/// gate reads its matrix to see which axis a drag took
/// (`test/telegram_fidelity/media_viewer_test.dart`, `viewerSlideOffset`).
const Key viewerDragOutKey = ValueKey('viewer-drag-out');

/// Telegram's media viewer. Paging, pinch zoom and panning come from
/// `extended_image`: an `ExtendedImageGesturePageView` of `ExtendedImage`s in
/// `ExtendedImageMode.gesture`. T100 took the drag-out dismiss away from the
/// package - there is no `ExtendedImageSlidePage` in this tree any more - so one
/// drag does exactly one thing: a horizontal one goes to the pager, a vertical
/// one to [dragOut]. Everything you see around the media - the close,
/// forward and download buttons, the `n / total` counter, the hover arrows and
/// the caption - is ours.
class ImageViewerView extends StatefulWidget {
  final ImageViewerController controller;

  const ImageViewerView(this.controller, {super.key});

  @override
  State<ImageViewerView> createState() => _ImageViewerViewState();
}

class _ImageViewerViewState extends State<ImageViewerView>
    with SingleTickerProviderStateMixin {
  /// Telegram rule 8: a double tap zooms to **exactly 3.0x at the finger**
  /// (`MIN_SCALE` 1.0 / `MAX_SCALE` 3.0, `PhotoViewer.java:19246-19247`; the
  /// double-tap target `PhotoViewer.java:21030-21049`), and a second one fits it
  /// back to 1.0.
  static const double doubleTapScale = 3.0;

  /// Telegram rule 5: one tap on the media hides the chrome, the next shows it.
  /// It never closes the viewer.
  bool chromeVisible = true;

  /// T90 : the axis the current gesture moves the media on.
  /// Telegram decides the axis when the drag starts and keeps it for the rest of
  /// the gesture, so a diagonal flick goes left or right ("Swiping diagonally on
  /// telegram just goes left or right, it doesn't let you swipe the media
  /// diagonally"). `extended_image` honours this value while it accumulates the
  /// finger delta: `horizontal` adds `Offset(value.dx, 0.0)`, `vertical` adds
  /// `Offset(0.0, value.dy)` and `both` adds `value` unchanged, which is what
  /// dragged the photo diagonally
  /// (`extended_image-10.1.0/lib/src/gesture/slide_page.dart:147-152`).
  /// `SlideAxis.both` doubles as the "not decided yet" state of a gesture.
  SlideAxis dragAxis = SlideAxis.both;

  /// Where the pointer of the current gesture went down, in window pixels.
  Offset? pointerDown;

  /// How far the finger travels before [dragAxis] is decided: 8 dp of slop, so a
  /// wobble inside a tap never picks the axis of a whole drag.
  static const double axisLockSlop = 8.0;

  /// How far the current drag-out has taken the media, in dp, on y only. T100:
  /// the pager owns every horizontal drag, so a horizontal gesture leaves this
  /// at 0 and can never close the viewer.
  double _dragDy = 0.0;

  /// The pointer y at the moment [dragAxis] locked to vertical. [dragOut] is
  /// measured from there, so the 8 dp of travel that decided the axis does not
  /// jump the media.
  double? _dragBaseY;

  /// The [dragOut] the spring-back started from, for [_snapBack] to interpolate.
  double _snapBackFrom = 0.0;

  /// Springs [dragOut] back to 0 after a drag under the dismiss threshold, on the
  /// close's clock (200 ms) like every other return in the viewer. The package's
  /// 500 ms `resetPageDuration` went with it (T96).
  late final AnimationController _snapBack;

  @override
  void initState() {
    super.initState();
    _snapBack =
        AnimationController(
          vsync: this,
          duration: TelegramViewerMotion.closeDuration,
        )..addListener(() {
          setState(() => _dragDy = _snapBackFrom * (1.0 - _snapBack.value));
        });
  }

  @override
  void dispose() {
    _snapBack.dispose();
    super.dispose();
  }

  /// Telegram's drag-out threshold and the distance the scrim fade runs over:
  /// a sixth of the container height (`PhotoViewer.java:19288`
  /// `abs(dragY - ev.getY()) > getContainerViewHeight() / 6.0f`). On a user's
  /// 871.4 dp media box that is 145.2 dp.
  double dismissSlop(BuildContext context) =>
      MediaQuery.sizeOf(context).height / 6;

  /// The value [dragOut] applies to the media.
  Offset get dragOut => Offset(0, _dragDy);

  /// True while the page in view is zoomed: its drag pans the photo, so it is
  /// never a drag-out, and `canScrollPage` tells the pager the same thing.
  bool get zoomedIn =>
      (gestureKeys[widget.controller.currentEvent.eventId]
              ?.currentState
              ?.gestureDetails
              ?.totalScale ??
          1.0) >
      1.0;

  /// Decide the axis once, from the total displacement of the finger since it
  /// went down, and hold it until the pointer lifts. This runs in a `Listener`,
  /// which sees the raw pointer stream and never joins the gesture arena, so
  /// paging, pinch zoom, the tap that toggles the chrome and the double-tap zoom
  /// keep their own recognisers.
  void handleAxisPointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      // A second finger (a pinch) must not restart the decision.
      if (pointerDown != null) return;
      _snapBack.stop();
      pointerDown = event.position;
      _dragBaseY = null;
      if (dragAxis != SlideAxis.both || _dragDy != 0.0) {
        setState(() {
          dragAxis = SlideAxis.both;
          _dragDy = 0.0;
        });
      }
      return;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      pointerDown = null;
      _dragBaseY = null;
      if (dragAxis != SlideAxis.both) setState(() => dragAxis = SlideAxis.both);
      // T100, Telegram `PhotoViewer.java:19288`: a vertical drag past a sixth of
      // the window closes the viewer, everything below it springs back. A
      // horizontal drag never reaches here with a delta, so it never closes.
      final dragged = _dragDy;
      if (dragged.abs() > dismissSlop(context)) {
        // T102: the offset stays where the finger left it. Zeroing it in the same
        // frame that starts the close put the media back at centre for the whole
        // 200 ms fade and snapped the chat back in behind it (user report,
        // 2026-10-30). Telegram springs back only *below* the threshold
        // (`PhotoViewer.java:19288`, the T100 threshold); past it the view
        // keeps its position and animates out from there. The spring-back below
        // stays the only branch that zeroes the drag.
        widget.controller.fadeAwayAndPop();
        return;
      }
      _snapBackFrom = dragged;
      if (_snapBackFrom != 0.0) _snapBack.forward(from: 0.0);
      return;
    }
    if (event is! PointerMoveEvent) return;
    final down = pointerDown;
    if (down == null) return;
    final dx = event.position.dx - down.dx;
    final dy = event.position.dy - down.dy;
    if (dx * dx + dy * dy < axisLockSlop * axisLockSlop) return;
    final axis = dx.abs() > dy.abs()
        ? SlideAxis.horizontal
        : SlideAxis.vertical;
    if (axis != dragAxis) {
      setState(() => dragAxis = axis);
      // Measure the drag-out from where the finger was when the axis locked, so
      // the 8 dp that decided it does not jump the media.
      _dragBaseY = axis == SlideAxis.vertical ? event.position.dy : null;
    }
    // T100: only a vertical-locked, un-zoomed gesture drags the media out. The
    // package never sees the horizontal half of a drag any more: with no
    // `ExtendedImageSlidePage` its slide branch cannot run
    // (`extended_image-10.1.0/lib/src/gesture/gesture.dart:345-390`), so every
    // delta at scale <= 1 reaches the pager and `TelegramPagerPhysics` decides.
    if (dragAxis != SlideAxis.vertical || zoomedIn) return;
    final dragDy = event.position.dy - (_dragBaseY ?? event.position.dy);
    if (dragDy == _dragDy) return;
    setState(() => _dragDy = dragDy);
  }

  /// One key per media page, so the viewer can ask `extended_image` to zoom the
  /// photo in view when its own double-tap recognizer does not win the gesture.
  final Map<String, GlobalKey<ExtendedImageGestureState>> gestureKeys = {};

  /// Telegram rule 8: `extended_image` scales the photo around the point that
  /// was tapped. [state] is the gesture state when the package asked for the
  /// zoom itself; otherwise the viewer takes the state of the page in view
  /// through its [gestureKeys].
  void handleDoubleTap([ExtendedImageGestureState? state]) {
    final gestureState =
        state ??
        gestureKeys[widget.controller.currentEvent.eventId]?.currentState;
    if (gestureState == null || !gestureState.mounted) return;

    final begin = gestureState.gestureDetails?.totalScale ?? 1.0;
    gestureState.handleDoubleTap(
      scale: begin >= doubleTapScale ? 1.0 : doubleTapScale,
      doubleTapPosition: gestureState.pointerDownPosition,
    );
  }

  /// Telegram rule 5: a tap toggles the chrome. The recognizers tell a lone tap
  /// from a pair, so a double tap goes to [handleDoubleTap] instead.
  void handleMediaTap() => setState(() => chromeVisible = !chromeVisible);

  /// Telegram's bar carries the chat's settings gear (`PhotoViewMedias.java:
  /// 2714-2745`), and it opens that chat's details. The viewer is a `Navigator`
  /// route laid over the GoRouter chat route, so the viewer closes first and the
  /// route change follows on the next frame - a bare `context.go` would leave the
  /// photo sitting on top of the details page.
  void openChatDetails() {
    final roomId = widget.controller.currentEvent.room.id;
    widget.controller.fadeAwayAndPop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go('/rooms/$roomId/details');
    });
  }

  /// The gesture key of one media page, created once per event.
  GlobalKey<ExtendedImageGestureState> gestureKey(Event event) =>
      gestureKeys.putIfAbsent(event.eventId, GlobalKey.new);

  /// The field behind the media. Owner, 2026-10-30: "gallery mode should show a
  /// black background screen UNTIL they start swiping away (fade away and show
  /// background conversation as it gets closer to closing)". So it is **opaque
  /// black at rest** - Telegram's `backgroundDrawable` sits at alpha 255 while
  /// `aty == 0` (`PhotoViewer.java:19769`) - and while a drag-out runs its alpha
  /// falls linearly with the drag over the dismiss distance
  /// ([dismissSlop], `PhotoViewer.java:19288`) to **fully transparent** at the
  /// threshold, so the conversation arrives with the finger. A spring-back
  /// animates it back to 255 on the same clock as the media, because
  /// [_snapBack] rebuilds this field with [dragOut].
  ///
  /// Telegram floors that alpha at `Math.max(127, ...)` (`PhotoViewer.java:19769`)
  /// and runs its fade over `containerWidth / 4` (`:19766`). This fork takes the
  /// fade to 0 over the dismiss distance, on a user's instruction, because the
  /// field here is the route over the live chat, not a drawable over Telegram's
  /// own black activity. The 127 floor stays cited in `docs/TELEGRAM_TARGET.md`.
  Color pageBackground() {
    final progress = (_dragDy.abs() / dismissSlop(context)).clamp(0.0, 1.0);
    return TelegramPalette.chatBackground.withAlpha(
      (255 * (1 - progress)).round(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final iconButtonStyle = IconButton.styleFrom(
      backgroundColor: Colors.black.withAlpha(200),
      foregroundColor: Colors.white,
    );
    return PopScope(
      // T91 : the Android back button closes the viewer and
      // lands on the chat, which is what Telegram does. This route is not one
      // the GoRouter delegate walks, so its canPop() is false and Router
      // answers the back with SystemNavigator.pop() - the app quit with the
      // photo still on screen (go_router-18.1.1/lib/src/delegate.dart:82-97).
      // Taking the pop here puts it back on the route stack, where it belongs.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // T96: the back gesture closes with a fade, not a flight into the row.
        controller.fadeAwayAndPop();
      },
      child: Scaffold(
        // The scrim: the chat stays behind the media (see [pageBackground]).
        backgroundColor: pageBackground(),
        extendBodyBehindAppBar: true,
        // T107 .
        // Telegram's gallery bar, measured on `the reference capture`
        // at 2.625 px/dp: the leading arrow's ink spans x dp 20.2..35.4, the
        // title ink starts at x dp 72.8 - which is the AppBar leading box
        // (56 dp) plus the default 16 dp of title spacing, so the placement
        // needs no hand-padding - and the three action icons ride a 48 dp
        // pitch (ink centres x dp 291.4, 339.5, 387.4, the last one flush with
        // the page edge). The two text lines occupy y dp 78.9..111.6, so the
        // bar is 64 dp under the status bar, not `kToolbarHeight`'s 56.
        //
        // The bar stays mounted and simply drops to `toolbarHeight: 0` with the
        // chrome, because an AppBar that leaves the tree takes its
        // `systemOverlayStyle` with it and the status bar would fall back to the
        // chat's coloured bar while the photo had no chrome. Telegram's status
        // bar over media is black with light icons - `the reference capture of 
        // the reference capture` shows it that way with the media area well below it.
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: chromeVisible ? 64.0 : 0.0,
          backgroundColor: Colors.transparent,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          // Telegram's gallery arrow returns to the chat; it is not a close
          // cross. Its tap target is the same 48 dp box and it fades the viewer
          // away on the T96 close, so the chat arrives the same way.
          leading: chromeVisible
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: controller.fadeAwayAndPop,
                  color: Colors.white,
                  tooltip: L10n.of(context).close,
                )
              : null,
          // T104: the two text lines Telegram carries at the leading edge of the
          // gallery header - the chat the media belongs to and when it was sent.
          title: chromeVisible
              ? _ViewerHeader(event: controller.currentEvent)
              : null,
          // Telegram's own three, in its own order: forward, the chat's
          // settings gear, and the overflow that carries the file actions
          // (`PhotoViewMedias.java:2714-2745`). No chip sits behind them -
          // `iconButtonStyle`'s black pill belongs to the mid-screen arrows,
          // not to the bar - and no gap sits between them, because the measured
          // pitch is the 48 dp an IconButton already is.
          actions: chromeVisible
              ? [
                  IconButton(
                    icon: const Icon(Icons.reply_outlined),
                    onPressed: controller.forwardAction,
                    color: Colors.white,
                    tooltip: L10n.of(context).forward,
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: openChatDetails,
                    color: Colors.white,
                    tooltip: L10n.of(context).chatDetails,
                  ),
                  // The ⋮ holds what the two file buttons used to be. Telegram
                  // folds them into the same overflow.
                  PopupMenuButton<void>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        onTap: () => controller.saveFileAction(context),
                        child: Text(L10n.of(context).downloadFile),
                      ),
                      PopupMenuItem(
                        onTap: () => controller.shareFileAction(context),
                        child: Text(L10n.of(context).share),
                      ),
                    ],
                  ),
                ]
              : const [],
        ),
        body: HoverBuilder(
          builder: (context, hovered) => Stack(
            children: [
              // T90: the axis lock reads the pointer stream of the media area.
              Listener(
                onPointerDown: handleAxisPointer,
                onPointerMove: handleAxisPointer,
                onPointerUp: handleAxisPointer,
                onPointerCancel: handleAxisPointer,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: handleMediaTap,
                  onDoubleTap: handleDoubleTap,
                  child: Transform.translate(
                    // T100: the drag-out, owned by this State. A horizontal-locked
                    // gesture leaves `dragOut` at `Offset.zero`, so only the pager
                    // moves; a vertical-locked one follows the finger and the
                    // chrome stays put.
                    key: viewerDragOutKey,
                    offset: dragOut,
                    child: KeyboardListener(
                      focusNode: controller.focusNode,
                      onKeyEvent: controller.onKeyEvent,
                      child: ExtendedImageGesturePageView.builder(
                        controller: controller.pageController,
                        scrollDirection: Axis.horizontal,
                        // Telegram's paging rule: a drag past a third of the viewport
                        // or a fling past dp(650) turns one page; below both it snaps
                        // back (`PhotoViewer.java:19315-19319`). Both halves are in
                        // that physics object, which needs the pager to leave its own
                        // page snap off: `pageSnapping: true` puts Flutter's
                        // `PageScrollPhysics` - a half-viewport commit - outside ours,
                        // where our `createBallisticSimulation` never runs.
                        physics: TelegramPagerPhysics(),
                        pageSnapping: false,
                        // Zoomed in, a drag pans the photo instead of paging.
                        canScrollPage: (gestureDetails) =>
                            (gestureDetails?.totalScale ?? 1.0) <= 1.0,
                        itemCount: controller.allEvents.length,
                        onPageChanged: controller.onPageChanged,
                        itemBuilder: (context, index) {
                          final event = controller.allEvents[index];
                          if (event.messageType == MessageTypes.Video) {
                            return _MediaPage(
                              event: event,
                              // T100: `ExtendedImageSlidePageHandler` went with
                              // the slide page - with no slide-page ancestor it
                              // builds a no-op `GestureDetector` and skips both
                              // transforms
                              // (`extended_image-10.1.0/lib/src/gesture/slide_page_handler.dart:33-70`).
                              media: Padding(
                                padding: const EdgeInsets.only(top: 52.0),
                                child: Center(
                                  child: EventVideoPlayer(
                                    event,
                                    index: index,
                                    // Live getter, not a field: the value
                                    // must be current when the page changes.
                                    currentIndex: () => controller.currentIndex,
                                    pageController: controller.pageController,
                                  ),
                                ),
                              ),
                            );
                          }
                          return _MediaPage(
                            event: event,
                            media: _DecryptedImage(
                              event: event,
                              heroTag: controller.heroTag(event),
                              gestureKey: gestureKey(event),
                              onDoubleTap: handleDoubleTap,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              if (chromeVisible && controller.allEvents.length > 1)
                // Telegram's "n / total" counter of the opened media. It ramps in
                // on the chrome ramp, 150 ms, started at the same moment as the
                // media ramp and not after it: PhotoViewCell.java:59-63 calls
                // setTextInAnimation.animateIn() and setViewsAnimation
                // (alpha 0 -> 1, 150 ms) unconditionally in animateIn(), next to
                // the cell's own alpha -> 1 at 220 ms (`:64`).
                EntranceFade(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      // T104. The counter sits BELOW the header row, not under the
                      // status bar: in a user's capture its ink starts at y 362 px
                      // = dp 137.9, and the header's own block ends at dp 108
                      // (`the reference capture`, 1 dp = 2.625 px). The AppBar
                      // is kToolbarHeight (56 dp) over the status inset, so the gap is
                      // the inset plus 41 dp.
                      padding: EdgeInsets.only(
                        top: MediaQuery.viewPaddingOf(context).top + 97.0,
                      ),
                      child: Text(
                        // T104. Telegram writes `"%1$d of %2$d"`, not a slash - the
                        // a user's capture reads "47330 of 47341" - in white glyphs of
                        // cap height 10.7 dp (a 16 sp face), centred at dp 204.4 of the
                        // 411 dp width.
                        '${controller.currentIndex + 1} of '
                        '${controller.allEvents.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              if (chromeVisible && hovered) ...[
                if (controller.canGoBack)
                  Align(
                    alignment: .centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: IconButton(
                        style: iconButtonStyle,
                        tooltip: L10n.of(context).previous,
                        icon: const Icon(Icons.keyboard_arrow_left_outlined),
                        onPressed: controller.prevImage,
                      ),
                    ),
                  ),
                if (controller.canGoNext)
                  Align(
                    alignment: .centerRight,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: IconButton(
                        style: iconButtonStyle,
                        tooltip: L10n.of(context).next,
                        icon: const Icon(Icons.keyboard_arrow_right_outlined),
                        onPressed: controller.nextImage,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The caption of a media event, or null when it has none.
///
/// `Event.body` is not a caption. matrix-14.1.0 `src/event.dart:298` defines it
/// as `content.tryGet('body')`, and every sender writes the file name there
/// when the media carries no caption - which is why the viewer printed
/// `IMG_3847.mp4` centred under a captionless video (T85, user capture
/// the reference capture). Telegram's gallery draws the caption and,
/// for captionless media, draws no line at all.
///
/// `Event.fileDescription` (`lib/utils/file_description.dart:11-31`) answers
/// first: that is the rule the timeline row, the album mosaic and the audio row
/// already use, so the viewer and the row agree about what a caption is. The
/// rest picks up captions other senders wrote into the media keys instead of
/// `body` - the legacy `caption` / `info.caption` pair and the MSC1767 text
/// list. A candidate equal to the file name is never a caption.
String? telegramMediaCaption(Event event) {
  final description = event.fileDescription;
  if (description != null) return description;
  final filename = event.content.tryGet<String>('filename') ?? event.body;
  final rawText = event.content['org.matrix.msc1767.text'];
  final candidates = <String?>[
    event.content.tryGet<String>('caption'),
    event.content.tryGetMap<String, Object?>('info')?.tryGet<String>('caption'),
    if (rawText is List)
      for (final part in rawText)
        if (part is Map && part['body'] is String) part['body'] as String,
  ];
  for (final candidate in candidates) {
    if (candidate == null || candidate.isEmpty) continue;
    if (candidate == filename) continue;
    return candidate;
  }
  return null;
}

/// One page of the viewer: the media with its caption under it (Telegram rule
/// 9), at most [viewerCaptionMaxLines] lines. A captionless page draws the
/// media alone (T85).
/// T104 (user, 2026-10-30: "make it look like my latest screenshot i
/// uploaded"). The capture is Telegram's gallery header, `the reference capture of 
/// the reference capture`, 1080x2424, 1 dp = 2.625 px, and it carries two lines that this
/// viewer never drew:
///
/// * the name: ink y 205..241 px = dp 78.1..91.8, so a cap height of **14.1 dp**,
///   which is a **20 sp** face (Roboto digits and caps sit at 0.711 em), drawn
///   in the medium weight Telegram uses for a header name;
/// * the date: ink y 266..292 px = dp 101.3..111.3, cap height **10.3 dp** =
///   **14 sp**;
/// * both start at x 192 px = **dp 73.1**, which is Material's own `leading 56 +
///   titleSpacing 16`, so the AppBar's default placement already matched and
///   only the text was missing. Both are pure **#FFFFFF** - the date is not
///   dimmed, it only reads lighter because it is thinner - and their ink gap
///   measures 9.5 dp, which is the 2 dp spacer below.
///
/// The block lands about 4 dp above Telegram's, which centres it on the action
/// icons rather than in Flutter's toolbar box; that residual is left alone, so
/// no hand-placed padding stands between this widget and the AppBar.
///
/// Telegram puts the **sender** of the media there inside a group and the chat
/// name in a DM (`ChatLocationView` is not in the vendored tree, so that is read
/// off a user's captures), and both lines re-read the event on every page,
/// which is what `ImageViewerController.currentEvent` hands over.
///
/// The date line is the form the capture shows - `"Oct 25 at 11:15 AM"`. The
/// day-relative forms Telegram may use for today or yesterday are in no capture
/// this repo holds, so the fork writes the measured form for every date instead
/// of inventing the others.
class _ViewerHeader extends StatelessWidget {
  const _ViewerHeader({required this.event});

  final Event event;

  /// 14.1 dp of cap height in the capture -> 20 sp.
  static const nameStyle = TextStyle(
    color: Colors.white,
    fontSize: 20,
    fontWeight: FontWeight.w500,
  );

  /// 10.3 dp of cap height in the capture -> 14 sp.
  static const dateStyle = TextStyle(color: Colors.white, fontSize: 14);

  @override
  Widget build(BuildContext context) {
    final sent = event.originServerTs;
    final locale = Localizations.localeOf(context).languageCode;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Telegram's first line names the **chat** the media belongs to - the
        // group name in a group, the peer's name in a DM - not whoever sent this
        // one file: `the reference capture` prints the group name
        // against "47330 of 47341", which is that one chat's whole media history.
        Text(
          event.room.getLocalizedDisplayname(),
          style: nameStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          '${DateFormat('MMM d', locale).format(sent.toLocal())} '
          'at ${sent.localizedTimeOfDay(context)}',
          style: dateStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _MediaPage extends StatelessWidget {
  final Event event;
  final Widget media;

  const _MediaPage({required this.event, required this.media});

  @override
  Widget build(BuildContext context) {
    final caption = telegramMediaCaption(event);
    return Column(
      children: [
        Expanded(child: media),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              caption,
              maxLines: viewerCaptionMaxLines,
              overflow: TextOverflow.ellipsis,
              // T104. The caption sits at the leading edge in white, not centred in
              // secondary grey: a user's capture puts its ink at x 46..540 px = dp
              // 17.5..205.7, full height 15.6 dp (top of the ascender to the bottom of
              // the descender) = a 16 sp face, colour #FFFFFF.
              textAlign: TextAlign.start,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
      ],
    );
  }
}

/// One image or sticker page, drawn from bytes the client decrypted itself -
/// the same call `MxcImage` makes. The viewer never loads media by URL.
class _DecryptedImage extends StatefulWidget {
  final Event event;

  /// The `Hero` tag of this page, from the viewer controller: it matches the
  /// timeline row while the viewer is open, and changes when a close begins so
  /// the close is a fade. See `ImageViewerController.heroTag`.
  final String heroTag;

  final Key? gestureKey;
  final void Function(ExtendedImageGestureState state) onDoubleTap;

  const _DecryptedImage({
    required this.event,
    required this.heroTag,
    required this.gestureKey,
    required this.onDoubleTap,
  });

  @override
  State<_DecryptedImage> createState() => _DecryptedImageState();
}

class _DecryptedImageState extends State<_DecryptedImage> {
  Uint8List? _bytes;

  /// T105: what the picture layer paints before the full media is decrypted - the
  /// event's thumbnail when it carries one. Telegram opens a photo on the frame
  /// it already has and never shows an empty one, which is why its video never
  /// flashed (T104: the video starts on a poster frame, `VideoMessageView.java:
  /// 548-550,1282-1285`) while its photos did.
  ///
  /// The two layers this replaces could only flash. `MxcImage`'s preview sat
  /// **behind** an `ExtendedImage` that started on `pendingMediaBytes` - a
  /// transparent 1 px - and the preview was dropped on the very frame the full
  /// bytes arrived, while the picture layer kept painting the transparent 1 px
  /// for the frames its own decode needed. Owner, 2026-10-30: "images are still
  /// flashing too when they aren't cached while loading". One layer whose bytes
  /// change under `gaplessPlayback: true` cannot: that flag keeps the OLD picture
  /// painted until the new provider has decoded (`image/extended_image_widget
  /// .dart:148-158,611-616`), so the swap has no empty frame in it.
  ///
  /// This also retires T99's `_previewBox` centring patch: with one layer there is
  /// no second rect to disagree with, and both the thumbnail and the full media
  /// are contain-fitted in the same page box.
  Uint8List? _thumbnailBytes;

  @override
  void initState() {
    super.initState();
    unawaited(_loadThumbnail());
    unawaited(_loadBytes());
  }

  Future<void> _loadThumbnail() async {
    // T122 stage 2: ask for a thumbnail only when the event carries one.
    // `downloadAndDecryptAttachment(getThumbnail: true)` resolves the url with
    // `attachmentOrThumbnailMxcUrl()`, which drops back to the ATTACHMENT url
    // when there is no thumbnail and then sets `getThumbnail = mxcUrl !=
    // attachmentMxcUrl` to `false` (`matrix-14.1.0/lib/src/event.dart:831-835`,
    // `:645-647`). So for a GIF re-sent by reference - 313 bytes of content,
    // no `thumbnail_url` - this call downloaded the **whole animated file a
    // second time**: measured 1594 ms for a 3,924,227-byte encrypted body from
    // the group homeserver (`the measurement log`), i.e. the gallery asked twice
    // per open for a user's ~4.4 MB GIF.
    if (!widget.event.hasThumbnail) return;
    try {
      final file = await widget.event.downloadAndDecryptAttachment(
        getThumbnail: true,
      );
      if (!mounted || _bytes != null) return;
      setState(() => _thumbnailBytes = file.bytes);
    } catch (error) {
      // No thumbnail on this event: the page stays black until the media lands,
      // which is what Telegram shows for media it has never seen.
      Logs().d('Viewer could not load the thumbnail', error);
      // T122 : "it's still showing a black screen for gif links
      // when I view in gallery". `Logs()` runs at INFO in a release build, so the
      // line above never reaches the phone and a black page carries no reason.
      // `debugPrint` does reach `adb logcat -s flutter` in a release APK - the
      // same channel as `[TelegramMedia] miss` and `[TelegramGif]`.
      debugPrint('[Viewer] thumbnail failed: $error');
    }
  }

  Future<void> _loadBytes() async {
    // T122 stage 2 (user, 2026-10-30: "gallery mode is re downloading the gif
    // each time instead of using the cache - that's why linked gifs are black
    // screen and then loading like 10 seconds later if I stay on the page").
    // The page paid for the media on **every** open: this was the only fetch
    // path, and the SDK's own store cannot hold a re-sent GIF reference (no
    // `info.size`, so `event.dart:852-858` calls it non-storeable). Consult the
    // fork's decrypted cache first: a hit is a file read (single-digit ms) with
    // no request and no AES-CTR pass, and a miss goes through `fileFor`, which
    // downloads **once** and keeps the result for the next open.
    try {
      final hit = await TelegramMediaCache.cached(widget.event);
      final cachedFile = hit ?? await TelegramMediaCache.fileFor(widget.event);
      if (cachedFile != null) {
        final bytes = await cachedFile.readAsBytes();
        if (!mounted) return;
        setState(() => _bytes = bytes);
        return;
      }
      debugPrint('[Viewer] cache miss, falling back to the SDK path');
    } on Object catch (error) {
      // `path_provider` has no implementation under `flutter test`, so the
      // cache can raise `MissingPluginException` here. It must never be able to
      // break the page: fall through to the SDK path below.
      debugPrint('[Viewer] cache failed: $error');
    }
    try {
      final file = await widget.event.downloadAndDecryptAttachment(
        getThumbnail: false,
      );
      if (!mounted) return;
      setState(() => _bytes = file.bytes);
    } catch (error) {
      // Keep showing the `MxcImage` preview under the transparent seed image.
      Logs().d('Viewer could not load its media', error);
      // T122: the reason a gallery page stays black. Read with
      // `adb logcat -s flutter | grep Viewer`.
      debugPrint('[Viewer] media failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    return telegramHero(
      tag: widget.heroTag,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExtendedImage.memory(
            // The thumbnail first, the full media when it lands, the transparent
            // 1 px only when the event carries neither. `gaplessPlayback: true`
            // below covers the swap between the two real pictures.
            _bytes ?? _thumbnailBytes ?? pendingMediaBytes,
            key: ValueKey(event.eventId),
            // Lets the viewer reach this page's gesture state to zoom it.
            extendedImageGestureKey: widget.gestureKey,
            fit: BoxFit.contain,
            // The seed swaps for the real bytes without a flicker.
            gaplessPlayback: true,
            // T100: no `enableSlideOutPage` - the drag-out is this State's
            // `Transform.translate`, not the package's, and the package only
            // translates the image when it finds an `ExtendedImageSlidePage`
            // ancestor (`extended_image-10.1.0/lib/src/gesture/gesture.dart:552-568`).
            mode: ExtendedImageMode.gesture,
            initGestureConfigHandler: (state) => GestureConfig(
              inPageView: true,
              initialScale: 1.0,
              // Telegram clamps pinch zoom to the same 1.0 - 3.0 band as the
              // double tap (`PhotoViewer.java:19246-19247`), and never lets the
              // media shrink below its fitted size, so `animationMinScale`
              // matches `minScale` instead of rubber-banding under 1.0.
              minScale: 1.0,
              animationMinScale: 1.0,
              maxScale: TelegramViewerMotion.maxZoomScale,
              animationMaxScale: TelegramViewerMotion.maxZoomScale,
              initialAlignment: InitialAlignment.center,
              cacheGesture: false,
            ),
            onDoubleTap: widget.onDoubleTap,
          ),
        ],
      ),
    );
  }
}
