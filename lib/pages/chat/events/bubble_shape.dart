// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:material_ui/material_ui.dart';

/// Timeline geometry from `verification/telegram-target.json` `geometry`
/// (dp = Flutter logical pixels here). Kept next to the shape that draws it so
/// the chat widgets read named numbers instead of literals.
abstract final class TelegramBubbleGeometry {
  /// `bubble_corner_radius_dp` - the corners away from the tail.
  ///
  /// Telegram's own mapping, `ChatMessageCell.java:9621-9624`: with the "Message
  /// corners" slider at R, a bubble corner is drawn at `dp(R - 2)`. A user's
  /// slider reads 17 and 17 is the top of Telegram's range (`ThemeActivity.java:358-359`,
  /// `startRadius = 0`, `endRadius = 17`), so the drawn radius is 15 dp. A
  /// quarter-circle fit on their capture puts the outer corners at 14.5 dp, which
  /// agrees inside sampling noise. A uniform 17 dp was tried first and reverted:
  /// with the tail-side corner rounded that wide the tail wedge vanished into the
  /// corner, and the rig probe `outgoing right margin+tail` measured the body box
  /// at 11 dp instead of the 3 dp Telegram leaves past its tail.
  static const double cornerRadius = 15;

  /// The corner that carries the tail. Telegram's `nearRad`
  /// (`ChatMessageCell.java:9626`, applied to the incoming bottom-left corner at
  /// `:9685`) is `min(dp(3), rad)` = 3 dp at a user's setting: the tail corner
  /// is deliberately much tighter than the other three.
  static const double tailSideCornerRadius = 3;

  /// A corner shared with a neighbour instead of facing open space. Telegram's
  /// `minRad` (`ChatMessageCell.java:9620`, applied by the group-position block
  /// at `:9648-9673`) is 4 dp: inside a sender run the corners that face the
  /// next message by the same sender flatten to 4 dp while the outer corners of
  /// the run keep the full radius. Recorded value; the sender-run case is not
  /// wired into `TelegramBubbleShape` yet (ROADMAP open item), and the album
  /// mosaic still clips tiles with the full bubble corner.
  static const double groupedCornerRadius = 4;

  /// `bubble_tail_dp` - the tail wedge is 8dp wide at the bubble edge and 3dp
  /// tall at the bubble's bottom edge: Telegram's published tail size, drawn out
  /// of the 3 dp corner above.
  static const double tailWidth = 8;
  static const double tailHeight = 3;

  /// `bubble_padding_h_dp` / `bubble_padding_v_dp`.
  static const double paddingH = 12;
  static const double paddingV = 7;

  // --- T47: the "Unread Messages" divider row, every number read from
  // `ui/Cells/ChatUnreadCell.java` (source, not pixels) ---

  /// `unread_divider_row_height_dp` - the cell pins its own height in
  /// `onMeasure`: `MeasureSpec.makeMeasureSpec(dp(40), EXACTLY)`.
  /// ChatUnreadCell.java:73.
  static const double unreadDividerRowHeight = 40;

  /// `unread_divider_band_height_dp` / `unread_divider_band_top_margin_dp` -
  /// the fill is added `MATCH_PARENT x 27` at `LEFT|TOP` with a 7 dp top
  /// margin, so it is a 27 dp band inside the 40 dp row, not a 40 dp block.
  /// ChatUnreadCell.java:39.
  static const double unreadDividerBandHeight = 27;
  static const double unreadDividerBandTopMargin = 7;

  /// `unread_divider_arrow_right_margin_dp` / `unread_divider_arrow_top_padding_dp`
  /// - the arrow lives inside the band at `RIGHT|CENTER_VERTICAL` with a 10 dp
  /// right margin (ChatUnreadCell.java:45) and `setPadding(0, dp(2), 0, 0)`
  /// (`:44`). The arrow is a right-edge glyph, not a leading icon.
  static const double unreadDividerArrowRightMargin = 10;
  static const double unreadDividerArrowTopPadding = 2;

