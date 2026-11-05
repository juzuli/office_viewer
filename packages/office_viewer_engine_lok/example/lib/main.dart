import 'package:flutter/material.dart';

/// Minimal placeholder. Use the repo-root `example/` app for the Phase 0 spike.
/// Colors match Leafpane Deep Teal (`replica/design/tokens.json`).
void main() {
  runApp(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF087F8C),
          primary: const Color(0xFF087F8C),
          secondary: const Color(0xFF55A6A0),
          tertiary: const Color(0xFFD5A64A),
          surface: const Color(0xFFF0F6F6),
        ),
        scaffoldBackgroundColor: const Color(0xFFF0F6F6),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text(
            'Use ../../example for the office_viewer + LOK spike harness.',
          ),
        ),
      ),
    ),
  );
}
