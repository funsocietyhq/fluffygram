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
import 'dart:io';

import 'package:async/async.dart';
import 'package:fluffychat/config/telegram_palette.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/error_reporter.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:ogg_caf_converter/ogg_caf_converter.dart';
import 'package:path_provider/path_provider.dart';

import '../../../utils/matrix_sdk_extensions/event_extension.dart';
import '../../../widgets/fluffy_chat_app.dart';
import '../../../widgets/matrix.dart';

class AudioPlayerWidget extends StatefulWidget {
  final Color color;
  final Color linkColor;
  final double fontSize;
  final Event event;

  static const int wavesCount = 40;

  const AudioPlayerWidget(
    this.event, {
    required this.color,
    required this.linkColor,
    required this.fontSize,
    super.key,
  });

  @override
  AudioPlayerState createState() => AudioPlayerState();
}

enum AudioPlayerStatus { notDownloaded, downloading, downloaded }

class AudioPlayerState extends State<AudioPlayerWidget> {
  /// Telegram's voice row geometry (dp). The play triangle, the waveform
  /// scrubber and the ±10s skip glyphs all read these named numbers, never a
  /// literal at the use site.
  static const double buttonSize = 36;

  /// Height of the waveform strip - the waveform IS the scrubber. The bars
  /// live in the 14 dp band centred inside it, so this number is the touch
  /// target (the 44 dp row geometry from T45), not the drawing height.
  static const double waveformHeight = 32;

  /// The band the bars are drawn in: `final int y = (height - dp(14)) / 2`
  /// with every bar centred on `y + dp(7)` (`SeekBarWaveform.java:418` and
  /// `:422-424`).
  static const double waveformBandHeight = 14;

  /// The bar width IS the stroke: Telegram strokes every bar 2 **physical** px
  /// (`AndroidUtilities.dpf2(2)`, `SeekBarWaveform.java:421`, `:434`, `:477`),
  /// so in logical dp it is `2 / devicePixelRatio` - 0.76 dp on a user's
  /// 2.625 px/dp phone. The 1.33 dp this task first shipped came from
  /// `setStrokeWidth(dp(1.33f))` at `:514`, which is the `Particles` send-off
  /// paint, not the bar paint (correction: `docs/TELEGRAM_TARGET.md`, "Voice
  /// waveform").
  static double waveformBarStrokeFor(double devicePixelRatio) =>
      2 / devicePixelRatio;

  /// Telegram's pitch is one bar per `dpf2(3)` **physical** px
  /// (`SeekBarWaveform.java:421`, `:434`, `:477`), so in logical dp it is
  /// `3 / devicePixelRatio` - 1.14 dp on a user's 2.625 px/dp phone. It is
  /// not a constant: it rides the device ratio. The voice bubble sizes to its
  /// bar run, `barCount * waveformPitchFor(ratio)` (T50.1).
  static double waveformPitchFor(double devicePixelRatio) =>
      3 / devicePixelRatio;

  /// Telegram never draws more than 100 bars (`SeekBarWaveform.java:1338`).
  /// Below the cap the bar count is the voice event's amplitude count.
  static const int waveformMaxBars = 100;

  /// The shortest bar: a silent bucket is still visible.
  static const double waveformMinBarHeight = 3;

  /// The tap target of a ±10s skip glyph.
  static const double skipButtonSize = 26;

  /// Telegram seeks ten seconds per tap on those glyphs.
  static const int skipSeconds = 10;

  /// Height of the speed pill (`1x` / `1.5x` / `2x`).
  static const double speedPillHeight = 20;

  /// Type size of the sender name, the duration and the speed label.
  static const double metaFontSize = 12;

  /// The sender name ellipsizes here so the waveform keeps its width.
  static const double senderNameMaxWidth = 120;

