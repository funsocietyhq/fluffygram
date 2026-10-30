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
import 'dart:math' as math;

import 'package:chewie/chewie.dart';
import 'package:fluffychat/pages/image_viewer/telegram_progress_ring.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

// Every geometry number below is quoted from `the measurement log`, the
// section "T86 - the video viewer's seek bar, Telegram **Android** numbers",
// which carries the Telegram Android source line each one came from
// (`ui/Components/VideoPlayerSeekBar.java` and its call site in
// `ui/PhotoViewer.java:9591-9685`). ROADMAP T63, T80, T86. The iOS numbers an
// earlier revision of this file used are superseded: a user's phone is
// Android, and Telegram Android's bar has a play-head dot and a 2 dp resting
// line, which iOS's has not.

/// The line while the chrome is **shown** - `transitionProgress == 0`, the
/// `lerp` source at `VideoPlayerSeekBar.java:344-345`: `lineHeight = dp(4)`,
/// centred in the band (`(height -/+ lineHeight) / 2`).
///
/// T86 recorded this pair as rest-vs-pressed. It is not: `pressed` changes only
/// the play-head radius (`:407` `newRad = dp(pressed ? 8 : 6)`), and
/// `transitionProgress` is driven by the chrome ramp - `PhotoViewer.java:3662`
/// calls `setTransitionProgress(1f - progress)` while the controls fade. So the
/// fat centred 4 dp bar is the state you see and aim at, and the hairline is
/// what survives after the 3 s fade. A user's a build report - "the video
/// player doesn't show any controls" (`the reference capture`) - is
/// this pair shipped the wrong way round: we kept the hairline on screen.
const _scrubLineHeightShown = 4.0; // VideoPlayerSeekBar.java:76

/// The line once the chrome has faded: `smallLineHeight = dp(2)`, sitting 3 dp
/// above the band's bottom (`height - dp(3) - smallLineHeight`), and its ends
/// run out to the 2 dp padding.
const _scrubLineHeightHidden = 2.0; // VideoPlayerSeekBar.java:77

/// The control band at the bottom of the video, and the minimum touch height:
/// `yOffset = size.height - 44.0`, `minHeightDiff = 44.0 - hitTestRect.height`.
///
/// the measurement log:169 (ChatVideoGalleryItemScrubberView.swift:365-368, 422)
const _scrubBandHeight =
    48.0; // VideoPlayerSeekBar's host: PhotoViewer.java:9592

/// Telegram accepts a tap on the media only inside a square of `dp(100)` at its
/// centre (`PhotoViewer.java:20862-20864`), and inside that square a video tap
/// plays or pauses (`:20921-20926` `manuallyPaused = true; toggleVideoPlayer()`).
/// Outside it the same tap only toggles the chrome (`:20932-20934`).
const _playTapSide = 100.0;

/// Bar insets: 58 pt at each side, growing to `min(100.0, 16.0 + textWidth +
/// 8.0)` once the time string is longer than 4 characters, so the bar never
/// runs under the time labels.
///
/// the measurement log:167 (ChatVideoGalleryItemScrubberView.swift:349-362)
/// The bar's bottom edge sits 3 dp above the band's bottom at rest
/// (`rect.bottom = height - dp(3) - smallLineHeight`, `VideoPlayerSeekBar.draw()`).
const _scrubBottomInset = 3.0;

/// `setHorizontalPadding(dp(2))` (`PhotoViewer.java:9655`); at rest each end of
/// the bar is inset by padding + half the thumb, so the 12 dp dot never overruns
/// the edge, and expanded it runs to 2 dp from each edge.
const _scrubHorizontalPadding = 2.0;
const _thumbWidth = 24.0; // VideoPlayerSeekBar.java:97
const _scrubEndInset = _scrubHorizontalPadding + _thumbWidth / 2; // = 14 dp

/// The play-head dot overhangs the band by 2 dp in the hidden state: the line's
/// bottom edge is 3 dp above the band, its centre 4 dp, and the dot's radius is
/// 6 dp, so it reaches 2 dp below the band's own rect. Telegram's `View` group
/// does not clip; a Flutter `Stack` clips at `Clip.hardEdge` by default, which
/// is what cut the dot off for a user (measured on
/// `the reference capture`: the dot's last row at y 2287 px, the
/// picture's bottom edge at 2288 px). The band is lifted by that overhang
/// instead of the inset being changed - every Telegram number stays intact.
const _thumbOverhang = 2.0;

