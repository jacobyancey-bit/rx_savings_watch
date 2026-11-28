import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/cabinet_provider.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RxSavingsWatchApp());
}

class RxSavingsWatchApp extends StatelessWidget {
  const RxSavingsWatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CabinetProvider()),
      ],
      child: Consumer<CabinetProvider>(
        builder: (context, cabinet, _) {
          return MaterialApp(
            title: 'Rx Savings Watch',
            debugShowCheckedModeBanner: false,
            builder: (context, child) {
              final mediaQuery = MediaQuery.of(context);
              final systemScale = mediaQuery.textScaler.scale(1.0);
              final combinedScale = (systemScale * cabinet.textScale).clamp(1.0, 1.85);
              final content = child ?? const SizedBox.shrink();

              return MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: TextScaler.linear(combinedScale),
                ),
                child: content,
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
    const primary = Color(0xFF0A6C67);
    const canvas = Color(0xFFF4F7F7);
    const surface = Color(0xFFFFFFFF);
    const ink = Color(0xFF0F1F1E);
    const outline = Color(0xFFDCE6E5);

    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
        primary: primary,
        surface: surface,
        onSurface: ink,
        outlineVariant: outline,
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          letterSpacing: -0.5,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          letterSpacing: -0.4,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          letterSpacing: -0.25,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          letterSpacing: -0.15,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: canvas,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: outline, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          // >= 3:1 non-text contrast against white and canvas (WCAG 1.4.11)
          side: const BorderSide(color: Color(0xFF728D8B)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.1),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: outline),
      ),
      dividerTheme: const DividerThemeData(color: outline, thickness: 1),
    );
  }

  ThemeData _buildDarkTheme() {
    const primary = Color(0xFF2EA39B);
    const canvas = Color(0xFF0E1515);
    const surface = Color(0xFF162020);
    const outline = Color(0xFF263534);

    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
        primary: primary,
        surface: surface,
        outlineVariant: outline,
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(letterSpacing: -0.5, fontWeight: FontWeight.w700),
        titleLarge: base.textTheme.titleLarge?.copyWith(letterSpacing: -0.4, fontWeight: FontWeight.w700),
        titleMedium: base.textTheme.titleMedium?.copyWith(letterSpacing: -0.25, fontWeight: FontWeight.w700),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: outline, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          // >= 3:1 non-text contrast against dark surface and canvas (WCAG 1.4.11);
          // the decorative card `outline` (#263534) is only ~1.3:1.
          side: const BorderSide(color: Color(0xFF5A7371)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: const DividerThemeData(color: outline, thickness: 1),
    );
  }
}
