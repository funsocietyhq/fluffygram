// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class StartChatFab extends StatelessWidget {
  final bool extended;
  const StartChatFab({this.extended = false, super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'start_chat_fab',
      // Owner decision 2026-10-26 (user item 4): the compose button wears the
      // theme accent through the accessor, and its icon ink is picked to read
      // on that fill.
      backgroundColor: FluffyThemes.accent,
      foregroundColor: FluffyThemes.accentInk(fill: FluffyThemes.accent),
      onPressed: () => context.go('/rooms/newprivatechat'),
      extendedIconLabelSpacing: extended ? 10 : 0,
      extendedPadding: extended
          ? null
          : const EdgeInsets.symmetric(horizontal: 16),
      label: AnimatedSize(
        alignment: Alignment.centerLeft,
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        child: extended ? Text(L10n.of(context).newChat) : SizedBox.shrink(),
      ),
      icon: const Icon(Icons.edit_square),
    );
  }
}