/// The play/pause control's box: `PhotoProgressView` is
/// `private int size = dp(64)`, drawn as one square over the middle of the
/// picture. the measurement log, "T101".
const _playPauseBoxSize = 64.0; // PhotoViewer.java:2489

/// The glyph inside that box: `playPauseDrawable = new PlayPauseDrawable(28)`.
const _playPauseGlyphSize = 28.0; // PhotoViewer.java:2512

/// The clock the play <-> pause shape change runs on:
/// `playPauseDrawable.setDuration(200)`.
const _playPauseMorph = Duration(milliseconds: 200); // PhotoViewer.java:2513

/// Telegram's skip step is **10 s**: `current += 10000` in the right third of the
/// width, `current -= 10000` in the left third (`onDoubleTap`). The buttons that
/// carry it are ours - Telegram has no permanent skip buttons in the gallery.
const _skipSeconds = 10; // PhotoViewer.java:21001,21003

/// Telegram's double-tap seek splits the picture in thirds: `x < width * 0.33f`
/// seeks back 10 s, `x > width * 0.66f` seeks forward 10 s (`PhotoViewer.java:
/// 20985-21021`). The middle third keeps the single tap's rules, so a double tap
/// there behaves like the tap under it.
const _skipZoneFraction = 1.0 / 3.0;

/// Telegram's skip feedback, `VideoForwardDrawable`: a 32 dp drawable
/// (`:291,296`) whose filled circle reaches alpha 80 of 255 (`:164`) and whose
/// time string is a 12 sp centred text (`:57`), one shot over 800 ms
/// (`animationProgress += dt / 800.0f`, `:237`), fading in over the first 30 %
/// of the run and out over the last 30 % (`:163-168`).
const _skipMarkCircle = 32.0; // VideoForwardDrawable.java:291
const _skipMarkTextSize = 12.0; // VideoForwardDrawable.java:57
const _skipMarkCircleAlpha = 80.0 / 255.0; // VideoForwardDrawable.java:164
const _skipMarkRun = Duration(
  milliseconds: 800,
); // VideoForwardDrawable.java:237
const _skipMarkBoxWidth = 64.0;
const _skipMarkBoxHeight = 52.0;

/// Telegram accepts the double-tap seek only on a clip longer than 15 s, and
/// forward only while more than 10 s remain (`canDoubleTapSeekVideo`,
/// `PhotoViewer.java:20972-20982`). A double tap that fails the gate falls back
/// to the single tap's behaviour.
const _skipMinDuration = Duration(seconds: 15); // PhotoViewer.java:20981

/// The bar gives way to the time label: `videoPlayerSeekbar.setSize(
/// getMeasuredWidth() - dp(2 + 14) - size - extraWidth, ...)` where `size` is
/// the measured width of the duration string written twice (`:3618,3624`).
const _scrubTimeGap = 2.0 + 14.0;

/// The play-head dot: `currentRadius = dp(6)` at rest, `dp(pressed ? 8 : 6)`
/// while the finger is down (`VideoPlayerSeekBar.draw()`).
const _thumbRadius = 6.0;
const _thumbRadiusPressed = 8.0;

/// Time labels: `Font.regular(13.0)`, drawn 14 pt from each edge
/// (`leftTimestampOffset = rightTimestampOffset = 14.0`).
///
/// the measurement log:168 (ChatVideoGalleryItemScrubberView.swift:354-363, 371-372)
// T104 . The
// Telegram gallery capture `the reference capture` measures the time
// label at x 831..1044 px = dp 316.6..397.7, y 2282..2310 px = dp 869.3..880.0,
// digit height 11.0 dp and 13.3 dp from the right edge (1 dp = 2.625 px). A
// digit cap of 11 dp is a 16 sp face (Roboto digits sit at 0.71 em), and the
// label's top sits 4 dp **above** the 48 dp band, so the top inset is negative.
const _timestampFontSize = 16.0;
const _timestampTopInset = -6.0;
const _timestampRightInset = 13.0;

