// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

abstract class AppConfig {
  // Fork identity. Telegram's accent blue, matching TelegramPalette.accentBlue.
  // A raw hex is allowed here: this is brand ink, not a measured target colour,
  // so it is outside the palette_contract.sh scope (that script reads only
  // lib/config/telegram_palette.dart).
  static const Color primaryColor = Color(0xFF2AABEE);

  static const Color chatColor = primaryColor;
  static const double messageFontSize = 16.0;
  static const bool allowOtherHomeservers = true;
  static const bool enableRegistration = true;
  static const bool hideTypingUsernames = false;

  static const String inviteLinkPrefix = 'https://matrix.to/#/';
  static const String deepLinkPrefix = 'fluffygram://chat/';
  static const String schemePrefix = 'matrix:';
  static const String pushNotificationsChannelId = 'fluffygram_push';
  // Must equal the Android applicationId / iOS bundle id, see docs/UPSTREAM.md.
  static const String pushNotificationsAppId = 'app.fluffygram.app';
  static const double borderRadius = 15.0;
  static const double spaceBorderRadius = 11.0;
  static const double columnWidth = 360.0;

  static const String enablePushTutorial =
      'https://ko-fi.com/post/How-can-I-get-Push-Notifications-without-Google-N7Q825URG6?fromEditor=true';
  static const String encryptionTutorial =
      'https://ko-fi.com/post/How-to-use-end-to-end-encryption-in-FluffyChat-A5O725WDR5';
  static const String howDoIGetStickersTutorial =
      'https://ko-fi.com/post/How-to-add-a-sticker-pack-to-FluffyChat-N4N01OXATI';
  // appId, appOpenUrlScheme and deepLinkPrefix move together: a deep link breaks
  // silently if one of them is left behind. appSsoUrlScheme does NOT move with them -
  // see its own comment. Renaming the first three is safe; renaming the fourth is not.
  static const String appId = 'app.fluffygram.app';
  static const String appOpenUrlScheme = 'fluffygram';
  // PINNED to the client_uri host, do not rename. MSC2966 redirect-URI validation for
  // `application_type: native` requires a private-use redirect scheme to be the reverse-DNS
  // form of the client's `client_uri` host (`im.fluffychat.auth:/login` for
  // `client_uri = https://fluffychat.im`, which is `AppSettings.website`). Matrix
  // Authentication Service enforces this in policies/client_registration/client_registration.rego
  // (`reverse_dns_match(client_uri.host, url.scheme)`), so a scheme like `fluffygram.auth`
  // gets the dynamic client registration POST refused with a policy-denied 400 and login dies
  // at `registerOidcClient` - measured on a phone at build 2. To rename this scheme, the fork
  // must first own a domain and set `chat.fluffy.website_url` to it: scheme and client_uri host
  // move together, and nothing in the repo gates the login path.
  static const String appSsoUrlScheme = 'im.fluffychat.auth';
  // Identifies the notification activation callback on Windows. Never change!
  static const String windowsNotificationGuid =
      '4894dfda-c70a-4ebc-b139-acae55f3988d';

  // AGPL-3.0 source offer: a user must point this at the public fork URL
  // before the APK goes out (docs/UPSTREAM.md "License duty"). Upstream is the
  // value of record until that URL exists.
  static const String sourceCodeUrl =
      'https://github.com/krille-chan/fluffychat';
  static const String supportUrl =
      'https://github.com/krille-chan/fluffychat/issues';
  static const String changelogUrl = 'https://fluffychat.im/changelog/';

  /// Empty = the update check is inert. The fork never asks upstream for a
  /// release, so the group is never nagged about a FluffyChat version they
  /// cannot install. `UpdateNotifier.showUpdateAvailableBanner` returns early
  /// on an empty value. Owner: set this to the fork's own GitHub releases API
  /// endpoint to re-enable the check.
  static const String latestReleaseApiUrl = '';
  static const String helpUrl =
      'https://ko-fi.com/post/How-can-I-support-FluffyChat-J2G325WE6I';

  static const Set<String> defaultReactions = {'👍', '❤️', '😂', '😮', '😢'};

  static final Uri newIssueUrl = Uri(
    scheme: 'https',
    host: 'github.com',
    path: '/krille-chan/fluffychat/issues/new',
  );

  static final Uri homeserverList = Uri(
    scheme: 'https',
    host: 'raw.githubusercontent.com',
    path: 'krille-chan/fluffychat/refs/heads/main/recommended_homeservers.json',
  );

  /// Null = crash reporting is disabled: reports are logged locally and sent
  /// nowhere. Upstream's endpoint (https://crash.fluffy.chat) receives the
  /// group's stack traces, which the fork must not do. Keep the constant;
  /// `AppSettings.autoSendErrorReports` defaults to false alongside this.
  static const Uri? crashReportEndpoint = null;

  static const String mainIsolatePortName = 'main_isolate';
  static const String pushIsolatePortName = 'push_isolate';
  static const String pushHelperCrashReportKey = 'push_helper_crash_report';

  static const String vodozemacVersion = '0.8.1';
}