  /// The arrow box. Telegram's `ic_ab_new` (`:42`) is a wrap-content vector in
  /// a `res/` tree this repo does not carry, and their binary assets may not
  /// enter the tree (AGENTS.md ground rule 2); the fork draws Material's
  /// `expand_more` chevron at Material's own default glyph size, 24 dp, which
  /// fits the 27 dp band the way Telegram's arrow does.
  static const double unreadDividerArrowSize = 24;

  /// `unread_divider_label_side_margin_dp` - the label is added at
  /// `Gravity.CENTER` with 32 dp left and right margins. ChatUnreadCell.java:52.
  static const double unreadDividerLabelSideMargin = 32;

  /// `unread_divider_label_sp` - `setTextSize(COMPLEX_UNIT_DIP, 14)`
  /// (ChatUnreadCell.java:49). dp through `dp()`, not sp, so Android's system
  /// font scale never touches it (`Theme.java:8035`). The typeface is
  /// `AndroidUtilities.bold()` (`:51`).
  static const double unreadDividerLabelFontSize = 14;

  /// `bubble_max_width_dp` - phone layout cap, tail included. Since T39 the
  /// user's bubble-width setting is a percent of the column
  /// (`AppSettings.bubbleWidthPercent`); this constant is the phone-column
  /// reference and the album mosaic's scaling denominator.
  /// T13 measured on a user's Pixel (1 dp = 2.625 px): Telegram's outgoing
  /// text bubble spans x = 147..892 = 746 px = 284 dp with its left edge at
  /// 56 dp; FluffyGram build 6 spanned x = 147..860 = 713 px = 272 dp on the
  /// same left edge. Only the width differed, so the cap moves to 284 dp.
  static const double maxBubbleWidth = 284;

  /// The bubble width setting, in percent of the chat column (T39): Telegram
  /// desktop's slider model - "Custom width for the message bubble" is a
  /// percentage of the column (50..100; Telegram's slider defaults to 72,
  /// tdesktop ChatListWidth, while this fork ships 100 by user decision
  /// 2026-10-29, T130), not an absolute dp. An absolute dp breaks on a mobile
  /// window: 600 dp on
  /// a 923 dp phone landscape fills the screen (user report 2026-10-27).
  static const int minBubbleWidthPercent = 50;
  static const int maxBubbleWidthPercent = 100;

  /// The chrome a bubble column never grows into: the 56dp incoming gutter
  /// (8 edge + 42 avatar + 6 gap) plus the 11dp outgoing margin (8 edge + 3).
  static const double bubbleColumnChrome =
      8 + avatarSize + incomingGapAfterAvatar + 8 + outgoingGapAfterEdge;

  /// The user's bubble width, as a percent of the chat column, clamped to the
  /// slider range (50..100; the shipped default is 100 - T130 - where
  /// Telegram's own slider default is 72, `the measurement log` "T39").
  static int get userBubbleWidthPercent {
    final p = AppSettings.bubbleWidthPercent.value;
    if (p < minBubbleWidthPercent) return minBubbleWidthPercent;
    if (p > maxBubbleWidthPercent) return maxBubbleWidthPercent;
    return p;
  }

  /// Window widths at or above this stop using the phone column. Owner rule
  /// 2026-10-26 (finding 24): a bubble must not stop at mobile width just
  /// because the display is larger - on a desktop web page the column grows
  /// with the window. The start sits above large tablet and phone-landscape
  /// sizes (and above Flutter's 800 px default test viewport, so the gate
  /// harness keeps measuring the phone column). Below it nothing changes, so
  /// every phone measurement stays.
  static const double wideWindowStartDp = 820;

