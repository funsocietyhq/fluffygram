// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// The demo seed, added 2026-10-24 for the `FLUFFYGRAM_DEMO` build flag.
//
// `buildDemoClient()` returns the one `Client` a demo build runs with: a real
// `Client` with the app's own database factory, a fake account record
// (`https://fluffygram.local`, never contacted), and two rooms written straight
// into `client.database` - the same in-memory-store + real-`Event`-object shape
// `test/telegram_fidelity/album_cluster_test.dart` proves in this repo.
//
// Everything below is written through the SDK's own store API
// (`storeRoomUpdate`, `storeEventUpdate`, `storeRoomAccountData`) with
// `EventTypes` / `MessageTypes` / `RelationshipTypes` constants, so the chat
// page, the chat list and the album cluster see an ordinary synced session.
// There is no protocol code here: no requests are sent, and `DemoHttpClient`
// (`demo_media.dart`) is what keeps the network off.

import 'dart:convert';

import 'package:fluffychat/config/demo_mode.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/demo/demo_media.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/builder.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `clientId` of the demo client. Its database file is `<clientId>.sqlite`, so a
/// demo build never opens a real session's database.
const String demoClientId = 'fluffygram-demo';

/// The signed-in user of the fake session.
const String demoUserId = '@alice:fluffygram.local';

/// Device id of the fake session (a local string; no device exists).
const String demoDeviceId = 'DEMOGRAM01';

/// The group chat the app opens on.
const String demoGroupId = '!demo:fluffygram.local';

/// The second room, so the chat list shows two rows with different states.
const String demoTripId = '!trip:fluffygram.local';

/// Route the demo build starts on: the group chat, not the intro page.
const String demoInitialRoute = '/rooms/!demo:fluffygram.local';

/// The plain-text messages the seed places in the timelines, as raw Matrix
/// event JSON fragments. The in-chat search stub (`demo_media.dart`) answers
/// `/_matrix/client/v3/search` from this list, filled as the seed builds
/// (T40.3a), so a query in the web demo finds real seeded text.
final List<Map<String, Object?>> demoSeedTextEvents = <Map<String, Object?>>[];

/// Members of the group chat, all on the fake server name.
const List<String> demoGroupMembers = <String>[
  '@sue:fluffygram.local',
  '@bob:fluffygram.local',
  '@mallory:fluffygram.local',
  '@alice:fluffygram.local',
];

/// Stickers seeded into the sticker tray's "recent" row (`RecentStickers`).
const List<String> demoRecentStickerUris = <String>[
  'mxc://fluffygram.local/sticker/sticker_1f602.png',
  'mxc://fluffygram.local/sticker/sticker_1f525.png',
  'mxc://fluffygram.local/sticker/sticker_1f6f8.png',
  'mxc://fluffygram.local/sticker/sticker_1f44d.png',
];

/// Text seeded as the group chat's draft, so the chat list shows the `Draft:`
/// row (the same `draft_<room id>` key `pages/chat_list/chat_list_draft.dart`
/// reads).
const String demoGroupDraft = 'Bring the coffee beans from the market';

/// State events loaded with the room row. `m.room.pinned_events` is added to the
/// SDK's default set here so the pinned bar has its data at first paint, not
/// only after `Room.postLoad()`.
const Set<String> demoImportantStateEvents = <String>{
  EventTypes.RoomPinnedEvents,
  EventTypes.RoomCreate,
  EventTypes.RoomJoinRules,
  EventTypes.HistoryVisibility,
  EventTypes.RoomPowerLevels,
  EventTypes.RoomTopic,
  EventTypes.RoomName,
  EventTypes.RoomAvatar,
  EventTypes.RoomMember,
  'im.ponies.room_emotes',
};

/// The day the seed is dated - the host date at the time this file was written.
final DateTime _seedDay = DateTime.utc(2026, 10, 24);

/// A timestamp inside the seed day.
DateTime _at(int hour, int minute, [int second = 0]) =>
    _seedDay.add(Duration(hours: hour, minutes: minute, seconds: second));

