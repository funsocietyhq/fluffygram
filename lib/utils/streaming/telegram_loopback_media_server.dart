// SPDX-FileCopyrightText: 2026-Present Contributors to FluffyGram
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'telegram_loopback_media_server_stub.dart'
    if (dart.library.io) 'telegram_loopback_media_server_io.dart'
    as impl;

/// Serves decrypted attachment bytes to the platform video player over
/// loopback HTTP, so the player can pull a file while it is still downloading
/// and decrypting (ROADMAP T55).
///
/// A video player only streams a file it can seek in, which means it must be
/// able to ask for a byte range. The Matrix attachment endpoint gives one
/// encrypted blob and no plaintext seekable view, so this is the seekable view:
/// a server bound to 127.0.0.1 that answers `Range` requests out of
/// `TelegramAttachmentStream.slice`.
///
/// The web build has no loopback socket: there [startTelegramLoopbackMediaServer]
/// returns null and callers keep the whole-file path.
abstract class TelegramLoopbackMediaServer {
  /// The URL to hand the player. Loopback, one path token, no credentials in
  /// it - the server answers that one path and nothing else.
  Uri get url;

  /// Plaintext bytes handed out so far, for a progress readout.
  int get servedBytes;

  /// Stops the socket. The player must be disposed first.
  Future<void> close();
}

/// Starts a server for one attachment. The caller owns [close]. Null when this
/// platform cannot run one.
Future<TelegramLoopbackMediaServer?> startTelegramLoopbackMediaServer({
  required int contentLength,
  required String contentType,
  required Future<Uint8List> Function(int start, int end) slice,
  required String fileName,
  String pathToken = 'media',
}) => impl.start(
  contentLength: contentLength,
  contentType: contentType,
  slice: slice,
  fileName: fileName,
  pathToken: pathToken,
);