/// Track and buffering, Telegram Android's `setColors(background, cache, ...)`:
/// `0x33ffffff` for both.
/// the measurement log:171 (ChatVideoGalleryItemScrubberView.swift:18-20, 406-408)
const _scrubTrackAlpha = 0.2; // 0x33ffffff - PhotoViewer.java:9656
const _scrubBufferedAlpha = 0.2; // 0x33ffffff - PhotoViewer.java:9656

/// Chrome fades: `0.2, .easeInOut` for the timestamps, `0.3, linear` for the
/// scrubber background.
///
/// the measurement log:172 (ChatVideoGalleryItemScrubberView.swift:171-189)
const _timestampsFade = Duration(milliseconds: 200);
const _scrubBarFade = Duration(milliseconds: 300);

/// A video of 30 s or less hides its bar with the rest of the chrome; a longer
/// video keeps the bar laid out (`collapsed = false`).
///
/// the measurement log:173 (ChatVideoGalleryItemScrubberView.swift:179-190)

const _timestampStyle = TextStyle(
  fontSize: _timestampFontSize,
  fontWeight: FontWeight.w400,
  color: Colors.white,
);

double _clamp01(double value) =>
    value < 0.0 ? 0.0 : (value > 1.0 ? 1.0 : value);

/// `0:07`, `12:34`, `1:02:03` - the shape the label width reserve is built for.
String _formatTimestamp(Duration time) {
  final hours = time.inHours;
  final minutes = time.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = time.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// How wide one timestamp string draws in [_timestampStyle] - Telegram's
/// `videoPlayerTime.getPaint().measureText(...)` (`PhotoViewer.java:3618`), the
/// number that shortens the seek bar so the two never overlap.
double _textWidth(String text) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: _timestampStyle),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

/// Where a skip lands. Telegram's clamp is the one from its 10 s double-tap seek:
/// `if (current > total) current = total;` and `if (current < 0) ... current = 0;`
/// (`PhotoViewer.java:21005-21011`), so never below 0 and never past the duration.
///
/// Telegram also refuses a backward seek that would start below -9000 ms
/// (`apply = false`, `:21007-21009`); this fork floors at 0 instead - that rule
/// protects Telegram's one-shoot chevron overlay, and a button that silently does
/// nothing at the start of a clip reads as a broken button. With no duration
/// there is nothing to skip into, so the answer is the start.
Duration telegramSeekTarget(
  Duration position,
  Duration duration,
  int stepSeconds,
) {
  if (duration.inMilliseconds <= 0) return Duration.zero;
  final target = position.inMilliseconds + stepSeconds * 1000;
  if (target <= 0) return Duration.zero;
  if (target >= duration.inMilliseconds) return duration;
  return Duration(milliseconds: target);
}

/// Telegram's video chrome, drawn over Chewie's playback engine (ROADMAP T63).
///
/// Chewie keeps the engine: this widget is the `ChewieController.customControls`
/// swap for its Material `AdaptiveControls`. It reads `position`, `duration`,
/// `isPlaying`, `buffering` and the buffered ranges off the player controller in
/// the tree and writes back with `play`, `pause` and `seekTo`. Nothing in the
/// playback, streaming or dispose path of `video_player.dart` changes.
class TelegramVideoControls extends StatefulWidget {
  const TelegramVideoControls({super.key});

  @override
  State<TelegramVideoControls> createState() => _TelegramVideoControlsState();
}

class _TelegramVideoControlsState extends State<TelegramVideoControls> {
  ChewieController? _chewie;
  VideoPlayerController? _subscribed;
  VideoPlayerValue? _value;
  Timer? _hideTimer;
  bool _chromeVisible = true;
  bool _dragging = false;
  double _dragFraction = 0.0;

  /// Where the last skip landed, for the `+10 s` / `-10 s` mark: null once the
  /// mark has faded.
  Offset? _skipAt;
  bool _skipForward = true;

