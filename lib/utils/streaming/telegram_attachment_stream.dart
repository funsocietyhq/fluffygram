// SPDX-FileCopyrightText: 2026-Present Contributors to FluffyGram
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:vodozemac/vodozemac.dart';

/// Playing an encrypted video before its last byte has landed (ROADMAP T55).
///
/// A Matrix encrypted attachment is AES-256-CTR. The counter block is a random
/// 64-bit IV prefix followed by a 64-bit big-endian counter that starts at 0 -
/// the Matrix Client-Server API says it in the words copied into the doc
/// comment of [CryptoUtils.aesCtr] (vodozemac-0.8.0/lib/src/api.dart:639-652):
/// "a single-use 256-bit AES key, and encrypt the file using AES-CTR. The
/// counter should be 64-bit long, starting at 0 and prefixed by a random 64-bit
/// Initialization Vector (IV), which together form a 128-bit unique counter
/// block." That layout is what makes a slice of the ciphertext decryptable on
/// its own: a chunk that begins on a 16-byte boundary needs only the counter
/// block of its first block index.
///
/// The AES is never reimplemented here. [CryptoUtils.aesCtr] is the same call
/// the SDK makes for a whole file
/// (matrix-14.1.0/lib/src/utils/crypto/encrypted_file.dart:49, reached through
/// `NativeImplementations.decryptFile`); this file only works out which
/// counter block each chunk starts on, and calls it per chunk.
///
/// The SHA-256 of `file.hashes` covers the **ciphertext**, not the plaintext
/// (matrix-14.1.0/lib/src/utils/crypto/encrypted_file.dart:40-43 hashes
/// `input.data`, which is the encrypted bytes, before decrypting). So the
/// integrity check runs on the bytes as they arrive, ahead of the decrypt.
/// This class feeds it in file order on one sequential pass, and reports the
/// result in [integrityOk]; a failed check stops the byte service.

/// The AES key, the IV and the ciphertext hash of one encrypted attachment.
class TelegramEncryptedFileKey {
  const TelegramEncryptedFileKey({
    required this.key,
    required this.iv,
    required this.sha256,
    required this.encryptedSize,
  });

  /// The 32-byte AES-256 key (`file.key.k`).
  final Uint8List key;

  /// The 16-byte initial counter block (`file.iv`): 8 random bytes, then the
  /// 8-byte counter field.
  final Uint8List iv;

  /// The expected SHA-256 of the whole ciphertext (`file.hashes.sha256`).
  final Uint8List sha256;

  /// The plaintext length (`content.info.size`). AES-CTR does not pad, so the
  /// ciphertext of a matrix-dart file is exactly this long. An Element file
  /// carries more bytes on the wire: a base64 header plus a 16-byte HMAC per
  /// 1 MiB chunk (a user's a build video: 10,000,211 = 51 + 10,000,000 +
  /// 16 x 10 for an `info.size` of 10,000,000).
  final int encryptedSize;

  /// Reads the `file` object of an encrypted attachment, the same fields
  /// `Event.downloadAndDecryptAttachment` reads
  /// (matrix-14.1.0/lib/src/event.dart:897-916). Returns null when any of them
  /// is missing or the key is not a 32-byte AES-256 key with a 16-byte IV, so
  /// a caller can fall back to the whole-file path.
  ///
  /// The Matrix `EncryptedFile` object has **no `size` field** - the spec puts
  /// the byte count in `content['info']['size']`. Owners' events confirm it
  /// (raw source 2026-10-28: `file` = url/v2/key/iv/hashes, `info.size` =
  /// 22548864). Some senders do add `file.size`, so both are read, and the
  /// caller passes the `info` value. Requiring `file.size` made every standard
  /// encrypted video fall back to the whole-file download.
  static TelegramEncryptedFileKey? fromFileMap(
    Map<Object?, Object?>? fileMap, {
    int? plaintextSize,
  }) {
    if (fileMap == null) return null;
    final keyMap = fileMap['key'];
    final k = keyMap is Map ? keyMap['k'] : null;
    final hashes = fileMap['hashes'];
    final ivString = fileMap['iv'];
    final shaString = hashes is Map ? hashes['sha256'] : null;
    final size = fileMap['size'] ?? plaintextSize;
    if (k is! String ||
        ivString is! String ||
        shaString is! String ||
        size is! int) {
      return null;
    }
    final key = _fromUnpaddedBase64(k);
    final iv = _fromUnpaddedBase64(ivString);
    final sha256 = _fromUnpaddedBase64(shaString);
    if (key == null || iv == null || sha256 == null) return null;
    if (key.length != 32 || iv.length != 16 || sha256.length != 32) {
      return null;
    }
    if (size <= 0) return null;
    return TelegramEncryptedFileKey(
      key: key,
      iv: iv,
      sha256: sha256,
      encryptedSize: size,
    );
  }
}

/// Decodes the unpadded base64 the Matrix attachment fields use, accepting both
/// the standard and the URL-safe alphabet - what `base64.normalize` plus
/// `base64decodeUnpadded` do inside the SDK
/// (matrix-14.1.0/lib/encryption/utils/base64_unpadded.dart:14).
Uint8List? _fromUnpaddedBase64(String value) {
  var s = value.replaceAll('-', '+').replaceAll('_', '/').replaceAll('=', '');
  // A base64 length of 4k+1 characters cannot decode to anything; 4k+3 gives
  // two bytes, which is what an unpadded 32-byte key (43 chars) and a 16-byte
  // IV (22 chars) look like.
  if (s.length % 4 == 1) return null;
  s = s.padRight(s.length + ((4 - s.length % 4) % 4), '=');
  try {
    return base64.decode(s);
  } on FormatException {
    return null;
  }
}

