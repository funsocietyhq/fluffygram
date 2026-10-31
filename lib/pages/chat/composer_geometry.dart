// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:material_ui/material_ui.dart';

/// Composer geometry and type scale from `verification/telegram-target.json`
/// (`geometry` + `typography`, measured 2026-10-24 in screenshot 112025 at
/// 2.75 px/dp; dp = Flutter logical pixels here). Kept in one file so the
/// composer widgets read named numbers instead of literals, and so
/// `verification/spec_app` can copy this file into the golden rig - which is
/// why it imports nothing but Material.
abstract final class TelegramComposerGeometry {
  /// `composer_field_height_dp` - the height the composer pill measures.
  /// Re-measured 2026-10-25 on a user's capture with an empty composer,
  /// `the reference capture`: the pill spans y = 2221..2336 = 116 px at
  /// 2.625 px/dp. [fieldMinHeight] is the same number.
  static const double fieldHeight = 44;

  /// `composer_field_min_height_dp` - one text line, the pill never shrinks.
  static const double fieldMinHeight = 44;

  /// `composer_field_max_height_dp` - the pill scrolls past this.
  static const double fieldMaxHeight = 140;

  /// `composer_field_radius_dp` - exactly half of [fieldMinHeight]: a full
  /// pill, not a rounded rectangle. Half the height is what a user's capture
  /// solves for on the field above it (a 104 px search field gives r = 19.7 dp at
  /// 6 px below its top edge).
  static const double fieldRadius = 22;

  /// `composer_side_button_diameter_dp` - the flat circle at the ends of the
  /// row (attach on the left, mic / send on the right). Measured 2026-10-25 in
  /// `the reference capture`: the mic disc spans y = 2221..2336 = 116 px
  /// at its centre (x = 1005) and 90 px at x = 1040 - a 44.2 dp circle, the same
  /// height as the pill.
  static const double sideButtonDiameter = 44;

  /// `composer_emoji_button_diameter_dp` - the box of the button at the pill's
  /// left end, which opens the emoji / GIF / sticker tray. Telegram gives it
  /// `DEFAULT_HEIGHT x DEFAULT_HEIGHT` = **44 x 44 dp** with a `dp(2)` left inset
  /// (`ChatActivityEnterView.java:2755`, `DEFAULT_HEIGHT = 44` at `:6469`), and
  /// the glyph inside is smaller than the box: the GIF badge Telegram draws there
  /// measures **25 x 22 dp** of ink in `the reference capture` (x = 50..115,
  /// y = 2250..2303 at 2.625 px/dp). The 33 dp this fork carried was the glyph, not
  /// the box - user, 2026-10-31: "make the left tray button the same too".
  static const double emojiButtonDiameter = 44;

  /// The gap between the left button's box and the text. Measured on the same
  /// capture: Telegram's 44 dp box ends at x = 19 px + dp(2) + 44 dp = 139.75 px
  /// and the hint ink starts at x = 151 px, so the gap is 11.25 px = **4.3 dp**.
  /// With [edgeMargin] 9 and a 44 dp box this puts our text ink on x = 57.5 dp,
  /// which is where Telegram's sits (151 px at 2.625 px/dp).
  static const double buttonTextGap = 4.5;

  /// `composer_h_margin_dp` - the row's margin from the screen edge.
  static const double edgeMargin = 9;

  /// `composer_pill_left_inset_dp` - where the pill starts, measured from the
  /// screen edge: the attach column sits left of it.
  static const double pillLeftInset = 107;

  /// The space the left column leaves between its two circles and the pill, so
  /// the pill's left edge lands on [pillLeftInset]. Telegram fills part of it
  /// with its camera button; FluffyChat has no composer camera button, so the
  /// gap stays. Not in the target - it is the remainder of [pillLeftInset].
  static const double leftColumnGap =
      pillLeftInset - edgeMargin - sideButtonDiameter - emojiButtonDiameter;

  /// `composer_text_dp` - the field's text and hint size. Telegram sets it in
  /// source: `messageEditText.setTextSize(COMPLEX_UNIT_DIP, 18)` at
  /// `ChatActivityEnterView.java:5811`. The 16 this fork carried came from a
  /// capture read; the ink says 18 too - the hint "Message" spans y = 2247..2309
  /// = 63 px = 24 dp of ascender-plus-descender at 2.625 px/dp, which is the 1.17
  /// em line the message text uses at an 18 dp size, not at 16. Owner,
  /// 2026-10-31: "Make the text input the same size as telegram".
  static const double textFontSize = 18;

  /// Field line height, the same ratio the message text uses (1.22).
  static const double textLineHeight = 1.22;

