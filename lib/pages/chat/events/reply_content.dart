// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../../config/telegram_palette.dart';
import '../../../utils/string_color.dart';
import '../composer_geometry.dart';

/// Telegram's reply quote panel, as measured on a user's captures.
///
/// Everything the panel paints follows the **quoted sender**, not the theme
/// accent: the 3 dp bar, the quoted sender name and the tint of the panel
/// itself. A user's captures show one bubble quoting one member drawing a
/// gold bar with a gold name, and another bubble quoting a different member
/// drawing a salmon bar with a salmon name; Telegram keeps `chat_inReplyLine`,
/// `chat_outReplyLine` and `chat_outReplyLine2` as three separate palette
/// keys, so it is not one accent either.
class ReplyContent extends StatelessWidget {
  final Event replyEvent;
  final bool ownMessage;
  final Timeline? timeline;

  /// The fill the panel sits on - the bubble fill for an in-bubble quote. When
  /// it is null the quote paints no panel of its own, because the caller
  /// already paints one: the composer reply strip of `reply_display.dart`
  /// tints itself with the same sender colour at its own measured ratio.
  final Color? bubbleFill;

  const ReplyContent(
    this.replyEvent, {
    this.ownMessage = false,
    super.key,
    this.timeline,
    this.bubbleFill,
  });

  // Uniform corners, the pinned bar's pattern (`PinnedMessageBar.cornerRadius`
  // is a `BorderRadius.all`). Owner finding 2026-10-28: "the left side of a
  // quoted message needs the curve just like we have for pinned messages" -
  // the leading corners were square, so the accent bar met the panel fill at
  // a right angle. Telegram's own quote panel rounds all four corners:
  // `QuoteHighlight.java:281` takes `lerp(dp(4), 0, t)`; we keep this panel's
  // measured radius (`reply_quote_corner` 11 dp, docs/TELEGRAM_TARGET.md) on
  // every corner so the curve matches the trailing side a user already
  // accepted. The 3 dp bar carries no radius: `clipBehavior` rounds it.
  static const BorderRadius borderRadius = BorderRadius.all(
    Radius.circular(panelRadius),
  );

  /// Corner radius of the in-bubble reply quote panel.
  ///
  /// Owner phone pass on build 49 (2026-10-28): "too much rounding on the
  /// quoted messages, probably about half that" - the panel carried the
  /// measured `reply_quote_corner` 11 dp, and on the phone it reads as a pill,
  /// not a strip. Halved to 5.5 dp.
  static const double panelRadius = 5.5;

  /// Air above and below the two quoted text lines inside the panel.
  ///
  /// Owner phone pass on build 49 (2026-10-28): "on quoted messages, add a
  /// SLIGHT vertical padding" - the panel's height was exactly the two text
  /// lines, so the name sat flush with the panel top. 2 dp is the slight.
  static const double panelPaddingVertical = 2;

  /// Gap from the accent strip to the quoted text. The strip itself is flush
  /// with the panel's leading edge - this is the padding *after* it, the same
  /// role as `PinnedMessageBar.contentPadding`.
  ///
  /// 6.5 puts the quoted ink 3 + 6.5 = 9.5 dp inside the panel, which is the
  /// measurement: on `the reference capture` the amber quote's fill
  /// starts at x 190 and its quoted ink at x 215 - 25 px = 9.5 dp (the 3 dp bar
  /// sits immediately outside the fill there, x 182..189, so it is inside our
  /// panel rect and its width counts against this inset). Owner finding
  /// 2026-10-28, "need horizontal padding on quoted message bubbles".
  static const double panelInsetLeft = 6.5;

  /// The panel's inset past the quoted ink on its trailing side.
  static const double panelInsetRight = 6;

  /// Alpha of the accent bar: the quoted sender's palette colour at 60 %.
  static const double barAlpha = 0.6;

  /// The panel fill is the quoted sender's colour at 10 % over the bubble fill
  /// - the rule read off two Telegram bubbles on a user's phone: a salmon
  /// quote gives `#322829` and a cyan quote `#232F30`, both over the `#1E1E20`
  /// bubble, and 0.10 of the sender over the bubble reproduces both (arithmetic
  /// in `the measurement log`, "Reply quote panel tint"). Telegram's
  /// `ChatMessageCell.java:14413` paints the same thing as
  /// `multAlpha(chat_inReplyLine, .2f)` over the bubble: a sender-tinted panel,
  /// never the bubble colour itself. Owner revision 2026-10-27: with the panel
  /// spanning the bubble interior, a bubble-coloured panel would draw nothing.
  static const double panelTintAlpha = 0.10;

