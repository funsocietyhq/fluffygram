// SPDX-FileCopyrightText: 2026 FluffyGram Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:matrix/matrix.dart';

/// Telegram draws ONE day pill per day change, centred between two message
/// groups, and never inside a group. Measured on a user's album capture
/// `the reference capture`: the photo container runs from the sender
/// name line down through the mosaic to the run's single caption line and the
/// clock, with no divider of any kind between its tiles; the day pills in the
/// a user's captures sit in the gap between two bubbles. An album is one group,
/// so a day change inside an album run gets its pill at the group's edge, not
/// between the tiles.
///
/// `ChatEventList` already takes this decision for an event that draws its own
/// row: the event starts a new day group when its day differs from the day of
/// its older neighbour in the list (the timeline list runs newest first, so the
/// older neighbour sits above it on screen). The same decision has to be taken
/// for an album member that draws no tiles of its own, and it lives here as
/// pure logic over timestamps: neither `ChatEventList` nor a `ChatController`
/// can be pumped by a test in this fork (`AGENTS.md`, "What the fidelity rig
/// cannot see").
bool startsTelegramDateGroup(Event event, Event? olderNeighbour) =>
    startsDateGroupAt(
      eventTs: event.originServerTs,
      olderTs: olderNeighbour?.originServerTs,
      roomCreate: event.type == EventTypes.RoomCreate,
    );

/// The same rule without an `Event`, so a unit test can drive it with plain
/// `DateTime`s. No older neighbour means the end of the loaded history: that is
/// where `ChatEventList` already draws a pill.
bool startsDateGroupAt({
  required DateTime eventTs,
  DateTime? olderTs,
  bool roomCreate = false,
}) => roomCreate || olderTs == null || !eventTs.sameDay(olderTs);
