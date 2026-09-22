import 'package:flutter/material.dart';

import 'screens/search_screen.dart';

void main() {
  runApp(const ShunoApp());
}

class ShunoApp extends StatelessWidget {
  const ShunoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shuno',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8EDBC5),
          brightness: Brightness.dark,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const SearchScreen(),
    );
  }
}
