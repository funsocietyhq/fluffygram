// SPDX-FileCopyrightText: 2026-Present Contributors to FluffyGram
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Telegram's own download ring, drawn in place of FluffyChat's
/// `CircularProgressIndicator.adaptive` (T83).
///
/// Every number is Telegram's, from the ring class the photo viewer puts over a
/// video: `RadialProgressView.java:71` sets the stroke to `dp(3)`, and
/// `PhotoViewer.java:6140-6143` adds that view with `setProgressColor(0xffffffff)`
/// over `R.drawable.circle_big` in a `createFrame(54, 54, Gravity.CENTER)`, so the
/// box is 54 dp and the arc is white. The circle path is inset by `dp(5) +
/// strokeWidth / 2` (`RoundVideoProgressView.java:32-33`) and the unfilled part of
/// the ring is the same stroke at 20 % of white (`RoundVideoProgressView.java:34,66-69`
/// `configureStroke(backgroundPaint, 0.20f)`).
///
/// While the fraction is unknown Telegram does not spin a fixed arc: it rotates the
/// whole ring once per `rotationTime = 2000` ms and breathes the arc length between
/// 4 deg and 270 deg every `risingTime = 500` ms, adding 270 deg of offset at each
/// rising-to-falling turn (`RadialProgressView.java:41-42,133-135,151-169`). That
/// maths is ported here rather than approximated: `accelerate` and `decelerate` are
/// Android's default-factor interpolators, which are `t^2` and `1 - (1 - t)^2`.
class TelegramProgressRing extends StatefulWidget {
  /// The filled fraction 0..1, or null while the size is unknown: Telegram then
  /// runs its rotating, breathing ring.
  final double? progress;

  final double size;

  const TelegramProgressRing({super.key, this.progress, this.size = 54.0});

  @override
  State<TelegramProgressRing> createState() => _TelegramProgressRingState();
}

class TelegramProgressRingGeometry {
  /// `PhotoViewer.java:6143` `createFrame(54, 54, Gravity.CENTER)`.
  static const double boxSize = 54.0;

  /// `RadialProgressView.java:71` and `RoundVideoProgressView.java:32` dp(3).
  static const double strokeWidth = 3.0;

  /// `RoundVideoProgressView.java:33` `dp(5) + strokeWidth * 0.5f`.
  static const double ringInset = 5.0 + strokeWidth / 2.0;

  /// `RadialProgressView.java:41` `rotationTime = 2000` ms.
  static const int rotationTimeMs = 2000;

  /// `RadialProgressView.java:42` `risingTime = 500` ms.
  static const int risingTimeMs = 500;

  /// `RadialProgressView.java:158-160`: the arc spans `4 + 266 * accelerate(t)`
  /// while rising, so 4 deg at rest and 270 deg at the turn.
  static const double arcBaseDeg = 4.0;
  static const double arcGrowDeg = 266.0;

  /// `RadialProgressView.java:164` `radOffset += 270`.
  static const double turnOffsetDeg = 270.0;

  /// White progress arc (`PhotoViewer.java:6140` `setProgressColor(0xffffffff)`)
  /// and its 20 %-white background ring (`RoundVideoProgressView.java:34`).
  static const Color progressColor = Color(0xFFFFFFFF);
  static const Color trackColor = Color(0x33FFFFFF); // alpha 51 = round(255 * 0.20)