/// `w, h, size, thumbnail size` of each bundled photo, as measured with
/// `identify` on the files in `assets/demo/`.
const Map<String, (int, int, int, int)> _photoDims =
    <String, (int, int, int, int)>{
      'photo/photo_01_cat.jpg': (1024, 768, 115285, 16229),
      'photo/photo_02_dumplings.jpg': (1024, 768, 144124, 15674),
      'photo/photo_03_frog.jpg': (1024, 768, 81564, 10244),
      'photo/photo_04_neonstreet.jpg': (1024, 768, 75771, 10117),
      'photo/photo_05_workshop.jpg': (1024, 768, 121507, 15750),
      'photo/photo_06_lighthouse.jpg': (1024, 768, 69057, 8164),
      'photo/photo_07_tomatoes.jpg': (1024, 768, 58047, 8073),
      'photo/photo_08_bike.jpg': (1024, 768, 66768, 12874),
      'photo/photo_09_hike.jpg': (768, 1024, 43729, 7373),
      'photo/photo_10_coffee.jpg': (768, 1024, 145136, 15108),
    };

/// `mxc://` for a name under `assets/demo/`.
String _mxc(String name) => 'mxc://$kFluffyGramDemoServerName/$name';

/// The MXC host check used by the media mapping.
String get demoMxcPrefix => 'mxc://$kFluffyGramDemoServerName/';

/// One event of the seed. [id] becomes a `$<id>:fluffygram.local` event id.
MatrixEvent _event({
  required String id,
  required String sender,
  required DateTime ts,
  required Map<String, Object?> content,
  String type = EventTypes.Message,
  String? stateKey,
}) => MatrixEvent(
  eventId: '\$$id:$kFluffyGramDemoServerName',
  senderId: sender,
  type: type,
  content: content,
  originServerTs: ts,
  stateKey: stateKey,
  unsigned: <String, Object?>{'age_ms': 0},
);

/// `$<id>:fluffygram.local` - the event id form used in relations.
String _eventId(String id) => '\$$id:$kFluffyGramDemoServerName';

/// A plain text message.
MatrixEvent _text(
  String id,
  String sender,
  DateTime ts,
  String body, {
  Map<String, Object?>? relatesTo,
}) {
  demoSeedTextEvents.add(<String, Object?>{
    'event_id': _eventId(id),
    'room_id': demoGroupId,
    'sender': sender,
    'origin_server_ts': ts.millisecondsSinceEpoch,
    'type': 'm.room.message',
    'content': <String, Object?>{'msgtype': 'm.text', 'body': body},
  });
  return _event(
    id: id,
    sender: sender,
    ts: ts,
    content: <String, Object?>{
      'msgtype': MessageTypes.Text,
      'body': body,
      'm.relates_to': ?relatesTo,
    },
  );
}

/// An edit of [targetId]: `m.new_content` plus `rel_type: m.replace`, which is
/// what makes the `(edited)` mark render.
MatrixEvent _editedText(
  String id,
  String targetId,
  String sender,
  DateTime ts,
  String newBody,
) => _event(
  id: id,
  sender: sender,
  ts: ts,
  content: <String, Object?>{
    'msgtype': MessageTypes.Text,
    'body': '* $newBody',
    'm.new_content': <String, Object?>{
      'msgtype': MessageTypes.Text,
      'body': newBody,
    },
    'm.relates_to': <String, Object?>{
      'rel_type': RelationshipTypes.edit,
      'event_id': _eventId(targetId),
    },
  },
);

/// A reaction with key [key] on [targetId].
MatrixEvent _reaction(
  String id,
  String targetId,
  String sender,
  DateTime ts,
  String key,
) => _event(
  id: id,
  sender: sender,
  ts: ts,
  type: EventTypes.Reaction,
  content: <String, Object?>{
    'm.relates_to': <String, Object?>{
      'rel_type': RelationshipTypes.reaction,
      'event_id': _eventId(targetId),
      'key': key,
    },
  },
);