  /// Telegram's phone text column is a formula, not a cap:
  /// `maxWidth = parentWidth - dp(80)`, and `dp(52)` more is subtracted when the
  /// row draws an avatar (`MessageObject.java:8509-8540`, the `maxWidth == 0`
  /// branch: `generatedWithMinSize - dp(80)`, then `- dp(52)` for
  /// `needDrawAvatarInternal() && !isOutOwner()`). On a user's 411 dp phone
  /// that is 331 dp outgoing and 279 dp incoming; their measured bubble fills
  /// are 338 and 296 dp, the extra 7-17 dp being the tail (5.7 dp) and the
  /// 2 dp stroke the capture reads into the box.
  ///
  /// The chat column inset both directions pay.
  static const double phoneColumnInset = 80;

  /// The extra inset an incoming row pays for its avatar column.
  static const double phoneAvatarColumnInset = 52;

  /// The cap of one bubble on a window of [windowWidth]. On a phone it is
  /// Telegram's column formula: the window, less [phoneColumnInset], less
  /// [phoneAvatarColumnInset] when the row is incoming. The user's bubble-width
  /// setting does not constrain a phone - Telegram's phone layout has no such
  /// slider, and the setting's 284 dp default is what made our outgoing bubbles
  /// 54 dp narrower than theirs (user capture pair, `the measurement log`
  /// row 6). The setting keeps governing the wide-window path below.
  /// From [wideWindowStartDp] the cap is the user's percent of the room
  /// (T39): derived from the window at every layout, so no setting value can
  /// make a bubble wider than the room it is drawn in.
  static double maxBubbleWidthForWindow(
    double windowWidth, {
    required bool outgoing,
  }) {
    final room = windowWidth - bubbleColumnChrome;
    if (windowWidth < wideWindowStartDp) {
      final formula =
          windowWidth -
          phoneColumnInset -
          (outgoing ? 0 : phoneAvatarColumnInset);
      return formula > room ? room : formula;
    }
    return room * userBubbleWidthPercent / 100.0;
  }

  /// Message text size, Telegram's slider: 12..24sp, default 16sp =
  /// `AppConfig.messageFontSize`. Stored as `AppSettings.fontSizeFactor`, the
  /// factor of that base, so the slider range is 0.75..1.5.
  static const double minMessageTextSp = 12;
  static const double maxMessageTextSp = 24;
  static const double minFontSizeFactor =
      minMessageTextSp / AppConfig.messageFontSize;
  static const double maxFontSizeFactor =
      maxMessageTextSp / AppConfig.messageFontSize;

  /// The user's message text size in sp, clamped to the slider range.
  static double get userMessageTextSp {
    var factor = AppSettings.fontSizeFactor.value;
    if (factor < minFontSizeFactor) factor = minFontSizeFactor;
    if (factor > maxFontSizeFactor) factor = maxFontSizeFactor;
    return AppConfig.messageFontSize * factor;
  }

  /// `bubble_group_gap_dp` / `bubble_separate_gap_dp`. Half of a gap goes into
  /// the top padding of a message and half into the bottom padding of the
  /// neighbour, so a pair of messages adds up to the target.
  static const double groupGapPerSide = 1;
  static const double interGroupGapPerSide = 4;

  /// `bubble_sender_gap_dp` = 8.5 dp of row padding, which is the measured
  /// 8.0 dp of black between two bubbles across a sender change (4.25 per
  /// side: the capture's fill-edge reading runs ~1.5 px under the layout box
  /// per edge at 2.625 px/dp, so the band a pair lays out reads 1-2 px small).
  ///
  /// Telegram folds a group's whole vertical spacing into the cell's own
  /// padding (`ChatMessageCell.java:11238`: `setPadding(0,
  /// starsPriceTopPadding + topicSeparatorTopPadding +
  /// suggestionOfferTopPadding, 0, askBotForumBottomPadding)`) - the space
  /// between two bubbles IS the sender gap there, with no block margin under
  /// it. Their source states no dp number for the sender change, so this value
  /// is measured: (21 px) = 8.0 dp on a user's Telegram capture
  /// `a measurement crop`, three runs (18-21 px) = 6.9-8.0
  /// dp.
  ///
  /// This constant is only the layout half of the gap. Measured fill-to-fill
  /// on a user's FluffyGram capture `the reference capture`
  /// (build 19, column x 400) the band across a sender change is
  /// (125 px) = 47.6 dp, not 8: the sender name line draws OUTSIDE and above
  /// the bubble fill (`the measurement log` row 15, T34 finding 14), so its
  /// 15.6 dp line box sits inside the band. Telegram keeps the name inside the
  /// fill, which is why its band measures (18-21 px) = 6.9-8.0 dp. Finding 11
  /// stays open until the name moves inside. An earlier pass read 6.5-7.6 dp
  /// for our side by profiling `the reference capture` - that file is
  /// a user's Telegram capture.
  static const double senderGapPerSide = 4.25;

