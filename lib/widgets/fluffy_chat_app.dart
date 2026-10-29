// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:developer';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/demo_mode.dart';
import 'package:fluffychat/config/routes.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets/layouts/call_overlay.dart';
import 'package:fluffychat/widgets/theme_builder.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/custom_scroll_behaviour.dart';
import '../utils/demo/demo_seed.dart';
import 'matrix.dart';

class FluffyChatApp extends StatelessWidget {
  final Widget? testWidget;
  final List<Client> clients;
  final ({String? pincode, bool useBiometrics}) appLockSettings;
  final SharedPreferences store;
  final Locale? locale;

  const FluffyChatApp({
    super.key,
    this.testWidget,
    required this.clients,
    required this.store,
    required this.appLockSettings,
    this.locale,
  });

  /// getInitialLink may rereturn the value multiple times if this view is
  /// opened multiple times for example if the user logs out after they logged
  /// in with qr code or magic link.
  static bool gotInitialLink = false;

  // Router must be outside of build method so that hot reload does not reset
  // the current path.
  static final GoRouter router = GoRouter(
    routes: AppRoutes.routes,
    // Demo mode opens straight on the seeded group chat; `intro_page` and
    // `sign_in` are never reached, and the login redirect on `/rooms` is
    // satisfied because the demo client is logged in.
    initialLocation: kFluffyGramDemo ? demoInitialRoute : '/',
    debugLogDiagnostics: true,
    redirect: (context, state) {
      // Workaround for content sharings passed to go router:
      if ({
        'content',
        'sharemedia-im.fluffychat.app',
      }.contains(state.uri.scheme)) {
        Logs().d('Ignore content sharing handling in go router', state.uri);
        return '/';
      }

      if (state.uri.scheme == 'matrix') {
        debugger();
        final type = state.uri.pathSegments.first;
        final id = state.uri.pathSegments[1];
        switch (type) {
          case 'roomid':
            final roomId = '!$id';
            return '/rooms/$roomId';
          case 'r':
            final alias = '#$id';
            return '/rooms/newprivatechat#$alias';
          case 'u':
            final userId = '@$id';
            return '/rooms/newprivatechat#$userId';
        }
      }

      // Pass deep links to app:
      if (state.uri.toString().startsWith(AppConfig.deepLinkPrefix)) {
        return '/rooms/newprivatechat#${state.uri}';
      }
      return null;
    },
  );

  @override
  Widget build(BuildContext context) {
    return ThemeBuilder(
      builder: (context, themeMode, primaryColor) => MaterialApp.router(
        title: AppSettings.applicationName.value,
        themeMode: themeMode,
        debugShowCheckedModeBanner: false,
        locale: locale,
        theme: FluffyThemes.buildTheme(context, Brightness.light, primaryColor),
        darkTheme: FluffyThemes.buildTheme(
          context,
          Brightness.dark,
          primaryColor,
        ),
        scrollBehavior: CustomScrollBehavior(),
        localizationsDelegates: [
          ...L10n.localizationsDelegates,
          ...GlobalMaterialLocalizations.delegates,
          ...GlobalCupertinoLocalizations.delegates,
        ],
        supportedLocales: L10n.supportedLocales,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          // Telegram's model (user finding 28): Android's system font-size
          // setting scales nothing in Telegram - a 16 is a 16 on every
          // surface. Flutter multiplies every Text by that scaler wherever
          // the fork does not pin it, which put the chat header 10 percent
          // above Telegram's identical title words on a user's phone
          // (identical header words measured 43 px against 39 and 43 against 39). The root pin
          // makes the fork's own Chat appearance -> Text size slider the
          // only multiplier, on every surface.
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(AppSettings.fontSizeFactor.value),
          ),
          child: AppLockWidget(
            pincode: appLockSettings.pincode,
            useBiometrics: appLockSettings.useBiometrics,
            isLoggedIn: clients.any((client) => client.isLogged()),
            // Need a navigator above the Matrix widget for
            // displaying dialogs
            child: Matrix(
              clients: clients,
              store: store,
              child: CallOverlay(
                child: testWidget ?? child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