  /// `chat_inVoiceSeekbarFill` - the played bars: night `#64B5EF`
  /// (`night.attheme:441`), day `#379BEF` (`day.attheme:286`).
  static Color playedColorOf(Brightness brightness) =>
      brightness == Brightness.dark
      ? TelegramPalette.voiceSeekbarFill
      : TelegramPalette.dayVoiceSeekbarFill;

  /// `chat_inVoiceSeekbar` - the unplayed bars: night `#636363`
  /// (`night.attheme:445`), day `#BAC0C8` (`day.attheme:289`).
  static Color unplayedColorOf(Brightness brightness) =>
      brightness == Brightness.dark
      ? TelegramPalette.voiceSeekbar
      : TelegramPalette.dayVoiceSeekbar;

  /// `chat_inVoiceSeekbarSelected` - the bars while the finger drags: night
  /// `#7391AB` (`night.attheme:237`), day `#BAC0C8` (`day.attheme:150`).
  static Color draggingColorOf(Brightness brightness) =>
      brightness == Brightness.dark
      ? TelegramPalette.voiceSeekbarSelected
      : TelegramPalette.dayVoiceSeekbarSelected;

  AudioPlayerStatus status = AudioPlayerStatus.notDownloaded;
  double? _downloadProgress;

  late final MatrixState matrix;
  List<int>? _waveform;
  String? _durationString;

