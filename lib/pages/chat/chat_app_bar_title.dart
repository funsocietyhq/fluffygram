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
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/sync_status_localization.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/presence_builder.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// What the subtitle of a group chat header shows. Telegram shows the member
/// count alone ("16 members") - the room topic never appears in a group
/// header, it lives on the chat details page. The `topic` argument exists so
/// the test can prove the topic never reaches the subtitle; the helper never
/// reads it. See the measurement log, "Chat header, user steering
/// addendum (T27b, 2026-10-25)", Difference 3, resolved by T29.
List<String> telegramGroupSubtitleParts({
  required String memberCount,
  required String topic,
}) {
  if (memberCount.isEmpty) {
    return [];
  }
  return [memberCount];
}

/// The member-count phrase of the group header subtitle. Telegram builds it as
/// `LocaleController.formatPluralString("Members", count)`
/// (`ChatAvatarContainer.java:1316-1318`, `:1362-1364`), so a group of four
/// reads "4 members". Our l10n table has only `countParticipants` - "4
/// participants" - and no "members" plural; adding a translatable key
/// regenerates every file under `lib/l10n/`, so the fork-local English phrase
/// lives here. ROADMAP T34 records the translatable key as deferred (the
/// group is English-speaking). The ", N online" suffix their header appends
/// when presence is known is deliberately not ported: it needs a presence
/// poll per member, and `/_matrix/client/v3/presence` is deprecated.
String telegramMemberCount(int count) =>
    count == 1 ? '1 member' : '$count members';

/// Whether the chat header draws Telegram's in-title mute glyph. Telegram puts
/// the speaker-with-slash glyph inside the title, after the name, for a chat
/// whose notifications are off - the same test the chat list uses
/// (`chat_list_item.dart:51`, `unread_bubble.dart:21`). Measured in
/// `the measurement log`, "The in-title mute glyph".
bool showTelegramMuteGlyph(PushRuleState state) =>
    state != PushRuleState.notify;

// T49 (the measurement log, "T49 - the chat-header online dot and the
// `Online` word take `user_statusOnline`"): Telegram tints its header's
// online presence with theme key `user_statusOnline` - day `#039615`
// (`Theme.java:1980-1985`, `day.attheme:49`), night `#6BE77D` (the night
// variant of the same key). File-local consts, not a `TelegramPalette`
// constant: the palette contract rejects a constant with no row in
// `verification/telegram-target.json` (the rig-sync follow-up owns that row).
const Color telegramOnlineInkDay = Color(0xFF039615);
const Color telegramOnlineInkNight = Color(0xFF6BE77D);

/// The theme-aware online ink. Telegram picks the attheme variant by theme
/// (`Theme.java:1980-1985`); the fork picks it by `Brightness`.
Color telegramOnlineInk(Brightness brightness) => brightness == Brightness.dark
    ? telegramOnlineInkNight
    : telegramOnlineInkDay;

/// The word a Telegram chat header shows for an online peer:
/// `ChatAvatarContainer.java:1242` sets the DM subtitle from
/// `LocaleController.formatUserStatus()`, which returns
/// `getString("Online", R.string.Online)` for a peer whose presence has not
/// expired (`LocaleController.java:2938,2949`). The English value of that key
/// is the lowercase word "online", because it reads as a subtitle.
///
/// A fork-local English literal, not an l10n key: `lib/l10n/intl_en.arb` has no
/// "online" string at all (its presence word is `currentlyActive` = "Currently
/// active", Element's wording, T49.1 in the measurement log), and adding a
/// key regenerates every file under `lib/l10n/` (AGENTS rule 7). Same precedent
/// as `telegramMemberCount`; T34 records the translatable key as deferred.
const String telegramPresenceOnline = 'online';

class ChatAppBarTitle extends StatelessWidget {
  final ChatController controller;
  const ChatAppBarTitle(this.controller, {super.key});

  // Header chrome geometry. The two text sizes are Telegram's own declared
  // values, not measurements: `titleTextView.setTextSize(18)`
  // (ChatAvatarContainer.java:282) and `subtitleTextView.setTextSize(14)`
  // (ChatAvatarContainer.java:307), both applied through dp() so the system
  // font scale never touches them (Theme.java:8035). The ink-box measurement
  // of a user's capture read 17 / 13 - cap-height measurement under-reads
  // the declared em size by about 1 dp, so the source value wins. Table:
  // the measurement log, "Conversation screen, read from Telegram's own UI
  // code". The avatar box stays measured (their class states no dp for it).
  static const double titleTextSize = 18;
  static const double subtitleTextSize = 14;
  // T27: the Telegram header avatar box measures x=159..266, y=192..300 =
  // 108 x 109 px = 41.14 x 41.52 dp at 2.625 px/dp, and the outer ~1 px ring
  // is antialias - a 40 dp box. FluffyGram build 6 (the reference capture of 
  // the reference capture) measured 83 x 85 px = 31.62 x 32.38 dp. The box also sets the
  // title column: the Telegram title ink starts at x=292 = 111.24 dp against
  // x=266 = 101.33 dp in build 6.
  static const double headerAvatarSize = 40;