  /// `timeline_avatar_diameter_dp`.
  static const double avatarSize = 42;

  /// `bubble_incoming_left_margin_dp` = 8 edge margin + 42 avatar + this gap.
  static const double incomingGapAfterAvatar = 6;

  /// `bubble_outgoing_right_margin_dp` = 8 edge margin + this gap.
  static const double outgoingGapAfterEdge = 3;

  /// Type scale: timestamp 12sp, sender name 14sp bold.
  static const double timestampFontSize = 12;

  /// Sender name 14sp bold. Re-measured on `the reference capture` at
  /// 2.75 px/dp: the capital C of the gold sender name inks 28 px tall and the
  /// capital N of the body line under it 30 px, so the name is 0.93 of the
  /// 16sp body (14.9sp) and its cap height alone reads 14.3sp. The shipped 14
  /// sits inside that bracket, so no new value was invented.
  static const double senderNameFontSize = 14;

  /// The gap under a group sender name, inside the bubble.
  ///
  /// Measured on a user capture `the reference capture` at
  /// 2.625 px/dp: the name's ink bottom (the quoted name's baseline band ends at
  /// y=677) sits 26 px = 9.9 dp above the body's ink top (the 'P' cap starts at
  /// y=703), and name-line top to body-line top is 53 px (20.2 dp) against a
  /// body pitch of 16 sp.
  ///
  /// A third pair, measured 2026-10-26 on a user's phone capture
  /// `the reference capture` at the same scale, reads 21, 23 and 21 px
  /// = 8.0, 8.8 and 8.0 dp, and a user flagged the fork's stack as too tall
  /// the same day. The median of the four pairs (8.0, 8.0, 8.8, 9.9) is 8.4 dp.
  ///
  /// A 14 sp label box carries about 3.4 dp of box below its baseline and a
  /// 16 sp body box about 3.5 dp above its cap, so the visible total is the
  /// constant plus 6.9 dp. 7 dp measured in the fork's own render as 42 px =
  /// 14 dp visible; 1.5 dp lands the visible total at 8.4 dp. The split
  /// between the two text boxes is Flutter's, not measured; the visible total
  /// is.
  static const double senderNameGapBelow = 1.5;

  /// T34 finding 14 - the name box's own top inset, on a TEXT bubble.
  ///
  /// Measured on a user captures at 2.625 px/dp
  /// (`the measurement log` rows 15, 17: `the reference capture`
  /// = Telegram, `the reference capture` = FluffyGram): Telegram's
  /// name cap inks (18 px) = 6.9 dp BELOW the fill's top edge - the name is
  /// inside the fill, at its top-left - while the fork's row 15 read put our
  /// name ink above the fill. Telegram's code agrees: the name box sits at
  /// `dp(10)` from the bubble top (`ChatMessageCell.java:21330`
  /// `nameY = dp(10)`) and the message content starts at `dp(12) +
  /// getNameHeightAnimated() + dp(1)` (`ChatMessageCell.java:20321`).
  ///
  /// Flutter's box starts its own cap 2.3 dp below the box top at 14 sp
  /// (Roboto ascent 0.9277 em = 13.0 dp against the measured cap (28 px) =
  /// 10.7 dp), so the box top sits at 6.9 - 2.3 = 4.6 dp inside the fill.
  ///
  /// The same pair's second row (17) reads (34 px) = 13.0 dp from the name's
  /// baseline to the first body line's ink. On a text row the visible gap is
  /// `senderNameGapBelow` (1.5 dp) + the 7 dp `paddingV` the text content box
  /// carries above its own first line (`message_content.dart:225-229`) + the
  /// 6.9 dp the two text boxes add themselves = 15.4 dp, so the row is 2.4 dp
  /// over that pair, and the value that would hit 13.0 dp is -0.9 dp - a
  /// negative gap. The same capture reads its three other pairs at (21, 23,
  /// 21 px) = 8.0, 8.8, 8.0 dp (the spread documented on
  /// `senderNameGapBelow`), so one pair inside that spread does not move a
  /// shipped constant. The gap goes to a user's eye on the web demo; this
  /// commit moves the position only.
  static const double senderNameTopInset = 4.6;

