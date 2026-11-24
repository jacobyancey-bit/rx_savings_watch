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
            theme: ThemeData(
              useMaterial3: true,
              scaffoldBackgroundColor: const Color(0xFFF3F6F5),
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF0F6B66),
                brightness: Brightness.light,
                surface: const Color(0xFFF8FAFA),
              ),
              appBarTheme: const AppBarTheme(
                centerTitle: false,
                elevation: 0,
                scrolledUnderElevation: 1,
                backgroundColor: Color(0xFFF3F6F5),
              ),
              cardTheme: CardThemeData(
                elevation: 0,
                color: const Color(0xFFFCFDFD),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              scaffoldBackgroundColor: const Color(0xFF121918),
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF2D8A84),
                brightness: Brightness.dark,
                surface: const Color(0xFF192221),
              ),
              appBarTheme: const AppBarTheme(
                centerTitle: false,
                elevation: 0,
                scrolledUnderElevation: 1,
                backgroundColor: Color(0xFF121918),
              ),
              cardTheme: CardThemeData(
                elevation: 0,
                color: const Color(0xFF1B2524),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
