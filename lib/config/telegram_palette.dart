// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'dart:ui';

/// Every colour measured from the group's Telegram screenshots.
///
/// Values come from `verification/telegram-target.json` (source of truth).
/// Drift is caught by `verification/palette_contract.sh` (both directions:
/// every 6-digit hex of the target must appear here, no colour here may be
/// absent from the target) and by
/// `test/telegram_fidelity/theme_parity_test.dart`.
abstract class TelegramPalette {
  // --- night surfaces (theme_night_group) ---
  /// chat_background, chat_list_background, status_bar_scrim.
  static const Color chatBackground = Color(0xFF000000);

  /// bubble_incoming.
  static const Color bubbleIncoming = Color(0xFF1E1E20);

  /// bubble_outgoing; also composer_send_button. Since T13 finding 13 this is
  /// the stock night `chat_outBubble`: the base `TelegramBubbleFill.outgoing`
  /// tints with the accent, and the fill of the composer send button. The
  /// timeline paints the derived colour, not this one.
  static const Color bubbleOutgoing = Color(0xFF4F556C);

  /// top_bar_bg, composer_pill_bg, input_field_bg, message_action_sheet_bg.
  static const Color surfaceRaised = Color(0xFF17191C);

  /// chat_list_row_bg.
  static const Color chatListRowBackground = Color(0xFF1C1C1C);

  /// chat_list_background - the field the chat list paints its rows on. Telegram's
  /// list is not black: measured 2026-10-25 on `the reference capture`,
  /// 87 percent of a text-free crop (x 700..1079, y 1400..1520) reads `#181818`.
  /// The chat PAGE keeps [chatBackground] `#000000`, which already matches the
  /// a user's chat capture.
  static const Color chatListBackground = Color(0xFF181818);

  /// chat_list_search_field_bg - the fill of the chat-list search field, measured
  /// `#282828` on a user's capture. Its corners solve to a stadium (19.7 dp),
  /// so the fork draws radius = half the height.
  static const Color searchFieldBackground = Color(0xFF282828);

  /// selected_message_tint; also unread_divider_pill.
  static const Color selectedMessageTint = Color(0xFF1E2A38);

  /// divider.
  static const Color divider = Color(0xFF1F2126);

  /// reply_quote_block_bg (block tinted by a teal sender colour).
  static const Color replyQuoteBlockTeal = Color(0xFF232F30);

  /// reply_quote_block_bg_amber (block tinted by an amber sender colour).
  static const Color replyQuoteBlockAmber = Color(0xFF322C26);

  /// reply_quote_text: the ink of the quoted text inside the quote panel,
  /// measured `#DFDFDF` in the two-quote crop against body ink `#FBFBFB` - a
  /// deliberate step dimmer than `textOnBubble`. The panel itself has no fill
  /// of its own: it takes the host bubble's colour (user revision 2026-10-26;
  /// the flat `#242426` constant this line once named is gone with it).
  static const Color quoteTextNight = Color(0xFFDFDFDF);

  /// reaction_pill_bg_on_incoming.
  static const Color reactionPillBgOnIncoming = Color(0xFF1B2531);

  // reaction_pill_bg_on_outgoing and chat_list_unread_badge_muted_bg are
  // measured values (reactionPillTinted, bubbleIncoming): the stock guesses
  // #323849 and #3A3F45 were dropped from the target on 2026-10-24.

  // --- night text (theme_night_group) ---
  /// text_primary_on_incoming, text_primary_on_outgoing.
  static const Color textOnBubble = Color(0xFFF9F9F9);

  /// header_title, context_menu_text.
  static const Color textPrimary = Color(0xFFE9E9E9);

  /// composer_icon, chat_list_folder_tab_inactive_text, mute_icon_tint,
  /// context_menu_icon, pinned_pin_icon.
  static const Color textSecondary = Color(0xFF8A929A);

  /// composer_pill_bg - the inked composer pill on the black chat background.
  static const Color composerPill = Color(0xFF171717);

