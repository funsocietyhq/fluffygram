// SPDX-FileCopyrightText: 2026 FluffyChat Telegram-UX fork contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Portions of the layout, geometry and behaviour of this file are derived
// from Telegram for Android, Copyright (C) 2017-2026 Telegram FZ-LLC,
// licensed under the GNU GPL v. 2 or later, and were changed by this fork
// in 2026 to implement the same interface in Flutter/Dart. The source file
// and line are cited where they were used. See NOTICE.

import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/config/attheme.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:material_ui/material_ui.dart';

/// Outcome of [ImportedTheme.pickAndImportFile].
enum AtthemeImportResult {
  /// The user closed the picker; nothing was stored.
  cancelled,

  /// The file parsed and is now the app's chat palette.
  imported,

  /// The file held no parsable `key=value` colour: nothing was stored.
  invalid,
}

/// The `.attheme` theme the user imported from Telegram (roadmap T8).
///
/// Telegram's own theme import reads a `.attheme` file the user exports from
/// the desktop client; this is the same idea: the group pastes a theme in and
/// the fork draws its colours. Storage is two device-local `AppSettings`
/// strings - the raw file text and its name - so this is appearance state
/// only: no Matrix room state, no protocol code. The parser and the role
/// mapping live in `lib/config/attheme.dart`, which stays free of app imports
/// so the golden rig can score it.
///
/// A role the theme does not define keeps the built-in `TelegramPalette`
/// value; see [AtthemePalette].
abstract class ImportedTheme {
  /// Writes notify through this listenable, because `SharedPreferences` has
  /// none: the style page wraps its row in a `ListenableBuilder` on it, and
  /// the theme rebuild goes through `ThemeController.refreshTheme()`.
  static final ImportedThemeStore store = ImportedThemeStore();

  static AtthemePalette? _cached;
  static String? _cachedSource;

  /// The stored file name, '' when no theme is imported.
  static String get fileName => AppSettings.importedAtthemeName.value;

  /// Whether an imported theme is in effect.
  static bool get isImported => AppSettings.importedAttheme.value.isNotEmpty;

  /// The imported palette, parsed once and cached on the stored text. Null
  /// when nothing is imported, so every caller falls back to the built-in
  /// theme. `FluffyThemes.buildTheme` and the `BubbleColorTheme` extension
  /// read this on every build.
  static AtthemePalette? get palette {
    final source = AppSettings.importedAttheme.value;
    if (source == _cachedSource) return _cached;
    _cachedSource = source;
    return _cached = source.isEmpty ? null : AtthemePalette.parse(source);
  }

  /// Import [source] under [name]. A file with no parsable colour is refused
  /// and changes nothing.
  static Future<AtthemePalette?> importText({
    required String name,
    required String source,
  }) async {
    final palette = AtthemePalette.parse(source);
    if (palette.isEmpty) return null;
    await AppSettings.importedAttheme.setItem(source);
    await AppSettings.importedAtthemeName.setItem(name);
    store.notify();
    return palette;
  }

  /// Open the system file picker for one `.attheme` file and import it. This
  /// is the app-side half of the feature - the rig never renders it.
  static Future<AtthemeImportResult> pickAndImportFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const [fileExtension],
    );
    final file = picked?.xFile;
    if (file == null) return AtthemeImportResult.cancelled;
    final String source;
    try {
      source = await file.readAsString();
    } on Exception {
      return AtthemeImportResult.invalid;
    }
    final palette = await importText(name: file.name, source: source);
    return palette == null
        ? AtthemeImportResult.invalid
        : AtthemeImportResult.imported;
  }

  /// Clear both keys, so the built-in palette shows again.
  static Future<void> clear() async {
    await AppSettings.importedAttheme.setItem('');
    await AppSettings.importedAtthemeName.setItem('');
    store.notify();
  }

  /// The picker's file filter and the extension the settings row names.
  static const String fileExtension = 'attheme';
}

/// The write side of [ImportedTheme]: [notify] runs once the keys are stored.
class ImportedThemeStore extends ChangeNotifier {
  void notify() => notifyListeners();
}