/// The 128-bit counter block the AES-CTR stream is at block [blockIndex].
///
/// matrix-dart's `encryptFile` (matrix-14.1.0
/// `lib/src/utils/crypto/encrypted_file.dart:25-31`) makes one
/// `CryptoUtils.aesCtr` pass with a **fully random 16-byte IV**, and the Rust
/// binding runs `Aes256Ctr64BE::new(key, iv)` (famedly/dart-vodozemac
/// `rust/src/bindings.rs:943-949`): the whole IV is the initial counter block,
/// its low 64 bits are the big-endian counter, and the stream **starts at that
/// stored value**, not at zero. Seeding the counter with zeros - reading only
/// `iv[0..8]` - shifts the keystream by the sender's counter base and garbles
/// every byte of a fully-random-IV file while the SHA-256 of the wire stays
/// clean. That is build 52's measurement: `hash=ok` on the full 4707393-byte
/// wire, `head plain: ee926169... ftyp=no`, and the IV `4b2c967d77f9ab60` +
/// `eef5d71c05501b3c` has a nonzero low half. An 8-byte IV (the spec's shape,
/// and what a Rust sender writes) keeps its counter base at zero, so that
/// branch is the old one.
Uint8List telegramCounterBlock(Uint8List iv, int blockIndex) {
  final block = Uint8List(16);
  if (iv.length >= 16) {
    block.setRange(0, 16, iv);
    final view = ByteData.sublistView(block);
    final base = view.getUint64(8, Endian.big);
    final sum = base + blockIndex;
    // Ctr64BE carries a 64-bit counter overflow into the nonce bytes
    // (ctr-rs Ctr64BE); the sign-bit carry formula on Dart's wrapping 64-bit
    // ints reproduces it.
    final carry = (((base & blockIndex) | ((base | blockIndex) & ~sum)) < 0)
        ? 1
        : 0;
    view.setUint64(8, sum, Endian.big);
    view.setUint64(0, view.getUint64(0, Endian.big) + carry, Endian.big);
    return block;
  }
  block.setRange(0, 8, iv);
  ByteData.sublistView(block).setUint64(8, blockIndex, Endian.big);
  return block;
}

/// Decrypts one chunk of a Matrix encrypted attachment. [byteOffset] is the
/// chunk's offset in the file and must be a multiple of 16; [cipherBytes] must
/// be a multiple of 16 as well, except for the final chunk of the file, where
/// the AES-CTR stream simply stops.
/// The shape of [decryptTelegramAttachmentChunk], so a test can run the fetch,
/// hash and slice bookkeeping of [TelegramAttachmentStream] without the Rust
/// bridge loaded.
typedef TelegramChunkDecrypter =
    Uint8List Function({
      required TelegramEncryptedFileKey file,
      required int byteOffset,
      required Uint8List cipherBytes,
    });

Uint8List decryptTelegramAttachmentChunk({
  required TelegramEncryptedFileKey file,
  required int byteOffset,
  required Uint8List cipherBytes,
}) {
  assert(byteOffset % 16 == 0);
  return CryptoUtils.aesCtr(
    input: cipherBytes,
    key: file.key,
    iv: telegramCounterBlock(file.iv, byteOffset ~/ 16),
  );
}

/// matrix-js-sdk (Element Web and Desktop) encrypts an attachment in uniform
/// **1 MiB** chunks and appends a **16-byte HMAC** to each chunk's ciphertext
/// (`encryptFile` / `_encryptWithCTR`: `CHUNK_SIZE = 1024 * 1024`,
/// `calcPbkdf2Hmac(macKey, intToString(chunkIndex), 16)`). matrix-dart, the
/// sender FluffyGram itself uses, writes **no chunks and no MACs** - one
/// `CryptoUtils.aesCtr` pass over the whole file
/// (matrix-14.1.0/lib/src/utils/crypto/encrypted_file.dart:27-38). So one room
/// delivers two ciphertext formats, and the byte counts separate them.
const int kTelegramElementChunkBytes = 1 << 20;

/// The HMAC matrix-js-sdk appends to each chunk's ciphertext. These bytes are
/// inside `file.hashes.sha256` - the stream hashes the whole body - so the
/// file-level SHA-256 gates integrity and the per-chunk MACs need no second
/// check here: the walk skips them.
const int kTelegramElementMacBytes = 16;

/// The AES key and IV for chunk [chunkIndex] of an Element-format attachment:
/// key = the whole 32-byte digest of
/// `SHA-256(key[0..32] ++ iv[8..16] ++ int32be(chunkIndex))`, IV = the file's
/// own IV, the derivation matrix-js-sdk's `_getCtrAlgorithmParams` runs per
/// chunk (its AES-CTR params are `{counter: iv, length: 64}` with that digest as
/// the key material). The chunk index goes into the **key** and every chunk
/// restarts the counter on the file IV: a per-chunk key is what keeps ten chunks
/// off the same keystream, and SHA-256 gives 32 bytes - all of it key, with no
/// room for a separate IV.
///
/// So each chunk decrypts from its own block 0 with the file's counter base, and
/// [decryptTelegramAttachmentChunk] answers for it unchanged.
TelegramEncryptedFileKey telegramElementChunkKey(
  TelegramEncryptedFileKey file,
  int chunkIndex,
) {
  final seed = Uint8List(44)
    ..setRange(0, 32, file.key)
    ..setRange(32, 40, file.iv, 8);
  ByteData.sublistView(seed).setUint32(40, chunkIndex, Endian.big);
  return TelegramEncryptedFileKey(
    key: Uint8List.fromList(sha256.convert(seed).bytes),
    iv: file.iv,
    sha256: file.sha256,
    encryptedSize: min(
      kTelegramElementChunkBytes,
      file.encryptedSize - chunkIndex * kTelegramElementChunkBytes,
    ),
  );
}

