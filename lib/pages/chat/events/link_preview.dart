// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:fluffychat/utils/url_launcher.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../../widgets/mxc_image.dart';

/// Telegram's link preview card - ROADMAP T160.
///
/// Telegram draws it in `ChatMessageCell.java` inside the text bubble, and the
/// geometry is `ui/Components/WebPagePreviewView.java`: a 3 dp accent rule at
/// the panel's own leading edge (`lineRect.set(0, 0, dp(3), getHeight())`,
/// line 53), uniform `dp(10)` corners (lines 46-47), `setPadding(dp(10), dp(2),
/// dp(7), dp(6))` (line 116) and a `dp(6)` rounded picture (line 105). Measured
/// on a user's capture `the reference capture` at 2.625 px/dp: rule
/// x 184..192 = 3.0 dp, padding 9.9 / 6.8 / 6.9 dp, panel `#322829` over the
/// `#1e1e20` bubble = the sender's colour at 7.5-8.6 %, picture 235.5 x 164.9 dp
/// at full panel width, 6.9 dp below the link text.
///
/// It is the reply-quote panel of `reply_content.dart` with content stacked
/// under the name line: same rule, same sender-tinted fill, same paints.
/// Telegram uses `chat_replyNamePaint` for the site name and
/// `chat_replyTextPaint` for the description (`ChatMessageCell.java:10693`), and
/// both are `dp(smallerDp)` = 14 dp at `SharedConfig.fontSize = 16`
/// (`Theme.java:8038-8041`), which is the size this card uses.
class LinkPreview extends StatelessWidget {
  /// MSC3860's preview object (`TelegramLinkPreview.toContent()`).
  final Map<String, Object?> preview;

  /// The fill of the bubble this card sits in: the panel is the sender's colour
  /// over it, not a colour of its own.
  final Color bubbleFill;

  /// The sender's palette colour - the rule, the site name.
  final Color senderColour;

  /// The bubble's text colour - the title and the description.
  final Color textColor;

  final Event event;

  const LinkPreview({
    required this.preview,
    required this.bubbleFill,
    required this.senderColour,
    required this.textColor,
    required this.event,
    super.key,
  });

  /// `WebPagePreviewView.java:53`.
  static const double ruleWidth = 3;

  /// `WebPagePreviewView.java:46-47`.
  static const double panelRadius = 10;

  /// `WebPagePreviewView.java:116` - left, top, right, bottom, inside the rule.
  static const double paddingStart = 10;
  static const double paddingTop = 2;
  static const double paddingEnd = 7;
  static const double paddingBottom = 6;

  /// Measured: the panel starts 6.9 dp under the link text.
  static const double gapAbove = 7;

  /// `Theme.java:8040-8041` - `chat_replyNamePaint` / `chat_replyTextPaint` are
  /// both `dp(smallerDp)`, and `smallerDp = (2 * fontSize + 10) / 3` = 14 at
  /// Telegram's phone `fontSize` of 16.
  static const double fontSize = 14;

  /// `ChatMessageCell.java:10693` truncates the description with
  /// `TruncateAt.END` at 6 lines.
  static const int descriptionMaxLines = 6;

  /// `ChatMessageCell.java:10693` also passes `spacingadd = dp(1)`.
  static const double descriptionLineSpacing = 1 / fontSize;

  /// `WebPagePreviewView.java:105` - `setRoundRadius(dp(6))`.
  static const double imageRadius = 6;

  /// Measured: 8 dp from the last text line to the picture.
  static const double imageGapAbove = 8;

  /// The picture keeps its own aspect at full panel width, clamped so a
  /// portrait `og:image` (a phone screenshot is 9:16) cannot out-shout the
  /// message it previews. A user's capture: 235.5 x 164.9 dp = ratio 0.70.
  static const double imageMaxHeightFactor = 1.25;
  static const double imageMinHeightFactor = 0.5;