  /// The sweep angle in degrees of the indeterminate ring after [elapsedMs], and
  /// the rotation its start angle carries. Exposed for the gate test: this is the
  /// only place the two Android interpolators and the turn offset meet.
  static ({double startDeg, double sweepDeg}) indeterminateArc(int elapsedMs) {
    final cycle = elapsedMs % (2 * risingTimeMs);
    final rising = cycle < risingTimeMs;
    final t = cycle / risingTimeMs.toDouble();
    final double sweepDeg;
    if (rising) {
      // Android AccelerateInterpolator, factor 1: t^2.
      sweepDeg = arcBaseDeg + arcGrowDeg * (t * t);
    } else {
      // Android DecelerateInterpolator, factor 1: 1 - (1 - t)^2. Telegram's falling
      // branch is `4 - 270 * (1 - decelerate(t))` (`RadialProgressView.java:160-161`),
      // which starts at the -266 deg it snaps to at the turn (`:165`) and shrinks to
      // 4 deg, so it is drawn against the direction of travel.
      final u = (cycle - risingTimeMs) / risingTimeMs.toDouble();
      final decelerate = 1 - (1 - u) * (1 - u);
      sweepDeg = arcBaseDeg - 270.0 * (1 - decelerate);
    }
    // One full turn per rotationTime, plus 270 deg for every completed rising turn.
    final turns = elapsedMs / rotationTimeMs.toDouble();
    final completedRisingTurns = ((elapsedMs + risingTimeMs) ~/ (2 * risingTimeMs))
        .toDouble();
    final startDeg = -90.0 + 360.0 * turns + turnOffsetDeg * completedRisingTurns;
    return (startDeg: _wrap(startDeg), sweepDeg: sweepDeg);
  }

  static double _wrap(double deg) {
    var d = deg % 360.0;
    if (d < 0) d += 360.0;
    return d;
  }
}

class _TelegramProgressRingState extends State<TelegramProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: TelegramProgressRingGeometry.rotationTimeMs),
  );

  int _elapsedMs = 0;
  double _baseMs = 0;
  double _lastMs = 0;

  @override
  void initState() {
    super.initState();
    if (widget.progress == null) _spin.repeat();
    _spin.addListener(() {
      // One repeat is one rotation, so add a rotation each time the controller
      // wraps: that keeps Telegram's 500 ms rising/falling cycle in phase with the
      // 2000 ms turn instead of letting it drift with the frame rate.
      final ms = _spin.value * TelegramProgressRingGeometry.rotationTimeMs;
      if (ms < _lastMs) _baseMs += TelegramProgressRingGeometry.rotationTimeMs;
      _lastMs = ms;
      setState(() => _elapsedMs = (_baseMs + ms).round());
    });
  }

  @override
  void didUpdateWidget(TelegramProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress == null) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    if (progress != null) {
      return SizedBox(
        width: TelegramProgressRingGeometry.boxSize,
        height: TelegramProgressRingGeometry.boxSize,
        child: CustomPaint(
          painter: _TelegramRingPainter(
            startDeg: -90.0,
            // `RoundVideoProgressView.java:69` `drawArc(arcBounds, -90f, progress * 360f)`.
            sweepDeg: progress.clamp(0.0, 1.0) * 360.0,
          ),
        ),
      );
    }
    final arc = TelegramProgressRingGeometry.indeterminateArc(_elapsedMs);
    return SizedBox(
      width: TelegramProgressRingGeometry.boxSize,
      height: TelegramProgressRingGeometry.boxSize,
      child: CustomPaint(
        painter: _TelegramRingPainter(startDeg: arc.startDeg, sweepDeg: arc.sweepDeg),
      ),
    );
  }
}

class _TelegramRingPainter extends CustomPainter {
  final double startDeg;
  final double sweepDeg;

  const _TelegramRingPainter({required this.startDeg, required this.sweepDeg});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = TelegramProgressRingGeometry.strokeWidth
      ..strokeCap = StrokeCap.round // RadialProgressView.java:70 setStrokeCap(ROUND)
      ..color = TelegramProgressRingGeometry.trackColor;
    // The ring path sits inside the box by dp(5) + strokeWidth / 2 on every side.
    const inset = TelegramProgressRingGeometry.ringInset;
    final rect = Rect.fromLTWH(inset, inset, size.width - 2 * inset, size.height - 2 * inset);
    canvas.drawOval(rect, stroke);
    if (sweepDeg.abs() < 0.5) return;
    canvas.drawArc(
      rect,
      startDeg * math.pi / 180.0,
      sweepDeg * math.pi / 180.0,
      false,
      stroke..color = TelegramProgressRingGeometry.progressColor,
    );
  }

  @override
  bool shouldRepaint(_TelegramRingPainter old) =>
      old.startDeg != startDeg || old.sweepDeg != sweepDeg;
}
