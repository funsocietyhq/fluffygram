// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:fluffychat/config/telegram_palette.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import 'chat.dart';
import 'composer_geometry.dart';

/// The row above the composer input while a reply or an edit is in progress.
///
/// Telegram's reply row is `ChatReplyContainer` (`ui/Components/ChatReplyContainer.java:122-135`,
/// wired at `ui/ChatActivity.java:8212`, label built at `:15241`). Its frame, and ours:
///
/// * a 52 dp glyph column at the left - a reply arrow, or a pencil while editing;
/// * two 18 dp text lines starting at x 52: **"Reply to \<name\>"** bold 14 in the quoted
///   sender's colour, and the quoted text below it, 14, in the lighter quote ink;
/// * a 52 dp column at the right end, which carries the close button;
/// * 46 dp tall, filled with the quoted sender's colour at ~12 % over the composer pill,
///   and **no vertical accent bar at all**.
///
/// The vertical rule with the tail belongs to the quote *inside* a bubble
/// (`events/reply_content.dart`), and only there. This row used to paint its own bar *and*
/// embed `ReplyContent`, which paints a second one - that is the double line a user
/// reported on builds 81-82 ("Quoting a message shows double lines. Should look like
/// telegram", 2026-10-29, T127).
class ReplyDisplay extends StatelessWidget {
  final ChatController controller;
  const ReplyDisplay(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final quoted = controller.replyEvent ?? controller.editEvent;
    final isReply = controller.replyEvent != null;
    return AnimatedSize(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      clipBehavior: Clip.hardEdge,
      child: quoted == null
          ? const SizedBox.shrink()
          : _ReplyRow(controller: controller, quoted: quoted, isReply: isReply),
    );
  }
}

class _ReplyRow extends StatelessWidget {
  const _ReplyRow({
    required this.controller,
    required this.quoted,
    required this.isReply,
  });

  final ChatController controller;
  final Event quoted;
  final bool isReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final senderColour = stringToColor(quoted.senderId);
    // Telegram paints the glyph and the label in `chat_replyPanelName`
    // (`ChatReplyContainer.java:129`, `ChatActivity.java:15252,15270`); the fork keeps its
    // sender-derived colour for both, as T70 established for the quote bar.
    final labelColour = senderColour;
    // Telegram's quoted text line takes `glass_defaultText` (`ChatReplyContainer.java:134`);
    // the fork's measured night value is `#DFDFDF` (`reply_quote_text`, the reference capture).
    final bodyColour = theme.brightness == Brightness.dark
        ? TelegramPalette.quoteTextNight
        : theme.textTheme.bodyMedium!.color;
    final label = isReply
        ? L10n.of(context).replyToQuoted(
            quoted.senderFromMemoryOrFallback.calcDisplayname(),
          )
        : L10n.of(context).edit;
    // Telegram's `setReplyText()` takes the plain text of the quoted message
    // (`ChatActivity.java:15253-15258`); `hideReply` keeps a nested quote out of one line.
    final body = quoted
        .calcLocalizedBodyFallback(
          MatrixLocals(L10n.of(context)),
          withSenderNamePrefix: false,
          hideReply: true,
          plaintextBody: true,
        )
        .trim()
        .replaceAll('\n', ' ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TelegramComposerGeometry.replyStripMargin,
        0,
        TelegramComposerGeometry.replyStripMargin,
        TelegramComposerGeometry.replyStripGap,
      ),
      child: Material(
        color: TelegramComposerGeometry.replyStripColor(
          senderColour,
          TelegramPalette.composerPill,
        ),
        borderRadius: BorderRadius.circular(
          TelegramComposerGeometry.replyStripRadius,
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: TelegramComposerGeometry.replyRowHeight,
          child: Row(
            // Telegram: glyph column 52 dp (ChatReplyContainer.java:123), close column
            // 52 dp (ChatActivity.java:8212), text between them from x 52.
            children: <Widget>[
              SizedBox(
                width: TelegramComposerGeometry.replyIconColumn,
                child: Icon(
                  isReply ? Icons.reply : Icons.edit,
                  color: labelColour,
                  size: TelegramComposerGeometry.replyGlyphSize,
                ),
              ),
              Expanded(
                child: Padding(
                  // The two text frames sit at y 6 and y 24 of the 46 dp row
                  // (ChatReplyContainer.java:126,131).
                  padding: const EdgeInsets.only(
                    top: TelegramComposerGeometry.replyTextBlockTop,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        height: TelegramComposerGeometry.replyLineHeight,
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: TelegramComposerGeometry.replyNameFontSize,
                            fontWeight:
                                TelegramComposerGeometry.replyNameFontWeight,
                            color: labelColour,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: TelegramComposerGeometry.replyLineHeight,
                        child: Text(
                          body,
                          maxLines: TelegramComposerGeometry.replyMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize:
                                TelegramComposerGeometry.replyTextFontSize,
                            color: bodyColour,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: TelegramComposerGeometry.replyCloseColumn,
                child: Center(
                  child: IconButton(
                    tooltip: L10n.of(context).close,
                    color: TelegramPalette.textSecondary,
                    icon: const Icon(Icons.close),
                    iconSize: TelegramComposerGeometry.replyGlyphSize,
                    padding: EdgeInsets.zero,
                    onPressed: controller.cancelReplyEventAction,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