  /// Panel tint: the sender's colour at 8 % over the bubble fill. Measured on
  /// `the reference capture`: `#1e1e20` bubble, sender `#e88878`,
  /// panel `#322829` - 0.075 of the sender over the bubble reproduces all three
  /// channels. The reply panel of `reply_content.dart` measures 0.10; the
  /// preview panel is one step lighter, and Telegram keeps them as separate
  /// palette keys (`chat_inWebPageBg` vs `chat_inReply*`).
  static const double panelTintAlpha = 0.08;

  String _text(String key) {
    final value = preview[key];
    return value is String ? value.trim() : '';
  }

  Uri? get _imageMxc {
    final image = preview['org.matrix.msc3860/image'];
    final raw = image is Map
        ? (image['url'] as String?)
        : preview['thumbnail_url'];
    if (raw is! String || raw.isEmpty) return null;
    return Uri.tryParse(raw);
  }

  (int, int)? get _imageSize {
    final image = preview['org.matrix.msc3860/image'];
    if (image is! Map) return null;
    final w = image['w'];
    final h = image['h'];
    if (w is int && h is int && w > 0 && h > 0) return (w, h);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final url = _text('url');
    final siteName = _text('site_name');
    final title = _text('title');
    final description = _text('description');
    final mxc = _imageMxc;
    // Nothing to show: Telegram draws no panel for an empty preview, and
    // neither do we - the link text is the message.
    if (siteName.isEmpty &&
        title.isEmpty &&
        description.isEmpty &&
        mxc == null) {
      return const SizedBox.shrink();
    }
    final panelFill = Color.alphaBlend(
      senderColour.withValues(alpha: panelTintAlpha),
      bubbleFill,
    );

    return Padding(
      padding: const EdgeInsets.only(top: gapAbove),
      // The picture's height comes from the panel's own width, so the layout is
      // read here, above the IntrinsicHeight: LayoutBuilder cannot sit inside
      // one, it answers no intrinsic query, and the rule on the left needs the
      // intrinsic pass to stretch it down the picture.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final innerWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth - ruleWidth - paddingStart - paddingEnd
              : null;
          final (pw, ph) = _imageSize ?? (16, 10);
          final imageHeight = innerWidth == null || innerWidth <= 0
              ? null
              : (innerWidth * ph / pw).clamp(
                  innerWidth * imageMinHeightFactor,
                  innerWidth * imageMaxHeightFactor,
                );
          return Material(
            color: panelFill,
            borderRadius: const BorderRadius.all(Radius.circular(panelRadius)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              // ChatMessageCell.java:3091 hit-tests the whole preview rect and
              // opens the page; no ink, the bubble has no ripples.
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              onTap: url.isEmpty
                  ? null
                  : () => UrlLauncher(context, url).launchUrl(),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ColoredBox(
                      color: senderColour,
                      child: const SizedBox(width: ruleWidth),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          paddingStart,
                          paddingTop,
                          paddingEnd,
                          paddingBottom,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (siteName.isNotEmpty)
                              Text(
                                siteName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: senderColour,
                                  fontSize: fontSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            if (title.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: paddingTop),
                                child: Text(
                                  title,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: fontSize,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            if (description.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: paddingTop),
                                child: Text(
                                  description,
                                  maxLines: descriptionMaxLines,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: fontSize,
                                    height: 1 + descriptionLineSpacing,
                                  ),
                                ),
                              ),
                            if (mxc case final Uri uri)
                              if (imageHeight case final double height)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: imageGapAbove,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.all(
                                      Radius.circular(imageRadius),
                                    ),
                                    child: MxcImage(
                                      uri: uri,
                                      client: event.room.client,
                                      cacheKey: '${event.eventId}:preview',
                                      width: innerWidth,
                                      height: height,
                                      fit: BoxFit.cover,
                                      borderRadius: const BorderRadius.all(
                                        Radius.circular(imageRadius),
                                      ),
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
