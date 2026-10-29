// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:intl/intl.dart';

/// The chat-list row's date column, following Telegram's four-case rule.
///
/// Port of `LocaleController.stringForMessageListDate()`, Telegram
/// LocaleController.java:2832-2856 (vendored tree, read 2026-10-27), called
/// from DialogCell.java:1410. `dayDiff` is a difference of day-of-year of
/// [date] minus [now] (LocaleController.java:2843), so "today" is calendar-day
/// based; the 8 h clause (:2844) prints the time for a late message from
/// yesterday seen this morning. Telegram's `Calendar.DAY_OF_YEAR` maths wraps
/// at the year border (Dec 31 seen on Jan 1 lands on `dd MMM`); the same
/// arithmetic, quirk included, is reproduced here to stay 1:1.
///
/// This file must not import `package:matrix`: the pure rule is unit-tested
/// in test/telegram_fidelity/dialog_date_test.dart.
String telegramDialogDateString(
  DateTime? date, {
  required DateTime now,
  required bool hourOfDayFirst,
  String? locale,
}) {
  if (date == null) return '';
  // LocaleController.java:2835 - one year or more: dd.MM.yy.
  if (now.difference(date).abs().inMilliseconds >= 31536000000) {
    return DateFormat('dd.MM.yy', locale).format(date);
  }
  final dayDiff = _dayOfYear(date) - _dayOfYear(now); // :2843
  if (dayDiff == 0 ||
      // :2844 - yesterday, less than 8 h ago: the time.
      (dayDiff == -1 &&
          now.difference(date).inMilliseconds < 8 * 3600 * 1000)) {
    return DateFormat(hourOfDayFirst ? 'HH:mm' : 'h:mm a', locale).format(date);
  } else if (dayDiff > -7 && dayDiff <= -1) {
    // :2846 - 2 to 7 calendar days ago: abbreviated weekday.
    return DateFormat.E(locale).format(date);
  }
  // :2848 - older than 7 days, under a year: dd MMM.
  return DateFormat('dd MMM', locale).format(date);
}

/// `Calendar.DAY_OF_YEAR` of [d] in the local calendar.
int _dayOfYear(DateTime d) => d.difference(DateTime(d.year, 1, 1)).inDays + 1;