/// An `m.image` for one bundled photo, with the thumbnail fields the album grid
/// and the image viewer read. A `caption` is a `body` that differs from
/// `filename`: `Event.fileDescription` (`lib/utils/file_description.dart`) -
/// what the timeline actually reads - reports null when the two are equal, so
/// only a captioned call puts a caption on the wire.
Map<String, Object?> _imageContent(String name, {String? caption}) {
  final (width, height, size, thumbSize) =
      _photoDims[name] ?? (1024, 768, 100000, 12000);
  final thumbName = name.replaceFirst('photo/', 'thumb/');
  return <String, Object?>{
    'msgtype': MessageTypes.Image,
    if (caption != null) 'filename': name.split('/').last,
    'body': caption ?? name.split('/').last,
    'url': _mxc(name),
    'info': <String, Object?>{
      'w': width,
      'h': height,
      'mimetype': 'image/jpeg',
      'size': size,
      'thumbnail_url': _mxc(thumbName),
      'thumbnail_info': <String, Object?>{
        'w': 240,
        'h': 240,
        'mimetype': 'image/jpeg',
        'size': thumbSize,
      },
    },
  };
}

/// A voice message: MSC3245 voice marker plus the MSC1767 duration and waveform
/// the voice bubble draws.
Map<String, Object?> _voiceContent(
  String name, {
  required int durationMs,
  required int size,
  required List<int> waveform,
}) => <String, Object?>{
  'msgtype': MessageTypes.Audio,
  'body': 'Voice message',
  'url': _mxc('voice/$name.wav'),
  // The waveform and the duration sit in two places on purpose. Under `info`
  // is where MSC1767 puts them and what Element sends; at the top level of the
  // content is what this app's own voice recorder writes (`chat.dart:1010`) and
  // therefore what the voice bubble reads (`audio_player.dart:360`). Seeding
  // only the `info` copy paints 40 equal-height bars, because the painter falls
  // back to its `emptyAmplitude` constant when it finds no waveform.
  'org.matrix.msc1767.audio': <String, Object?>{
    'duration': durationMs,
    'waveform': waveform,
  },
  'info': <String, Object?>{
    'duration': durationMs,
    'mimetype': 'audio/wav',
    'size': size,
    'org.matrix.msc1767.audio': <String, Object?>{
      'duration': durationMs,
      'waveform': waveform,
    },
    'org.matrix.msc3245.voice': <String, Object?>{},
  },
};

/// A fake waveform: 40 bars, 0..256 scale, shaped like speech.
List<int> _waveform(int seed) => <int>[
  for (var i = 0; i < 40; i++)
    40 + ((seed * 37 + i * 61 + (i.isEven ? 90 : 0)) % 190),
];

/// The state events of a joined room: create, join rules, history, power levels,
/// name, optional avatar, optional pinned list, and one `m.room.member` per
/// member.
List<MatrixEvent> _stateEvents({
  required String creator,
  required List<String> members,
  required String roomName,
  required DateTime ts,
  String? avatarMxc,
  List<String> pinned = const <String>[],
}) => <MatrixEvent>[
  _event(
    id: 'create',
    sender: creator,
    ts: ts,
    stateKey: '',
    type: EventTypes.RoomCreate,
    content: <String, Object?>{'creator': creator, 'room_version': '11'},
  ),
  _event(
    id: 'join_rules',
    sender: creator,
    ts: ts,
    stateKey: '',
    type: EventTypes.RoomJoinRules,
    content: <String, Object?>{'join_rule': 'public'},
  ),
  _event(
    id: 'history',
    sender: creator,
    ts: ts,
    stateKey: '',
    type: EventTypes.HistoryVisibility,
    content: <String, Object?>{'history_visibility': 'shared'},
  ),
  _event(
    id: 'power_levels',
    sender: creator,
    ts: ts,
    stateKey: '',
    type: EventTypes.RoomPowerLevels,
    content: <String, Object?>{
      'users': <String, int>{
        for (final member in members) member: member == creator ? 100 : 50,
      },
      'users_default': 0,
      'events_default': 0,
      'state_default': 50,
      'ban': 50,
      'kick': 50,
      'redact': 50,
      'invite': 0,
    },
  ),
  _event(
    id: 'name',
    sender: creator,
    ts: ts,
    stateKey: '',
    type: EventTypes.RoomName,
    content: <String, Object?>{'name': roomName},
  ),
  if (avatarMxc != null)
    _event(
      id: 'avatar',
      sender: creator,
      ts: ts,
      stateKey: '',
      type: EventTypes.RoomAvatar,
      content: <String, Object?>{'url': avatarMxc},
    ),
  if (pinned.isNotEmpty)
    _event(
      id: 'pinned',
      sender: creator,
      ts: ts,
      stateKey: '',
      type: EventTypes.RoomPinnedEvents,
      content: <String, Object?>{'pinned': pinned},
    ),
  for (final member in members)
    _event(
      id: 'member_${member.localpart}',
      sender: member,
      ts: ts,
      stateKey: member,
      type: EventTypes.RoomMember,
      content: <String, Object?>{
        'membership': 'join',
        'displayname': member.localpart,
      },
    ),
];