  @override
  void dispose() {
    super.dispose();
    final audioPlayer = matrix.voiceMessageEventId.value != widget.event.eventId
        ? null
        : matrix.audioPlayer;
    if (audioPlayer != null) {
      if (audioPlayer.playing && !audioPlayer.isAtEndPosition) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(matrix.context).showMaterialBanner(
            MaterialBanner(
              padding: EdgeInsets.zero,
              leading: StreamBuilder(
                stream: audioPlayer.playerStateStream.asBroadcastStream(),
                builder: (context, _) => IconButton(
                  onPressed: () {
                    if (audioPlayer.isAtEndPosition) {
                      audioPlayer.seek(Duration.zero);
                    } else if (audioPlayer.playing) {
                      audioPlayer.pause();
                    } else {
                      audioPlayer.play();
                    }
                  },
                  icon: audioPlayer.playing && !audioPlayer.isAtEndPosition
                      ? const Icon(Icons.pause_outlined)
                      : const Icon(Icons.play_arrow_outlined),
                ),
              ),
              content: StreamBuilder(
                stream: audioPlayer.positionStream.asBroadcastStream(),
                builder: (context, _) => GestureDetector(
                  onTap: () => FluffyChatApp.router.go(
                    '/rooms/${widget.event.room.id}?event=${widget.event.eventId}',
                  ),
                  child: Text(
                    '🎙️ ${audioPlayer.position.minuteSecondString} / ${audioPlayer.duration?.minuteSecondString} - ${widget.event.senderFromMemoryOrFallback.calcDisplayname()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              actions: [
                IconButton(
                  onPressed: () {
                    audioPlayer.pause();
                    audioPlayer.dispose();
                    matrix.voiceMessageEventId.value = matrix.audioPlayer =
                        null;

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      ScaffoldMessenger.of(
                        matrix.context,
                      ).clearMaterialBanners();
                    });
                  },
                  icon: const Icon(Icons.close_outlined),
                ),
              ],
            ),
          );
        });
        return;
      }
      audioPlayer.pause();
      audioPlayer.dispose();
      matrix.voiceMessageEventId.value = matrix.audioPlayer = null;
    }
  }

  Future<void> _onButtonTap() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(matrix.context).clearMaterialBanners();
    });
    final currentPlayer =
        matrix.voiceMessageEventId.value != widget.event.eventId
        ? null
        : matrix.audioPlayer;
    if (currentPlayer != null && !currentPlayer.isAtEndPosition) {
      if (currentPlayer.playing) {
        currentPlayer.pause();
      } else {
        currentPlayer.play();
      }
      return;
    }

    matrix.voiceMessageEventId.value = widget.event.eventId;
    matrix.audioPlayer
      ?..stop()
      ..dispose();
    File? file;
    MatrixFile? matrixFile;

    setState(() => status = AudioPlayerStatus.downloading);
    try {
      final fileSize = widget.event.content
          .tryGetMap<String, Object?>('info')
          ?.tryGet<int>('size');
      matrixFile = await widget.event.downloadAndDecryptAttachment(
        onDownloadProgress: fileSize != null && fileSize > 0
            ? (progress) {
                final progressPercentage = progress / fileSize;
                setState(() {
                  _downloadProgress = progressPercentage < 1
                      ? progressPercentage
                      : null;
                });
              }
            : null,
      );

      final attachmentUrl = widget.event.attachmentOrThumbnailMxcUrl();

      if (!kIsWeb && attachmentUrl != null) {
        final tempDir = await getTemporaryDirectory();
        final fileName = Uri.encodeComponent(attachmentUrl.pathSegments.last);
        file = File('${tempDir.path}/${fileName}_${matrixFile.name}');

        await file.writeAsBytes(matrixFile.bytes);

        if (Platform.isIOS &&
            matrixFile.mimeType.toLowerCase() == 'audio/ogg') {
          Logs().v('Convert ogg audio file for iOS...');
          final convertedFile = File('${file.path}.caf');
          if (await convertedFile.exists() == false) {
            await OggCafConverter().convertOggToCaf(
              input: file.path,
              output: convertedFile.path,
            );
          }
          file = convertedFile;
        }
      }

      setState(() {
        status = AudioPlayerStatus.downloaded;
      });
    } catch (e, s) {
      Logs().v('Could not download audio file', e, s);
      if (!mounted) rethrow;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
      rethrow;
    }
    if (!context.mounted) return;
    if (matrix.voiceMessageEventId.value != widget.event.eventId) return;

    final audioPlayer = matrix.audioPlayer = AudioPlayer();

    if (file != null) {
      audioPlayer.setFilePath(file.path);
    } else {
      await audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.dataFromBytes(matrixFile.bytes, mimeType: matrixFile.mimeType),
        ),
      );
    }
    if (!mounted) return;

    audioPlayer.play().onError(
      ErrorReporter(context, 'Unable to play audio message').onErrorCallback,
    );
  }

  /// Telegram's voice speed cycle: 1x -> 1.5x -> 2x -> 1x. The value is
  /// always visible in the speed pill.
  Future<void> _toggleSpeed() async {
    final audioPlayer = matrix.audioPlayer;
    if (audioPlayer == null) return;
    final double nextSpeed;
    switch (audioPlayer.speed) {
      case 1.0:
        nextSpeed = 1.5;
      case 1.5:
        nextSpeed = 2.0;
      default:
        nextSpeed = 1.0;
    }
    await audioPlayer.setSpeed(nextSpeed);
    if (!mounted) return;
    setState(() {});
  }

  /// `1x`, `1.5x`, `2x` - Telegram trims the trailing zero.
  static String _speedLabel(double speed) =>
      speed == speed.roundToDouble() ? '${speed.round()}x' : '${speed}x';

  /// The thumb: the fraction of the waveform the finger holds while dragging
  /// (Telegram's `thumbX / width`, `SeekBarWaveform.java:163-170`). Null while
  /// not dragging, and the seek commits to the player only on release.
  double? _dragFraction;

  /// The fraction of the file the x position [x] in a [width] wide strip maps
  /// to, clamped to the strip the way Telegram clamps the thumb (`:166-170`).
  static double fractionAtX(double x, double width) =>
      width <= 0 ? 0.0 : (x / width).clamp(0.0, 1.0);

  /// Commit a thumb position to the player. With no player yet, a tap on the
  /// waveform starts playback - the play triangle's own path.
  void _seekToFraction(double fraction, double maxPositionMs) {
    final audioPlayer = matrix.audioPlayer;
    if (audioPlayer == null) {
      _onButtonTap();
      return;
    }
    if (maxPositionMs <= 0) return;
    audioPlayer.seek(
      Duration(milliseconds: (fraction * maxPositionMs).round()),
    );
    setState(() {});
  }

  /// Drag release: the thumb's fraction is the new position. Telegram commits
  /// on `ACTION_UP` (`onSeekBarDrag(thumbX / width)`, `:153-155`).
  void _endDrag(double maxPositionMs) {
    final fraction = _dragFraction;
    if (fraction == null) return;
    _seekToFraction(fraction, maxPositionMs);
    setState(() => _dragFraction = null);
  }

  /// One flat ±10s skip glyph (Telegram's seek step).
  Widget _skipButton(AudioPlayer audioPlayer, IconData icon, int seconds) {
    return InkWell(
      borderRadius: BorderRadius.circular(skipButtonSize / 2),
      onTap: () => _skip(audioPlayer, seconds),
      child: SizedBox(
        width: skipButtonSize,
        height: skipButtonSize,
        child: Icon(
          icon,
          size: skipButtonSize - 3,
          color: TelegramPalette.textSecondary,
        ),
      ),
    );
  }

  /// The speed pill: the current value is always visible, a tap cycles
  /// 1x -> 1.5x -> 2x -> 1x.
  Widget _speedPill(AudioPlayer audioPlayer, Color accent) {
    return Material(
      color: widget.color.withAlpha(36),
      borderRadius: BorderRadius.circular(speedPillHeight / 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(speedPillHeight / 2),
        onTap: _toggleSpeed,
        child: SizedBox(
          height: speedPillHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Center(
              child: Text(
                _speedLabel(audioPlayer.speed),
                style: TextStyle(
                  color: accent,
                  fontSize: metaFontSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Seek by [skipSeconds] on the running player, clamped to the file.
  void _skip(AudioPlayer audioPlayer, int seconds) {
    var target = audioPlayer.position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    final duration = audioPlayer.duration;
    if (duration != null && target > duration) target = duration;
    audioPlayer.seek(target);
    setState(() {});
  }

  List<int>? _getWaveform() {
    final eventWaveForm = widget.event.content
        .tryGetMap<String, Object?>('org.matrix.msc1767.audio')
        ?.tryGetList<int>('waveform');
    if (eventWaveForm == null || eventWaveForm.isEmpty) {
      return null;
    }
    // Newer versions of this MSC define 256 as the maximum instead of 1024.
    // Hard to determine which version we should follow. At the time of writing
    // this, Element X still sends 1024 while Mautrix WhatsApp uses 256.
    // https://github.com/matrix-org/matrix-spec-proposals/blob/travis/msc/audio-waveform/proposals/3246-audio-waveform.md#unstable-prefix
    if (!eventWaveForm.any((value) => value > 256)) {
      _maxWaveForm = 256;
    }

    // T50.1: the raw amplitudes go through unsampled. The bar count is
    // `min(waveformMaxBars, amplitudes.length)` and the painter samples the
    // amplitudes evenly to that count - the old resample to `wavesCount` is
    // what made a 2 s and a 60 s voice draw the same 40-bar row.
    return eventWaveForm
        .map((i) => i > _maxWaveForm ? _maxWaveForm : i)
        .toList();
  }

  int _maxWaveForm = 1024;

  @override
  void initState() {
    super.initState();
    matrix = Matrix.of(context);
    _waveform = _getWaveform();

    if (matrix.voiceMessageEventId.value == widget.event.eventId &&
        matrix.audioPlayer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(matrix.context).clearMaterialBanners();
      });
    }

    final durationInt = widget.event.content
        .tryGetMap<String, Object?>('info')
        ?.tryGet<int>('duration');
    if (durationInt != null) {
      final duration = Duration(milliseconds: durationInt);
      _durationString = duration.minuteSecondString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waveform = _waveform;
    // The theme's own accent (the seed the user picked on the style page) tints
    // the played part of the waveform. No new colour is introduced here.
    final accentColor = theme.colorScheme.primary;
    // The waveform colours are night/day theme keys, chosen by brightness the
    // way `TelegramUnreadDivider.backgroundColorOf` chooses its band.
    final brightness = theme.brightness;

    return ValueListenableBuilder(
      valueListenable: matrix.voiceMessageEventId,
      builder: (context, eventId, _) {
        final audioPlayer = eventId != widget.event.eventId
            ? null
            : matrix.audioPlayer;

        final fileDescription = widget.event.fileDescription;

        return StreamBuilder<Object>(
          stream: audioPlayer == null
              ? null
              : StreamGroup.merge([
                  audioPlayer.positionStream.asBroadcastStream(),
                  audioPlayer.playerStateStream.asBroadcastStream(),
                ]),
          builder: (context, _) {
            final maxPosition =
                audioPlayer?.duration?.inMilliseconds.toDouble() ?? 1.0;
            var currentPosition =
                audioPlayer?.position.inMilliseconds.toDouble() ?? 0.0;
            if (currentPosition > maxPosition) currentPosition = maxPosition;

            final playedFraction = maxPosition <= 0
                ? 0.0
                : (currentPosition / maxPosition).clamp(0.0, 1.0);
            // While the finger drags, the played prefix follows the finger -
            // Telegram's thumb, not the player's position.
            final thumbFraction = _dragFraction ?? playedFraction;

            final statusText = audioPlayer == null
                ? _durationString ?? '0:00'
                : audioPlayer.position.minuteSecondString;
            // T50.1: Telegram's fixed pitch, the bar count the amplitudes
            // carry capped at 100 (`SeekBarWaveform.java:1338`), and a
            // waveform box that IS the bar run - no dead space right of the
            // last bar, a narrower bubble for a shorter voice.
            final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
            final pitch = waveformPitchFor(devicePixelRatio);
            final barCount = waveform == null
                ? AudioPlayerWidget.wavesCount
                : waveform.length.clamp(1, waveformMaxBars);
            return Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: FluffyThemes.columnWidth,
                    ),
                    child: Column(
                      mainAxisSize: .min,
                      crossAxisAlignment: .start,
                      spacing: 2,
                      children: [
                        // Telegram's voice row is bare: a play triangle with
                        // nothing behind it, the waveform as the scrubber, and
                        // the duration as plain text at the trailing end. No mic
                        // glyph, no circle behind the triangle, no pill behind
                        // the number - a user's phone capture shows three
                        // plain elements and nothing else.
                        Row(
                          mainAxisSize: .min,
                          crossAxisAlignment: .center,
                          spacing: 6,
                          children: <Widget>[
                            SizedBox(
                              width: buttonSize,
                              height: buttonSize,
                              child: status == AudioPlayerStatus.downloading
                                  ? CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: widget.color,
                                      value: _downloadProgress,
                                    )
                                  : // The ink splash needs a Material host. It is
                                    // transparent: the tap target keeps its
                                    // 36dp box and its ripple, and the only
                                    // visible thing is the bare triangle.
                                    Material(
                                      type: MaterialType.transparency,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(
                                          buttonSize / 2,
                                        ),
                                        onLongPress: () =>
                                            widget.event.saveFile(context),
                                        onTap: _onButtonTap,
                                        child: Icon(
                                          audioPlayer?.playing == true &&
                                                  audioPlayer
                                                          ?.isAtEndPosition ==
                                                      false
                                              ? Icons.pause_outlined
                                              : Icons.play_arrow_outlined,
                                          color: widget.color,
                                        ),
                                      ),
                                    ),
                            ),
                            SizedBox(
                              width: barCount * pitch,
                              height: waveformHeight,
                              child: LayoutBuilder(
                                builder: (context, box) => GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  // The waveform replaces the Material slider:
                                  // a tap seeks to the touched fraction, a
                                  // drag moves a thumb that commits on
                                  // release - Telegram's `onTouch` press /
                                  // move / release split (`:138-182`).
                                  onTapUp: (details) => _seekToFraction(
                                    fractionAtX(
                                      details.localPosition.dx,
                                      box.maxWidth,
                                    ),
                                    maxPosition,
                                  ),
                                  onHorizontalDragStart: (details) => setState(
                                    () => _dragFraction = fractionAtX(
                                      details.localPosition.dx,
                                      box.maxWidth,
                                    ),
                                  ),
                                  onHorizontalDragUpdate: (details) => setState(
                                    () => _dragFraction = fractionAtX(
                                      details.localPosition.dx,
                                      box.maxWidth,
                                    ),
                                  ),
                                  onHorizontalDragEnd: (details) =>
                                      _endDrag(maxPosition),
                                  onHorizontalDragCancel: () =>
                                      setState(() => _dragFraction = null),
                                  child: CustomPaint(
                                    size: Size(box.maxWidth, waveformHeight),
                                    painter: TelegramWaveformPainter(
                                      waveform: waveform,
                                      maxAmplitude: _maxWaveForm,
                                      playedFraction: thumbFraction,
                                      dragging: _dragFraction != null,
                                      playedColor: playedColorOf(brightness),
                                      unplayedColor: unplayedColorOf(
                                        brightness,
                                      ),
                                      draggingColor: draggingColorOf(
                                        brightness,
                                      ),
                                      barStroke: waveformBarStrokeFor(
                                        devicePixelRatio,
                                      ),
                                      bandHeight: waveformBandHeight,
                                      minBarHeight: waveformMinBarHeight,
                                      barCount: barCount,
                                      devicePixelRatio: devicePixelRatio,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              statusText,
                              style: TextStyle(
                                color: widget.color,
                                fontSize: metaFontSize,
                              ),
                            ),
                          ],
                        ),
                        // Telegram's ±10s skip glyphs and the visible speed
                        // value, shown while this bubble owns the player.
                        if (audioPlayer != null)
                          Row(
                            mainAxisSize: .min,
                            spacing: 2,
                            children: [
                              _skipButton(
                                audioPlayer,
                                Icons.replay_10,
                                -skipSeconds,
                              ),
                              _skipButton(
                                audioPlayer,
                                Icons.forward_10,
                                skipSeconds,
                              ),
                              const SizedBox(width: 4),
                              _speedPill(audioPlayer, accentColor),
                            ],
                          ),
                      ],
                    ),
                  ),
                  if (fileDescription != null) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Linkify(
                        text: fileDescription,
                        textScaleFactor: MediaQuery.textScalerOf(
                          context,
                        ).scale(1),
                        style: TextStyle(
                          color: widget.color,
                          fontSize: widget.fontSize,
                        ),
                        options: const LinkifyOptions(humanize: false),
                        linkStyle: TextStyle(
                          color: widget.linkColor,
                          fontSize: widget.fontSize,
                          decoration: TextDecoration.underline,
                          decorationColor: widget.linkColor,
                        ),
                        onOpen: (url) =>
                            UrlLauncher(context, url.url).launchUrl(),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Telegram's voice waveform: one bar per slot on a fixed pitch, each bar a
/// stroked capsule of [barStroke] width standing in the [bandHeight] band that
/// is centred in the strip. The played prefix takes `chat_inVoiceSeekbarFill`,
/// the rest takes `chat_inVoiceSeekbar`, and while the finger drags the whole
/// unplayed part takes `chat_inVoiceSeekbarSelected` - Telegram paints the
/// strip once with the unplayed key and once with the fill key up to the thumb
/// (`SeekBarWaveform.drawFill` `:434-448`). The row itself carries the tap and
/// the drag - there is no Material slider and no thumb widget.
class TelegramWaveformPainter extends CustomPainter {
  const TelegramWaveformPainter({
    required this.waveform,
    required this.maxAmplitude,
    required this.playedFraction,
    required this.dragging,
    required this.playedColor,
    required this.unplayedColor,
    required this.draggingColor,
    required this.barStroke,
    required this.bandHeight,
    required this.minBarHeight,
    required this.barCount,
    required this.devicePixelRatio,
  });

  final List<int>? waveform;
  final int maxAmplitude;
  final double playedFraction;
  final bool dragging;
  final Color playedColor;
  final Color unplayedColor;
  final Color draggingColor;
  final double barStroke;
  final double bandHeight;
  final double minBarHeight;
  final int barCount;
  final double devicePixelRatio;

  /// A voice event with no waveform data draws a flat row of short bars, so
  /// the scrubber stays visible and tappable.
  static const double emptyAmplitude = 0.35;

  @override
  void paint(Canvas canvas, Size size) {
    if (barCount <= 0 || size.width <= 0 || size.height <= 0) return;
    // T50.1: Telegram's fixed pitch - one bar per 3 **physical** px
    // (`SeekBarWaveform.java:421`), not `strip width / barCount`.
    final pitch = 3.0 / devicePixelRatio;
    // The band's middle line: `y + dp(7)` with `y = (height - dp(14)) / 2`.
    final centre = size.height / 2;
    final barsPlayed = (playedFraction * barCount).round();
    final amplitudes = waveform;
    final amplitudeCount = amplitudes?.length ?? 0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barStroke;
    for (var i = 0; i < barCount; i++) {
      // The amplitudes sample evenly across the run to `barCount` (T50.1):
      // bar i takes the amplitude at `i * count / barCount`.
      final amplitude = amplitudeCount == 0 || maxAmplitude <= 0
          ? emptyAmplitude
          : (amplitudes![(i * amplitudeCount / barCount).floor()] /
                    maxAmplitude)
                .clamp(0.0, 1.0);
      // A bar spans `2 * (h + strokeWidth / 2)` (`:422-424`): the stroke plus
      // its two round caps add `barStroke`, so the line itself is
      // `height - barStroke` long.
      final height = (minBarHeight + (bandHeight - minBarHeight) * amplitude)
          .clamp(barStroke, bandHeight);
      final halfLine = (height - barStroke) / 2;
      final x = pitch * (i + 0.5);
      paint.color = i < barsPlayed
          ? playedColor
          : dragging
          ? draggingColor
          : unplayedColor;
      canvas.drawLine(
        Offset(x, centre - halfLine),
        Offset(x, centre + halfLine),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(TelegramWaveformPainter oldDelegate) =>
      oldDelegate.playedFraction != playedFraction ||
      oldDelegate.dragging != dragging ||
      oldDelegate.waveform != waveform ||
      oldDelegate.playedColor != playedColor ||
      oldDelegate.unplayedColor != unplayedColor ||
      oldDelegate.draggingColor != draggingColor ||
      oldDelegate.maxAmplitude != maxAmplitude ||
      oldDelegate.barStroke != barStroke ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}

extension on AudioPlayer {
  bool get isAtEndPosition {
    final duration = this.duration;
    if (duration == null) return true;
    return position >= duration;
  }
}

/// The voice duration as Telegram prints it: `0:12` for twelve seconds, `1:00`
/// for a minute, `1:02:03` past an hour. Minutes are not zero padded - `00:07`
/// is this app's old form, not Telegram's.
extension TelegramVoiceDuration on Duration {
  String get minuteSecondString {
    final seconds = (inSeconds % 60).toString().padLeft(2, '0');
    if (inHours == 0) return '$inMinutes:$seconds';
    return '$inHours:${(inMinutes % 60).toString().padLeft(2, '0')}:$seconds';
  }
}
