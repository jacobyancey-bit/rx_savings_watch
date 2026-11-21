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
              return MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: TextScaler.linear(combinedScale),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal,
                brightness: Brightness.light,
              ),
              appBarTheme: const AppBarTheme(
                centerTitle: false,
                elevation: 0,
                scrolledUnderElevation: 1,
              ),
              cardTheme: CardThemeData(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal,
                brightness: Brightness.dark,
              ),
            ),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