/// One room, written through the SDK's own store calls.
///
/// [timeline] is oldest first: `storeEventUpdate` with
/// [EventUpdateType.timeline] inserts at the head of the stored id list, which
/// is the newest-first order `Timeline` walks.
Future<void> _seedRoom(
  Client client, {
  required String roomId,
  required List<MatrixEvent> state,
  required List<MatrixEvent> timeline,
  required List<String> heroes,
  int notificationCount = 0,
  Map<String, Object?>? roomTag,
}) async {
  final room = Room(id: roomId, client: client);
  final update = JoinedRoomUpdate(
    summary: RoomSummary.fromJson(<String, Object?>{
      'm.heroes': heroes,
      'm.joined_member_count': heroes.length,
      'm.invited_member_count': 0,
    }),
    state: state,
    timeline: TimelineUpdate(
      events: timeline,
      limited: false,
      prevBatch: 'demo-batch',
    ),
    unreadNotifications: UnreadNotificationCounts(
      notificationCount: notificationCount,
      highlightCount: 0,
    ),
  );
  final lastEvent = timeline.isEmpty
      ? null
      : Event.fromMatrixEvent(timeline.last, room);

  await client.database.transaction(() async {
    await client.database.storeRoomUpdate(roomId, update, lastEvent, client);
    for (final event in state) {
      await client.database.storeEventUpdate(
        roomId,
        event,
        EventUpdateType.state,
        client,
      );
    }
    for (final event in timeline) {
      await client.database.storeEventUpdate(
        roomId,
        event,
        EventUpdateType.timeline,
        client,
      );
    }
  });

  if (roomTag != null) {
    await client.database.storeRoomAccountData(
      roomId,
      BasicEvent(type: 'm.tag', content: roomTag),
    );
  }
}

