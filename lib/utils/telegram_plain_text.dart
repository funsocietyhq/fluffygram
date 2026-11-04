// SPDX-FileCopyrightText: 2026 FluffyGram Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Telegram has no blockquote rule: a line that starts with `>` is text, and it
/// stays on screen exactly as typed. matrix-dart's send path does not agree -
/// `Room.sendTextEvent` runs the body through `markdown()` (matrix-14.1.0
/// `room.dart:759` -> `utils/markdown.dart:209` -> package `markdown`'s
/// `markdownToHtml`), and package `markdown`'s default block syntaxes include
/// `BlockquoteSyntax`, so `> hi` arrives as `<blockquote>hi</blockquote>` and
/// this fork paints it as a quote panel.
///
/// Escaping the marker is the smallest fix that keeps the rest of the rule set:
/// `\>` is a markdown punctuation escape, so the blockquote parser never sees
/// the line and the renderer prints a literal `>`. Bold, italic, code, links
/// and mentions keep working, which is Telegram's set.
String telegramKeepGtLiteral(String body) => body.replaceAllMapped(
  // A `>` at the start of a line, with the leading spaces Telegram allows.
  RegExp(r'^([ \t]*)>', multiLine: true),
  (match) => '${match.group(1)}\\>',
);