  /// `quote_inset_left_dp` / `quote_inset_right_dp` - the reply quote panel
  /// spans the bubble interior and is inset 1.1 dp from the bubble edge on both
  /// sides, and the panel is NOT edge to edge. Owner finding 2026-10-27, and
  /// the pair is measured on the OWNER's own Telegram capture
  /// `the reference capture` at 2.625 px/dp, over the FULL image (the
  /// 3 px pair this replaces, shipped in build 48, was read off a translated
  /// crop: the crop's x 0 was not the screen's x 0, so the insets it reported
  /// were the crop's, not the bubble's). Two quotes, measured straight from the
  /// screen pixels:
  ///
  /// | Quote | Bubble x | Panel fill x | Lead inset | Trail inset |
  /// | --- | --- | --- | --- | --- |
  /// | amber | 155..923 | 190..891 | 35 px = 13.3 dp | 32 px = 12.2 dp |
  /// | salmon | 155..887 | 190..855 | 35 px = 13.3 dp | 32 px = 12.2 dp |
  ///
  /// Both quotes land on the same pair, so it is a padding rule and not a
  /// property of the quoted text. Inside the panel the quoted ink starts 25 px =
  /// 9.5 dp past the fill (`ReplyContent.panelInsetLeft` carries it), and the 3
  /// dp accent bar sits immediately OUTSIDE the fill - amber bar x 182..189,
  /// fill from x 190 - so it reads as flush against the panel, which is what the
  /// panel's own clip gives us.
  static const double quoteInsetLeft = 13.3;
  static const double quoteInsetRight = 12.2;

  /// `timestamp_inline_gap_dp` - gap between the message text and the
  /// timestamp + ticks that sit inline on the bubble's last line.
  static const double timestampInlineGap = 6;

  /// The gutter the timestamp box keeps from the message text. Telegram's
  /// `getTimeExtra()` reserves the time box **plus** this inset, so the last
  /// text line ends before the time and never under it
  /// (`ChatMessageCell.java:3396`). Phone measurement: an outgoing text row
  /// loses 47.2 dp of its last line (124 px at 2.625 on
  /// `the reference capture`) - the 12 sp time box, the 12 dp tick
  /// box, the 6 dp inline gap and this 12 dp.
  static const double timestampReserveGap = 5;

  /// Distance from the timestamp's box to the bubble's inner side edge - the
  /// phone measures 19 px = 7.2 dp from the time's cap edge to the bubble edge
  /// (`the reference capture` pair B, row 2). Telegram's time rect is
  /// inset 12 dp and the glyph box carries its own leading, so the ink lands
  /// at 7.2.
  static const double timestampEdgeMargin = 7.2;

  /// The tick glyph box: the checks share the 12sp line of the timestamp.
  static const double tickGlyphSize = 12;

  /// Fallback height of the in-bubble meta line (the 12sp timestamp box the
  /// text wraps around). The bubble measures its own meta and uses the real
  /// number; this is the reserve for a meta it cannot measure.
  static const double timestampMetaBoxHeight = 14;

  /// A message still on its way to the server draws its single check faded.
  static const double sendingTickOpacity = 0.4;
}

