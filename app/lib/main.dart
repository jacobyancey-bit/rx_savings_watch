import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/cabinet_provider.dart';
import 'screens/home_screen.dart';
import 'services/subscription_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RxSavingsWatchApp());
}

/// Enables mouse-drag scrolling and removes mobile overscroll glow on Web.
class WebScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class RxSavingsWatchApp extends StatelessWidget {
  const RxSavingsWatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CabinetProvider()),
        ChangeNotifierProvider(create: (_) => SubscriptionService()..init()),
      ],
      child: Consumer<CabinetProvider>(
        builder: (context, cabinet, _) {
          return MaterialApp(
            title: 'Rx Savings Watch',
            debugShowCheckedModeBanner: false,
            scrollBehavior: WebScrollBehavior(),
            builder: (context, child) {
              final mediaQuery = MediaQuery.of(context);
              final systemScale = mediaQuery.textScaler.scale(1.0);
              final combinedScale = (systemScale * cabinet.textScale).clamp(
                1.0,
                1.85,
              );
              final content = child ?? const SizedBox.shrink();

              return MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: TextScaler.linear(combinedScale),
                ),
                // Allows desktop users to highlight/copy drug names, NDCs, & prices
                child: SelectionArea(child: content),
              );
            },
            theme: _buildLightTheme(),
            darkTheme: _buildDarkTheme(),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }

  ThemeData _buildLightTheme() {
    // Deep Clinical Forest + Warm Alabaster Paper (replaces mint/teal AI defaults)
    const primary = Color(0xFF0F5132);
    const primaryHover = Color(0xFF0A3622);
    const canvas = Color(0xFFFAF9F6);
    const surface = Color(0xFFFFFFFF);
    const surfaceSubtle = Color(0xFFF3F2EE);
    const ink = Color(0xFF11181C);
    const inkSecondary = Color(0xFF59636E);
    const outline = Color(0xFFE5E4E0);
    // Preserves your >= 3:1 WCAG 1.4.11 non-text contrast for interactive controls
    const controlOutline = Color(0xFF757D7A);

    final baseText = GoogleFonts.plusJakartaSansTextTheme();

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      // Explicit ColorScheme prevents fromSeed() pastel tonal leaks
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: Colors.white,
        secondary: Color(0xFF1E293B),
        onSecondary: Colors.white,
        surface: surface,
        onSurface: ink,
        onSurfaceVariant: inkSecondary,
        outline: controlOutline,
        outlineVariant: outline,
        surfaceContainerLowest: canvas,
        surfaceContainerLow: surfaceSubtle,
        surfaceContainer: surfaceSubtle,
        surfaceContainerHigh: Color(0xFFEBEAE4),
      ),
      textTheme: baseText.copyWith(
        displaySmall: baseText.displaySmall?.copyWith(
          letterSpacing: -0.9,
          fontWeight: FontWeight.w600,
          height: 1.1,
          color: ink,
        ),
        headlineSmall: baseText.headlineSmall?.copyWith(
          letterSpacing: -0.6,
          fontWeight: FontWeight.w600,
          height: 1.15,
          color: ink,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          letterSpacing: -0.45,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          letterSpacing: -0.3,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        titleSmall: baseText.titleSmall?.copyWith(
          letterSpacing: -0.15,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(color: ink, height: 1.55),
        bodyMedium: baseText.bodyMedium?.copyWith(
          color: inkSecondary,
          height: 1.5,
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: canvas,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: outline, width: 1)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surface,
        surfaceTintColor: Colors.transparent,
        // Architectural 8px radius instead of soft 16px mobile cards
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: outline, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return primaryHover;
            return primary;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return surfaceSubtle;
            return surface;
          }),
          foregroundColor: const WidgetStatePropertyAll(ink),
          side: const WidgetStatePropertyAll(
            BorderSide(color: controlOutline, width: 1),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          ),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: controlOutline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: controlOutline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: const Color(0xFFECFDF5),
        side: const BorderSide(color: outline, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: ink,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: outline,
        thickness: 1,
        space: 1,
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    // Obsidian Financial Terminal + Crisp Emerald Accent
    const primary = Color(0xFF34D399);
    const canvas = Color(0xFF0A0B0B);
    const surface = Color(0xFF121414);
    const surfaceSubtle = Color(0xFF1A1D1D);
    const ink = Color(0xFFEDEDEF);
    const inkSecondary = Color(0xFF9CA3AF);
    const outline = Color(0xFF232726);
    // Preserves your >= 3:1 WCAG 1.4.11 non-text contrast in dark mode
    const controlOutline = Color(0xFF64706D);

    final baseText = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData.dark().textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: Color(0xFF052E16),
        secondary: Color(0xFF94A3B8),
        onSecondary: Color(0xFF0F172A),
        surface: surface,
        onSurface: ink,
        onSurfaceVariant: inkSecondary,
        outline: controlOutline,
        outlineVariant: outline,
        surfaceContainerLowest: canvas,
        surfaceContainerLow: surfaceSubtle,
        surfaceContainer: surfaceSubtle,
        surfaceContainerHigh: Color(0xFF222626),
      ),
      textTheme: baseText.copyWith(
        headlineSmall: baseText.headlineSmall?.copyWith(
          letterSpacing: -0.6,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          letterSpacing: -0.45,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          letterSpacing: -0.3,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(color: ink, height: 1.55),
        bodyMedium: baseText.bodyMedium?.copyWith(
          color: inkSecondary,
          height: 1.5,
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: canvas,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: outline, width: 1)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: outline, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: const Color(0xFF052E16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          side: const BorderSide(color: controlOutline, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          textStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: controlOutline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: controlOutline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: outline,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