  /// composer_hint_text - composer placeholder ink and the bottom nav bar icons.
  static const Color composerHint = Color(0xFF737373);

  /// timestamp_in_incoming.
  static const Color timestampIncoming = Color(0xFF8CA0B3);

  /// read_tick (measured #B6BECA, delta 2 from this value).
  static const Color timestampOutgoing = Color(0xFFB4BCC8);

  // --- measured 2026-10-24 from a user's Telegram screenshots ---

  /// timestamp_in_outgoing; also edited_label - Telegram draws both in one ink.
  static const Color timestampInk = Color(0xFF909AAB);

  /// reaction_pill_bg_on_outgoing (pill tinted by the reaction emoji).
  static const Color reactionPillTinted = Color(0xFF262D2B);

  /// reaction_pill_text_count.
  static const Color reactionPillCount = Color(0xFF485454);

  /// date_separator_pill_bg - this theme tints the date pill warm.
  static const Color datePillBackground = Color(0xFF2A2A1C);

  /// date_separator_text.
  static const Color datePillText = Color(0xFF6D7592);

  /// `chat_unreadMessagesStartBackground` - the fill of Telegram's
  /// "Unread Messages" band, night. `ChatUnreadCell.java:38` paints the band
  /// with this key; the value is the ARGB int `-14606046` = `#212122` at
  /// `night.attheme:350` (T47, source-measured 2026-10-27).
  static const Color unreadDividerBackground = Color(0xFF212122);

  /// `chat_unreadMessagesStartArrowIcon` - the down arrow pinned to the
  /// band's right end, night. `ChatUnreadCell.java:43`; `-9605777` =
  /// `#6D6D6F` at `night.attheme:87` (T47).
  static const Color unreadDividerArrow = Color(0xFF6D6D6F);

  /// `chat_unreadMessagesStartText` - the band label ink, night.
  /// `ChatUnreadCell.java:50`; Telegram ships white at alpha `0xDB`
  /// (`-620756993`, `night.attheme:10`). The surface under the ink is itself a
  /// source value, so the theme alpha is baked the way this palette does it:
  /// blended over the night band `(219*219 + 33*36) / 255 = 193` per channel =
  /// `#C1C1C1` (T47, `the measurement log`).
  static const Color unreadDividerText = Color(0xFFC1C1C1);

  /// chat_list_title - the row title ink, measured `#F1F1F1` on a user's
  /// chat-list capture. The `#FAFAFA` this fork shipped was a chat-view reading.
  /// The day theme takes its own on-surface ink in `chat_list_item.dart`.
  static const Color chatListTitle = Color(0xFFF1F1F1);

  /// chat_list_preview_text.
  static const Color chatListPreview = Color(0xFF7C7C7E);

  /// `chats_nameMessage_threeLines` - the chat-list preview's name slot (the
  /// inline `<sender>:` prefix and the `Draft:` label). Telegram re-inks that one
  /// paint per case (`DialogCell.java:4213-4221`) and reads `#EBEBEB` against the
  /// `#828282` message text in a user's capture. "Colored sender names" does
  /// **not** govern this slot (T43.1): Telegram colours the *timeline* sender
  /// label, never the preview prefix, so the hash palette stays out of the chat
  /// list.
  static const Color chatListSenderPrefix = Color(0xFFEBEBEB);

  /// `chats_nameMessage_threeLines` in the day theme: `#424449`
  /// (`day.attheme:35`). The day theme's blue `#298ACF` is the four-line
  /// `chats_nameMessage` key (`day.attheme:18`) - the folder layout, not a phone.
  static const Color dayChatListSenderPrefix = Color(0xFF424449);

  /// chat_list_time.
  static const Color chatListTime = Color(0xFF707070);

