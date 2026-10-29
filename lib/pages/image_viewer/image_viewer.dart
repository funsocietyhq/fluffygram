// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:extended_image/extended_image.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer_view.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/show_scaffold_dialog.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../utils/matrix_sdk_extensions/event_extension.dart';

class ImageViewer extends StatefulWidget {
  final Event event;
  final Timeline? timeline;
  final BuildContext outerContext;

  const ImageViewer(
    this.event, {
    required this.outerContext,
    this.timeline,
    super.key,
  });

  @override
  ImageViewerController createState() => ImageViewerController();
}

class ImageViewerController extends State<ImageViewer> {
  final FocusNode focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    allEvents =
        widget.timeline?.events
            .where(
              (event) => {
                MessageTypes.Image,
                MessageTypes.Sticker,
                if (PlatformInfos.supportsVideoPlayer) MessageTypes.Video,
              }.contains(event.messageType),
            )
            .toList()
            .reversed
            .toList() ??
        [widget.event];
    var index = allEvents.indexWhere(
      (event) => event.eventId == widget.event.eventId,
    );
    if (index < 0) index = 0;
    _currentPage = index;
    pageController = ExtendedPageController(
      initialPage: index,
      // No gap: Telegram pages one photo straight into the next. A gap also
      // breaks `extended_image`'s own extent math on Flutter 3.47
      // (`computeMaxScrollOffset()` is no longer an even multiple of
      // `itemExtent`, which throws in the viewer's first layout).
      pageSpacing: mediaPageSpacing,
      // False: the photo may take a pinch zoom even while the page is still
      // settling. A one finger drag stays a page swipe (GestureConfig
      // inPageView), so paging and zooming do not fight for the gesture.
      shouldIgnorePointerWhenScrolling: false,
    );
  }

  /// Gap between two media pages, dp. Zero keeps the package's page-extent
  /// maths exact, and it is what Telegram does.
  static const double mediaPageSpacing = 0;

  late final ExtendedPageController pageController;

  late final List<Event> allEvents;

  /// Whether a close of this viewer is a plain fade. The viewer starts `false`
  /// and every close path sets it one frame before the pop.
  ///
  /// T96 : "Instead of having the animation collapse into the
  /// message, just have it fade away (exactly as it does now if the message isn't
  /// on screen)". A message that is scrolled away has no `Hero` on screen, so
  /// Flutter builds no flight and the pop is only the route's own fade
  /// (`FadeThroughBlackPageRoute`, 200 ms, `TelegramViewerMotion.closeDuration`).
  /// That is the close a user wants in every case. Flutter starts a flight
  /// only when one tag sits on both routes (`hero.dart`, `_HeroFlight`), so the
  /// way to get the fade while keeping the entrance flight is to change the
  /// viewer's tag before the pop: the timeline keeps its tag, no pair matches,
  /// no shuttle is built, and the media simply fades where it stands.
  bool fadeAwayOnClose = false;

  /// The tag this viewer shows for [event]: matching the timeline while open, and
  /// deliberately different once a close has begun. See [fadeAwayOnClose].
  String heroTag(Event event) =>
      fadeAwayOnClose ? 'fade-away:${event.eventId}' : event.eventId;

  /// Close the viewer as a fade. The tag change has to be in the widget tree
  /// before the route pops - `HeroController` reads the heroes of a route while
  /// it is popping, so a `setState()` in the same frame as the pop is too late -
  /// hence the one-frame wait. This is the only close path that keeps the Android
  /// back button working: `PopScope` hands the pop here.
  void fadeAwayAndPop() {
    if (fadeAwayOnClose) return;
    setState(() => fadeAwayOnClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void onKeyEvent(KeyEvent event) {
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        if (canGoBack) prevImage();
        break;
      case LogicalKeyboardKey.arrowRight:
        if (canGoNext) nextImage();
        break;
    }
  }

  Future<void> prevImage() async {
    await pageController.previousPage(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> nextImage() async {
    await pageController.nextPage(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
    );
    if (!mounted) return;
    setState(() {});
  }

  /// The page the viewer shows, kept here instead of read back from
  /// `pageController.page`.
  ///
  /// That read is what killed the viewer on a phone (`Bad state: No element`,
  /// roadmap T12). `PageController.page` asserts that a `PageView` is already
  /// attached, and in a release build Flutter strips the assert and evaluates
  /// `positions.first` on an empty list instead. Building the viewer reads it
  /// in the very first frame, before the `PageView` has laid out and registered
  /// its scroll position, so the counter threw the app out of `Scaffold`
  /// layout and the whole UI went blank.
  int _currentPage = 0;

  /// The page in view - what the viewer's `n / total` counter shows and what
  /// `currentEvent` resolves.
  int get currentIndex => _currentPage;

  Event get currentEvent => allEvents[_currentPage];

  bool get canGoNext => _currentPage < allEvents.length - 1;

  bool get canGoBack => _currentPage > 0;

  /// The `PageView` settled on [index]. Fires while the user swipes and when a
  /// `prevImage`/`nextImage` animation lands.
  void onPageChanged(int index) {
    final page = index.clamp(0, allEvents.length - 1);
    if (page == _currentPage) return;
    setState(() => _currentPage = page);
  }

  /// Forward this image to another room.
  void forwardAction() => showScaffoldDialog(
    context: context,
    builder: (context) =>
        ShareScaffoldDialog(items: [ContentShareItem(currentEvent.content)]),
  );

  /// Save this file with a system call.
  void saveFileAction(BuildContext context) => currentEvent.saveFile(context);

  /// Save this file with a system call.
  void shareFileAction(BuildContext context) => currentEvent.shareFile(context);

  @override
  void dispose() {
    focusNode.dispose();
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ImageViewerView(this);
}