  /// Bumped per skip so the mark's 800 ms run restarts on a second skip.
  int _skipSeq = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chewie = ChewieController.of(context);
    _chewie = chewie;
    final video = chewie.videoPlayerController;
    if (!identical(video, _subscribed)) {
      _subscribed?.removeListener(_onVideoChanged);
      _subscribed = video;
      video.addListener(_onVideoChanged);
      _value = video.value;
    }
    _showChrome();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _subscribed?.removeListener(_onVideoChanged);
    _subscribed = null;
    super.dispose();
  }

  void _onVideoChanged() {
    final video = _subscribed;
    if (!mounted || video == null) return;
    setState(() => _value = video.value);
  }

  void _showChrome() {
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    final chewie = _chewie;
    if (chewie == null) return;
    _hideTimer = Timer(chewie.hideControlsTimer, () {
      if (!mounted || _dragging) return;
      setState(() => _chromeVisible = false);
    });
  }

  /// Telegram splits one tap on a video page: inside the `dp(100)` square at the
  /// media's centre it plays or pauses, anywhere else it only brings the chrome
  /// back (`PhotoViewer.java:20862-20864`, `:20921-20926`, `:20932-20934`). The
  /// centre square is where the play glyph sits, so the glyph is also the target.
  void _handleVideoTap(Offset localPosition, Size boxSize) {
    final centre = Offset(boxSize.width / 2, boxSize.height / 2);
    if ((localPosition - centre).distance <= _playTapSide / 2) {
      _playPause();
      return;
    }
    if (_chromeVisible) {
      _hideTimer?.cancel();
      setState(() => _chromeVisible = false);
      return;
    }
    _showChrome();
  }

  void _playPause() {
    final chewie = _chewie;
    final value = _value;
    if (chewie == null || value == null) return;
    if (value.isPlaying) {
      unawaited(chewie.pause());
      _hideTimer?.cancel();
      if (!_chromeVisible) setState(() => _chromeVisible = true);
      return;
    }
    final isFinished =
        value.duration.inSeconds > 0 && value.position >= value.duration;
    if (isFinished) unawaited(chewie.seekTo(Duration.zero));
    unawaited(chewie.play());
    _showChrome();
  }

  /// The 10 s skip. The step and the clamp are Telegram's (`PhotoViewer.java:
  /// 21000-21011`); the buttons are this fork's (T101). The seek goes through the
  /// same `ChewieController` the scrub band writes to - `video_player.dart` owns
  /// the `VideoPlayerController` and needs no new seam.
  void _skip(int stepSeconds, [Offset? at]) {
    final chewie = _chewie;
    final value = _value;
    if (chewie == null || value == null) return;
    unawaited(
      chewie.seekTo(
        telegramSeekTarget(value.position, value.duration, stepSeconds),
      ),
    );
    _skipAt = at;
    _skipForward = stepSeconds > 0;
    _skipSeq++;
    _showChrome();
  }

  /// Telegram's double-tap seek (`PhotoViewer.java:20985-21021`): `x < width / 3`
  /// back 10 s, `x >= width / 3 * 2` forward 10 s, the clamp `current > total ->
  /// total` and `current < 0 -> 0` (`:21001-21009`). A user asked for this
  /// form of the skip in place of the two buttons build 69 shipped (2026-10-30:
  /// "also yes, use telegram's double tap skip"). A double tap outside both
  /// thirds, or on a clip `canDoubleTapSeekVideo` refuses, behaves as the single
  /// tap under it.
  void _handleVideoDoubleTap(Offset localPosition, Size boxSize) {
    final value = _value;
    if (boxSize.width <= 0 || value == null) return;
    final seekable =
        value.duration > _skipMinDuration || value.duration.inMilliseconds == 0;
    final zone = boxSize.width * _skipZoneFraction;
    if (localPosition.dx < zone) {
      if (seekable) {
        _skip(-_skipSeconds, localPosition);
        return;
      }
    } else if (localPosition.dx >= boxSize.width - zone) {
      if (seekable &&
          value.duration - value.position >
              const Duration(seconds: _skipSeconds)) {
        _skip(_skipSeconds, localPosition);
        return;
      }
    }
    _handleVideoTap(localPosition, boxSize);
  }

  void _onScrubStart(double fraction) {
    _hideTimer?.cancel();
    setState(() {
      _dragging = true;
      _dragFraction = fraction;
    });
  }

  void _onScrubUpdate(double fraction) {
    setState(() => _dragFraction = fraction);
  }

  void _onScrubEnd() {
    if (!_dragging) return;
    final chewie = _chewie;
    final value = _value;
    if (chewie != null && value != null && value.duration.inMilliseconds > 0) {
      unawaited(chewie.seekTo(value.duration * _dragFraction));
    }
    setState(() => _dragging = false);
    _startHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    if (value == null) return const SizedBox.shrink();

    final durationMs = value.duration.inMilliseconds;
    final played = _dragging
        ? _dragFraction
        : (durationMs <= 0 ? 0.0 : value.position.inMilliseconds / durationMs);
    final buffered = (durationMs <= 0 || value.buffered.isEmpty)
        ? 0.0
        : value.buffered.last.end.inMilliseconds / durationMs;
    // Telegram's only rule for the scrub band: it is hidden while the duration
    // is unknown, and by nothing else (`ChatVideoGalleryItemScrubberView.swift
    // :117-134` - `hideWhenDurationIsUnknown` is the one `isHidden` driver, and
    // the bar's two timestamps hide and show with it, never separately).
    // Playback never folds it away. The `_keepBarSeconds = 30` rule this
    // replaces is why a user saw no scrubber on a 28 s clip (build 57,
    // 2026-10-29): the chrome's 3 s hide timer (`chewie.hideControlsTimer`)
    // took the bar with it for every clip under 30 s, and left it on for a 31 s
    // one. A length cut that flips a control's visibility at 30 s is not
    // Telegram's behaviour.
    // What the 3 s fade takes away is the fat, aimable form and the time label:
    // Telegram's chrome ramp drives `transitionProgress`, so the bar thins to
    // its 2 dp hairline and the timestamp fades out with the rest of the chrome
    // (`PhotoViewer.java:3655,3662`). The bar itself never disappears.
    final shown = _dragging || _chromeVisible;
    final timeText =
        '${_formatTimestamp(value.position)} / '
        '${_formatTimestamp(value.duration)}';
    // The bar's right end is reserved with the DURATION string written twice,
    // so the layout never re-flows as the position counts up
    // (`PhotoViewer.java:3618`).
    final timeReserveText =
        '${_formatTimestamp(value.duration)} / '
        '${_formatTimestamp(value.duration)}';

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) =>
                _handleVideoTap(d.localPosition, context.size ?? Size.zero),
            // Telegram's skip is a double tap, so it belongs on the same
            // detector as the tap: one recognizer pair resolves tap vs double
            // tap, and a second detector over the picture would contest the
            // arena with the single tap below it.
            onDoubleTapDown: (d) => _handleVideoDoubleTap(
              d.localPosition,
              context.size ?? Size.zero,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        if (_skipAt != null)
          // The skip's mark at the finger: Telegram's press-and-hold skip draws
          // a chevron and a ring while the finger is down
          // (`PhotoViewer.java:1165-1213`); a double tap has no held finger, so
          // the mark is this fork's and runs on `_skipFeedbackTime`.
          Positioned(
            left: _skipAt!.dx - _skipMarkBoxWidth / 2,
            top: _skipAt!.dy - _skipMarkBoxHeight / 2,
            child: IgnorePointer(
              child: _SkipMark(forward: _skipForward, sequence: _skipSeq),
            ),
          ),
        if (value.isBuffering)
          // Telegram's ring again, centred over the picture: the same
          // `RadialProgressView` the photo viewer adds at `PhotoViewer.java:6139-6143`,
          // running its 2000 ms turn with the 500 ms arc breath (`RadialProgressView.java:41-42,133-135`).
          const Center(child: TelegramProgressRing()),
        // The play/pause control: Telegram's `PhotoProgressView` box of dp(64)
        // with a 28 dp glyph inside that morphs play into pause over 200 ms
        // (`PhotoViewer.java:2489,2512-2513`). Which glyph shows is Telegram's
        // state rule - `PROGRESS_PLAY -> setPause(false)`, `PROGRESS_PAUSE ->
        // setPause(true)` (`:2587-2595`) - so a paused video carries the
        // triangle and a playing one the two bars.
        //
        // The pause half is **this fork's**. Telegram hands the video in view
        // `PROGRESS_NONE` while it plays and `PROGRESS_PLAY` once it is paused
        // (`:10295,10303`) - `PROGRESS_PAUSE` is the state of a video that is not
        // the page in view - so it paints nothing over a clip the user is
        // watching. A user's finding is exactly that (2026-10-30: "there's no
        // pause, skip forward, or skip backward buttons for videos"), so the
        // pause glyph ships on Telegram's geometry and Telegram's state rule, and
        // fades with the chrome like the rest of the control (`:10296`). It is
        // inside the `dp(100)` centre square, which is where Telegram's own tap
        // acts on these two states (`:20929`).
        //
        // The disc the glyph sits on (`R.drawable.circle_big`, combined with the
        // drawable at `PhotoViewer.java:2515`) is not in the vendored tree -
        // `res/drawable` sits outside the sparse checkout - so its fill comes
        // from pixels: in a user's capture `the reference capture`
        // (1 dp = 2.625 px) the disc darkens the sky behind it to exactly 0.60x
        // (row y 1110: #C5DAEE outside, #76828E across the disc span x 491..589),
        // which is **black at alpha 0.40**, and its diameter measures 65 dp - the
        // `dp(64)` box of the control itself (`:2489`).
        Center(
          child: AnimatedOpacity(
            opacity: shown ? 1.0 : 0.0,
            duration: _timestampsFade,
            curve: Curves.easeInOut,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _playPause,
              child: SizedBox(
                width: _playPauseBoxSize,
                height: _playPauseBoxSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.40),
                  ),
                  // The morph, ported: Telegram lerps one drawable's four corners
                  // into the other's over `setDuration(200)`. A Flutter path morph
                  // of `PlayPauseDrawable` costs more than it buys, so the two
                  // glyphs cross-fade on Telegram's 200 ms clock instead.
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedOpacity(
                        key: const ValueKey('telegram-glyph-play'),
                        opacity: value.isPlaying ? 0.0 : 1.0,
                        duration: _playPauseMorph,
                        curve: Curves.easeInOut,
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: _playPauseGlyphSize,
                          color: Colors.white,
                        ),
                      ),
                      AnimatedOpacity(
                        key: const ValueKey('telegram-glyph-pause'),
                        opacity: value.isPlaying ? 1.0 : 0.0,
                        duration: _playPauseMorph,
                        curve: Curves.easeInOut,
                        child: const Icon(
                          Icons.pause_rounded,
                          size: _playPauseGlyphSize,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // The band rides the bottom of the picture, lifted by the play-head
        // overhang. `MATCH_PARENT x 48 dp, Gravity.BOTTOM | LEFT` is Telegram's
        // own `LayoutHelper.createFrame` at `PhotoViewer.java:9592`.
        Positioned(
          left: 0,
          right: 0,
          bottom: _thumbOverhang,
          height: _scrubBandHeight,
          child: _ScrubBand(
            shown: shown,
            pressed: _dragging,
            timeLabel: timeText,
            timeReserveText: timeReserveText,
            played: _clamp01(played),
            buffered: _clamp01(buffered),
            onScrubStart: _onScrubStart,
            onScrubUpdate: _onScrubUpdate,
            onScrubEnd: _onScrubEnd,
          ),
        ),
      ],
    );
  }
}