  /// `chat_list_unread_badge_disc_bg` - Telegram's badge fill
  /// `chats_unreadCounter`: the ARGB int `-13000973` = `#399EF3` at
  /// `night.attheme:79` (T44, source-measured 2026-10-27). The grey `#454545`
  /// this constant carried was measured on a user's pill crop, and it is
  /// `chats_unreadCounterMuted` (`night.attheme:282`) - that crop showed a
  /// muted room's counter, not the stock fill. The older key
  /// `chat_list_unread_badge_bg` `#322C26` was a chat-view reading; it stays
  /// in the target only because the spec_app golden still draws it.
  static const Color chatListUnreadBadge = Color(0xFF399EF3);

  /// `chat_list_unread_badge_disc_bg` in the day theme -
  /// `chats_unreadCounter`, the ARGB int `-14373129` = `#24AEF7` at
  /// `day.attheme:41`.
  static const Color dayChatListUnreadBadge = Color(0xFF24AEF7);

  /// chat_list_unread_badge_muted_bg - the DIGITS of a muted room's outline
  /// badge: `chats_unreadCounterMuted`, the ARGB int `-12237499` = `#454545`
  /// at `night.attheme:282` (T44). The `#1E1E20` this constant carried filled a
  /// disc; Telegram outlines a muted counter instead (`DialogCell.java:
  /// 5271-5291`) and the outline is `chatListUnreadBadgeMutedOutline`.
  static const Color chatListUnreadBadgeMuted = Color(0xFF454545);

  /// The day theme's muted digits. `chats_unreadCounterMuted` is absent from
  /// `day.attheme`, so the fork's derived grey stays: the same hex as
  /// theme_day_stock `timestamp_in_incoming`, so the palette adds no colour.
  static const Color dayChatListUnreadBadgeMuted = Color(0xFF939599);

  /// The 2 dp outline of a muted room's counter (T44):
  /// `blendARGB(windowBackgroundWhite, setAlpha(chats_pinnedOverlay, 255),
  /// alpha(pinnedOverlay) / 255)` (`DialogCell.java:5284-5288`) - white at
  /// alpha `0x0B` (`night.attheme:186`) over `windowBackgroundWhite` `#181819`
  /// (`night.attheme:235`) = `#212428`.
  static const Color chatListUnreadBadgeMutedOutline = Color(0xFF212428);

  /// The day outline: black at alpha `0x06` (`day.attheme:112`) over the
  /// Theme default white (`day.attheme` carries no `windowBackgroundWhite`
  /// key) = `#F9F9F9`.
  static const Color dayChatListUnreadBadgeMutedOutline = Color(0xFFF9F9F9);

  /// `chat_list_draft_label` - the "Draft:" label ink of a chat with a saved
  /// draft (T45, source-measured 2026-10-27): Telegram's theme key
  /// `chats_draft`, the ARGB int `-637778102` = `0xD9FC474A` at
  /// `night.attheme:119`, painted over the whole label by
  /// `ForegroundColorSpanThemable(Theme.key_chats_draft)`
  /// (`DialogCell.java:1622`). The theme alpha `0xD9` (85 %) is not applied -
  /// the palette ships opaque inks; see `the measurement log` `## T45`.
  static const Color chatListDraftLabel = Color(0xFFFC474A);

  /// `chat_list_draft_label` in the day theme - `chats_draft`, the ARGB int
  /// `-85777850` = `0xFAE32246` at `day.attheme:70` (theme alpha `0xFA`, 98 %).
  static const Color dayChatListDraftLabel = Color(0xFFE32246);

  /// `chat_list_online_dot` - Telegram's theme key `chats_onlineCircle`, the ink
  /// of the presence dot on a chat-list DM avatar (T49). The ARGB int
  /// `-13130503` = `0xFF37A4F9` at `night.attheme:146`, painted by
  /// `Theme.dialogs_onlineCirclePaint` on the dp(5) disc at
  /// `DialogCell.java:5130-5131`. The ring around it is not a theme colour of
  /// its own: Telegram re-inks the same paint with `key_windowBackgroundWhite`
  /// for the dp(7) disc underneath (`:5128-5129`), so the ring takes the page
  /// field, not a palette constant.
  static const Color chatListOnlineDot = Color(0xFF37A4F9);

