import 'package:flutter/material.dart';
import 'package:flutter_cli_ui/dependency_manager.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(final BuildContext context) => MaterialApp(
    title: 'Dependency Manager',
    theme: ThemeData(brightness: Brightness.dark, primarySwatch: Colors.blue),
    home: const DependencyManager(),
  );
}
