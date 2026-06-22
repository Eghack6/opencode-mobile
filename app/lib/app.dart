import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/chat_provider.dart';
import 'screens/chat_screen.dart';
import 'services/theme_provider.dart';

/// Glass-themed color palette
class GlassColors {
  // Primary gradient stops
  static const primaryStart = Color(0xFF6C5CE7); // purple
  static const primaryEnd = Color(0xFFA29BFE);   // light purple
  // Accent gradient stops
  static const accentStart = Color(0xFF0984E3);  // blue
  static const accentEnd = Color(0xFF74B9FF);    // light blue

  // Light mode
  static const lightBg = Color(0xFFF0F2F8);
  static const lightGlass = Color(0xCCFFFFFF);       // white 80%
  static const lightGlassBorder = Color(0x33FFFFFF);  // white 20%
  static const lightSurface = Color(0xE6F5F6FA);     // near-white 90%

  // Dark mode
  static const darkBg = Color(0xFF0F0F1A);
  static const darkGlass = Color(0x4D1E1E2E);        // dark 30%
  static const darkGlassBorder = Color(0x1AFFFFFF);   // white 10%
  static const darkSurface = Color(0xB31A1A2E);      // dark 70%

  static LinearGradient primaryGradient = const LinearGradient(
    colors: [primaryStart, primaryEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient lightBgGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      const Color(0xFFE8EAF6), // indigo-50
      const Color(0xFFF3E5F5), // purple-50
      const Color(0xFFE3F2FD), // blue-50
    ],
    stops: const [0.0, 0.5, 1.0],
  );

  static LinearGradient darkBgGradient = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF0D0D1A),
      Color(0xFF141428),
      Color(0xFF0A0A1E),
    ],
    stops: [0.0, 0.5, 1.0],
  );
}

class OpenCodeMobileApp extends StatefulWidget {
  const OpenCodeMobileApp({super.key});

  @override
  State<OpenCodeMobileApp> createState() => _OpenCodeMobileAppState();
}

class _OpenCodeMobileAppState extends State<OpenCodeMobileApp> {
  @override
  void initState() {
    super.initState();
    _loadTheme();
    OpenCodeThemeProvider.notifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    OpenCodeThemeProvider.notifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('theme_mode') ?? 0;
    OpenCodeThemeProvider.setThemeMode(ThemeMode.values[themeIndex]);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ChatProvider(),
      child: MaterialApp(
        title: 'OpenCode Mobile',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: OpenCodeThemeProvider.notifier.value,
        home: const ChatScreen(),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: GlassColors.primaryStart,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? GlassColors.darkBg : GlassColors.lightBg,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: isDark ? GlassColors.darkGlass : GlassColors.lightGlass,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? GlassColors.darkGlassBorder : GlassColors.lightGlassBorder,
            width: 1,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withOpacity(0.3),
        thickness: 0.5,
      ),
      dialogTheme: DialogTheme(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        backgroundColor: isDark ? GlassColors.darkSurface : GlassColors.lightGlass,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.white.withOpacity(0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.black.withOpacity(0.06),
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.black.withOpacity(0.06),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(
            color: GlassColors.primaryStart.withOpacity(0.5),
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        hintStyle: TextStyle(
          color: colorScheme.onSurface.withOpacity(0.35),
          fontSize: 15,
          fontWeight: FontWeight.w300,
        ),
      ),
      // Override text theme for lighter weights
      textTheme: _buildTextTheme(colorScheme),
    );
  }

  TextTheme _buildTextTheme(ColorScheme colorScheme) {
    const baseWeight = FontWeight.w300;
    return TextTheme(
      displayLarge: TextStyle(fontWeight: FontWeight.w200, letterSpacing: -1),
      displayMedium: TextStyle(fontWeight: FontWeight.w200, letterSpacing: -0.5),
      headlineLarge: TextStyle(fontWeight: FontWeight.w400, letterSpacing: -0.3),
      headlineMedium: TextStyle(fontWeight: FontWeight.w400, letterSpacing: -0.2),
      titleLarge: TextStyle(fontWeight: FontWeight.w500, letterSpacing: -0.2),
      titleMedium: TextStyle(fontWeight: FontWeight.w500, letterSpacing: -0.1),
      titleSmall: TextStyle(fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(fontWeight: baseWeight, height: 1.6),
      bodyMedium: TextStyle(fontWeight: baseWeight, height: 1.5),
      bodySmall: TextStyle(fontWeight: baseWeight, height: 1.4),
      labelLarge: TextStyle(fontWeight: FontWeight.w400, letterSpacing: 0.2),
      labelMedium: TextStyle(fontWeight: FontWeight.w400),
      labelSmall: TextStyle(fontWeight: FontWeight.w400, letterSpacing: 0.3),
    );
  }
}