  /// `chat_list_online_dot` in the day theme - `chats_onlineCircle`, the ARGB
  /// int `-14047001` = `0xFF29A8E7` at `day.attheme:88`.
  static const Color dayChatListOnlineDot = Color(0xFF29A8E7);

  /// chat_list_folder_tab_pill_bg.
  static const Color folderTabPill = Color(0xFF181816);

  /// header_subtitle_online - the member-count line in the chat header pill.
  static const Color headerSubtitle = Color(0xFF83807D);

  /// header_title - the chat header title ink, measured white (#FFFFFF) in S1
  /// and S3 and again on the title of the reference capture. The
  /// context-menu text keeps its own dimmer #E9E9E9 (`textPrimary`).
  static const Color chatHeaderTitle = Color(0xFFFFFFFF);

  /// mute_icon_tint - the mute glyph beside the chat header title.
  static const Color muteIcon = Color(0xFF515350);

  /// link_blue - the link ink of the pinned message bar, the theme's muted
  /// accent and the same ink as the date-separator text.
  static const Color linkInPinnedBar = Color(0xFF6C7490);

  /// pinned_bar_bg - the raised panel Telegram draws its pinned message bar on.
  /// Measured on a user's Pixel (their Telegram theme, slate accent): fill
  /// `#282D3B`, variants `#2A2F3C` and `#282E3B`, read along the panel band.
  /// Telegram's panel is translucent over the chat wallpaper, so these readings
  /// sit above what is underneath; the flat hex is what a wallpaper-free chat
  /// field must paint to land at the same tone.
  static const Color pinnedBarBackground = Color(0xFF282D3B);

  /// chat_header_pill_night - the chat AppBar pill fill, night theme.
  /// Measured on a user's Telegram capture the reference capture:
  /// (40,46,59). T36 ships it as a flat value: the accent-blend formula
  /// `chatChromeFill` lands the phone pill at (39,40,55) with the default
  /// accent, and a custom accent in Settings moves the blend off the target
  /// (the same formula pushed the FAB disc to (70,72,94) on the phone).
  static const Color chatHeaderPillNight = Color(0xFF282E3B);

  /// jump_fab_night - the scroll-down (jump to latest) FAB disc, night theme.
  /// Measured on a user's Telegram capture the reference capture:
  /// (38,43,56). The phone read (70,72,94) through the 0.50 accent blend of
  /// T36 `50c2e00f4` (probe on the reference capture, build 21), so
  /// the disc takes the flat measured value.
  static const Color jumpFabNight = Color(0xFF262B38);

  /// pinned_bar_accent - the leading accent strip of the pinned message bar and
  /// the ink of its "Pinned Message" label line. Measured 2026-10-26 on the
  /// a user's Pixel capture the reference capture (2.625 px/dp): the strip
  /// at x 48..56 reads this slate, and the label glyphs read #6C7491 - antialiased
  /// ink of the same accent. Telegram pulls a brighter accent for the label line
  /// than the picked accent `accentSlate`, so the label no longer takes
  /// `FluffyThemes.accent`.
  static const Color pinnedBarAccent = Color(0xFF676D87);

  /// pinned_label_ink - the ink of the pinned bar's label line, night theme.
  /// Measured 2026-10-26 on the reference capture (histogram of
  /// x 70..420, y 322..368: 1074 px of this slate) and confirmed as the target
  /// on 2026-10-27, when build 21 on the phone read the shared
  /// `pinnedBarAccent` `#676D87` verbatim (103,109,135) where Telegram reads
  /// this value: the label line takes a brighter accent than the strip.
  static const Color pinnedLabelInk = Color(0xFF6C7491);

  /// pinned_bar_fill_near_strip - the pinned bar panel fill at its leading edge,
  /// beside the accent strip. Measured 2026-10-26 on the same capture at x 60,
  /// y 386: the panel is tinted lighter and warmer there than in its body. The
  /// mid-panel reading #1F1D1D was taken through the translucent panel over the
  /// chat wallpaper, so the body keeps `pinnedBarBackground` and this hex paints
  /// only the leading end of the panel gradient.
  static const Color pinnedBarFillNearStrip = Color(0xFF3B3D47);

