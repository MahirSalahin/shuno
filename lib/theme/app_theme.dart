import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppPalette {
  emerald(
    id: 'emerald',
    name: 'Spotify Green',
    primary: Color(0xFF1DB954),
    secondary: Color(0xFF1ED760),
    background: Color(0xFF121212),
    surface: Color(0xFF121212),
    surfaceContainerLow: Color(0xFF181818),
    surfaceContainer: Color(0xFF242424),
    surfaceContainerHigh: Color(0xFF282828),
    surfaceContainerHighest: Color(0xFF3E3E3E),
    outlineVariant: Color(0xFF2A2A2A),
  ),
  cyan(
    id: 'cyan',
    name: 'Neon Cyan',
    primary: Color(0xFF00D2FF),
    secondary: Color(0xFF0284C7),
    background: Color(0xFF0C1017),
    surface: Color(0xFF0C1017),
    surfaceContainerLow: Color(0xFF121824),
    surfaceContainer: Color(0xFF1B2436),
    surfaceContainerHigh: Color(0xFF232E45),
    surfaceContainerHighest: Color(0xFF2F3E5C),
    outlineVariant: Color(0xFF222D42),
  ),
  amethyst(
    id: 'amethyst',
    name: 'Deep Violet',
    primary: Color(0xFFA855F7),
    secondary: Color(0xFFEC4899),
    background: Color(0xFF110D1B),
    surface: Color(0xFF110D1B),
    surfaceContainerLow: Color(0xFF181326),
    surfaceContainer: Color(0xFF231B38),
    surfaceContainerHigh: Color(0xFF2C2246),
    surfaceContainerHighest: Color(0xFF382C59),
    outlineVariant: Color(0xFF292042),
  ),
  amber(
    id: 'amber',
    name: 'Warm Amber',
    primary: Color(0xFFF59E0B),
    secondary: Color(0xFFF43F5E),
    background: Color(0xFF14120E),
    surface: Color(0xFF14120E),
    surfaceContainerLow: Color(0xFF1C1813),
    surfaceContainer: Color(0xFF27221B),
    surfaceContainerHigh: Color(0xFF322C23),
    surfaceContainerHighest: Color(0xFF40382D),
    outlineVariant: Color(0xFF2D271F),
  );

  const AppPalette({
    required this.id,
    required this.name,
    required this.primary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.outlineVariant,
  });

  final String id;
  final String name;
  final Color primary;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color outlineVariant;

  static AppPalette fromId(String? id) {
    return AppPalette.values.firstWhere(
      (e) => e.id == id,
      orElse: () => AppPalette.emerald,
    );
  }
}

class AppTheme {
  static ThemeData buildTheme(AppPalette palette) {
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: palette.primary,
      onPrimary: Colors.black,
      primaryContainer: palette.primary.withAlpha(40),
      onPrimaryContainer: palette.primary,
      secondary: palette.secondary,
      onSecondary: Colors.black,
      secondaryContainer: palette.secondary.withAlpha(40),
      onSecondaryContainer: palette.secondary,
      surface: palette.background,
      onSurface: const Color(0xFFFFFFFF),
      surfaceContainerLowest: palette.background,
      surfaceContainerLow: palette.surfaceContainerLow,
      surfaceContainer: palette.surfaceContainer,
      surfaceContainerHigh: palette.surfaceContainerHigh,
      surfaceContainerHighest: palette.surfaceContainerHighest,
      onSurfaceVariant: const Color(0xFFB3B3B3),
      outline: const Color(0xFF727272),
      outlineVariant: palette.outlineVariant,
      error: const Color(0xFFE91E63),
      onError: Colors.white,
    );

    const baseTextTheme = TextTheme(
      headlineMedium: TextStyle(
        color: Color(0xFFFFFFFF),
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(
        color: Color(0xFFFFFFFF),
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleMedium: TextStyle(
        color: Color(0xFFFFFFFF),
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleSmall: TextStyle(
        color: Color(0xFFFFFFFF),
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(color: Color(0xFFFFFFFF)),
      bodyMedium: TextStyle(color: Color(0xFFB3B3B3)),
      bodySmall: TextStyle(color: Color(0xFFB3B3B3)),
      labelLarge: TextStyle(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
      labelSmall: TextStyle(
        fontWeight: FontWeight.w500,
      ),
    );

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(baseTextTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: palette.background,
      colorScheme: colorScheme,
      textTheme: textTheme,

      // App Bar Theme
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFFFFFFF),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFFFFFFF)),
      ),

      // Card Theme
      cardTheme: CardThemeData(
        color: palette.surfaceContainerLow,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // Navigation Bar Theme (Spotify style: clean, unboxed active icons)
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.background,
        elevation: 0,
        height: 60,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: palette.primary, size: 24);
          }
          return const IconThemeData(color: Color(0xFFB3B3B3), size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              color: palette.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            );
          }
          return const TextStyle(
            color: Color(0xFFB3B3B3),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          );
        }),
      ),

      // Tab Bar Theme
      tabBarTheme: TabBarThemeData(
        labelColor: const Color(0xFFFFFFFF),
        unselectedLabelColor: const Color(0xFFB3B3B3),
        indicatorColor: palette.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),

      // Input Decoration Theme (Spotify search input)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.primary, width: 1.5),
        ),
        hintStyle: const TextStyle(
          color: Color(0xFF757575),
          fontSize: 14,
        ),
        prefixIconColor: const Color(0xFFB3B3B3),
        suffixIconColor: const Color(0xFFB3B3B3),
      ),

      // Slider Theme (Spotify scrub bar)
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.primary,
        inactiveTrackColor: const Color(0xFF4D4D4D),
        thumbColor: Colors.white,
        overlayColor: palette.primary.withAlpha(30),
        trackHeight: 2.5,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      ),

      // Dialog Theme
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surfaceContainerHigh,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFFFFFFFF),
        ),
      ),

      // Bottom Sheet Theme
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surfaceContainerHigh,
        modalBackgroundColor: palette.surfaceContainerHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
        dragHandleColor: const Color(0xFF4D4D4D),
      ),

      // Buttons
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: Colors.black,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        ),
      ),

      // Divider Theme
      dividerTheme: DividerThemeData(
        color: palette.outlineVariant,
        thickness: 0.8,
        space: 1,
      ),
    );
  }
}
