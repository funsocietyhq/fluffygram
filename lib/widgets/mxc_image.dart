// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/attachments/telegram_media_cache.dart';
import 'package:fluffychat/utils/client_download_content_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:lottie/lottie.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class MxcImage extends StatefulWidget {
  final Uri? uri;
  final Event? event;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final bool isThumbnail;
  final bool animated;
  final Duration retryDuration;
  final Duration animationDuration;
  final Curve animationCurve;
  final ThumbnailMethod thumbnailMethod;
  final Widget Function(BuildContext context)? placeholder;
  final String? cacheKey;
  final String? cacheName;
  final Client? client;
  final BorderRadius borderRadius;

  static void clearCache(String cacheName) =>
      _MxcImageState._imageDataCaches.remove(cacheName);

  const MxcImage({
    this.uri,
    this.event,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.isThumbnail = true,
    this.animated = false,
    this.animationDuration = FluffyThemes.animationDuration,
    this.retryDuration = const Duration(seconds: 2),
    this.animationCurve = FluffyThemes.animationCurve,
    this.thumbnailMethod = ThumbnailMethod.scale,
    this.cacheKey,
    this.client,
    this.borderRadius = BorderRadius.zero,
    this.cacheName,
    super.key,
  });

  @override
  State<MxcImage> createState() => _MxcImageState();
}

class _MxcImageState extends State<MxcImage> {
  static final Map<String?, Map<String, Uint8List>> _imageDataCaches = {};
  Map<String, Uint8List> get _imageDataCache =>
      _imageDataCaches[widget.cacheName ?? ''] ??= {};

  Uint8List? _imageDataNoCache;

  Uint8List? get _imageData => widget.cacheKey == null
      ? _imageDataNoCache
      : _imageDataCache[widget.cacheKey];

  set _imageData(Uint8List? data) {
    if (data == null) return;
    final cacheKey = widget.cacheKey;
    cacheKey == null
        ? _imageDataNoCache = data
        : _imageDataCache[cacheKey] = data;
  }

  Future<void> _load() async {
    if (!mounted) return;
    final client =
        widget.client ?? widget.event?.room.client ?? Matrix.of(context).client;
    if (!client.isLogged()) return;

    final uri = widget.uri;
    final event = widget.event;

    if (uri != null && uri.scheme == 'mxc') {
      final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      final width = widget.width;
      final realWidth = width == null ? null : width * devicePixelRatio;
      final height = widget.height;
      final realHeight = height == null ? null : height * devicePixelRatio;

      final remoteData = await client.downloadMxcCached(
        uri,
        width: realWidth,
        height: realHeight,
        thumbnailMethod: widget.thumbnailMethod,
        isThumbnail: widget.isThumbnail,
        animated: widget.animated,
      );
      if (!mounted) return;
      setState(() {
        _imageData = remoteData;
      });
    }

    if (event != null) {
      final useThumbnail = widget.isThumbnail && event.hasThumbnail;
      if (!useThumbnail &&
          !{
            MessageTypes.Image,
            MessageTypes.Sticker,
          }.contains(event.messageType)) {
        Logs().e('Event of type ${event.messageType} has no thumbnail!');
      }
      // T120 .
      // A full-size row used to pay fetch + AES-CTR on **every** draw: this
      // file called `downloadAndDecryptAttachment()` alone, which reads the
      // **encrypted** bytes back out of the SDK's own store (10 MB per file,
      // 30-day prune - `flutter_matrix_dart_sdk_database/builder.dart:127-129`)
      // and re-runs the cipher, and nothing read the fork's decrypted cache.
      // A hit there is a plain file open. The thumbnail path stays as it was:
      // its bytes are not the file the cache key names.
      final started = DateTime.now();
      if (!useThumbnail) {
        final hit = await TelegramMediaCache.cached(event);
        if (hit != null) {
          // Hits print nothing: they cost a few milliseconds and the timeline
          // redraws often. Misses print one line, like the GIF tray's.
          final bytes = await hit.readAsBytes();
          if (!mounted) return;
          setState(() {
            _imageData = bytes;
          });
          return;
        }
      }
      final data = await event.downloadAndDecryptAttachment(
        getThumbnail: useThumbnail,
      );
      if (data.detectFileType is MatrixImageFile) {
        if (!useThumbnail) {
          // Decrypted **once**: hand the bytes to the cache so the next open of
          // this row is the hit above, and paint from what is already in hand.
          await TelegramMediaCache.keep(event, data.bytes);
          debugPrint(
            '[TelegramMedia] miss '
            '${DateTime.now().difference(started).inMilliseconds} ms '
            '${data.bytes.length} bytes',
          );
        }
        if (!mounted) return;
        setState(() {
          _imageData = data.bytes;
        });
        return;
      }
    }
  }

