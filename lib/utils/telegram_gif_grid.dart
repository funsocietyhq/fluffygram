// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'dart:math' as math;

/// One cell of Telegram's GIF tray grid: which gif, and its box in dp.
final class TelegramGifCell {
  final int index;
  final double w;
  final double h;
  const TelegramGifCell(this.index, this.w, this.h);
}

/// T115 .
/// A port of the layout Telegram's GIF tray draws, so the tray keeps each
/// GIF's **own aspect ratio** in rows that fill the width, instead of a fixed
/// square grid. Every value is read from the vendored reference, not from
/// pixels:
///
/// * `ui/Components/EmojiView.java:9111-9116` - `GifLayoutManager extends
///   ExtendedGridLayoutManager`, `super(context, 100, true)`: **100 spans**
///   across the grid, `lastRowFullWidth = true` (the last row is stretched
///   like any other: `prepareLayout()` runs one extra turn for it,
///   `ExtendedGridLayoutManager.java:73`).
/// * `ExtendedGridLayoutManager.java:65` - `preferredRowSize = dp(100)`, the
///   row height a gif is measured against.
/// * `:87` - `requiredSpan = min(spanCount, floor(spanCount * (aspect *
///   preferredRowSize / viewPortAvailableSize)))`.
/// * `:88` - a gif starts a new row when `spanLeft < requiredSpan`, or when it
///   needs more than 33 spans and the row has less than `requiredSpan - 15`.
/// * `:95-108` - the spans a row did not use are shared out (`spanPerItem`),
///   with the last gif of the row taking the remainder. That is what makes a
///   row end at the grid edge.
/// * `:143-157` `fixSize()` - a missing size reads as square, and an aspect
///   over 4 or under 0.2 is treated as square.
/// * `ui/Components/EmojiView.java:2050-2051` - the gutters: `outRect.top =
///   dp(2)` and `outRect.right = dp(2)`, and `GifLayoutManager` (the GIF
///   subclass, `:9156-9168`) adds the right gutter to every cell **except** the
///   last one in a row. So the box a gif draws is its span minus the gutter it
///   hands to its neighbour, and a row's boxes plus its gutters equal the grid
///   width exactly.
/// * `ui/Components/EmojiView.java:9182-9196` - the aspect comes from the
///   thumbnail's `w`/`h`, else from the document attribute's.
abstract final class TelegramGifGrid {
  /// `EmojiView.java:9116` - the grid is cut into 100 spans.
  static const int spanCount = 100;

  /// `ExtendedGridLayoutManager.java:65` - the row a gif is measured against.
  static const double rowBaseDp = 100;

  /// `EmojiView.java:2050-2051` - `dp(2)` between tiles, on both axes.
  static const double gutterDp = 2;

  /// `ExtendedGridLayoutManager.java:150` - the aspect clamp of `fixSize()`.
  static const double aspectMin = 0.2, aspectMax = 4.0;

  /// The aspect of a stored gif: 1 when its size is unknown, square when the
  /// aspect leaves `fixSize()`'s clamp.
  static double aspectOf(int w, int h) {
    if (w <= 0 || h <= 0) return 1.0;
    final aspect = w / h;
    if (aspect > aspectMax || aspect < aspectMin) return 1.0;
    return aspect;
  }

  /// The rows of a tray [width] dp wide, for gifs with these aspect ratios.
  /// A row's boxes plus its gutters sum to `width`; the cells keep their
  /// `index` into [aspects] and their order.
  static List<List<TelegramGifCell>> rows(List<double> aspects, double width) {
    if (aspects.isEmpty || width <= 0) return const [];
    final unit = width / spanCount;
    final rows = <List<TelegramGifCell>>[];
    var rowStart = 0;
    var spans = <int>[];
    var rowAspects = <double>[];
    var spanLeft = spanCount;

    void closeRow() {
      if (spans.isEmpty) return;
      final per = spanLeft ~/ spans.length;
      for (var i = 0; i < spans.length; i++) {
        // The last gif of the row takes what the even share left over.
        spans[i] += i == spans.length - 1 ? spanLeft - per * i : per;
        final gutter = i == spans.length - 1 ? 0.0 : gutterDp;
        final w = spans[i] * unit - gutter;
        rows.last.add(TelegramGifCell(rowStart + i, w, w / rowAspects[i]));
      }
      rowStart += spans.length;
      spans = <int>[];
      rowAspects = <double>[];
      spanLeft = spanCount;
      rows.add(<TelegramGifCell>[]);
    }

    rows.add(<TelegramGifCell>[]);
    for (final aspect in aspects) {
      final a = aspect <= 0 ? 1.0 : aspect;
      var required = math.min(
        spanCount,
        (spanCount * (a * rowBaseDp / width)).floor(),
      );
      if (required < 1) required = 1;
      if (spans.isNotEmpty &&
          (spanLeft < required ||
              (required > 33 && spanLeft < required - 15))) {
        closeRow();
      }
      final take = math.min(required, spanLeft);
      spans.add(take);
      rowAspects.add(a);
      spanLeft -= take;
    }
    closeRow();
    return rows.where((row) => row.isNotEmpty).toList();
  }
}
