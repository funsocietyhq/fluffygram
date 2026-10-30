// SPDX-FileCopyrightText: 2026-Present FluffyGram fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:matrix/matrix.dart';

/// True when this event carries a GIF, in either of the two shapes a Matrix
/// client sends one in: our own upload path puts it in `m.image` with
/// `info['mimetype'] == 'image/gif'`, and Element and the Telegram bridges send
/// the same picture as `m.video` with a top-level `mimetype` of
/// `'image/gif'`.
///
/// Both mean "draw this moving". Telegram loops a GIF in the timeline cell -
/// the loop switch on its side is `VideoPlayer.setLooping(boolean)` at
/// `ui/Components/VideoPlayer.java:1636`, and a GIF there is an animated video
/// file, not a still. The fork's half is the fetch: `MxcImage.animated` asks
/// the homeserver for the animated original, and `Image.memory` plays a
/// multi-frame image on its own once those bytes are in hand.
///
/// T123  adds a third shape: a GIF the Compress toggle
/// turned into an **animated WebP** on the way out (`lib/utils/
/// telegram_gif_webp.dart`). It is `m.image` with a mimetype of
/// `'image/webp'`, and it is still a GIF to the reader - it loops in the
/// timeline row (`lib/pages/chat/events/message_content.dart:129`), it enters
/// the GIF tray (`:137`, `RecentGifs.recordFromEvent`), and T121's badge reads
/// this same predicate. The webp half is gated on `event.messageType ==
/// MessageTypes.Image`: a sticker is `m.sticker` plus `image/webp` and must
/// stay out of the GIF tray. The `image/gif` half is byte-for-byte unchanged.
///
/// Why the converted file is still worth calling a GIF: measured
/// (`the measurement log`, "Animated WebP instead of GIF: measured, and it
/// goes both ways") a photo-like clip went 144,106 B -> 30,832 B, **4.7x
/// smaller**. The `image` package's WebP encoder writes the animated container
/// (`ANIM` at `webp_encoder.dart:141`, one `ANMF` per frame at `:150`) and
/// `decodeWebP` reads it back at `webp_decoder.dart:330` with every frame kept.
/// The resize keeps frames too: `copyResize` resizes every frame instead of
/// flattening the animation (`image-4.12.0/lib/src/transform/
/// copy_resize.dart:19,41,111`). The other direction is why the send path only
/// converts when WebP genuinely won: a flat 249 x 46 clip of 149 text frames
/// went 65,324 B -> 224,528 B, **3.4x bigger**.
/// The content key a **Convert to gif** send of ours carries on its `m.video`
/// event (T131, user 2026-10-30: "I just want to maintain quality with the
/// original mp4"). Telegram's own GIF is a video file: `isNewGifDocument()`
/// (`messenger/MessageObject.java:6984-7003`) calls a `video/mp4` document a
/// GIF when both sides are `<= 1280` px, and plays those bytes inline, muted,
/// looping. Telegram knows the sender's intent from a
/// `TL_documentAttributeAnimated` on the document; Matrix has no such attribute
/// on a video, so the sender writes this key instead.
///
/// Only this fork's own sends carry it, which is deliberate. Telegram's size
/// rule alone would turn every short clip the group sends - a ten second
/// handheld video with sound - into a silent loop here.
const String telegramMp4GifContentKey = 'org.fluffygram.gif';

/// True for an `m.video` this fork sent as a GIF: same mp4 bytes, drawn and
/// played like a GIF - inline autostart, muted, looping (T131).
bool telegramEventIsMp4Gif(Event event) =>
    event.messageType == MessageTypes.Video &&
    event.content[telegramMp4GifContentKey] == true;

bool telegramEventIsGif(Event event) {
  const gif = 'image/gif';
  const webp = 'image/webp';
  final info = event.content['info'];
  final infoMimetype = info is Map ? info['mimetype'] : null;
  if (infoMimetype == gif || event.content['mimetype'] == gif) return true;
  // An animated WebP upload is a GIF. A sticker is not: it is `m.sticker` plus
  // `image/webp`, and it must never enter the GIF tray.
  if (event.messageType != MessageTypes.Image) return false;
  return infoMimetype == webp || event.content['mimetype'] == webp;
}