/// The header length of an Element-format body, or null when [head] carries no
/// header signature. Element prepends the unpadded base64 of
/// `{"v":"v2","key":{...}}` to the ciphertext (51 bytes for the JWK shape the
/// a user's file carries); matrix-dart prepends nothing, so a body with no such
/// prefix is its single-pass format. Probed at every length up to
/// [_maxHeaderProbeBytes], once per file: a random ciphertext prefix cannot
/// decode as base64 **and** as a JSON object with `v` and `key`.
int? _telegramHeaderBytes(Uint8List head) {
  for (var len = 8; len <= head.length; len++) {
    if (len % 4 == 1) continue; // no base64 length reads as 4k+1
    final decoded = _fromUnpaddedBase64(
      String.fromCharCodes(head.sublist(0, len)),
    );
    if (decoded == null) continue;
    Object? json;
    try {
      json = jsonDecode(utf8.decode(decoded));
    } catch (_) {
      continue;
    }
    if (json is Map && json.containsKey('v') && json.containsKey('key')) {
      return len;
    }
  }
  return null;
}

/// The widest header [_telegramHeaderBytes] reads. The Element header is the
/// base64 of a fixed-shape JWK object: 51 bytes for the compact form, and under
/// this cap for every layout seen.
const int _maxHeaderProbeBytes = 256;

/// One region of the downloaded body: [cipherBytes] bytes arriving at the
/// fetch cursor, decrypting to plaintext offset [plainStart], or feeding the
/// hash alone when [plainStart] is negative (the header, a chunk HMAC).
class _TelegramCipherUnit {
  const _TelegramCipherUnit(this.cipherBytes, this.plainStart);

  final int cipherBytes;
  final int plainStart;
}

/// Where an MP4 keeps its index, read off the first bytes of the file.
enum TelegramMp4Layout {
  /// `moov` sits before `mdat`: a player can start at byte 0.
  frontLoaded,

  /// `mdat` came first, so the index is at the end of the file: a player can
  /// only start if it can jump to the tail, which needs byte-range support.
  moovAfterMdat,

  /// Not an MP4, or the head read is too short to walk the boxes.
  unknown,
}

/// Walks the top-level MP4 boxes of [head] - the decrypted first bytes of a
/// video - and says where the `moov` box sits relative to `mdat`. A box is a
/// 4-byte big-endian size then a 4-byte type; size 1 means the real 64-bit
/// size follows, size 0 means the box runs to the end of the file.
TelegramMp4Layout probeTelegramMp4Layout(Uint8List head) {
  final data = ByteData.sublistView(head);
  var offset = 0;
  var sawFtyp = false;
  var sawMdat = false;
  while (offset + 8 <= head.length) {
    var size = data.getUint32(offset);
    var headerSize = 8;
    if (size == 1) {
      if (offset + 16 > head.length) return TelegramMp4Layout.unknown;
      final wide = data.getUint64(offset + 8);
      if (wide > int.parse('1099511627775')) return TelegramMp4Layout.unknown;
      size = wide;
      headerSize = 16;
    }
    if (size == 0) {
      // Runs to the end of the file; from the head alone we cannot tell what
      // follows, so treat the walk as finished here.
      size = head.length - offset;
    }
    if (size < headerSize) return TelegramMp4Layout.unknown;
    final type = String.fromCharCodes(head.sublist(offset + 4, offset + 8));
    switch (type) {
      case 'moov':
        // The index position is only good news when nothing data-carrying came
        // in front of it.
        return sawMdat
            ? TelegramMp4Layout.moovAfterMdat
            : TelegramMp4Layout.frontLoaded;
      case 'mdat':
        sawMdat = true;
      case 'ftyp':
        sawFtyp = true;
    }
    offset += size;
  }
  if (!sawFtyp) return TelegramMp4Layout.unknown;
  return sawMdat ? TelegramMp4Layout.moovAfterMdat : TelegramMp4Layout.unknown;
}

/// Fetches `[start, end)` bytes of the ciphertext. The implementation is a
/// `Range` GET on the authenticated media download URI; the tests hand in a
/// byte buffer.
typedef TelegramRangeFetcher = Future<Uint8List> Function(int start, int end);

/// A decrypted-while-it-downloads attachment.
///
/// One sequential pass (started by [start]) walks the file in [chunkBytes]
/// chunks: fetch a range, feed its ciphertext to the SHA-256, decrypt it into
/// the plaintext buffer. [slice] hands out plaintext for any byte range,
/// fetching out-of-order ranges on demand for a player that seeks. The
/// plaintext lives in memory for the life of the object.
class TelegramAttachmentStream {
  TelegramAttachmentStream({
    required this.file,
    required this.fetchRange,
    this.chunkBytes = 1 << 19, // 512 KiB, a multiple of the 16-byte AES block
    TelegramChunkDecrypter decryptChunk = decryptTelegramAttachmentChunk,
  }) : assert(chunkBytes % 16 == 0),
       _decryptChunk = decryptChunk,
       rangeFallback = null,
       _cipherStream = null {
    _plain = Uint8List(file.encryptedSize);
    _chunkFilled = List<bool>.filled(_chunkCount, false);
  }