/// The `Weekend Crew` timeline, oldest first. Senders rotate, and every surface
/// the verification rig cannot render has at least one event in here.
List<MatrixEvent> _groupTimeline() {
  final (sue, bob, mallory, alice) = (
    '@sue:fluffygram.local',
    '@bob:fluffygram.local',
    '@mallory:fluffygram.local',
    '@alice:fluffygram.local',
  );

  // The 12-photo burst: ten photos, then photo_09 and photo_10 again, all from
  // one sender inside 120 seconds. That is more than
  // `TelegramAlbumGeometry.maxRunLength`, so the cluster draws a 10-tile mosaic
  // with an overflow marker and a second, smaller album for the overflow.
  final albumNames = <String>[
    'photo/photo_01_cat.jpg',
    'photo/photo_02_dumplings.jpg',
    'photo/photo_03_frog.jpg',
    'photo/photo_04_neonstreet.jpg',
    'photo/photo_05_workshop.jpg',
    'photo/photo_06_lighthouse.jpg',
    'photo/photo_07_tomatoes.jpg',
    'photo/photo_08_bike.jpg',
    'photo/photo_09_hike.jpg',
    'photo/photo_10_coffee.jpg',
    'photo/photo_09_hike.jpg',
    'photo/photo_10_coffee.jpg',
  ];

  final album = <MatrixEvent>[
    for (var i = 0; i < albumNames.length; i++)
      _event(
        id: 'album_${i + 1}',
        sender: bob,
        ts: _at(9, 20, i * 10),
        content: _imageContent(albumNames[i]),
      ),
  ];

  // The 4-photo burst: four photos from one sender, 60 seconds apart - exactly
  // `TelegramAlbumGeometry.maxGapSeconds` - so the run stays together AND
  // crosses local midnight inside itself: two members are still on 23 October
  // and two are on 24 October. That is the T7.6 render case, because the hidden
  // member that starts 24 October draws the day pill at this album's lower
  // edge. Host-local `DateTime`s are deliberate: the SDK returns
  // `originServerTs` as host-local time and `sameDay` reads wall-clock days.
  // Its neighbours are other senders, which breaks the cluster on both sides, so
  // the run is exactly 4 - the case Telegram draws as a 2x2 mosaic
  // (`mosaicColumns(4) == 2`).
  final burst4Names = <String>[
    'photo/photo_01_cat.jpg',
    'photo/photo_02_dumplings.jpg',
    'photo/photo_05_workshop.jpg',
    'photo/photo_07_tomatoes.jpg',
  ];

  final burst4 = <MatrixEvent>[
    for (var i = 0; i < burst4Names.length; i++)
      _event(
        id: 'burst4_${i + 1}',
        sender: sue,
        ts: DateTime(2026, 10, 23, 23, 58).add(Duration(seconds: i * 60)),
        content: _imageContent(burst4Names[i]),
      ),
  ];

  // A captioned 3-photo burst - the T7 caption item. Three photos from one
  // sender 15 seconds apart, each carrying the same send text, which is how a
  // Matrix burst carries Telegram's one album caption. The neighbours break the
  // cluster on both sides: alice's sticker (a sticker never joins a run) before
  // it, the voice rows after it.
  const burstCaption = 'Sunset at the harbour. Which one goes on the poster?';
  final burstCaptionedNames = <String>[
    'photo/photo_06_lighthouse.jpg',
    'photo/photo_04_neonstreet.jpg',
    'photo/photo_10_coffee.jpg',
  ];

  final burstCaptioned = <MatrixEvent>[
    for (var i = 0; i < burstCaptionedNames.length; i++)
      _event(
        id: 'capburst_${i + 1}',
        sender: alice,
        ts: DateTime(2026, 10, 24, 0, 30).add(Duration(seconds: i * 15)),
        content: _imageContent(burstCaptionedNames[i], caption: burstCaption),
      ),
  ];

  return <MatrixEvent>[
    // 1. Plain text - the pinned message and the reply target.
    _text('welcome', sue, _at(8, 58), 'Morning! Are we still on for Saturday?'),
    // 2. Plain text, long and multi-line: the wrap test.
    _text(
      'cabin',
      bob,
      _at(9, 2),
      'Yes. I booked the cabin for Saturday and Sunday.\n'
          'Two nights, four beds, kitchen with a gas stove.\n'
          'It is 40 minutes past the second tunnel, then the dirt road.\n'
          'Check-in is from 15:00 and the key sits in box 4.\n'
          'Bring firewood money: 30 euro for the bundle stack.',
    ),
    // 3. Plain text.
    _text(
      'stove',
      mallory,
      _at(9, 5),
      'I can bring the stove and the coffee pot.',
    ),
    // 4. Reply to the first message.
    _text(
      'drive',
      alice,
      _at(9, 7),
      'Yes - and I can drive. Leave at 8?',
      relatesTo: <String, Object?>{
        'm.in_reply_to': <String, Object?>{'event_id': _eventId('welcome')},
      },
    ),
    // 5. Text, then its edit - the `(edited)` mark.
    _text(
      'shopping',
      sue,
      _at(9, 10),
      'I bring bread and jam, plus the coffee.',
    ),
    _editedText(
      'shopping_edit',
      'shopping',
      sue,
      _at(9, 12),
      'I bring bread, jam and the good coffee. Two bags in total.',
    ),
    // 6. One reaction, from two senders, on the reply.
    _reaction('react_sue', 'drive', sue, _at(9, 15), '👍'),
    _reaction('react_bob', 'drive', bob, _at(9, 16), '👍'),
    // 7. The album.
    ...album,
    // 7b. The 4-photo burst - the 2x2 mosaic test.
    ...burst4,
    // 8. One single image - the image viewer test.
    _event(
      id: 'single_image',
      sender: mallory,
      ts: DateTime(2026, 10, 24, 0, 20),
      content: _imageContent('photo/photo_04_neonstreet.jpg'),
    ),
    // 9. One sticker: no bubble, transparency, 256x256.
    _event(
      id: 'sticker',
      sender: alice,
      ts: DateTime(2026, 10, 24, 0, 25),
      type: EventTypes.Sticker,
      content: <String, Object?>{
        'msgtype': MessageTypes.Sticker,
        'body': '🎉',
        'url': _mxc('sticker/sticker_1f389.png'),
        'info': <String, Object?>{
          'w': 256,
          'h': 256,
          'mimetype': 'image/png',
          'size': 20147,
        },
      },
    ),
    // 9b. The captioned 3-photo burst - ONE caption line for the whole run.
    ...burstCaptioned,
    // 10. Three voice messages: 7600 / 7400 / 6000 ms.
    _event(
      id: 'voice_1',
      sender: sue,
      ts: DateTime(2026, 10, 24, 0, 40),
      content: _voiceContent(
        'voice_01',
        durationMs: 7600,
        size: 364844,
        waveform: _waveform(1),
      ),
    ),
    _event(
      id: 'voice_2',
      sender: bob,
      ts: DateTime(2026, 10, 24, 0, 42),
      content: _voiceContent(
        'voice_02',
        durationMs: 7400,
        size: 357164,
        waveform: _waveform(2),
      ),
    ),
    _event(
      id: 'voice_3',
      sender: mallory,
      ts: DateTime(2026, 10, 24, 0, 44),
      content: _voiceContent(
        'voice_03',
        durationMs: 6000,
        size: 288044,
        waveform: _waveform(3),
      ),
    ),
    // 11. One video: play badge and duration pill.
    _event(
      id: 'video',
      sender: alice,
      ts: DateTime(2026, 10, 24, 0, 50),
      content: <String, Object?>{
        'msgtype': MessageTypes.Video,
        'body': 'clip_01.mp4',
        'url': _mxc('video/clip_01.mp4'),
        'info': <String, Object?>{
          'duration': 3000,
          'w': 480,
          'h': 854,
          'mimetype': 'video/mp4',
          'size': 204014,
          'thumbnail_url': _mxc('thumb/clip_01.jpg'),
          'thumbnail_info': <String, Object?>{
            'w': 480,
            'h': 854,
            'mimetype': 'image/jpeg',
            'size': 20310,
          },
        },
      },
    ),
    // 12. Newest event, so the room preview in the chat list is a text line.
    _text(
      'goodnight',
      alice,
      DateTime(2026, 10, 24, 0, 55),
      'See you Saturday at my place, then.',
    ),
  ];
}

