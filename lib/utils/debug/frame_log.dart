// SPDX-FileCopyrightText: 2026-Present Contributors to FluffyGram
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Build flag for the scroll telemetry build (ROADMAP T51). Built with
/// `--dart-define=FLUFFYGRAM_FRAMELOG=true`. Absent from every group build,
/// which is why nothing here is behind `kDebugMode`.
const kFluffyGramFrameLog = bool.fromEnvironment('FLUFFYGRAM_FRAMELOG');

/// Second flag, off by default: paints Flutter's two frame graphs on screen.
///
/// It has its own flag because the graphs are not free. They are repainted
/// every frame, and the capture this fork made with them on (26 windows, 1,224
/// frames, a user's Pixel) therefore measured the app plus the instrument.
/// A tall `raster` column in that capture is partly the instrument. With the
/// log path proven to reach the phone, the graphs buy nothing: the log is the
/// deliverable.
const kFluffyGramFrameScreen = bool.fromEnvironment('FLUFFYGRAM_FRAMESCREEN');

/// Writes the per-frame time split to the log, so a phone answers "is the UI
/// thread busy, or is the raster thread busy?" with one grep and no laptop
/// tooling.
///
/// `FrameTiming` comes from the engine, not from the debug layer, so this works
/// in a signed release build and installs over an installed app. The split is
/// the whole point: `buildDuration` is our Dart-side build, layout and paint
/// (widget code, text layout), `rasterDuration` is the GPU submission (the
/// renderer's cost). ROADMAP T51 has a user ruling that Impeller is fine
/// and Skia is worse, so a tall raster column points at our layers, not at the
/// renderer.
///
/// The frame budget is read from the display, not assumed. The first build
/// counted lateness against 16.667 ms (60 Hz) while a user's Pixel runs a
/// 120 Hz panel, which reported a smooth-looking 8% late for a build that can
/// only reach the 60 Hz cadence.
///
/// The sink is `print()`, not `dart:developer`'s `log()`: in an AOT release
/// build `log()` is delivered to the Dart VM service and nothing else, so the
/// lines never reach `logcat` - the first capture from a user's phone came
/// back with the build flag on and no telemetry in it, which is what taught
/// this. `print()` is what FluffyChat's own `Logs()` uses, and its lines do
/// show up under the `flutter` tag.
class FrameLog {
  FrameLog._();

  /// Frames per log line. Small enough that a 5 second flick produces several
  /// lines, large enough that one line is a stable average.
  static const int _window = 30;

  /// A window also closes this long after the last frame, so a one second
  /// scroll reports what it drew instead of waiting for frames that never
  /// come. Flutter renders on demand: a timeline at rest schedules no frames.
  static const Duration _quiet = Duration(milliseconds: 400);

  /// One 60 Hz frame, in microseconds. Used until [_start] reads the panel.
  static const int _budget60Us = 16667;

  static final List<FrameTiming> _batch = <FrameTiming>[];

  /// Wall clock of the previous timings delivery, and the cadence totals built
  /// from the gaps between deliveries.
  static int _lastReceiptUs = 0;
  static int _cadenceSumUs = 0;
  static int _cadenceFrames = 0;
  static Timer? _quietTimer;
  static int _budgetUs = _budget60Us;

  static void startIfEnabled() {
    if (!kFluffyGramFrameLog) {
      return;
    }
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    final hz = _refreshHz();
    if (hz != null && hz > 0) {
      _budgetUs = (1000000 / hz).round();
    }
    // The line a log needs to be read against. A capture with no SCROLLPERF
    // line at all means the flag was not compiled in; a capture with this line
    // and no window lines means no frames were drawn.
    // ignore: avoid_print - see the class doc: logcat only, in a release build.
    print(
      'SCROLLPERF enabled window=$_window quiet=${_quiet.inMilliseconds}ms '
      'refresh=${hz == null ? "?" : hz.toStringAsFixed(1)}Hz '
      'budget=${_budgetUs}us overlay=$kFluffyGramFrameScreen',
    );
  }

  /// The panel's refresh rate in Hz, or null when the platform hides it.
  static double? _refreshHz() {
    try {
      final displays = SchedulerBinding.instance.platformDispatcher.displays;
      if (displays.isEmpty) return null;
      return displays.first.refreshRate;
    } catch (_) {
      return null;
    }
  }

  static void _onTimings(List<FrameTiming> timings) {
    // Flutter 3.47 gives a `FrameTiming` no public frame-start timestamp, and
    // the engine delivers timings in batches, so a per-receipt clock measures
    // nothing (the first build of this printed cadence=0). What is measurable
    // is the wall clock between deliveries: the engine delivers as frames
    // complete, so the gap divided by the frames in it is the panel cadence.
    final now = DateTime.now().microsecondsSinceEpoch;
    if (_lastReceiptUs != 0 && timings.isNotEmpty) {
      final gap = now - _lastReceiptUs;
      if (gap > 0) {
        _cadenceSumUs += gap;
        _cadenceFrames += timings.length;
      }
    }
    _lastReceiptUs = now;
    _batch.addAll(timings);
    _quietTimer?.cancel();
    _quietTimer = Timer(_quiet, _flush);
    if (_batch.length < _window) {
      return;
    }
    _flush();
  }

  /// Emits the frames collected so far. Called on a full window and on the
  /// quiet timer.
  static void _flush() {
    _quietTimer?.cancel();
    if (_batch.length < 5) {
      _batch.clear();
      _cadenceSumUs = 0;
      _cadenceFrames = 0;
      return;
    }
    final batch = List<FrameTiming>.of(_batch);
    final cadenceSum = _cadenceSumUs;
    final cadenceFrames = _cadenceFrames;
    _batch.clear();
    _cadenceSumUs = 0;
    _cadenceFrames = 0;
    var buildMax = 0, buildSum = 0, rasterMax = 0, rasterSum = 0;
    var spanMax = 0, spanSum = 0;
    var lateFrames = 0, veryLateFrames = 0;
    for (final timing in batch) {
      final build = timing.buildDuration.inMicroseconds;
      final raster = timing.rasterDuration.inMicroseconds;
      final span = timing.totalSpan.inMicroseconds;
      buildSum += build;
      rasterSum += raster;
      spanSum += span;
      if (build > buildMax) buildMax = build;
      if (raster > rasterMax) rasterMax = raster;
      if (span > spanMax) spanMax = span;
      if (span > _budgetUs) lateFrames++;
      if (span > _budgetUs * 2) veryLateFrames++;
    }
    final n = batch.length;
    // Cadence in microseconds between frames. This is the number that maps to
    // what the eye calls smooth: `span` is busy time inside a frame, the gap
    // between frames is the panel's answer.
    final cadence = cadenceFrames > 0 ? cadenceSum ~/ cadenceFrames : 0;
    // ignore: avoid_print - see the class doc: logcat only, in a release build.
    print(
      'SCROLLPERF n=$n'
      ' ui_avg=${(buildSum / n).round()} ui_max=$buildMax'
      ' raster_avg=${(rasterSum / n).round()} raster_max=$rasterMax'
      ' span_avg=${(spanSum / n).round()} span_max=$spanMax'
      ' cadence=$cadence hz=${cadence > 0 ? (1000000 / cadence).toStringAsFixed(1) : "?"}'
      ' late=$lateFrames/$n pct=${(lateFrames * 100 / n).round()}'
      ' veryLate=$veryLateFrames',
    );
  }
}
