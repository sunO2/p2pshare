import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LocalP2PApp());
}

class LocalP2PApp extends StatelessWidget {
  const LocalP2PApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local P2P',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3D8A5A),
          primary: const Color(0xFF3D8A5A),
          onPrimary: const Color(0xFFFFFFFF),
          primaryContainer: const Color(0xFFC8F0D8),
          onPrimaryContainer: const Color(0xFF1A1918),
          secondary: const Color(0xFF6D6C6A),
          onSecondary: const Color(0xFFFFFFFF),
          surface: const Color(0xFFFFFFFF),
          onSurface: const Color(0xFF1A1918),
          surfaceContainerHighest: const Color(0xFFEDECEA),
          outline: const Color(0xFFE5E4E1),
          outlineVariant: const Color(0xFFE5E4E1),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F8F6),
        fontFamily: 'Inter',
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 26,
            fontWeight: FontWeight.normal,
            color: Color(0xFF1A1918),
          ),
          displayMedium: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 20,
            fontWeight: FontWeight.normal,
            color: Color(0xFF1A1918),
          ),
          displaySmall: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 18,
            fontWeight: FontWeight.normal,
            color: Color(0xFF1A1918),
          ),
          headlineMedium: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 16,
            fontWeight: FontWeight.normal,
            color: Color(0xFF1A1918),
          ),
          titleLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.normal,
            color: Color(0xFF1A1918),
          ),
          bodyLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: Color(0xFF1A1918),
          ),
          bodyMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.normal,
            color: Color(0xFF6D6C6A),
          ),
          bodySmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: Color(0xFF9C9B99),
          ),
          labelSmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.normal,
            color: Color(0xFF9C9B99),
          ),
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            side: BorderSide(color: Color(0xFFCCCCCC), width: 1),
          ),
          color: Color(0xFFF8F8F6),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8F8F6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFCCCCCC)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFCCCCCC)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF3D8A5A)),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
