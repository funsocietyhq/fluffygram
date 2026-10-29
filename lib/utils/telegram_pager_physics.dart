// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:flutter/widgets.dart';

/// Telegram's paging rule for the media viewer, as a `ScrollPhysics`.
///
/// Telegram turns one page on one of two tests per direction
/// (`PhotoViewer.java:19315` and `:19319`, read per side of the translation):
///
/// * the drag passed **one third** of the viewport width, or
/// * the release fling is past **dp(650)**.
///
/// Below both, the page springs back. Both halves live in this file, which is
/// why the viewer must pass `pageSnapping: false` to its pager (see the note on
/// `createBallisticSimulation`).
///
/// The velocity unit is Flutter's own: pointer positions reach the gesture layer
/// in logical pixels, so `velocity.pixelsPerSecond` is dp/s and Telegram's
/// `dp(650)` needs no scaling. 1 dp = 1 unit here, 1706 of them per second on
/// a user's phone at 2.625 px/dp, which is what a real fling looks like.
///
/// Three Flutter API facts this file needed, so the next one does not re-derive
/// them: `ScrollPhysics.minFlingVelocity` has no setter a subclass can call
/// (`assignment_to_final_no_setter`), so it is overridden as a getter, and
/// `BouncingScrollPhysics` narrows it to a non-nullable `double`, so the override
/// must be `double`, not `double?`; `BouncingScrollPhysics.applyTo` returns
/// `BouncingScrollPhysics`, so an override must return that type or narrower; and
/// a constructor of an `@immutable` physics class must be `const`.
class TelegramPagerPhysics extends BouncingScrollPhysics {
  const TelegramPagerPhysics({super.parent});

  /// dp/s. Telegram's own fling threshold (`PhotoViewer.java:19319`).
  static const double flingVelocityDp = 650;

  /// Of the viewport width: how far the drag has to travel for the page to turn
  /// without a fling (`PhotoViewer.java:19315`: `translationX < minX - width / 3`).
  static const double turnDragFraction = 1 / 3;

  /// Handed to the pager's own drag recognizers, which copy the fling limits off
  /// the physics object they are given (`extended_image-10.1.0/lib/src/gesture/
  /// page_view/gesture_page_view.dart:259-261` horizontal, `:284-286` vertical).
  /// Flutter's default is `kMinFlingVelocity`, 210, which is why a gentle flick
  /// paged FluffyGram where Telegram keeps the photo put.
  @override
  double get minFlingVelocity => flingVelocityDp;

  /// Telegram's commit point, in place of Flutter's nearest-page snap.
  ///
  /// `PageScrollPhysics` - the physics Flutter snaps a `PageView` with - commits
  /// to whichever page is nearest, so a drag has to cross **half** the viewport.
  /// Telegram commits at **one third** (`:19315`). On a user's 411 dp-wide
  /// phone that is 137 dp against 205 dp: a deliberate medium swipe springs back,
  /// which is the "janky" swipe they reported.
  ///
  /// This override only runs if our object is the OUTERMOST physics on the scroll
  /// position, because `createBallisticSimulation` is decided by the outer object
  /// of the chain. `ExtendedImageGesturePageView` puts `NeverScrollableScrollPhysics`
  /// outside what we hand it (`gesture_page_view.dart:52-54`, whose
  /// `_defaultScrollPhysics` is that class - it overrides only
  /// `shouldAcceptUserOffset`, so everything else still reaches us), and its inner
  /// `GesturePageView` puts Flutter's `PageScrollPhysics` outside that **only when
  /// `pageSnapping` is true** (`widgets/page_view.dart:333`). So the viewer passes
  /// `pageSnapping: false` and this method owns the commit; with snapping left on,
  /// `PageScrollPhysics` answers first and this file only supplies the fling
  /// limits through the parent chain.
  ///
  /// Springing back is explicit here (the `else` branch), not inherited: the base
  /// `ScrollPhysics.createBallisticSimulation` returns null below its fling gate,
  /// which would leave the pager parked between two photos.
  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // viewportFraction is 1.0 here - `ExtendedPageController` is built with the
    // default - so one pitch is one viewport, and `ScrollMetrics` does not carry
    // the fraction to multiply by anyway.
    final pitch = position.viewportDimension;
    if (pitch <= 0) return super.createBallisticSimulation(position, velocity);

    // Which page the finger left. A deliberate drag can cross half a pitch, so
    // the nearest boundary is the wrong anchor for a moving finger: anchoring on
    // it and then adding the fling turned TWO pages, which is what the gate caught
    // (260 dp of swipe landed the counter on `3 / 5`). While the recognizer reports
    // a velocity, the direction of travel says which side the finger came from; a
    // sub-fling release arrives with velocity 0 (extended_image's recognizer emits
    // `DragEndDetails()` below its fling gate), and then the nearest page is right.
    final page = position.pixels / pitch;
    final anchor = velocity > 0
        ? page.floorToDouble()
        : velocity < 0
        ? page.ceilToDouble()
        : page.roundToDouble();
    final from = anchor * pitch;
    final dragged = position.pixels - from;
    final turn = pitch * turnDragFraction;

    var target = from;
    if (dragged > turn) {
      target = from + pitch;
    } else if (dragged < -turn) {
      target = from - pitch;
    } else if (velocity >= flingVelocityDp) {
      target = from + pitch;
    } else if (velocity <= -flingVelocityDp) {
      target = from - pitch;
    }
    // Under both tests `target` is still `from`: the page springs back.

    // Off the end of the strip: leave it to the bounce, as Telegram does at the
    // first and last photo.
    if (target < position.minScrollExtent ||
        target > position.maxScrollExtent) {
      return super.createBallisticSimulation(position, velocity);
    }
    if (target == from && dragged == 0) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }

  @override
  TelegramPagerPhysics applyTo(ScrollPhysics? ancestor) =>
      TelegramPagerPhysics(parent: buildParent(ancestor));
}