  /// pinned_message_bar_text - the preview ink on the pinned bar panel.
  static const Color pinnedMessagePreview = Color(0xFFFFFFFF);

  /// jump_to_latest_chevron, top_bar_action_icon.
  static const Color textTertiary = Color(0xFF9CA3AF);

  /// unread_divider_text, pinned_message_bar_text, bot_inline_button_text,
  /// chat_list_time_unread.
  static const Color textLightBlue = Color(0xFF6FC3F3);

  /// reaction_pill_text_count_active.
  static const Color reactionCountActive = Color(0xFF7FB2F0);

  // reaction_pill_text_count is measured (reactionPillCount): the stock guess
  // #82A8CE was dropped from the target on 2026-10-24.

  /// chat_list_unread_badge_text - Telegram paints the count in white: 431 px
  /// of white digits on a user's pill crop, and white digits on the blue
  /// fill in both stock themes (T44 - the theme key `chats_unreadCounterText`
  /// is absent from both `.attheme` files and from Theme.java's defaults, so
  /// the paint follows Telegram's rendering). The near-black `#0D0E12` this
  /// constant carried was a chat-view reading and leaves the target with it.
  static const Color unreadBadgeText = Color(0xFFFFFFFF);

  /// `chat_list_unread_badge_text` in the day theme - white, like the night
  /// ink: Telegram draws white digits on the blue pill in both themes (T44).
  static const Color dayUnreadBadgeText = Color(0xFFFFFFFF);

  // --- night accents (theme_night_group) ---
  /// accent_blue; also swipe_reply_action_icon, day accent_blue.
  static const Color accentBlue = Color(0xFF2AABEE);

  /// accent_teal: sender_name, reply_quote_accent, status_online,
  /// chat_list_unread_badge_bg, folder tab active,
  /// checkbox_checked, tab_indicator, typing_indicator, swipe_read_action_icon.
  static const Color accentTeal = Color(0xFF53CCC6);

  /// sender_name_amber, chat_list_sender_prefix_amber.
  static const Color accentAmber = Color(0xFFE8AB5A);

  /// swipe_archive_action_icon.
  static const Color accentYellow = Color(0xFFF2C94C);

  /// swipe_delete_action_icon.
  static const Color accentRed = Color(0xFFE5595F);

  /// accent_slate - the accent measured on a user's Pixel (their Telegram
  /// Chat Settings accent picker shows it). This is the fork's default accent:
  /// `AppSettings.telegramAccentIndex` defaults to its `accentValues` index.
  static const Color accentSlate = Color(0xFF4D506E);

  // --- in-chat voice waveform (chat_inVoiceSeekbar*, T50) ---
  /// `chat_inVoiceSeekbar` - the **unplayed** bars of a voice row, night
  /// `#636363` (`-10263709`, `night.attheme:445`), passed to
  /// `SeekBarWaveform.setColors` at `ChatMessageCell.java:14647` (T50).
  static const Color voiceSeekbar = Color(0xFF636363);

  /// `chat_inVoiceSeekbarFill` - the **played** bars, night `#64B5EF`
  /// (`-10177041`, `night.attheme:441`, T50).
  static const Color voiceSeekbarFill = Color(0xFF64B5EF);

  /// `chat_inVoiceSeekbarSelected` - every bar **while the finger drags** the
  /// waveform, night `#7391AB` (`-9203285`, `night.attheme:237`, T50). The
  /// played prefix keeps [voiceSeekbarFill] (`SeekBarWaveform.java:437-448`).
  static const Color voiceSeekbarSelected = Color(0xFF7391AB);

  // --- day (theme_day_stock) ---
  /// theme_day_stock bubble_incoming.
  static const Color dayBubbleIncoming = Color(0xFFF0F0F0);

