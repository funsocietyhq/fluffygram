// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';

/// Motion and placement numbers of the chat chrome (T4), named so the chat
/// widgets carry no inline magic numbers. Values come from
/// `verification/telegram-target.json` (`geometry`, `behaviors`) and from the
/// Telegram app's feel recorded in `docs/TELEGRAM_TARGET.md`.
abstract final class TelegramMotion {
  // --- swipe to reply (behaviors: "swipe-to-reply ... rubber band") ---

  /// The bubble follows the finger at half the finger speed: Telegram's
  /// rubber band, not a 1:1 drag.
  static const double swipeFingerDamping = 0.5;

  /// Snap back to rest after a released swipe that did not reach the
  /// threshold (`SwipeToReply.threshold`). Instant with animations off.
  /// The rubber band drag itself (`swipeFingerDamping`) is a direct finger
  /// response, not an animation, so it stays.
  static const Duration swipeSnapBackTime = Duration(milliseconds: 300);
  static Duration get swipeSnapBackDuration =>
      animationsEnabled ? swipeSnapBackTime : Duration.zero;
  static const Curve swipeSnapBackCurve = Curves.easeOutCubic;

  // --- jump to latest chevron (geometry: jump_to_latest_*) ---

  /// `jump_to_latest_diameter_dp` - the circle, not Material's 56dp FAB.
  static const double jumpToLatestSize = 40;

  /// `jump_to_latest_right_margin_dp` - from the edge of the chat column.
  static const double jumpToLatestRightMargin = 8;

  /// The circle sits this far above the top edge of the composer pill.
  static const double jumpToLatestAboveComposerGap = 11;

  /// The chevron inside the 40dp circle.
  static const double jumpToLatestChevronSize = 24;

  /// The circle scales up from this when it appears.
  static const double jumpToLatestHiddenScale = 0.6;

  // --- shared chrome fade ---

  /// Fade + scale of the jump-to-latest circle. `animation_ms` has no measured
  /// value in the target; this is the fork's one chrome duration (250ms).
  static Duration get chromeFadeDuration => animationDuration;
  static const Curve chromeFadeCurve = FluffyThemes.animationCurve;

  /// Telegram's "Animations" switch (`AppSettings.animationsEnabled`). With it
  /// off every motion this file gates runs in `Duration.zero`: the
  /// jump-to-latest fade + scale, the swipe-to-reply snap-back and the
  /// bubble/reaction size changes in `message.dart`. Scroll physics are never
  /// disabled - Telegram keeps scrolling when animations are off.
  static bool get animationsEnabled => AppSettings.animationsEnabled.value;

  /// The fork's one chrome duration, zero when `animationsEnabled` is off.
  static Duration get animationDuration =>
      animationsEnabled ? FluffyThemes.animationDuration : Duration.zero;
}

/// A chat timeline with no Material overscroll glow: Telegram draws no
/// overscroll indicator on Android (`behaviors`: "no overscroll glow").
/// Applied to the chat timeline only - see `chat_view.dart`.
class TelegramScrollBehavior extends MaterialScrollBehavior {
  const TelegramScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