/// The `Weekend Trip` room: two members, one message, unread count 3.
List<MatrixEvent> _tripTimeline() => <MatrixEvent>[
  _text(
    'trail',
    '@bob:fluffygram.local',
    _at(11, 30),
    'The ridge trail is closed on Monday. Sunday works.',
  ),
];

/// Build the demo client: account record, seed, `init()`, sync loop off.
/// [database] lets a test pass an in-memory store; the app takes its own
/// `flutterMatrixSdkDatabaseBuilder` (SQLCipher + secure storage), which needs
/// platform channels a `flutter test` isolate does not have.
Future<Client> buildDemoClient({DatabaseApi? database}) async {
  final client = Client(
    demoClientId,
    httpClient: DemoHttpClient(),
    database: database ?? await flutterMatrixSdkDatabaseBuilder(demoClientId),
    // A COPY, not the const set: the matrix SDK's `Client` constructor adds its
    // own defaults to the set it is handed, so passing `demoImportantStateEvents`
    // directly threw `Unsupported operation: Cannot modify constant Set` at
    // startup and the web build died before it created a canvas.
    importantStateEvents: <String>{...demoImportantStateEvents},
    logLevel: Level.info,
    supportedLoginTypes: <String>{AuthenticationTypes.password},
    defaultNetworkRequestTimeout: const Duration(seconds: 5),
    sendTimelineEventTimeout: const Duration(seconds: 5),
  );

  // The account record `init()` reads back. `https://fluffygram.local` is a
  // name that does not exist, and `DemoHttpClient` never opens a socket.
  await client.database.storeClient(
    homeserverUrl: kFluffyGramDemoHomeserverUrl,
    token: 'fluffygram-demo-token',
    userId: demoUserId,
    deviceId: demoDeviceId,
    deviceName: 'FluffyGram demo',
  );

  final groupState = _stateEvents(
    creator: demoUserId,
    members: demoGroupMembers,
    roomName: 'Weekend Crew',
    ts: _at(8, 50),
    avatarMxc: _mxc('sticker/sticker_1f431.png'),
    pinned: <String>[_eventId('welcome')],
  );
  final groupTimeline = _groupTimeline();

  final tripMembers = <String>[
    '@bob:fluffygram.local',
    '@alice:fluffygram.local',
  ];
  final tripState = _stateEvents(
    creator: '@bob:fluffygram.local',
    members: tripMembers,
    roomName: 'Weekend Trip',
    ts: _at(11, 20),
  );
  final tripTimeline = _tripTimeline();

  await _seedRoom(
    client,
    roomId: demoGroupId,
    state: groupState,
    timeline: groupTimeline,
    heroes: demoGroupMembers,
    // `m.favourite`, so the pinned chip renders in the chat list.
    roomTag: <String, Object?>{
      'tags': <String, Object?>{TagType.favourite: <String, Object?>{}},
    },
  );
  await _seedRoom(
    client,
    roomId: demoTripId,
    state: tripState,
    timeline: tripTimeline,
    heroes: tripMembers,
    // The chat list's second row, with an unread badge.
    notificationCount: 3,
  );

  // Sync is off before `init()`: init starts one `/sync` round (answered
  // locally, with an empty update) and the loop stops because
  // `_backgroundSync` is false. No `/sync` runs on a timer.
  client.backgroundSync = false;
  await client.init(
    waitForFirstSync: false,
    waitUntilLoadCompletedLoaded: false,
  );
  client.backgroundSync = false;
  client.syncPresence = PresenceType.offline;
  await client.roomsLoading;
  await client.accountDataLoading;
  return client;
}

/// Seed the two local stores that are not Matrix state: the chat list's draft
/// row and the sticker tray's recent row.
///
/// They live in two different places, and both have to be hit for the two rows
/// to render:
///
///  * the draft is a plain key of the *client* store, key `draft_<roomId>` -
///    `chat_list_draft.dart:37` reads it through `Matrix.of(context).store`,
///    and `chat.dart:326` writes it there, so the seed writes it with
///    `store.setString()`; `Matrix.of(context).store` is the same
///    `SharedPreferences` object the app seeds at startup
///  * the recent sticker row is an app setting, so it lives in the
///    `SharedPreferences`-backed `AppSettings` store.
Future<void> seedDemoLocalState(SharedPreferences store) async {
  await store.setString('draft_$demoGroupId', demoGroupDraft);
  await AppSettings.recentStickers.setItem(jsonEncode(demoRecentStickerUris));
}
