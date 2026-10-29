// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:material_ui/material_ui.dart';

/// Chat-list geometry and type scale. The row, avatar, margin, type and badge
/// numbers were re-measured on 2026-10-25 from a user's real chat-list
/// capture `the reference capture` (night theme, 1080x2424, 2.625
/// px/dp); the arithmetic is in `the project log` and in the work-dir note
/// `the measurement log`. `verification/telegram-target.json` still holds
/// the old screenshot-112035 numbers and needs one rig pass to move - see the
/// `docs/TELEGRAM_TARGET.md` Changelog. dp = Flutter logical pixels here.
abstract final class ChatListGeometry {
  /// `chat_list_row_height_dp` - one title line + one preview line.
  static const double rowHeight = 70;

  /// `chat_list_avatar_dp` - the avatar circle. `chat_list_avatar_corner_dp`
  /// is 26, measured: the corner fits a circle of radius 25.75 dp, half the
  /// 52.2 dp diameter, so the default `size / 2` radius of [Avatar] is what
  /// Telegram draws.
  static const double avatarSize = 52;

  /// `chat_list_h_padding_dp` - the avatar's margin from the screen edge.
  static const double edgeMargin = 11;

  /// `chat_list_text_left_margin_dp` - where the title and preview start.
  static const double textLeftMargin = 77;

  /// The gap the tile puts between the avatar and the text column:
  /// `textLeftMargin - avatarSize - edgeMargin`, passed to
  /// `ListTile.horizontalTitleGap`.
  static const double avatarToTextGap =
      textLeftMargin - avatarSize - edgeMargin;

  /// Half of the free row height: `(rowHeight - avatarSize) / 2`, passed to
  /// `ListTile.minVerticalPadding`.
  static const double rowVerticalPadding = (rowHeight - avatarSize) / 2;

  // --- type scale ---
  /// `chat_list_title_sp` / `chat_list_title_weight`.
  static const double titleFontSize = 17;
  static const FontWeight titleFontWeight = FontWeight.w400;

  /// `chat_list_preview_sp`.
  static const double previewFontSize = 16;

  /// `chat_list_sender_prefix_sp` / `chat_list_sender_prefix_weight` -
  /// `Theme.dialogs_messageNamePaint.setTextSize(dp(14))` (`Theme.java:7896`),
  /// bold (`Theme.java:7822-7823`). The 16 this file carried was a band
  /// measurement of the preview line, which cannot separate a 14 from the 16
  /// next to it; the source value is 14 (T43.1, 2026-10-27).
  static const double senderPrefixFontSize = 14;
  static const FontWeight senderPrefixFontWeight = FontWeight.bold;

  /// `chat_list_time_sp`.
  static const double timeFontSize = 12;

  /// `chat_list_unread_badge_sp`.
  static const double badgeFontSize = 12;

  // The unread badge, source-measured on Telegram's DialogCell.java 2026-10-27
  // (T44). BADGE_SIZE 20.666f is the height and the width of a single-digit
  // badge (DialogCell.java:1230); the corner radius is the draw call's
  // dp(11.5) (DialogCell.java:5342, 5394); the text padding is
  // BADGE_TEXT_PADDING 6.333f per side (DialogCell.java:1231). Line 1229
  // states BADGE_SIZE = BADGE_TEXT_PADDING * 2 + BADGE_TEXT_MIN_WIDTH
  // (6.333 * 2 + 8), so a one-digit count is a round disc and a longer count
  // a pill.
  static const double badgeMinWidth = 20.666;
  static const double badgeHeight = 20.666;
  static const double badgeRadius = 11.5;
  static const double badgeTextPadding = 6.333;

  // --- online presence dot (T49) ---
  // Source-measured on Telegram's DialogCell.java 2026-10-27, the draw of
  // `key_chats_onlineCircle` on a direct chat's avatar. The centre sits dp(6)
  // in from the avatar rect's right edge (`:5125`) and dp(8) above its bottom
  // (`:5120`) - the phone layout; the three-lines layout moves them to dp(10)
  // and dp(6) and this fork draws the phone row. Both discs draw at that
  // centre: the ring of page-background colour at dp(7) (`:5128-5129`), the
  // online ink at dp(5) (`:5130-5131`). `onlineProgress` multiplies both radii
  // and walks 16f/150f per frame, so the marker grows in over 150 ms and shrinks
  // out on the same ramp (`:5132-5148`). Only a direct chat with an online peer
  // draws it (`:5116-5131`); a chat row falls to the `chat != null` branch at
  // `:5150`, which paints no marker.

  /// Inset of the dot centre from the avatar box's right edge.
  static const double onlineDotRightInset = 6;

  /// Inset of the dot centre from the avatar box's bottom edge.
  static const double onlineDotBottomInset = 8;

  /// Radius of the ring disc, painted in the page field colour.
  static const double onlineDotRingRadius = 7;

  /// Radius of the online ink disc, drawn over the ring.
  static const double onlineDotRadius = 5;

  /// How long the dot takes to grow in (and to shrink out).
  static const Duration onlineDotGrowDuration = Duration(milliseconds: 150);

  // --- search field ---
  // Measured on a user's chat-list capture `the reference capture`
  // (1080 px wide at 2.625 px/dp): the field is 104 px tall, its corners solve to
  // a stadium, and it stands 30 px from each screen edge.

  /// `chat_list_search_field_height_dp` - 104 px = 39.6 dp.
  static const double searchFieldHeight = 39.6;

  /// `chat_list_search_field_radius_dp` - half of [searchFieldHeight]: the measured
  /// corners read 19.7 dp, so the fill is a stadium.
  static const double searchFieldRadius = searchFieldHeight / 2;

  /// `chat_list_search_field_inset_dp` - 30 px = 11.4 dp. Applied here as the inset
  /// of the text and hint inside the fill, which is what the capture reads at the
  /// text edge; the bar's own margin from the screen edge belongs to the app bar.
  static const double searchFieldInset = 11.4;

  /// The vertical content padding that puts the input container on
  /// [searchFieldHeight] with `isDense: true` at this type size.
  static const double searchFieldVerticalPadding = 9;

  /// `chat_list_folder_tab_height_dp` / `..._radius_dp` / `folder_tab_sp`.
  static const double folderTabHeight = 20;
  static const double folderTabRadius = 10;
  static const double folderTabFontSize = 13;

  /// `chat_list_section_header_sp` - section headers above a group of rows.
  static const double sectionHeaderFontSize = 13;
}
