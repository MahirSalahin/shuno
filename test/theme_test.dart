import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shuno/services/storage_service.dart';
import 'package:shuno/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('AppTheme & Palettes', () {
    test('AppPalette resolves all 4 curated palettes with correct defaults', () {
      expect(AppPalette.fromId('emerald'), AppPalette.emerald);
      expect(AppPalette.fromId('cyan'), AppPalette.cyan);
      expect(AppPalette.fromId('amethyst'), AppPalette.amethyst);
      expect(AppPalette.fromId('amber'), AppPalette.amber);
      // Fallback
      expect(AppPalette.fromId('unknown'), AppPalette.emerald);
      expect(AppPalette.fromId(null), AppPalette.emerald);
    });

    test('buildTheme returns dark Material 3 ThemeData with palette colors', () {
      for (final palette in AppPalette.values) {
        final theme = AppTheme.buildTheme(palette);
        expect(theme.brightness, Brightness.dark);
        expect(theme.useMaterial3, isTrue);
        expect(theme.colorScheme.primary, palette.primary);
        expect(theme.scaffoldBackgroundColor, palette.background);
      }
    });

    test('StorageService persists and switches themeKey', () async {
      final tempFile = File('${Directory.systemTemp.path}/test_theme_storage_${DateTime.now().millisecondsSinceEpoch}.json');
      addTearDown(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });

      final storage = StorageService();
      await storage.init(overrideFile: tempFile);

      // Default theme is emerald
      expect(storage.themeKey, 'emerald');

      // Change to amethyst
      int notifyCount = 0;
      storage.addListener(() => notifyCount++);

      await storage.setThemeKey('amethyst');
      expect(storage.themeKey, 'amethyst');
      expect(notifyCount, 1);

      // Reload from disk to verify persistence
      final reloadedStorage = StorageService();
      await reloadedStorage.init(overrideFile: tempFile);
      expect(reloadedStorage.themeKey, 'amethyst');
    });
  });
}