  /// The panel carries no fill of its own. Owner revision 2026-10-26
  /// (finding 26): the in-bubble quote panel takes the SAME colour as the
  /// bubble it sits in - the caller's [bubbleFill] - so the quote reads as a
  /// region of the bubble, defined by its bar and its name line, not as a
  /// separate box. Superseded: finding 16's flat `#242426` of the same day,
  /// and before it the sender-tint blend (both recorded in
  /// `docs/TELEGRAM_TARGET.md`'s Changelog).

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final timeline = this.timeline;
    final displayEvent = timeline != null
        ? replyEvent.getDisplayEvent(timeline)
        : replyEvent;
    // Telegram colours the bar and the quoted name with the quoted sender's own
    // palette entry - the `avatar_nameInMessage*` set `stringToColor` hashes a
    // user id into. Keyed on the sender id, the way Telegram keys it.
    final quotedSenderColour = stringToColor(displayEvent.senderId);
    final bubbleFill = this.bubbleFill;
    final panelFill = bubbleFill == null
        ? Colors.transparent
        : Color.alphaBlend(
            quotedSenderColour.withValues(alpha: panelTintAlpha),
            bubbleFill,
          );

    // The panel spans the content width the caller gives it, and the strip
    // hugs its leading edge - the pinned bar's construction
    // (`PinnedMessageBar`), which is Telegram's own: `ReplyMessageLine.drawLine`
    // (ReplyMessageLine.java:536-556) draws the bar from `rect.left`, the
    // reply rect's own left edge, `max(dp(3), dp(2 * rad))` wide and clipped
    // to `dp(3)`, so the bar shares the panel's rounded corner instead of
    // floating inside it. Owner revision 2026-10-27, measured on
    // the reference capture: our panel ended at x 575 inside a bubble
    // that runs to x 1050, and our bar started 48 px inside the bubble where
    // the pinned bar's strip starts 1 px inside its panel.
    // `IntrinsicHeight` + `CrossAxisAlignment.stretch` is what lets the strip
    // run the panel's full height: the panel's height is the two text lines.
    return IntrinsicHeight(
      child: Material(
        color: panelFill,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            // Target `reply_quote_bar_width_dp`. The bar takes the quoted
            // sender colour at 60 % alpha (`reply_quote_accent_rule` in
            // `verification/telegram-target.json`: a teal quote samples
            // `#53CCC6`, an amber quote samples `#E8AB5A`). It carries no
            // radius of its own: the panel's `clipBehavior` rounds it.
            ColoredBox(
              color: quotedSenderColour.withValues(alpha: barAlpha),
              child: const SizedBox(
                width: TelegramComposerGeometry.replyBarWidth,
              ),
            ),
            const SizedBox(width: panelInsetLeft),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                mainAxisAlignment: .center,
                children: <Widget>[
                  const SizedBox(height: panelPaddingVertical),
                  FutureBuilder<User?>(
                    initialData: displayEvent.senderFromMemoryOrFallback,
                    future: displayEvent.fetchSenderUser(),
                    builder: (context, snapshot) {
                      return Text(
                        snapshot.data?.calcDisplayname() ??
                            displayEvent.senderFromMemoryOrFallback
                                .calcDisplayname(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          // Target `reply_quote_name_sp` / `_weight`.
                          fontWeight:
                              TelegramComposerGeometry.replyNameFontWeight,
                          // Target `reply_quote_name_*`: the same ink as the bar,
                          // i.e. the quoted sender's palette colour.
                          color: quotedSenderColour,
                          fontSize: TelegramComposerGeometry.replyNameFontSize,
                        ),
                      );
                    },
                  ),
                  Text(
                    displayEvent
                        .calcLocalizedBodyFallback(
                          MatrixLocals(L10n.of(context)),
                          withSenderNamePrefix: false,
                          hideReply: true,
                          plaintextBody: true,
                        )
                        .trim()
                        .replaceAll('\n', ' '),
                    overflow: TextOverflow.ellipsis,
                    // `reply_quote_max_lines`.
                    maxLines: TelegramComposerGeometry.replyMaxLines,
                    style: TextStyle(
                      // `reply_quote_text`: the quoted text is a lighter grey than
                      // body ink (`#DFDFDF` against `#FBFBFB` measured in the same
                      // crop), so night quotes read one step dimmer than the body
                      // they sit in. The day branch keeps the theme's own bubble
                      // inks - Telegram's light-theme quote ink is unmeasured.
                      color: theme.brightness == Brightness.dark
                          ? TelegramPalette.quoteTextNight
                          : ownMessage
                          ? theme.colorScheme.onTertiary
                          : theme.colorScheme.onSurface,
                      // `reply_quote_text_sp`.
                      fontSize: TelegramComposerGeometry.replyTextFontSize,
                    ),
                  ),
                  const SizedBox(height: panelPaddingVertical),
                ],
              ),
            ),
            const SizedBox(width: panelInsetRight),
          ],
        ),
      ),
    );
  }
}