/// The mark a skip leaves behind: Telegram's `VideoForwardDrawable` one-shoot
/// animation, ported. A 32 dp filled circle at alpha 80 (`:164,291`) and the
/// added time as a 12 sp centred string (`:57,309-311`), running 800 ms
/// (`animationProgress += dt / 800.0f`, `:237`) with the alpha ramps of
/// `:163-168` - in over the first 30 % of the run, out over the last 30 %.
/// Telegram pins it beside the media's centre, offset to the side it seeks to
/// (`:138-140`); ours sits under the finger, where the eye already is.
class _SkipMark extends StatelessWidget {
  const _SkipMark({required this.forward, required this.sequence});

  final bool forward;

  /// Re-keys the widget per skip, so a second skip restarts the 800 ms run.
  final int sequence;

  static double _opacity(double t) {
    if (t <= 0.3) return t / 0.3;
    if (t >= 0.7) return (1 - t) / 0.3;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey('telegram-skip-mark-$sequence'),
    tween: Tween(begin: 0.0, end: 1.0),
    duration: _skipMarkRun,
    curve: Curves.linear,
    builder: (context, t, _) {
      final opacity = _opacity(t);
      return SizedBox(
        width: _skipMarkBoxWidth,
        height: _skipMarkBoxHeight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _skipMarkCircle,
              height: _skipMarkCircle,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(
                  alpha: _skipMarkCircleAlpha * opacity,
                ),
              ),
              child: Icon(
                forward ? Icons.forward_10 : Icons.replay_10,
                size: 20,
                color: Colors.white.withValues(alpha: opacity),
              ),
            ),
            Text(
              // Telegram writes `formatPluralString("Seconds", 10)`; "10 s" says
              // the same thing in less room (`VideoForwardDrawable.java:309-311`).
              '${forward ? '+' : '-'}$_skipSeconds s',
              style: TextStyle(
                fontSize: _skipMarkTextSize,
                color: Colors.white.withValues(alpha: opacity),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// The bottom band: Telegram Android's `VideoPlayerSeekBar` in its two states.
/// the measurement log, "T86 - the video viewer's seek bar, Telegram
/// **Android** numbers".
///
/// While the chrome is shown the bar is the fat form: a 4 dp line centred in the
/// 48 dp band, its ends inset 14 dp so the 12 dp play-head dot never overruns the
/// edge, and the play head a filled white circle of radius 6 dp - 8 dp while the
/// finger is down (`VideoPlayerSeekBar.java:407`). Once the chrome fades the same
/// bar thins to a 2 dp hairline 3 dp above the band, its ends run out to the 2 dp
/// padding, and the time label fades with it: the two rects `draw()` lerps by
/// `transitionProgress` at `:343-345,373`, taken at their ends instead of
/// animating the lerp. The label sits inside the band at its top-right (`:9685`)
/// and the bar's right end stops short of it by `dp(2 + 14) + its width` (`:3624`).
class _ScrubBand extends StatelessWidget {
  const _ScrubBand({
    required this.shown,
    required this.pressed,
    required this.timeLabel,
    required this.timeReserveText,
    required this.played,
    required this.buffered,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
  });

  /// The fat form: true while the chrome is up or the finger is on the bar.
  final bool shown;

  /// True only while the finger is down, which grows the play head 6 -> 8 dp.
  final bool pressed;

  /// The time the user sees, and the string whose width the bar gives way to.
  final String timeLabel;
  final String timeReserveText;
  final double played;
  final double buffered;
  final void Function(double fraction) onScrubStart;
  final void Function(double fraction) onScrubUpdate;
  final VoidCallback onScrubEnd;

  static const _grow = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The time label is measured, not guessed - Telegram measures the same
        // string (`PhotoViewer.java:3618`) and subtracts it from the bar.
        final reserve = _textWidth(timeReserveText) + _scrubTimeGap;
        final left = shown ? _scrubEndInset : _scrubHorizontalPadding;
        final right = shown
            ? _scrubEndInset + reserve
            : _scrubHorizontalPadding;
        final barWidth = math.max(1.0, constraints.maxWidth - left - right);
        final lineHeight = shown
            ? _scrubLineHeightShown
            : _scrubLineHeightHidden;
        final bottom = shown
            ? (_scrubBandHeight - lineHeight) / 2
            : _scrubBottomInset;
        final thumbRadius = pressed ? _thumbRadiusPressed : _thumbRadius;
        double fractionAt(double x) => _clamp01((x - left) / barWidth);

        // `clipBehavior: Clip.none` on both Stacks: the time label sits a few dp
        // above the 48 dp band, where the capture puts it (y 869.3..880.0 dp
        // against a band top of 873.4 dp), and a clipping Stack would cut it.
        return Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedOpacity(
              // The bar never fades out; only its form changes. Telegram's
              // 300 ms linear ramp (`the measurement log:172`) is what the
              // form change runs on.
              opacity: 1.0,
              duration: _scrubBarFade,
              curve: Curves.linear,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // `setColors(background = 0x33ffffff, ...)` - the track, white
                  // at 20 percent, a round cap at each end.
                  AnimatedPositioned(
                    key: const ValueKey('telegram-scrub-track'),
                    duration: _grow,
                    curve: Curves.easeOut,
                    left: left,
                    bottom: bottom,
                    width: barWidth,
                    height: lineHeight,
                    child: AnimatedContainer(
                      duration: _grow,
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: _scrubTrackAlpha),
                        borderRadius: BorderRadius.circular(lineHeight / 2),
                      ),
                    ),
                  ),
                  // `cacheColor = 0x33ffffff` - the buffered span.
                  AnimatedPositioned(
                    key: const ValueKey('telegram-scrub-buffered'),
                    duration: _grow,
                    curve: Curves.easeOut,
                    left: left,
                    bottom: bottom,
                    width: barWidth * buffered,
                    height: lineHeight,
                    child: AnimatedContainer(
                      duration: _grow,
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: _scrubBufferedAlpha,
                        ),
                        borderRadius: BorderRadius.circular(lineHeight / 2),
                      ),
                    ),
                  ),
                  // `progressColor = Color.WHITE` - the played span.
                  AnimatedPositioned(
                    key: const ValueKey('telegram-scrub-played'),
                    duration: _grow,
                    curve: Curves.easeOut,
                    left: left,
                    bottom: bottom,
                    width: barWidth * played,
                    height: lineHeight,
                    child: AnimatedContainer(
                      duration: _grow,
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(lineHeight / 2),
                      ),
                    ),
                  ),
                  // `canvas.drawCircle(rect.right, rect.centerY(), currentRadius)`
                  // with `currentRadius = dp(6)`, `dp(pressed ? 8 : 6)`, in
                  // `circleColor = Color.WHITE`. The dot is the whole reason the
                  // bar reads as a handle: a user's "hard to see, hard to tap"
                  // is this circle, which the iOS-shaped bar never had.
                  AnimatedPositioned(
                    key: const ValueKey('telegram-scrub-thumb'),
                    duration: _grow,
                    curve: Curves.easeOut,
                    left: left + barWidth * played - thumbRadius,
                    bottom: bottom + lineHeight / 2 - thumbRadius,
                    width: thumbRadius * 2,
                    height: thumbRadius * 2,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  // The time, inside the band at its top-right: `Gravity.RIGHT |
                  // TOP` with top margin 15 and right margin 12 on a 14 sp white
                  // `SimpleTextView` (`PhotoViewer.java:9679-9685`). It sat at the
                  // top of the picture until now, which put it in the viewer's own
                  // button row on a user's phone
                  // (`the reference capture`, "00:01 / 00:28" over the
                  // share icons) and left the band with no readable state.
                  Positioned(
                    key: const ValueKey('telegram-scrub-time'),
                    top: _timestampTopInset,
                    right: _timestampRightInset,
                    child: AnimatedOpacity(
                      opacity: shown ? 1.0 : 0.0,
                      // the measurement log:172 - timestamps, 200 ms easeInOut.
                      duration: _timestampsFade,
                      curve: Curves.easeInOut,
                      child: Text(timeLabel, style: _timestampStyle),
                    ),
                  ),
                ],
              ),
            ),
            // The hit area goes LAST in the Stack: painted on top, so it wins the hit
            // test over the track, the played span and the dot - those are DecoratedBoxes
            // and each one absorbs a touch, which is what made the bar untappable. It
            // paints nothing, so being on top costs no pixels.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragDown: (d) =>
                    onScrubStart(fractionAt(d.localPosition.dx)),
                onHorizontalDragUpdate: (d) =>
                    onScrubUpdate(fractionAt(d.localPosition.dx)),
                onHorizontalDragEnd: (_) => onScrubEnd(),
                onHorizontalDragCancel: onScrubEnd,
                child: const SizedBox.expand(),
              ),
            ),
          ],
        );
      },
    );
  }
}