  /// The **single-request** form (ROADMAP T59b): the caller hands over the body
  /// of one `GET` of the whole file - it sent **no `Range` header** - and this
  /// consumes it as a stream.
  ///
  /// Why the mode exists, measured (the measurement log): a byte-range
  /// video is a request generator, and the media endpoint answers the 86 ranges
  /// of one 22 MB video with `429 M_LIMIT_EXCEEDED` (build 41). For media the
  /// homeserver does **not** host it refuses ranges at all - a user's
  /// a build capture reads `Range fetch answered 500` for
  /// `/_matrix/client/v1/media/download/beta.matrix.org/<id>`, which sent every
  /// remote video to the whole-file path. One request per video is the request
  /// count of a plain download.
  ///
  /// The difference for a reader: [slice] waits for [filledBytes] to reach the
  /// byte, so the front of a faststart video is readable in about a second. T77
  /// adds the one exception: with a [rangeFallback], a span the sequential pass has
  /// not reached yet is fetched out of order by one ranged GET. That is the answer
  /// to a user's a build phone, which asked `bytes=31625342-` while 4,194,304
  /// bytes were resident, waited 8.12 s for the crawl and died with
  /// `Loading finished before preparation is complete {contentIsMalformed=true}`.
  /// The group's media endpoint answers `Range:` with **206 + Content-Range** on
  /// this very media id (`the measurement log`, "The group's media API answers
  /// `Range:` with 206"), and a tail seek of 20,000 bytes end to end in 550 ms.
  TelegramAttachmentStream.singleStream({
    required this.file,
    required Stream<List<int>> cipherStream,
    this.chunkBytes = 1 << 19,
    this.rangeFallback,
    TelegramChunkDecrypter decryptChunk = decryptTelegramAttachmentChunk,
  }) : assert(chunkBytes % 16 == 0),
       _decryptChunk = decryptChunk,
       fetchRange = null,
       _cipherStream = cipherStream {
    _plain = Uint8List(file.encryptedSize);
    _chunkFilled = List<bool>.filled(_chunkCount, false);
  }

  final TelegramEncryptedFileKey file;
  final TelegramRangeFetcher? fetchRange;

  /// Single-request mode's out-of-order answer to a seek past the fill cursor
  /// (T77): a `Range` GET of `[start, end)` **cipher** bytes. Null means this
  /// stream never issues one and every slice waits for the one body, which is what
  /// the mode did from T59b to T77.
  final TelegramRangeFetcher? rangeFallback;

  /// How many out-of-order spans one [slice] may have in flight. Measured on the
  /// a user's own media id (`notes/matrix-media-range-budget.sh`, 2026-10-28): a
  /// burst of 12 back-to-back 64 KiB ranged GETs answered **206 twelve times with
  /// zero 429s**, so the request count is not what bounds this - the per-request
  /// latency is: 0.4-0.6 s each (tail seek 550 ms, head 64 KiB 644 ms, a 1 MiB
  /// middle range 1068 ms). Four spans cover a player's tail ask plus its next two
  /// reads while staying far under the burst that made build 41 read
  /// `M_LIMIT_EXCEEDED`.
  // 8 spans = the 4 MiB `fetchSpan` of TelegramLoopbackMediaServer (T64) at this
  // mode's 512 KiB crypto chunk: one player seek is answered in one call, with no
  // wait on the sequential body. Measured safe against rate limiting: 12 back-to-back
  // ranged GETs of a group media id answered 206 with no 429 (T76 probe).
  static const int maxOutOfOrderSpans = 8;

  final int chunkBytes;
  final TelegramChunkDecrypter _decryptChunk;

  /// The one response body of single-request mode; null in the chunked mode.
  final Stream<List<int>>? _cipherStream;

  late final Uint8List _plain;
  late final List<bool> _chunkFilled;
  final Map<int, Future<void>> _inFlight = {};
  int _fillCursor = 0;

  /// Chunks an out-of-order ranged GET filled (T77). Kept apart from
  /// [_chunkFilled], which the sequential pass also sets for a chunk it has only
  /// partially reached: this list says "every plaintext byte of this chunk is
  /// here", and only such a chunk may answer a slice.
  late final List<bool> _rangeFilled = List<bool>.filled(_chunkCount, false);

  /// Set once [rangeFallback] answers `TelegramRangeNotSupportedException` - the
  /// server that replies 200 to a `Range` (Synapse still does). From that point
  /// this file is served by its one body request alone, as before T77.
  bool _rangesDisabled = false;

  /// How much decrypted head the MP4 box walk reads for its verdict (T76). A
  /// faststart file answers inside its first boxes; a tail-index file answers as
  /// soon as its `mdat` header jumps past this window.
  static const int _mp4LayoutProbeBytes = 1 << 15; // 32 KiB

  /// Where the MP4 sample index sits: true when `moov` lies inside the head this
  /// class already holds, false when the box walk left the window behind an
  /// `mdat` - so the index sits at the file end and a forward-only byte service
  /// cannot answer a seek to it (user a build logcat a log id: the
  /// player asked `bytes=31625342-` of 31,645,902 while 4,194,304 bytes were
  /// here, waited 8.12 s, and died with `contentIsMalformed=true`). Null while
  /// the head has not filled the probe window, or is not a parsable container.
  bool? _containerIndexInHead;

  /// Body bytes that reached the client, header, MACs and trailing extras
  /// included. `the measurement log` "build 51's wire numbers": a silent server
  /// truncation reads as a hash failure, so the arrival count gets printed.
  int _arrivedBytes = 0;

  /// The byte length of the header in front of the ciphertext: 51 for an
  /// Element body, 0 for a matrix-dart one. -1 until the first bytes arrive,
  /// which is what picks the format - see [_elementChunks].
  int _headerBytes = -1;
  Future<void>? _formatProbe;
  bool _hashRunning = false;
  bool _hashDone = false;
  bool _integrityOk = false;
  bool _stopped = false;
  bool _sawExtraBytes = false;
  Object? _failure;

  int get _chunkCount => (file.encryptedSize + chunkBytes - 1) ~/ chunkBytes;

  /// The plaintext length (`info.size`), which is what [_plain] holds.
  int get _plainBytes => file.encryptedSize;

  /// True when the first bytes carried the Element header: the body is 1 MiB
  /// chunks with a 16-byte HMAC on each. matrix-dart writes no header, so a
  /// body without the signature is its single-pass format.
  bool get _elementChunks => _headerBytes > 0;

  /// The fetch step. It never exceeds a crypto chunk and always divides one,
  /// so a fetched span never runs across the MAC bytes between chunks.
  int get _stepBytes =>
      _elementChunks ? min(chunkBytes, kTelegramElementChunkBytes) : chunkBytes;

