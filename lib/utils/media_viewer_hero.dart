// SPDX-FileCopyrightText: 2024 Phoenix Han <me@fluffyprod.com>
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:fluffychat/pages/chat/events/bubble_shape.dart';
import 'package:flutter/material.dart';

/// The media viewer's open and close flight (ROADMAP T12.1).
///
/// Telegram morphs the photo from its cell rect to the full-screen frame over
/// 250 ms on `CubicBezierInterpolator.DEFAULT` (`PhotoViewer.java:9228-9231`,
/// `CubicBezierInterpolator.java:11`) while its chrome fades in 150 ms behind
/// it (`PhotoViewer.java:17935-17950`). The rect part is what Flutter's `Hero`
/// already does. This file adds the two halves a plain `Hero` does not: the
/// corners rounding back to the cell's own radius during flight, and the
/// entrance ramps - background, then media, then chrome - so opening a photo
/// reads as one move instead of a cut with the buttons already on screen.
///
/// Owner instruction 2026-10-27 on this task: "hero transition - just make it
/// pretty, doesn't need to be exact." The curve and duration are Telegram's,
/// taken from their code; the ramp shape is our design choice, because
/// Telegram's own flight classes are not in the vendored snapshot (see
/// `docs/TELEGRAM_TARGET.md`, Media viewer section, Open point 1).
class TelegramViewerMotion {
  TelegramViewerMotion._();

  /// 250 ms, Telegram's flight body (`PhotoViewer.java:9230`).
  static const Duration flightDuration = Duration(milliseconds: 250);

  /// cubic-bezier(0.25, 0.1, 0.25, 1) = `CubicBezierInterpolator.DEFAULT`
  /// (`CubicBezierInterpolator.java:11`).
  static const Curve flightCurve = Cubic(0.25, 0.1, 0.25, 1);

  /// The page fades through black in 220 ms: out first, in second.
  static const Duration fadeDuration = Duration(milliseconds: 220);

  /// The close is **one** ramp of 200 ms: Telegram's gallery exit animates the
  /// backdrop drawable's alpha to 0, the media's alpha to 0 and off screen, and
  /// the container's alpha to 0 in a single `playTogether` set
  /// (`PhotoViewer.java:18473-18484`) at `setDuration(200)` (`:18515`). Our exit
  /// ran three clocks at once - the route's 220 ms fade, the Hero's 250 ms
  /// flight, and extended_image's 500 ms snap-back - which is a user's "the
  /// return animation is still a little janky" (2026-10-29).
  static const Duration closeDuration = Duration(milliseconds: 200);

  /// That animator set leaves Android's `ValueAnimator` default interpolator,
  /// `AccelerateDecelerateInterpolator`, which Flutter's nearest match is.
  static const Curve closeCurve = Curves.easeInOut;

  /// Telegram's chrome ramp: 150 ms (`PhotoViewer.java:17935-17950`, read
  /// straight off `PhotoViewCell.java:41-46` as `viewsEnterDuration`).
  static const Duration chromeDuration = Duration(milliseconds: 150);

  /// Chrome does not wait for the media. `PhotoViewCell.animateIn()` (`:56-65`)
  /// starts the media alpha ramp (220 ms), the counter alpha ramp and the views
  /// alpha + translationY ramp (150 ms) from one call, each with no delay; the
  /// only delay in that method belongs to the GIF play callback (`:81-90`).
  static const Duration chromeDelay = Duration.zero;

  /// The viewer shows the media at full bleed, corners square
  /// (`PhotoViewer.java:924` paints an opaque `#000000` behind it).
  static const double viewerCornerRadius = 0;

  /// Telegram's zoom band is 1.0 to **3.0** (`MIN_SCALE` / `MAX_SCALE`,
  /// `PhotoViewer.java:19246-19247`); the double tap targets exactly 3.0.
  static const double maxZoomScale = 3.0;

  /// A flight that carries no cell radius (a video, a sticker-sized image)
  /// starts square.
  static const double defaultCornerRadius = 0;
}

/// A `Hero` that morphs its corners from [cornerRadius] in the chat to square
/// in the viewer, on Telegram's curve and duration. Pass the radius the media
/// actually shows with in the timeline: a photo inside a bubble container uses
/// the bubble's radius, a mosaic tile inside an album container is square
/// (radius 0) because the container carries the corners.
Widget telegramHero({
  required String tag,
  required Widget child,
  double cornerRadius = TelegramViewerMotion.defaultCornerRadius,
}) {
  return Hero(
    tag: tag,
    flightShuttleBuilder:
        (context, animation, flightDirection, fromHeroContext, toHeroContext) {
          const to = TelegramViewerMotion.viewerCornerRadius;
          final from = cornerRadius;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Material(
              type: MaterialType.transparency,
              child: ValueListenableBuilder(
                valueListenable: animation,
                builder: (context, t, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(
                    Tween<double>(begin: from, end: to).transform(t),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: flightDirection == HeroFlightDirection.push
                      ? toHeroContext.widget
                      : fromHeroContext.widget,
                ),
              ),
            ),
          );
        },
    child: child,
  );
}