  /// Telegram's in-title mute glyph, measured on the same capture: ink box
  /// 25 x 27 px = 9.5 x 10.3 dp, sitting 17 px = 6.5 dp after the title ink
  /// and centred on the title cap band. A 27 px ink box needs a 27 / 0.72
  /// = 37.5 px = 14.3 dp em box, so the glyph draws at 14.
  static const double muteGlyphSize = 14;
  static const double muteGlyphGap = 6.5;

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    if (controller.selectedEvents.isNotEmpty) {
      return Text(
        controller.selectedEvents.length.toString(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onTertiaryContainer,
        ),
      );
    }
    return InkWell(
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: controller.room.membership != .join
          ? null
          : () => FluffyThemes.isThreeColumnMode(context)
                ? controller.toggleDisplayChatDetailsColumn()
                : context.go('/rooms/${room.id}/details'),
      child: Row(
        children: [
          Hero(
            tag: 'content_banner',
            child: Avatar(
              mxContent: room.avatar,
              name: room.getLocalizedDisplayname(
                MatrixLocals(L10n.of(context)),
              ),
              size: headerAvatarSize,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                Row(
                  spacing: muteGlyphGap,
                  children: [
                    // T11 finding 2 (user rule 2026-10-26): Telegram paints
                    // no glyph in front of a chat title, so this header draws
                    // none. The verification state is still checked on the
                    // security page and in the encryption settings.
                    // Flexible, not Expanded: the glyph must sit after the
                    // title's ink (measured 6.5 dp behind it), so a short
                    // title keeps the glyph beside the text, not at the
                    // column's far edge.
                    Flexible(
                      child: Text(
                        room.getLocalizedDisplayname(
                          MatrixLocals(L10n.of(context)),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: titleTextSize,
                          color: TelegramPalette.chatHeaderTitle,
                        ),
                      ),
                    ),
                    // T11 finding 15: a muted chat carries the mute glyph
                    // inside its title, on the title's own line, not as a
                    // header action button.
                    if (showTelegramMuteGlyph(room.pushRuleState))
                      Icon(
                        Icons.volume_off,
                        size: muteGlyphSize,
                        color: TelegramPalette.muteIcon,
                      ),
                  ],
                ),
                StreamBuilder(
                  stream: room.client.onSyncStatus.stream,
                  builder: (context, snapshot) {
                    final status =
                        room.client.onSyncStatus.value ??
                        const SyncStatusUpdate(SyncStatus.waitingForResponse);
                    final hide =
                        FluffyThemes.isColumnMode(context) ||
                        (room.client.onSync.value != null &&
                            status.status != SyncStatus.error &&
                            room.client.prevBatch != null);
                    final style = TextStyle(
                      fontSize: subtitleTextSize,
                      color: TelegramPalette.headerSubtitle,
                    );
                    return AnimatedSize(
                      duration: FluffyThemes.animationDuration,
                      child: hide
                          ? room.isDirectChat
                                ? PresenceBuilder(
                                    userId: room.directChatMatrixID,
                                    builder: (context, presence) {
                                      final statusMessage = presence?.statusMsg
                                          ?.trim();

                                      final lastActiveTimestamp =
                                          presence?.lastActiveTimestamp;

                                      // T49.1: the online test is the peer's
                                      // presence state - the same test the
                                      // chat-list dot reads
                                      // (`client.presences[peerId]?.presence ==
                                      // PresenceType.online`) - with
                                      // `currently_active` as a second signal.
                                      // Matrix sends both and Synapse does not
                                      // keep them equal, so keying on
                                      // `currentlyActive` alone lets the row
                                      // show its dot while the header shows a
                                      // last-seen line.
                                      final isOnline =
                                          presence?.presence ==
                                              PresenceType.online ||
                                          presence?.currentlyActive == true;
                                      final texts = [
                                        if (isOnline)
                                          telegramPresenceOnline
                                        else if (lastActiveTimestamp != null)
                                          L10n.of(context).lastActiveAgo(
                                            lastActiveTimestamp
                                                .localizedTimeShort(context),
                                          ),
                                        ?statusMessage,
                                      ];
                                      final text = texts.join(' ◦ ');
                                      if (text.isEmpty) {
                                        return const SizedBox.shrink();
                                      }

                                      // T49: Telegram tints the header's
                                      // online word with `user_statusOnline`
                                      // (`Theme.java:1980-1985`). The fork's
                                      // `Online` word is the online line
                                      // (`telegramPresenceOnline`, T49.1); a
                                      // last-seen line stays the
                                      // muted grey, as Telegram paints
                                      // `last seen` in its offline ink.
                                      final isOnlineLine = isOnline;
                                      return Text(
                                        text,
                                        style: isOnlineLine
                                            ? style.copyWith(
                                                color: telegramOnlineInk(
                                                  Theme.of(context).brightness,
                                                ),
                                              )
                                            : style,
                                      );
                                    },
                                  )
                                : Builder(
                                    // T29: the member count is the whole group
                                    // subtitle. The old code appended the
                                    // separator ' ◦ ' plus room.topic after it;
                                    // Telegram never prints the topic here.
                                    builder: (context) {
                                      final joined =
                                          room.summary.mJoinedMemberCount;
                                      return Row(
                                        children: [
                                          for (final part
                                              in telegramGroupSubtitleParts(
                                                memberCount: joined == null
                                                    ? ''
                                                    : telegramMemberCount(
                                                        joined +
                                                            (room
                                                                    .summary
                                                                    .mInvitedMemberCount ??
                                                                0),
                                                      ),
                                                topic: room.topic,
                                              ))
                                            Expanded(
                                              child: Text(
                                                part,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: style,
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  )
                          : Row(
                              children: [
                                SizedBox.square(
                                  dimension: 10,
                                  child: CircularProgressIndicator.adaptive(
                                    strokeWidth: 1,
                                    value: status.progress,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    status.calcLocalizedString(context),
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