  /// The picture **decoded inside this widget's own pixel box** (T120).
  /// `Image.memory` decodes at file resolution, and an animated gif decodes
  /// frame by frame into Flutter's image cache: one 400 x 400, 50-frame gif is
  /// about 24 MB of RGBA (T117.1 measurement) against the 1000 images /
  /// 100 MB budget at `PaintingBinding.maximumSizeBytes`, so visible rows
  /// evict each other and a scroll re-decodes them. Telegram's loader sets
  /// `BitmapFactory.Options.inSampleSize` from the requested rect instead
  /// (`ImageLoader.java:1295-1321, :3972-3978`) and keeps those scaled bitmaps
  /// in an `LruCache` memcache (`:2087, :2109`). Build 77 shipped this same
  /// mechanism for GIF tray tiles - `chat_emoji_picker.dart:773-780`, T117.1.
  ImageProvider _provider(Uint8List data, BuildContext context) {
    final provider = MemoryImage(data);
    final width = widget.width;
    final height = widget.height;
    // No box declared -> no target size to decode to: unchanged behaviour.
    if (width == null && height == null) return provider;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ResizeImage(
      provider,
      width: width == null ? null : (width * dpr).round(),
      height: height == null ? null : (height * dpr).round(),
      // `fit` keeps the source aspect and never upscales; `exact` would
      // stretch a landscape gif into a square bubble box.
      policy: ResizeImagePolicy.fit,
    );
  }

  Future<void> _tryLoad() async {
    if (_imageData != null) {
      return;
    }
    try {
      await _load();
    } on IOException catch (_) {
      if (!mounted) return;
      await Future.delayed(widget.retryDuration);
      _tryLoad();
    } on MatrixException catch (e) {
      Logs().d('Unable to load image', e);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryLoad());
  }

  @override
  Widget build(BuildContext context) {
    final data = _imageData;
    final hasData = data != null && data.isNotEmpty;
    final ungzippedLottieData = data == null ? null : _ungzipLottie(data);

    Widget errorFallback(
      BuildContext context,
      Object error,
      StackTrace? stackTrace,
    ) {
      Logs().d('Unable to render mxc image', error, stackTrace);
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Icon(
            Icons.broken_image_outlined,
            size: min(widget.height ?? 64, 64),
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
    }

    final imageChild = data == null
        ? _MxcImagePlaceholder(
            width: widget.width,
            height: widget.height,
            placeholder: widget.placeholder,
          )
        : (ungzippedLottieData != null
              ? Lottie.memory(
                  ungzippedLottieData,
                  width: widget.width,
                  height: widget.height,
                  fit: widget.fit,
                  errorBuilder: errorFallback,
                )
              : Image(
                  image: _provider(data, context),
                  width: widget.width,
                  height: widget.height,
                  fit: widget.fit,
                  filterQuality: widget.isThumbnail
                      ? FilterQuality.low
                      : FilterQuality.medium,
                  errorBuilder: errorFallback,
                ));

    return AnimatedCrossFade(
      duration: FluffyThemes.animationDuration,
      firstChild: ClipRRect(
        borderRadius: widget.borderRadius,
        child: imageChild,
      ),
      secondChild: _MxcImagePlaceholder(
        width: widget.width,
        height: widget.height,
        placeholder: widget.placeholder,
      ),
      crossFadeState: hasData
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
    );
  }
}

class _MxcImagePlaceholder extends StatelessWidget {
  final double? width;
  final double? height;
  final Widget Function(BuildContext context)? placeholder;

  const _MxcImagePlaceholder({
    required this.width,
    required this.height,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return placeholder?.call(context) ??
        Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          child: const CircularProgressIndicator.adaptive(strokeWidth: 2),
        );
  }
}

Uint8List? _ungzipLottie(Uint8List data) {
  // early return if the data is not gzipped
  if (data.length < 2 || data.first != 0x1f || data[1] != 0x8b) {
    return null;
  }

  // try decoding json
  try {
    final decompressed = GZipDecoder().decodeBytes(data);
    final jsonStr = utf8.decode(decompressed);
    final json = jsonDecode(jsonStr);
    if (json is Map && json.containsKey('v')) {
      return Uint8List.fromList(utf8.encode(jsonStr));
    }
  } catch (_) {
    return null;
  }

  return null;
}
