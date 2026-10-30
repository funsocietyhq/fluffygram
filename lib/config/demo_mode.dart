// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Compile-time switch of the demo build, added 2026-10-24.
///
/// Build with `--dart-define=FLUFFYGRAM_DEMO=true` (see `docs/BUILD.md`). The
/// value is a `const`, so a production build compiles every
/// `if (kFluffyGramDemo)` block away and behaves exactly as before this file
/// existed.
///
/// `bool.fromEnvironment` recognises only the strings `true` and `false`, so
/// the common shorthand `=1` silently produced a PRODUCTION build - every
/// artifact built that way was a production build with demo assets added. The
/// second clause accepts `1` as well, so a build cannot quietly come out
/// switched off. Check a web bundle for the string `fluffygram.local` to prove
/// the mode is live.
const bool kFluffyGramDemo =
    bool.fromEnvironment('FLUFFYGRAM_DEMO') ||
    String.fromEnvironment('FLUFFYGRAM_DEMO') == '1';

/// Matrix server name of the fake session. Every demo MXC URI is
/// `mxc://fluffygram.local/<name>` and resolves to a bundled asset
/// (`lib/utils/demo/demo_media.dart`), never to a server.
const String kFluffyGramDemoServerName = 'fluffygram.local';

/// Homeserver origin written into the demo client's account record. It is a
/// name that does not exist; the origin is never resolved because
/// `DemoHttpClient` answers every request in-process.
const String kFluffyGramDemoHomeserverUrl = 'https://fluffygram.local';