/// The timeline-side convenience: a media widget inside a Telegram bubble
/// container flies with that container's corner radius.
Widget telegramBubbleHero({required String eventId, required Widget child}) =>
    telegramHero(
      tag: eventId,
      cornerRadius: TelegramBubbleGeometry.cornerRadius,
      child: child,
    );

/// The route the chat uses to open the viewer: the fade and both durations live
/// here, so `Navigator.push` carries the whole entrance and exit.
///
/// It is a `PageRouteBuilder`, not a `MaterialPageRoute`, and that is a measured
/// constraint rather than a style choice. The route has to be **non-opaque**: an
/// opaque route tells the `Overlay` to stop painting the page below it once the
/// transition ends, and the viewer's own background is a scrim, so an opaque
/// route is what left a bare black field where the chat should be (user,
/// 2026-10-29: "telegram also shows the chat behind it instead of a black
/// screen"). `MaterialPageRoute` cannot be non-opaque - its own constructor
/// asserts it, and the gate run showed it:
/// `'opaque': is not true`, `material/page.dart:48`, thrown by every test that
/// opens the viewer. Flutter 3.47 also exports no `Route.setOpaque` (measured:
/// `The method 'setOpaque' isn't defined`). `PageRouteBuilder` takes `opaque`,
/// both durations and the transition slot.
///
/// Telegram keeps its chat under the gallery the same way: the backdrop is a
/// drawable whose alpha animates over a chat that stays drawn
/// (`PhotoViewer.java:924, 18473-18484`), not a layer that hides what is below.
class FadeThroughBlackPageRoute<T> extends PageRouteBuilder<T> {
  FadeThroughBlackPageRoute({required WidgetBuilder builder, super.settings})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        opaque: false,
        // The Hero flight reads these two durations, so the media's flight and
        // the page's fade cannot drift apart: open 220 ms, close one 200 ms ramp.
        transitionDuration: TelegramViewerMotion.fadeDuration,
        reverseTransitionDuration: TelegramViewerMotion.closeDuration,
        transitionsBuilder: fadeThroughBlackTransitions,
      );
}

/// Fades a widget in once, with an optional start delay - the viewer's
/// entrance ramps. Unlike `AnimatedOpacity` this has a defined first frame:
/// it starts hidden and plays on mount, so a viewer that opens never shows the
/// chrome before the media.
class EntranceFade extends StatefulWidget {
  const EntranceFade({
    super.key,
    required this.child,
    this.duration = TelegramViewerMotion.chromeDuration,
    this.delay = TelegramViewerMotion.chromeDelay,
    this.curve = TelegramViewerMotion.flightCurve,
  });

  final Widget child;
  final Duration duration;
  final Duration delay;
  final Curve curve;

  @override
  State<EntranceFade> createState() => _EntranceFadeState();
}

class _EntranceFadeState extends State<EntranceFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 0,
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _start = Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  Future<void>? _start;

  @override
  void dispose() {
    _start?.ignore();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: CurvedAnimation(parent: _controller, curve: widget.curve),
    child: widget.child,
  );
}

/// The viewer page transition: the chat fades out to black, the media page
/// fades in from black. Telegram's enter ramps are 220 ms for the media and
/// 150 ms for the chrome (`PhotoViewer.java:17963`, `:17935-17950`); the black
/// backdrop itself is opaque (`PhotoViewer.java:924`).
///
/// It is installed by `FadeThroughBlackPageRoute`, which every chat open site
/// pushes since T12.1.
Widget fadeThroughBlackTransitions(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  // Opening rides Telegram's default cubic, closing its accelerate-decelerate.
  // The direction comes off the animation itself, the way Flutter's own
  // transition builders read it.
  final reversing =
      animation.status == AnimationStatus.reverse ||
      animation.status == AnimationStatus.dismissed;
  final incoming = CurvedAnimation(
    parent: animation,
    curve: reversing
        ? TelegramViewerMotion.closeCurve
        : TelegramViewerMotion.flightCurve,
  );
  // Only this page fades. The page below is left alone on purpose: it is the
  // chat, and a user wants to see it behind the media and to have the media
  // fade back onto it when the viewer closes. The black sheet this method used
  // to paint over the outgoing route is what produced the black screen in the
  // middle of the return (`PhotoViewer.java:18473-18484` animates the
  // gallery's own backdrop alpha to 0 over the still-visible chat - it never
  // covers the chat with a second black layer).
  //
  // No Hero wrapper is needed here: Flutter 3.47 exports no public
  // `HeroTransition` widget (measured: analyze calls it an undefined name),
  // and the `HeroController` that `MaterialApp` installs drives the flight
  // from this route's own `transitionDuration` / `reverseTransitionDuration`.
  return FadeTransition(opacity: incoming, child: child);
}
