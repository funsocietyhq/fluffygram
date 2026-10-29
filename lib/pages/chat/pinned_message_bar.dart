// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The pinned message bar, drawn the way Telegram draws it (roadmap T28).
///
/// A rounded panel inset from both screen edges, holding: a thin accent strip on
/// its leading edge, the label line "Pinned Message" in the accent ink, the pinned
/// content under it (text, or a rich preview), and a small pin glyph at the
/// trailing end that opens the pinned-messages list. The close glyph this bar used
/// to carry is ours, not Telegram's, and it is gone.
///
/// Measured on a user's Pixel Telegram capture
/// `the reference capture` (1080 px wide, 1 dp = 2.625 px): band
/// y 318..455 = 52.6 dp tall, left edge x 23 = 8.8 dp in, leading accent strip
/// x 48..56 = 3.0 dp wide in `#676D87`, panel fill tinted `#3B3D47` at x 60 next to
/// that strip, label ink `#6C7491` (the antialiased ink of the same accent),
/// preview ink white, trailing pin glyph x 994..1025 = 11.8 dp, centred in the
/// band. The corner radius keeps the T20 reading of 15 dp: this capture's left arc
/// measures 34 px = 13 dp, inside the top-edge uncertainty (the top edge lies
/// between y 312 and 330). Table, arithmetic and the readings this pass added:
/// `the measurement log`, section "Pinned message bar, measured on a user's
/// phone (T28)". Keys: `pinned_bar_*` in `verification/telegram-target.json`.
///
/// The bar is a text-preview bar. Telegram grows it for rich content - the same
/// capture shows a 216 dp link-preview card starting at y 456 - and that growth is
/// not built here. Paging several pinned messages (`1 of 3`, swipe) needs a capture
/// that shows more than one pin, and is named in `the project log`.
///
/// This widget serves the pinned bar only. The thread tile and the scroll-up banner
/// keep `ChatAppBarListTile` at its 40 dp row height.
library;

import 'package:fluffychat/config/telegram_palette.dart';
import 'package:flutter/material.dart';

class PinnedMessageBar extends StatelessWidget {
  /// Panel height: 137 measured px at 2.625 px/dp. `chat_view.dart` adds this to
  /// the app bar bottom slot, so the timeline starts below the panel. A text
  /// preview fills it; rich content is a separate, unbuilt case.
  static const double fixedHeight = 52.6;

  /// Gap between the panel and each screen edge: the measured left edge is x 23.
  /// The measured right edge (x 1025) is the trailing glyph's ink, so the panel
  /// keeps one inset on both sides.
  static const double sideInset = 8.8;

  /// Panel corner radius: the T20 arc reading, 15 dp. This capture's arc measures
  /// 13 dp, which is inside its top-edge reading (y 312..330).
  static const double cornerRadius = 15.0;

  /// The accent strip on the panel's leading edge: 8 measured px at 2.625 px/dp.
  /// It runs the height of the panel and is clipped by its corner rounding.
  static const double accentStripWidth = 3.0;

  /// Leading sender avatar of the pinned message: measured 84 px ink box at
  /// 2.625 px/dp (T20, on `the reference capture`).
  static const double avatarSize = 32.0;

  /// Gap between the panel edge and its content, measured at the top and the
  /// bottom of the panel, and kept at the trailing end.
  static const double contentPadding = 8.0;

  /// Both text lines. Measured ink boxes: 36 px tall for the label, 44 px for the
  /// preview with its descenders, and a 40 px line pitch.
  static const double fontSize = 14.0;

  /// The trailing pin glyph: 31 measured px at 2.625 px/dp, centred in the band.
  static const double pinGlyphSize = 11.8;

  final Widget? leading;
  final String label;
  final String preview;

  /// How many messages are pinned. The count is shown beside the glyph when there
  /// is more than one; paging through them is a separate case (see the header).
  final int pinCount;

  final void Function()? onTap;

  /// Opens the pinned-messages list. The trailing glyph and the panel share it.
  final void Function()? onOpenPinList;

  const PinnedMessageBar({
    super.key,
    this.leading,
    required this.label,
    required this.preview,
    this.pinCount = 1,
    this.onTap,
    this.onOpenPinList,
  });

  @override
  Widget build(BuildContext context) {
    final leading = this.leading;
    return SizedBox(
      height: fixedHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: sideInset),
        child: Container(
          key: const Key('pinned-message-bar-panel'),
          decoration: BoxDecoration(
            // T36 (2026-10-27): the panel body is a flat opaque fill. The
            // two-stop gradient shipped in 3ecc3fc56 painted on a user's
            // Pixel as a neutral, leading-dark wash - #131313 at x 50 rising
            // to #222223 at x 700 (saturation 0.32 -> 0.03), the inverse of
            // the coded #3B3D47 -> #282D3B navy ramp - probe on
            // the reference capture (the measurement log,
            // finding 30, T36 probe). One opaque color is one paint with no
            // gradient compositing to invert: the body lands #282D3B.
            // The x 60 `pinnedBarFillNearStrip` reading was taken through
            // Telegram's translucent panel over its wallpaper; the panel
            // body keeps the T20 fill value, the strip keeps its ink.
            color: TelegramPalette.pinnedBarBackground,
            borderRadius: const BorderRadius.all(Radius.circular(cornerRadius)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(onTap: onTap ?? onOpenPinList),
                ),
              ),
              Row(
                children: [
                  SizedBox(
                    width: accentStripWidth,
                    height: fixedHeight,
                    child: ColoredBox(
                      key: const Key('pinned-bar-accent-strip'),
                      color: TelegramPalette.pinnedBarAccent,
                    ),
                  ),
                  const SizedBox(width: contentPadding),
                  if (leading != null) ...[
                    leading,
                    const SizedBox(width: contentPadding),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          key: const Key('pinned-bar-label'),
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            // Measured: the label line takes the accent, and
                            // Telegram pulls that accent brighter than the strip
                            // of the same bar - its own constant (T36; the phone
                            // read the strip value verbatim at build 21, 5-10
                            // units under the target).
                            color: TelegramPalette.pinnedLabelInk,
                            fontSize: fontSize,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          key: const Key('pinned-bar-preview'),
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: TelegramPalette.pinnedMessagePreview,
                            fontSize: fontSize,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pinCount > 1)
                    Text(
                      '$pinCount',
                      style: const TextStyle(
                        color: TelegramPalette.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  // Telegram ends the bar with a pin, centred in the band, and it
                  // opens the pinned-messages list. Mean luminance of the measured
                  // glyph box is 42.7/255: dim ink, not white.
                  IconButton(
                    key: const Key('pinned-bar-pin-glyph'),
                    // The measured glyph ink box is 11.8 dp, so the icon carries
                    // the size itself, not only the button's icon theme.
                    icon: const Icon(Icons.push_pin, size: pinGlyphSize),
                    iconSize: pinGlyphSize,
                    visualDensity: VisualDensity.compact,
                    color: TelegramPalette.textSecondary,
                    onPressed: onOpenPinList,
                  ),
                  const SizedBox(width: contentPadding / 2),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
