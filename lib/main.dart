import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/ble_service.dart';
import 'screens/scan_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0A1929),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  
  runApp(const TennisStrokeApp());
}

class TennisStrokeApp extends StatelessWidget {
  const TennisStrokeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BleService(),
      child: MaterialApp(
        title: 'Tennis Stroke Detector',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4CAF50),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF0A1929),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1A2F4A),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        ),
        home: const ScanScreen(),
      ),
    );
  }
}
