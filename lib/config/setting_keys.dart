// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'dart:convert';

import 'package:async/async.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:managed_configurations/managed_configurations.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppSettings<T> {
  textMessageMaxLength<int>('textMessageMaxLength', 16384),

  /// Max lines for unselected HTML/text bubbles; 0 = unlimited (no fade).
  messagePreviewMaxLines<int>('chat.fluffy.message_preview_max_lines', 50),
  audioRecordingNumChannels<int>('audioRecordingNumChannels', 1),
  audioRecordingAutoGain<bool>('audioRecordingAutoGain', true),
  audioRecordingEchoCancel<bool>('audioRecordingEchoCancel', false),
  audioRecordingNoiseSuppress<bool>('audioRecordingNoiseSuppress', true),
  audioRecordingBitRate<int>('audioRecordingBitRate', 64000),
  audioRecordingSamplingRate<int>('audioRecordingSamplingRate', 48000),
  showNoGoogle<bool>('chat.fluffy.show_no_google', false),
  unifiedPushRegistered<bool>('chat.fluffy.unifiedpush.registered', false),
  unifiedPushEndpoint<String>('chat.fluffy.unifiedpush.endpoint', ''),
  // Empty = derive it from the client's own homeserver, see `pushGatewayUrl()`
  // in lib/utils/background_push.dart. Upstream's shipped default was
  // 'https://push.fluffychat.im/_matrix/push/v1/notify', FluffyChat's own
  // Sygnal: it answers 404 for a pusher whose app_id is app.fluffygram.app,
  // Synapse deletes that pusher, and no member is ever notified.
  //
  // The group build pins the gateway at compile time:
  //   --dart-define=PUSH_GATEWAY_URL=https://<gateway-host>/_matrix/push/v1/notify?s=<token>
  // Two rules the value has to satisfy, both measured on a user's phone on a
  // hosted Synapse (2026-10-26, ROADMAP T35.2):
  //   1. the path must be exactly /_matrix/push/v1/notify. A URL whose path is
  //      '/' is refused at POST /_matrix/client/v3/pushers/set with
  //      M_MISSING_PARAM: Config Error: 'url' must have a path of
  //      '/_matrix/push/v1/notify' - no pusher row is created, so the phone is
  //      never notified and nothing retries.
  //   2. the gateway cannot live on the homeserver, which nobody here
  //      administers, so the URL has to travel in the APK. The ?s= token is the
  //      only credential that can ride along: Synapse sends no auth header to a
  //      pusher URL. A plain build passes no flag, `String.fromEnvironment` is
  //      '', and the homeserver derivation still applies.
  pushNotificationsGatewayUrl<String>(
    'pushNotificationsGatewayUrl',
    String.fromEnvironment('PUSH_GATEWAY_URL'),
  ),
  pushNotificationsPusherFormat<String>(
    'pushNotificationsPusherFormat',
    'event_id_only',
  ),
  renderHtml<bool>('chat.fluffy.renderHtml', true),

  /// Message text size as a factor of `AppConfig.messageFontSize` (16sp).
  /// Telegram's slider is 12..24sp = 0.75..1.5, default 16sp = 1.0.
  fontSizeFactor<double>('chat.fluffy.font_size_factor', 1.0),
  hideRedactedEvents<bool>('chat.fluffy.hideRedactedEvents', false),
  hideUnknownEvents<bool>('chat.fluffy.hideUnknownEvents', true),
  autoplayImages<bool>('chat.fluffy.autoplay_images', true),
  sendTypingNotifications<bool>('chat.fluffy.send_typing_notifications', true),
  sendPublicReadReceipts<bool>('chat.fluffy.send_public_read_receipts', true),
  swipeRightToLeftToReply<bool>('chat.fluffy.swipeRightToLeftToReply', true),
  sendOnEnter<bool>('chat.fluffy.send_on_enter', false),
  displayNavigationRail<bool>('chat.fluffy.display_navigation_rail', false),
  shareKeysWith<String>('chat.fluffy.share_keys_with_2', 'all'),
  noEncryptionWarningShown<bool>(
    'chat.fluffy.no_encryption_warning_shown',
    false,
  ),
  displayChatDetailsColumn('chat.fluffy.display_chat_details_column', false),
  // AppConfig-mirrored settings. Fork name (T9): this string is the app name
  // the app shows in-app (about page, notifications, share sheets).
  applicationName<String>('chat.fluffy.application_name', 'FluffyGram'),
  defaultHomeserver<String>('chat.fluffy.default_homeserver', 'matrix.org'),
  // colorSchemeSeed stored as ARGB int. Used as the theme seed while
  // `telegramAccentIndex` is -1 (a custom colour picked from the old grid).
  colorSchemeSeedInt<int>('chat.fluffy.color_scheme_seed', 0xFF2AABEE),

  /// Telegram's accent colour picker: index into
  /// `TelegramPalette.accentValues` (indexes 0..6 are Telegram's own presets,
  /// index 7 is the measured slate appended on 2026-10-25), -1 = use
  /// `colorSchemeSeedInt`. Default 7 = `TelegramPalette.accentSlate #4D506E`,
  /// the accent measured on a user's Pixel.
  telegramAccentIndex<int>('chat.fluffy.telegram_accent_index', 7),

  /// The bubble width: the percent of the chat column a bubble may use on a
  /// wide window, 50..100. Telegram desktop's "Custom width for the message
  /// bubble" slider defaults to 72 (tdesktop ChatListWidth); **this fork ships
  /// 100** - user decision 2026-10-29 (T130), "make 100% bubble width the
  /// default option". A member who moves the slider keeps their own value.
  /// The dp cap is derived from it and the window, never typed (T39, user
  /// 2026-10-27). A phone-width window ignores this setting entirely - see
  /// `TelegramBubbleGeometry.maxBubbleWidthForWindow` - because Telegram's
  /// phone layout has no width knob.
  bubbleWidthPercent<int>('chat.fluffy.bubble_width_percent', 100),

  /// Telegram's "Animations" switch: off = the jump-to-latest fade, the
  /// swipe-to-reply snap-back and the bubble/reaction size changes use
  /// `Duration.zero`. Scroll physics are never disabled.
  animationsEnabled<bool>('chat.fluffy.animations_enabled', true),

  /// Telegram's "Colored sender names" switch: off = the sender name and the
  /// chat-list sender prefix draw in `TelegramPalette.textSecondary`.
  colorSenderNames<bool>('chat.fluffy.color_sender_names', true),

  /// Telegram's chat background, every chat: a `#RRGGBB` solid fill, '' = the
  /// theme's own chat field. Device-local appearance, never room state.
  chatBackground<String>('chat.fluffy.chat_background', ''),

  /// Telegram's per-chat chat background: a JSON object
  /// `{"!room:server":"#RRGGBB"}`. Device-local appearance, never room state.
  chatBackgrounds<String>('chat.fluffy.chat_backgrounds', '{}'),

  /// Telegram's recently used stickers: a JSON list of `mxc://` URIs, most
  /// recent first, capped at `RecentStickers.cap`. Device-local, never room
  /// state - the sticker send events themselves are unchanged.
  recentStickers<String>('chat.fluffy.recent_stickers', '[]'),

  /// The GIF tray's own collection: a JSON list of `mxc://` URIs, most recent
  /// first, capped at `RecentGifs.cap`. Device-local, never room state - the
  /// GIF send events themselves are unchanged. Separate from the sticker key:
  /// stickers and GIFs are different media.
  recentGifs<String>('chat.fluffy.recent_gifs', '[]'),

  /// T56.3.1: set once the device has run its single GIF-history seed scan
  /// for `RecentGifs`. Superseded by `recentGifsSeededRooms` (T113): a device
  /// that scanned one chat had no way to fill the next one. Kept so an
  /// installed device loses nothing.
  recentGifsSeeded<bool>('chat.fluffy.recent_gifs_seeded', false),

  /// T113: the rooms whose GIF-history scan has run, `|`-joined. T125
  /// (2026-10-30) deleted that scan - the tray is persistent storage now, not
  /// something recomputed when the app opens the picker. The key stays: an
  /// installed device already carries the value, and deleting the enum entry
  /// would rename nothing and save nothing. `recentGifsSeeded` is kept for the
  /// same reason.
  recentGifsSeededRooms<String>('chat.fluffy.recent_gifs_seeded_rooms', ''),

  /// T125 (user, 2026-10-30: "Even if I remove something from my gif tray, it
  /// comes back when I restart the app. The tray should be persistent storage,
  /// not calculated when I open the app"): the mxc urls a user removed from
  /// the GIF tray, `|`-joined, newest last, capped at `RecentGifs.removedCap`
  /// (500). The **bare url** is the key, so a removal hides that GIF in every
  /// chat. Every writer that builds a GIF row from an event refuses a url
  /// held here; the message long-press menu's "Add to gifs" is the one way to
  /// lift it. Device-local, like the tray itself.
  recentGifsRemoved<String>('chat.fluffy.recent_gifs_removed', ''),

  /// T118 (user, 2026-10-30: "the drawer must remember the last tab picked, so
  /// I do not tap GIF every time"): which tray tab the chat composer opens on.
  /// The index is read straight into `DefaultTabController.initialIndex`, so it
  /// is the order the tray lists its tabs in, not a name. Device-wide, not per
  /// chat: that is what a user picked, and it is the smaller diff. Telegram
  /// stores no tray tab at all, so this key is a fork convenience, not a ported
  /// behaviour (`the measurement log`, "Does Telegram restore the last tray
  /// tab? No.").
  chatEmojiPickerTab<int>('chat.fluffy.chat_emoji_picker_tab', 0),

  /// A `.attheme` theme imported from Telegram (roadmap T8): the raw file text,
  /// parsed at read time by `lib/config/attheme.dart`. '' = none imported.
  /// Device-local appearance state - zero Matrix room state, zero protocol.
  importedAttheme<String>('chat.fluffy.imported_attheme', ''),

  /// File name of the imported theme above, shown on the style page. '' = none.
  importedAtthemeName<String>('chat.fluffy.imported_attheme_name', ''),
  emojiSuggestionLocale<String>('emoji_suggestion_locale', ''),
  enableSoftLogout<bool>('chat.fluffy.enable_soft_logout', true),
  enableMatrixNativeOIDC<bool>('chat.fluffy.enable_matrix_native_oidc', true),
  // Non-empty = the server-pick screen is skipped at login: `intro_page_presenter.dart:102` routes
  // straight into `connectToHomeserverFlow(PublicHomeserverData(name: presetHomeserver))`, so the
  // user never sees the list and cannot type a hostname. Empty = the sign-in screen opens, whose
  // filter field accepts any hostname (`sign_in_view_model.dart:50`). Keep this empty for a group on
  // its own server; set it to that one hostname only when the group is fixed to it and nobody needs
  // to choose. T9 set it to matrix.org, which locked every login to matrix.org (seen on a phone).
  // `defaultHomeserver` is the softer knob: it only decides which entry is preselected.
  presetHomeserver<String>('chat.fluffy.preset_homeserver', ''),
  welcomeText<String>('chat.fluffy.welcome_text', ''),
  website<String>('chat.fluffy.website_url', 'https://fluffychat.im'),
  logoUrl<String>(
    'chat.fluffy.logo_url',
    'https://fluffychat.im/assets/favicon.png',
  ),
  privacyPolicy<String>(
    'chat.fluffy.privacy_policy_url',
    'https://fluffychat.im/privacy',
  ),
  tos<String>('chat.fluffy.tos_url', 'https://fluffychat.im/tos'),
  sendTimelineEventTimeout<int>('chat.fluffy.send_timeline_event_timeout', 15),
  webNotificationSound<bool>('chat.fluffy.web_notification_sound', true),
  chatFilter<String>('chat.fluffy.chat_filter', 'allChats'),
  hideRoomsInSpaces<bool>('chat.fluffy.hideRoomsInSpaces', false),
  showThumbnailsInTimeline<bool>('chat.fluffy.showThumbnailsInTimeline', true),
  doubleTapToReact<bool>('chat.fluffy.double_tap_to_react', false),
  doubleTapReaction<String>('chat.fluffy.double_tap_reaction', '❤️'),
  benchmarksInLogs<bool>('chat.fluffy.benchmarks_in_logs', false),
  // Fork: false = crash reports are never sent off the phone. Upstream's
  // default (null) asks the user, then posts to AppConfig.crashReportEndpoint,
  // which the fork has set to null.
  autoSendErrorReports<bool?>('chat.fluffy.auto_send_eror_reports', false),
  knownErrorHashes<List<String>>('chat.fluffy.known_crash_hashes', []),
  // Fork: the update check is off (and AppConfig.latestReleaseApiUrl is empty),
  // so the app cannot nag the group about an upstream release.
  checkForUpdates<bool>('chat.fluffy.check_for_updates', false),
  lastUpdateCheckDate<String>('chat.fluffy.last_update_check_date', ''),
  fallbackLiveKitInstance<String>('chat.fluffy.fallback_live_kit_instance', '');

  final String key;
  final T _defaultValue;

  const AppSettings(this.key, this._defaultValue);

  static SharedPreferences get store => _store!;
  static SharedPreferences? _store;

  static Map<String, Object?>? _platformConfiguration;

  T get defaultValue {
    final platformConfig = _platformConfiguration?[name];
    if (platformConfig is T) return platformConfig;
    return _defaultValue;
  }

  static Future<void> reset({bool loadWebConfigFile = true}) async {
    for (final setting in AppSettings.values) {
      await AppSettings.store.remove(setting.key);
    }
    await init(loadWebConfigFile: loadWebConfigFile);
  }

  static Future<SharedPreferences> init({bool loadWebConfigFile = true}) async {
    if (AppSettings._store != null) return AppSettings.store;

    final store = AppSettings._store = await SharedPreferences.getInstance();

    // Migrate wrong datatype for fontSizeFactor
    final fontSizeFactorString = Result(
      () => store.getString(AppSettings.fontSizeFactor.key),
    ).asValue?.value;
    if (fontSizeFactorString != null) {
      Logs().i('Migrate wrong datatype for fontSizeFactor!');
      await store.remove(AppSettings.fontSizeFactor.key);
      final fontSizeFactor = double.tryParse(fontSizeFactorString);
      if (fontSizeFactor != null) {
        await store.setDouble(AppSettings.fontSizeFactor.key, fontSizeFactor);
      }
    }

    if (store.getBool(AppSettings.sendOnEnter.key) == null) {
      await store.setBool(AppSettings.sendOnEnter.key, !PlatformInfos.isMobile);
    }
    if (store.getBool(AppSettings.doubleTapToReact.key) == null) {
      await store.setBool(
        AppSettings.doubleTapToReact.key,
        PlatformInfos.isMobile,
      );
    }

    // Load configuration from config.json file or MDM:
    if (PlatformInfos.isMobile) {
      _platformConfiguration =
          await ManagedConfigurations().getManagedConfigurations;
    } else if (kIsWeb && loadWebConfigFile) {
      try {
        final configJsonString = utf8.decode(
          (await http.get(Uri.parse('config.json'))).bodyBytes,
        );
        _platformConfiguration =
            json.decode(configJsonString) as Map<String, Object?>;
      } on FormatException catch (_) {
        Logs().v('[ConfigLoader] config.json not found');
      } catch (e) {
        Logs().v('[ConfigLoader] config.json not found', e);
      }
    }

    return store;
  }
}

extension AppSettingsBoolNExtension on AppSettings<bool?> {
  bool? get value {
    final value = Result(() => AppSettings.store.getBool(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value;
  }

  Future<void> setItem(bool value) => AppSettings.store.setBool(key, value);
}

extension AppSettingsBoolExtension on AppSettings<bool> {
  bool get value {
    final value = Result(() => AppSettings.store.getBool(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(bool value) => AppSettings.store.setBool(key, value);
}

extension AppSettingsStringExtension on AppSettings<String> {
  String get value {
    final value = Result(() => AppSettings.store.getString(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(String value) => AppSettings.store.setString(key, value);
}

extension AppSettingsIntExtension on AppSettings<int> {
  int get value {
    final value = Result(() => AppSettings.store.getInt(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(int value) => AppSettings.store.setInt(key, value);
}

extension AppSettingsDoubleExtension on AppSettings<double> {
  double get value {
    final value = Result(() => AppSettings.store.getDouble(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(double value) => AppSettings.store.setDouble(key, value);
}

extension AppSettingsStringListExtension on AppSettings<List<String>> {
  List<String> get value {
    final value = Result(() => AppSettings.store.getStringList(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(List<String> value) =>
      AppSettings.store.setStringList(key, value);
}