  /// How many text lines fit inside the pill's [fieldMaxHeight] box -
  /// `(fieldMaxHeight - 2 * pillVerticalPadding) / (textFontSize *
  /// textLineHeight)` = (140 - 20) / (18 * 1.22) = 5.5 - passed to the field as
  /// `maxLines` so the field never grows past the measured maximum. It was 6 while
  /// [textFontSize] was 16.
  static const int maxFieldLines = 5;

  // --- values the target does not measure (layout padding, glyph size) ---

  /// Inner padding of the pill on the text's **right** side, between the text and
  /// the paperclip. Telegram's paperclip ink ends 21.7 dp inside the pill's right
  /// edge (`the reference capture`); the 44 dp button box plus this gap
  /// covers it. The left side uses [buttonTextGap] instead.
  static const double pillHorizontalPadding = 16;

  /// Inner padding of the pill, above and below the text. Not measured.
  static const double pillVerticalPadding = 10;

  /// Glyph size of the flat side buttons inside their circles. Not measured.
  static const double sideIconSize = 24;

  /// Text ink of the field (the caret takes it too). Layout value.
  static const double fieldCaretWidth = 2;

  // --- reply quote strip above the field ---

  /// `reply_quote_bar_width_dp` - the accent bar of the quoted sender.
  static const double replyBarWidth = 3;

  /// `reply_quote_bar_radius_dp`.
  static const double replyBarRadius = 2;

  /// `reply_quote_padding_dp` - padding inside the quote strip.
  static const double replyPadding = 6;

  /// `reply_quote_max_lines` - lines the quoted text may take.
  ///
  /// Owner instruction 2026-10-27: "quoted messages should be cut off with
  /// ellipsis before they wrap to separate lines". Telegram's own cell allows
  /// 4 name / 6 text lines (`ChatMessageCell.java:8094,8179`); a user puts
  /// the timeline quote at ONE truncated line, and the fork ships a user's
  /// value. This supersedes the 2026-10-26 report that set 3 lines
  /// (ROADMAP Decisions).
  static const int replyMaxLines = 1;

  /// `reply_quote_text_sp` - the quoted text line of the strip.
  static const double replyTextFontSize = 14;

  /// `reply_quote_name_sp` / `reply_quote_name_weight` - the quoted sender.
  static const double replyNameFontSize = 14;
  static const FontWeight replyNameFontWeight = FontWeight.w700;

  /// --- the composer reply ROW itself, T127 (`ChatReplyContainer.java:122-135`) ---

  /// `ChatReplyContainer.java:122` - the reply row is 46 dp tall.
  static const double replyRowHeight = 46;

  /// `ChatReplyContainer.java:123` - the glyph column is 52 dp wide. The text lines
  /// start at x 52, so this column IS the left inset; there is no accent bar.
  static const double replyIconColumn = 52;

  /// `ChatActivity.java:8212` - `addReplyView(reactionRow, 0, 0, 52, 0)` reserves a
  /// 52 dp column at the right end of the row for the close button.
  static const double replyCloseColumn = 52;

  /// `ChatReplyContainer.java:126,131` - both text frames are 18 dp tall, the label at
  /// y 6 and the quoted text at y 24.
  static const double replyLineHeight = 18;
  static const double replyTextBlockTop = 6;

  /// The reply-arrow / pencil glyph and the close glyph. Telegram draws its own
  /// `msg_reply` (a curved arrow with a branch node) at ~20 dp; `Icons.reply` is the
  /// nearest Flutter glyph and Telegram's asset may not be copied.
  static const double replyGlyphSize = 20;

  /// The reply strip's tint: the quoted sender's colour over
  /// `composer_pill_bg` at about 12 %. Telegram tints the quote block the same
  /// way (`reply_quote_block_bg` in the target). Alpha, not a measured value.
  static const int replyStripTintAlpha = 31;

  /// Corner radius of the reply strip: a pill segment, so half its own height.
  /// Not measured.
  static const double replyStripRadius = 12;

  /// Gap between the reply strip and the pill. Not measured.
  static const double replyStripGap = 6;

  /// Margin around the reply strip, so it lines up with the pill column.
  static const double replyStripMargin = edgeMargin;

  /// The strip background: the quoted sender's colour at
  /// [replyStripTintAlpha] over the composer pill.
  static Color replyStripColor(Color senderColor, Color pillColor) =>
      Color.alphaBlend(senderColor.withAlpha(replyStripTintAlpha), pillColor);

  // --- mention picker ---

  /// Avatar of one row of the `@` mention picker (Telegram's picker rows show
  /// a 40 dp avatar next to the coloured name). `chat_list_avatar_dp` is the
  /// same 40; the picker itself is not measured.
  static const double mentionAvatarSize = 40;
}