  /// The offset in the downloaded body of the ciphertext of plaintext byte
  /// [plain] - the header, plus one MAC per chunk already passed.
  int _cipherOffsetOf(int plain) =>
      _headerBytes +
      plain +
      (_elementChunks
          ? kTelegramElementMacBytes * (plain ~/ kTelegramElementChunkBytes)
          : 0);

  /// Plaintext bytes available so far.
  int get filledBytes => min(_fillCursor, _plainBytes);

  /// Total plaintext bytes.
  int get byteLength => file.encryptedSize;

  /// True once the whole ciphertext has been hashed and matched
  /// `file.hashes.sha256`.
  bool get integrityOk => _hashDone && _integrityOk;

  /// True when the file is fully downloaded, hashed and decrypted.
  bool get complete => _hashDone && _integrityOk && filledBytes >= byteLength;

  /// True when the bytes arrive on one response stream (T59b): [slice] then
  /// waits for the fill cursor and the class issues no range fetch at all.
  bool get singleStreamMode => _cipherStream != null;

  /// The MP4 index verdict for this file's head: see [_containerIndexInHead].
  bool? get containerIndexInHead => _containerIndexInHead;

  /// Runs the box walk over the head published so far and keeps its first
  /// verdict. Only file-order fills call it, so the window holds no holes.
  void _updateContainerLayout() {
    if (_containerIndexInHead != null) return;
    final window = min(min(_fillCursor, _plainBytes), _mp4LayoutProbeBytes);
    if (window < 16) return;
    switch (probeTelegramMp4Layout(Uint8List.sublistView(_plain, 0, window))) {
      case TelegramMp4Layout.frontLoaded:
        _containerIndexInHead = true;
      case TelegramMp4Layout.moovAfterMdat:
        _containerIndexInHead = false;
      case TelegramMp4Layout.unknown:
        break; // the next fill may say more; a non-container stays null
    }
  }