/// The Telegram bubble outline: `TelegramBubbleGeometry.cornerRadius` on the
/// corners that face open space (15dp at a user's slider value 17, because
/// Telegram draws `slider - 2`), a tight 3dp corner carrying the tail wedge on
/// the outer bottom corner (bottom-left for incoming, bottom-right for outgoing)
/// when [tail] is set.
///
/// `ShapeDecoration(color: ..., shape: TelegramBubbleShape(...))` fills the
/// outline with the bubble colour. The body fills the box and the tail reaches
/// [TelegramBubbleGeometry.tailWidth] beyond its outer edge, like Telegram:
/// the bubble column stays aligned and the tail fills the edge margin. Cap the
/// body at `maxBubbleWidth - tailWidth` so bubble plus tail stays inside the
/// cap.
class TelegramBubbleShape extends ShapeBorder {
  const TelegramBubbleShape({this.tail = false, this.tailOnLeft = false});

  /// Draw the tail: true on the last (newest) message of a run by one sender.
  final bool tail;

  /// Incoming bubbles point left, outgoing bubbles point right.
  final bool tailOnLeft;

  /// The bubble outline for [rect]: the body rounded rect plus the tail wedge.
  static Path buildPath({
    required Rect rect,
    required bool tail,
    required bool tailOnLeft,
  }) {
    // The body fills the box; the tail wedge reaches `tailWidth` beyond its
    // outer edge, so callers cap the body at `maxBubbleWidth - tailWidth`.
    final body = rect;
    const corner = Radius.circular(TelegramBubbleGeometry.cornerRadius);
    const tailCorner = Radius.circular(
      TelegramBubbleGeometry.tailSideCornerRadius,
    );
    final path = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          body,
          topLeft: corner,
          topRight: corner,
          bottomLeft: tailOnLeft ? tailCorner : corner,
          bottomRight: tailOnLeft ? corner : tailCorner,
        ),
      );
    if (!tail) return path;
    const w = TelegramBubbleGeometry.tailWidth;
    const h = TelegramBubbleGeometry.tailHeight;
    final wedge = Path();
    if (tailOnLeft) {
      wedge
        ..moveTo(body.left, body.bottom - w)
        ..quadraticBezierTo(
          body.left - w * .85,
          body.bottom - h * .5,
          body.left - w,
          body.bottom,
        )
        ..lineTo(body.left + h, body.bottom)
        ..close();
    } else {
      wedge
        ..moveTo(body.right, body.bottom - w)
        ..quadraticBezierTo(
          body.right + w * .85,
          body.bottom - h * .5,
          body.right + w,
          body.bottom,
        )
        ..lineTo(body.right - h, body.bottom)
        ..close();
    }
    // The wedge winds the same way as the rrect, so the default non-zero fill
    // unions the two sub-paths instead of punching a hole where they overlap.
    path.addPath(wedge, Offset.zero);
    return path;
  }

  /// The corner set of the outline, for the widgets that clip with a
  /// `BorderRadius` (`MessageContent`, `ImageBubble`).
  static BorderRadius borderRadius({required bool tailOnLeft}) {
    const corner = Radius.circular(TelegramBubbleGeometry.cornerRadius);
    const tailCorner = Radius.circular(
      TelegramBubbleGeometry.tailSideCornerRadius,
    );
    return BorderRadius.only(
      topLeft: corner,
      topRight: corner,
      bottomLeft: tailOnLeft ? tailCorner : corner,
      bottomRight: tailOnLeft ? corner : tailCorner,
    );
  }

  Path _outline(Rect rect, TextDirection? textDirection) =>
      buildPath(rect: rect, tail: tail, tailOnLeft: tailOnLeft);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _outline(rect, textDirection);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _outline(rect, textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    // No border: `ShapeDecoration.color` fills `getInnerPath`, which is the
    // bubble body plus the tail wedge.
  }

  @override
  ShapeBorder scale(double t) => this;
}