  /// theme_day_stock bubble_outgoing.
  static const Color dayBubbleOutgoing = Color(0xFF2D7ED5);

  /// theme_day_stock bubble_outgoing_gradient.
  static const Color dayBubbleOutgoingGradient = Color(0xFF5CB6E0);

  /// theme_day_stock timestamp_in_outgoing.
  static const Color dayTimestampOutgoing = Color(0xFFC7E6FF);

  /// theme_day_stock timestamp_in_incoming.
  static const Color dayTimestampIncoming = Color(0xFF939599);

  /// theme_day_stock reply_quote_name_outgoing; text on day bubbles.
  static const Color dayTextOnBubble = Color(0xFFFFFFFF);

  /// theme_day_stock reply_quote_name_incoming.
  static const Color dayReplyQuoteNameIncoming = Color(0xFF3186DF);

  /// theme_day_stock chat_background - the day theme's chat field, the light
  /// twin of [chatBackground]. Telegram ships it as a solid fill or a pattern
  /// image; the fork ships the solid fill (pattern wallpapers are deferred).
  static const Color dayChatBackground = Color(0xFFE6EBEE);

  /// theme_day_stock `chat_unreadMessagesStartBackground` - the "Unread
  /// Messages" band fill, day. `-13329946` = `#3499E6` at `day.attheme:233`
  /// (`ChatUnreadCell.java:38`, T47).
  static const Color dayUnreadDividerBackground = Color(0xFF3499E6);

  /// theme_day_stock `chat_unreadMessagesStartArrowIcon` - the band's arrow,
  /// day. `-3741702` = `#C6E7FA` at `day.attheme:47` (T47).
  static const Color dayUnreadDividerArrow = Color(0xFFC6E7FA);

  /// theme_day_stock `chat_unreadMessagesStartText` - the band label ink, day.
  /// Opaque white (`-1` = `0xFFFFFFFF` at `day.attheme:1`): the night twin
  /// carries a theme alpha and blends, this one needs no blend (T47).
  static const Color dayUnreadDividerText = Color(0xFFFFFFFF);

  /// theme_day_stock `chat_inVoiceSeekbar` - the unplayed bars, day `#BAC0C8`
  /// (`-4538168`, `day.attheme:289`, T50).
  static const Color dayVoiceSeekbar = Color(0xFFBAC0C8);

  /// theme_day_stock `chat_inVoiceSeekbarFill` - the played bars, day
  /// `#379BEF` (`-13132817`, `day.attheme:286`, T50).
  static const Color dayVoiceSeekbarFill = Color(0xFF379BEF);

  /// theme_day_stock `chat_inVoiceSeekbarSelected` - the bars while dragging,
  /// day `#BAC0C8` (`-4538168`, `day.attheme:150`, T50). Same hex as
  /// [dayVoiceSeekbar]: the day theme does not tint the dragged strip.
  static const Color dayVoiceSeekbarSelected = Color(0xFFBAC0C8);

  // --- sender set (sender_colors_night) ---
  // Telegram's own standard peer colours, ids 0..6: key order from
  // `Theme.java:2707`, night hex values from their `assets/night.attheme`
  // (Red:163, Orange:166, Violet:37, Green:193, Cyan:200, Blue:318, Pink:313).
  /// sender_colors_night red - Telegram id 0 (Red), night.attheme:163.
  static const Color senderRed = Color(0xFFE88878);

  /// sender_colors_night orange - Telegram id 1, night.attheme:166.
  static const Color senderOrange = Color(0xFFE8AB5A);

  /// sender_colors_night purple - Telegram id 2 (Violet), night.attheme:37.
  static const Color senderPurple = Color(0xFF8C8DEA);

  /// sender_colors_night green - Telegram id 3, night.attheme:193.
  static const Color senderGreen = Color(0xFF7DD071);

  /// sender_colors_night cyan - Telegram id 4, night.attheme:200.
  static const Color senderCyan = Color(0xFF53CCC6);

