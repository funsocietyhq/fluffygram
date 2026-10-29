// SPDX-FileCopyrightText: 2026-Present Contributors to FluffyGram
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'telegram_loopback_media_server.dart';

/// The web build has no loopback socket, so a web client keeps the whole-file
/// attachment path. See `telegram_loopback_media_server_io.dart` for Android,
/// Linux, macOS and Windows.
Future<TelegramLoopbackMediaServer?> start({
  required int contentLength,
  required String contentType,
  required Future<Uint8List> Function(int start, int end) slice,
  required String fileName,
  String pathToken = 'media',
}) async => null;
