import 'package:flutter/material.dart';

/// The composition site: the one place that constructs the application.
void main() {
  runApp(const SmartmanApp());
}

/// The application root, showing a placeholder home screen.
class SmartmanApp extends StatelessWidget {
  const SmartmanApp({super.key});

  static const String name = 'smartman';

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: name,
      home: Scaffold(body: Center(child: Text(name))),
    );
  }
}