  /// sender_colors_night blue - Telegram id 5, night.attheme:318.
  static const Color senderBlue = Color(0xFF5CADEA);

  /// sender_colors_night pink - Telegram id 6, night.attheme:313.
  static const Color senderPink = Color(0xFFE8749A);

  /// Telegram's accent colour picker: Telegram's own 7 presets in Telegram's
  /// red-orange-blue-teal-green-purple-pink order (indexes 0..6), plus the
  /// measured `accentSlate` appended at index 7. Index numbers are permanent:
  /// a stored `AppSettings.telegramAccentIndex` is an index into THIS list, so
  /// an existing pick must keep pointing at the same colour - append only, never
  /// renumber. Index 7 is the fork's default (`telegramAccentIndex`'s default).
  /// Every entry is an existing `TelegramPalette` constant: the picker adds no
  /// colour beyond `accentSlate`.
  /// Indexes 4-6 are peer colours on purpose: Telegram's own picker draws those
  /// swatches from the same theme keys it uses for peer names
  /// (`ui/PeerColorActivity.java:2795`), so a pick and a name match.
  static const List<Color> accentValues = [
    accentRed, // index 0
    accentAmber, // index 1
    accentBlue, // index 2 - Telegram's own default
    accentTeal, // index 3
    senderGreen, // index 4
    senderPurple, // index 5
    senderPink, // index 6
    accentSlate, // index 7 - appended 2026-10-25, the fork's default
  ];

  /// Telegram's chat background picker (roadmap T5B), solid fills only, in
  /// dark-to-light order. Index 0 is the measured `chat_background` the fork
  /// ships with. Every entry is an existing `TelegramPalette` constant: the
  /// picker adds no new colour. A pick reaches the chat through
  /// `AppSettings.chatBackground` (global) and `AppSettings.chatBackgrounds`
  /// (per chat); light picks are darkened by the contrast guard in
  /// `lib/config/chat_backgrounds.dart`.
  static const List<Color> chatBackgroundValues = [
    chatBackground, // index 0 - #000000, the measured default
    surfaceRaised, // index 1
    chatListRowBackground, // index 2
    bubbleIncoming, // index 3
    divider, // index 4
    reactionPillBgOnIncoming, // index 5 - blue tint
    selectedMessageTint, // index 6 - blue tint
    reactionPillTinted, // index 7 - green tint
    replyQuoteBlockTeal, // index 8 - teal tint
    replyQuoteBlockAmber, // index 9 - amber tint
    datePillBackground, // index 10 - warm tint
    dayChatBackground, // index 11 - the day theme's own chat field
  ];

  /// The fixed 7-colour night palette Telegram assigns senders, in their own
  /// colour id order: `Theme.java:2707` lists
  /// `keys_avatar_nameInMessage = {Red, Orange, Violet, Green, Cyan, Blue,
  /// Pink}` and a standard peer (id < 7, `MessagesController.java:5188`) reads
  /// its name ink straight from that key (`MessagesController.java:5301-5304`).
  /// Hex values are their night-theme values from `assets/night.attheme`; the
  /// day defaults sit in `ThemeColors.java:184-190`. An unassigned peer gets
  /// its id from `user.id % 7` (`UserObject.java:215`) or `chat.id % 7`
  /// (`ChatObject.java:2582`), so we hash the sender id the same way.
  static const List<int> senderColorValues = [
    0xFFE88878, // senderRed - Telegram night.attheme:163 (id 0)
    0xFFE8AB5A, // senderOrange - Telegram night.attheme:166 (id 1)
    0xFF8C8DEA, // senderPurple - Telegram Violet, night.attheme:37 (id 2)
    0xFF7DD071, // senderGreen - Telegram night.attheme:193 (id 3)
    0xFF53CCC6, // senderCyan - Telegram night.attheme:200 (id 4)
    0xFF5CADEA, // senderBlue - Telegram night.attheme:318 (id 5)
    0xFFE8749A, // senderPink - Telegram night.attheme:313 (id 6)
  ];
}
