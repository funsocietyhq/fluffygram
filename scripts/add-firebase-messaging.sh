#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# FluffyGram runs this after an upstream rebase, not before a build: upstream keeps
# the //<GOOGLE_SERVICES> markers commented in lib/ and keeps the FcmPushService body
# block-commented, so a rebase that touches either file puts the markers back and
# silently switches this fork's builds back to UnifiedPush-only. The Kotlin path below
# is the fork's package dir - upstream's copy of this script points at
# chat/fluffy/fluffychat/, which does not exist here.

flutter pub add fcm_shared_isolate
flutter pub get

if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' 's,//<GOOGLE_SERVICES>,,g' lib/utils/background_push.dart
  sed -i '' -e 's,^/\*,,' -e 's,\*/$,,' android/app/src/main/kotlin/app/fluffygram/app/FcmPushService.kt
else
  sed -i 's,//<GOOGLE_SERVICES>,,g' lib/utils/background_push.dart
  sed -i -e 's,^/\*,,' -e 's,\*/$,,' android/app/src/main/kotlin/app/fluffygram/app/FcmPushService.kt
fi
