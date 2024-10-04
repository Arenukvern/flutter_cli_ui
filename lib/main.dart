import 'package:flutter/material.dart';

import 'dependency_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dependency Manager',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const DependencyManager(),
    );
  }
}