  /// Waits for [containerIndexInHead] to get its verdict and answers it. The
  /// walk needs [_mp4LayoutProbeBytes] of head, which is the first crypto chunk
  /// of any real video: the answer lands in the first milliseconds of the fetch,
  /// long before a player's measured 8.12 s patience runs out
  /// (`the measurement log`, build 53). Null when the fill cursor crossed
  /// the probe window with no verdict (not an MP4 we can walk), or when this
  /// stream stopped; [timeout] guards a body that never fills the window.
  Future<bool?> awaitContainerLayout({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (_containerIndexInHead == null) {
      if (_stopped || _hashDone || _failure != null) {
        return _containerIndexInHead;
      }
      if (_fillCursor >= _mp4LayoutProbeBytes) return null;
      if (DateTime.now().isAfter(deadline)) return null;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return _containerIndexInHead;
  }

  /// Waits until every plaintext byte has arrived and matched the attachment
  /// SHA-256, and answers whether it got there (T76: a tail-index video plays
  /// from the finished file this same download wrote).
  Future<bool> awaitComplete() async {
    while (!complete) {
      if (_stopped || _failure != null) return false;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return true;
  }

  /// The whole plaintext, and only once [complete]. The byte server already
  /// hands out views of this buffer, so the file for a tail-index video costs no
  /// second request.
  Uint8List? get plainBytesWhenComplete => complete ? _plain : null;

  /// The reason streaming gave up (a failed hash, a fetch error), null while
  /// healthy.
  Object? get failure => _failure;

  /// Starts the sequential decrypt-and-verify pass.
  void start() {
    if (_hashRunning || _stopped) return;
    _hashRunning = true;
    _runSequentialPass();
  }

  Future<void> _runSequentialPass() async {
    final digests = <Digest>[];
    final hashing = sha256.startChunkedConversion(
      ChunkedConversionSink<Digest>.withCallback(digests.addAll),
    );
    // A user's a build log died with the generic integrity exception and
    // no numbers: the format decision, the body length, the fill and the hash
    // verdict are the facts that tell a short body from a re-encoded one.
    var wireBytes = 0;
    void addCipher(List<int> cipher) {
      wireBytes += cipher.length;
      hashing.add(cipher);
    }

    try {
      if (_cipherStream != null) {
        await _pumpSingleStream(addCipher);
      } else {
        await _pumpRangeChunks(addCipher);
      }
      if (_stopped) return;
      hashing.close();
      final digest = digests.single.bytes;
      _integrityOk = _bytesEqual(digest, file.sha256) && !_sawExtraBytes;
      _hashDone = true;
      debugPrint(
        '[TelegramStream] verify header=${_headerBytes >= 0 ? _headerBytes : "?"} '
        'wire=$wireBytes arrived=$_arrivedBytes declared=${file.encryptedSize} '
        'fill=$_fillCursor extra=$_sawExtraBytes '
        'hash=${_integrityOk ? "ok" : "BAD"}',
      );
      if (!_integrityOk) {
        _failure = const TelegramAttachmentIntegrityException();
      }
    } catch (e) {
      _stopped = true;
      _failure = e;
    }
  }

  /// The chunked mode: one range fetch per [_stepBytes] block, in file order.
  /// Every fetch is a plaintext span mapped into the body, so it carries that
  /// span's ciphertext and nothing else. The Element format needs the bytes a
  /// plaintext span does not use - the header in front of byte 0, the MAC at the
  /// end of each 1 MiB chunk - so the fetches that touch them take them along
  /// and hand them to the hasher.
  Future<void> _pumpRangeChunks(
    void Function(List<int> cipher) addCipher,
  ) async {
    await _ensureFormat();
    var plain = 0;
    while (plain < _plainBytes && !_stopped) {
      final step = min(
        _stepBytes,
        min(_plainBytes - plain, _bytesToChunkEnd(plain)),
      );
      final dataStart = _cipherOffsetOf(plain);
      final withHeader = plain == 0;
      final trailingMac = _macAfter(plain, step);
      final cipher = await fetchRange!(
        withHeader ? 0 : dataStart,
        dataStart + step + trailingMac,
      );
      if (_stopped) return;
      addCipher(cipher);
      _arrivedBytes += cipher.length;
      _decryptPlainSpan(
        plain,
        withHeader
            ? Uint8List.sublistView(cipher, _headerBytes, _headerBytes + step)
            : cipher,
      );
      _markFilled(plain, plain + step);
      _fillCursor = plain + step;
      _updateContainerLayout();
      plain += step;
    }
    if (_elementChunks && !_stopped) {
      // The final chunk's HMAC sits past the last plaintext byte.
      final macStart = _cipherOffsetOf(_plainBytes);
      addCipher(
        await fetchRange!(macStart, macStart + kTelegramElementMacBytes),
      );
    }
  }

  /// The range mode must know the format before it fetches anything: the format
  /// picks the AES key of byte 0 and every fetch offset. One small range read of
  /// the body head answers it, once per file - the Element header is plain text
  /// in front of the ciphertext, matrix-dart starts with the ciphertext itself.
  /// Single-request mode needs no probe: its pump reads the head off the one
  /// body it is already receiving.
  Future<void> _ensureFormat() {
    if (_headerBytes >= 0) return Future.value();
    return _formatProbe ??= () async {
      final head = await fetchRange!(0, _maxHeaderProbeBytes);
      if (_stopped) {
        throw _failure ?? const TelegramAttachmentIntegrityException();
      }
      _headerBytes = _telegramHeaderBytes(head) ?? 0;
      _logBodyFormat(head);
    }();
  }

  /// Plaintext bytes from [plain] to the end of its crypto chunk (a whole
  /// remainder in the single-pass format, which has no chunks).
  int _bytesToChunkEnd(int plain) => _elementChunks
      ? kTelegramElementChunkBytes - (plain % kTelegramElementChunkBytes)
      : _plainBytes - plain;

  /// The MAC bytes that sit directly after the plaintext span
  /// `[plain, plain + step)`, so one fetch can carry them to the hasher.
  int _macAfter(int plain, int step) =>
      _elementChunks &&
          (plain + step) % kTelegramElementChunkBytes == 0 &&
          plain + step < _plainBytes
      ? kTelegramElementMacBytes
      : 0;

  /// The single-request mode (T59b): drain the one response body, block by
  /// block. Every block starts on a multiple of [chunkBytes], so its counter
  /// block is the file's IV plus that block index - AES-CTR from offset 0 is a
  /// single forward keystream, and a stream that only moves forward needs no
  /// other maths. The SHA-256 runs on the ciphertext as it arrives, so the
  /// integrity check costs no second pass over the bytes.
  Future<void> _pumpSingleStream(
    void Function(List<int> cipher) addCipher,
  ) async {
    final queue = <Uint8List>[];
    var buffered = 0;
    Uint8List take(int count) {
      final out = Uint8List(count);
      var taken = 0;
      while (taken < count) {
        final head = queue.first;
        final n = min(head.length, count - taken);
        out.setRange(taken, taken + n, head);
        if (n == head.length) {
          queue.removeAt(0);
        } else {
          queue[0] = Uint8List.sublistView(head, n);
        }
        taken += n;
      }
      buffered -= count;
      return out;
    }

    void decideFormat() {
      if (_headerBytes >= 0) return;
      final head = Uint8List(min(buffered, _maxHeaderProbeBytes));
      var at = 0;
      for (final part in queue) {
        final n = min(part.length, head.length - at);
        head.setRange(at, at + n, part);
        at += n;
        if (at == head.length) break;
      }
      _headerBytes = _telegramHeaderBytes(head) ?? 0;
      _logBodyFormat(head);
    }

    var plan = const <_TelegramCipherUnit>[];
    var unitIndex = 0;
    await for (final part in _cipherStream!) {
      if (_stopped) return;
      final bytes = part is Uint8List ? part : Uint8List.fromList(part);
      queue.add(bytes);
      buffered += bytes.length;
      _arrivedBytes += bytes.length;
      while (true) {
        if (_headerBytes < 0) {
          // The format is a fact about the whole body, and the AES key of byte
          // 0 follows from it, so the walk waits for the probe window.
          if (buffered < _maxHeaderProbeBytes) break;
          decideFormat();
          plan = _buildPlan();
        }
        if (unitIndex >= plan.length ||
            buffered < plan[unitIndex].cipherBytes) {
          break;
        }
        final unit = plan[unitIndex++];
        final cipher = take(unit.cipherBytes);
        addCipher(cipher);
        if (unit.plainStart >= 0) {
          _decryptPlainSpan(unit.plainStart, cipher);
          _markFilled(unit.plainStart, unit.plainStart + unit.cipherBytes);
          _fillCursor = max(_fillCursor, unit.plainStart + unit.cipherBytes);
          _updateContainerLayout();
          // The await after each unit is what lets a [slice] waiting on the
          // fill cursor see the bytes as they land.
          await Future<void>.delayed(Duration.zero);
        }
      }
      if (_sawExtraBytes || _stopped) return;
    }
    if (_headerBytes < 0) {
      // A body shorter than the probe window: decide on what arrived.
      decideFormat();
      plan = _buildPlan();
    }
    if (buffered > 0) {
      // The body is longer than the attachment declares. The SHA-256 cannot
      // match what it covers, so say so and stop taking bytes.
      _sawExtraBytes = true;
    }
  }

  /// The regions of the body, in arrival order: the Element header (hash only),
  /// each fetch span of ciphertext, and the MAC that closes each 1 MiB chunk
  /// (hash only). The single-pass format is one plain run with no header.
  List<_TelegramCipherUnit> _buildPlan() {
    final units = <_TelegramCipherUnit>[];
    if (_headerBytes > 0) {
      units.add(_TelegramCipherUnit(_headerBytes, -1));
    }
    var plain = 0;
    while (plain < _plainBytes) {
      final len = min(
        _stepBytes,
        min(_plainBytes - plain, _bytesToChunkEnd(plain)),
      );
      units.add(_TelegramCipherUnit(len, plain));
      plain += len;
      // Every chunk carries a MAC, the last one included: it closes a chunk when
      // the span lands on a chunk border, and closes the file otherwise.
      if (_elementChunks &&
          (plain % kTelegramElementChunkBytes == 0 || plain == _plainBytes)) {
        units.add(_TelegramCipherUnit(kTelegramElementMacBytes, -1));
      }
    }
    return units;
  }

  /// Decrypts the ciphertext of plaintext span `[plainStart, plainStart +
  /// cipher.length)` into [_plain]. The Element format decrypts each 1 MiB chunk
  /// with its own derived key and IV, at the chunk's own counter base; the
  /// matrix-dart format is one AES-CTR pass over the file, so its span decrypts
  /// at its own file offset - the scheme of [decryptTelegramAttachmentChunk].
  void _decryptPlainSpan(int plainStart, Uint8List cipher) {
    assert(plainStart % 16 == 0);
    if (_elementChunks) {
      final chunk = plainStart ~/ kTelegramElementChunkBytes;
      _plain.setRange(
        plainStart,
        plainStart + cipher.length,
        _decryptChunk(
          file: telegramElementChunkKey(file, chunk),
          byteOffset: plainStart - chunk * kTelegramElementChunkBytes,
          cipherBytes: cipher,
        ),
      );
      _logPlainHeadOnce(plainStart);
      return;
    }
    _plain.setRange(
      plainStart,
      plainStart + cipher.length,
      _decryptChunk(file: file, byteOffset: plainStart, cipherBytes: cipher),
    );
    _logPlainHeadOnce(plainStart);
  }

  bool _plainHeadLogged = false;

  /// The first decrypted plaintext block, printed once. A media container magic
  /// (`ftyp` at byte 4) separates "the event key does not decrypt this wire"
  /// from "the bytes are right and the loopback served them badly" - the open
  /// question of `the measurement log` "build 51's wire numbers".
  void _logPlainHeadOnce(int plainStart) {
    if (_plainHeadLogged || plainStart != 0) return;
    _plainHeadLogged = true;
    final h = Uint8List.sublistView(_plain, 0, min(16, _plain.length));
    final ftyp =
        h.length >= 8 &&
        h[4] == 0x66 &&
        h[5] == 0x74 &&
        h[6] == 0x79 &&
        h[7] == 0x70;
    debugPrint(
      '[TelegramStream] head plain: ${_hex(h)} ${ftyp ? "ftyp=YES" : "ftyp=no"}',
    );
  }

  void _markFilled(int start, int end) {
    for (var c = start ~/ chunkBytes; c < _chunkCount; c++) {
      if (c * chunkBytes >= end) break;
      _chunkFilled[c] = true;
    }
  }

  /// Waits until every chunk overlapping `[start, end)` holds plaintext,
  /// fetching out-of-order ones on demand, then returns that view.
  Future<Uint8List> slice(int start, int end) async {
    final from = max(0, start);
    final to = min(end, file.encryptedSize);
    if (to <= from) return Uint8List(0);
    if (_cipherStream != null) {
      // Single-request mode (T59b): answer from the bytes the one response has
      // published, and (T77) fetch the chunks it has not reached with a ranged GET
      // - bounded, deduped, and off the hash.
      await _answerSingleStreamSpan(from, to);
      return Uint8List.sublistView(_plain, from, to);
    }
    final first = from ~/ chunkBytes;
    final last = (to - 1) ~/ chunkBytes;
    for (var c = first; c <= last; c++) {
      await _ensureChunk(c);
    }
    return Uint8List.sublistView(_plain, from, to);
  }

  /// True when chunk [chunkIndex] holds its full plaintext: the sequential pass
  /// published past it, or an out-of-order span covered every byte of it.
  bool _chunkHasPlain(int chunkIndex) =>
      _rangeFilled[chunkIndex] ||
      min((chunkIndex + 1) * chunkBytes, _plainBytes) <= _fillCursor;

  /// Single-request mode: make every crypto chunk that overlaps `[from, to)` hold
  /// its plaintext. Chunks the one body already published need nothing. A chunk it
  /// has not reached is fetched out of order through [rangeFallback], tail first -
  /// a tail-indexed MP4 keeps its sample index in its last chunk, and that is the
  /// span a player asks for - at most [maxOutOfOrderSpans] spans per call, with the
  /// rest left to the sequential body. A server that will not give ranges turns the
  /// mode off for the rest of this file and everything then waits, as it did before
  /// T77.
  Future<void> _answerSingleStreamSpan(int from, int to) async {
    final first = from ~/ chunkBytes;
    final last = (to - 1) ~/ chunkBytes;
    if (rangeFallback == null || _rangesDisabled) {
      await _awaitChunksFilled(first, last);
      return;
    }
    // `_cipherOffsetOf` maps a plaintext span onto its cipher span only once the
    // body head has said which format this is, so a seek that lands before that
    // decision waits for it: the pump answers inside the first 256 bytes, which is
    // milliseconds. A file whose whole body is shorter than that probe window is
    // served by its body alone.
    final decided = DateTime.now().add(const Duration(milliseconds: 500));
    while (_headerBytes < 0 &&
        !_stopped &&
        _failure == null &&
        DateTime.now().isBefore(decided)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    if (_headerBytes >= 0) {
      final missing = <int>[];
      for (var c = first; c <= last; c++) {
        if (!_chunkHasPlain(c)) missing.add(c);
      }
      if (missing.isNotEmpty) {
        final spans = missing.length > maxOutOfOrderSpans
            ? missing.sublist(missing.length - maxOutOfOrderSpans)
            : missing;
        try {
          await Future.wait(spans.map(_ensureRangeChunk));
        } on TelegramRangeNotSupportedException catch (e) {
          _rangesDisabled = true;
          debugPrint(
            '[TelegramStream] ranges refused: $e - this file finishes on its '
            'one body request (T77)',
          );
        }
      }
    }
    await _awaitChunksFilled(first, last);
  }

  /// Fetches one crypto chunk out of order and decrypts it into [_plain]. Deduped
  /// in [_inFlight] exactly like [_ensureChunk], so two readers that ask for the
  /// same span fetch it once. The bytes never enter the sequential SHA-256: the one
  /// body hashes them again in file order, so an out-of-order span is hashed once
  /// (T77).
  Future<void> _ensureRangeChunk(int chunkIndex) async {
    if (_chunkHasPlain(chunkIndex)) return;
    final running = _inFlight[chunkIndex];
    if (running != null) return running;
    final start = chunkIndex * chunkBytes;
    final end = min(start + chunkBytes, _plainBytes);
    debugPrint(
      '[TelegramStream] out-of-order range chunk=$chunkIndex cipher='
      '${_cipherOffsetOf(start)}..${_cipherOffsetOf(end) - 1} '
      'fillCursor=$_fillCursor declared=${file.encryptedSize} (T77)',
    );
    final task = () async {
      await _fetchPlainSpan(start, end, fetch: rangeFallback);
    }();
    _inFlight[chunkIndex] = task;
    try {
      await task;
      _rangeFilled[chunkIndex] = true;
    } finally {
      _inFlight.remove(chunkIndex);
    }
  }

  /// Single-request mode: wait until every chunk overlapping the asked span holds
  /// its plaintext, published by the one body or filled out of order. Before T77
  /// this was the fill cursor alone - and a player that jumped to the tail of a
  /// tail-indexed video waited there for 8.12 s (build 53) and died.
  Future<void> _awaitChunksFilled(int first, int last) async {
    while (true) {
      var waiting = false;
      for (var c = first; c <= last; c++) {
        if (!_chunkHasPlain(c)) {
          waiting = true;
          break;
        }
      }
      if (!waiting) return;
      if (_stopped || _hashDone) {
        throw _failure ?? const TelegramAttachmentIntegrityException();
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> _ensureChunk(int chunkIndex) async {
    if (_stopped) {
      throw _failure ?? const TelegramAttachmentIntegrityException();
    }
    if (_chunkFilled[chunkIndex]) return;
    final running = _inFlight[chunkIndex];
    if (running != null) return running;
    final start = chunkIndex * chunkBytes;
    final end = min(start + chunkBytes, _plainBytes);
    final task = () async {
      await _fetchPlainSpan(start, end);
    }();
    _inFlight[chunkIndex] = task;
    try {
      await task;
    } finally {
      _inFlight.remove(chunkIndex);
    }
  }

  /// Fetches the ciphertext of the plaintext span `[start, end)`, decrypts it
  /// into [_plain] and marks the span filled. In the Element format the span is
  /// cut at the 1 MiB chunk borders, because the MAC bytes between the chunks
  /// belong to no plaintext; in the single-pass format it is one fetch.
  /// [fetch] overrides the fetcher: single-request mode passes its
  /// [rangeFallback] here, so the out-of-order span travels over its own `Range`
  /// GET while the whole file still arrives on one body (T77).
  Future<void> _fetchPlainSpan(
    int start,
    int end, {
    TelegramRangeFetcher? fetch,
  }) async {
    final fetcher = fetch ?? fetchRange!;
    await _ensureFormat();
    var plain = start;
    while (plain < end) {
      final step = min(min(chunkBytes, _bytesToChunkEnd(plain)), end - plain);
      final from = _cipherOffsetOf(plain);
      final cipher = await fetcher(from, from + step);
      if (_stopped) {
        throw _failure ?? const TelegramAttachmentIntegrityException();
      }
      _decryptPlainSpan(plain, cipher);
      plain += step;
    }
    _markFilled(start, end);
  }

  /// Stops the sequential pass; a player that went away should not keep the
  /// connection pulling bytes. The state line goes out first: build 51 proved a
  /// viewer close cancels the pump before the hash verdict prints, and that
  /// verdict is the open question ("build 51's wire numbers",
  /// `the measurement log`).
  Future<void> stop() async {
    debugPrint(
      '[TelegramStream] stream stop: fill=$_fillCursor arrived=$_arrivedBytes '
      'plan=${file.encryptedSize} header=$_headerBytes '
      'hash=${_hashDone ? (_integrityOk ? "ok" : "BAD") : "not-run"}',
    );
    _stopped = true;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');

  /// The wire identity: the probe's 64-byte head, a SHA-256 fingerprint of the
  /// event key (six bytes - enough to tell two files' keys apart, not enough to
  /// leak one), and the full IV, on one line.
  void _logBodyFormat(Uint8List head) {
    debugPrint(
      '[TelegramStream] body format: header=$_headerBytes '
      'declared=${file.encryptedSize} '
      'key=${_hex(sha256.convert(file.key).bytes.sublist(0, 6))} '
      'iv=${_hex(file.iv)} '
      'head=${base64Encode(head.sublist(0, min(64, head.length)))}',
    );
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The homeserver answered a `Range` request with the whole file, so it will
/// not give byte ranges and a player cannot seek in the video. Thrown by
/// `telegram_attachment_stream_client.dart`'s `_rangeResult`; single-request mode
/// catches it here and stops asking for ranges (T77).
class TelegramRangeNotSupportedException implements Exception {
  const TelegramRangeNotSupportedException();

  @override
  String toString() => 'The homeserver does not answer byte-range requests';
}

/// The ciphertext did not hash to `file.hashes.sha256`.
class TelegramAttachmentIntegrityException implements Exception {
  const TelegramAttachmentIntegrityException();

  @override
  String toString() => 'Telegram attachment SHA-256 check failed';
}
