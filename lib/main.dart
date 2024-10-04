import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

void main() {
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

class DependencyManager extends StatefulWidget {
  const DependencyManager({super.key});

  @override
  _DependencyManagerState createState() => _DependencyManagerState();
}

class _DependencyManagerState extends State<DependencyManager> {
  String? selectedDirectory;
  List<String> flutterPackages = [];
  Map<String, dynamic> dependencies = {};
  bool isLoading = false;

  Future<void> pickDirectory() async {
    String? directory = await FilePicker.platform.getDirectoryPath();
    if (directory != null) {
      setState(() {
        selectedDirectory = directory;
        flutterPackages = [];
        dependencies = {};
      });
      await scanPackages();
    }
  }

  Future<void> scanPackages() async {
    setState(() {
      isLoading = true;
    });
    final dir = Directory(selectedDirectory!);
    final entities = await dir.list(recursive: true).toList();
    for (var entity in entities) {
      if (entity is File && entity.path.endsWith('pubspec.yaml')) {
        flutterPackages
            .add(entity.parent.path.split(Platform.pathSeparator).last);
      }
    }
    setState(() {
      isLoading = false;
    });
  }

  Future<void> fetchDependencies(String packagePath) async {
    setState(() {
      isLoading = true;
      dependencies = {};
    });
    final pubspecFile = File(
        '$selectedDirectory${Platform.pathSeparator}$packagePath${Platform.pathSeparator}pubspec.yaml');
    if (await pubspecFile.exists()) {
      final content = await pubspecFile.readAsString();
      final yamlMap = loadYaml(content);
      setState(() {
        dependencies = {
          'dependencies': yamlMap['dependencies'] ?? {},
          'dev_dependencies': yamlMap['dev_dependencies'] ?? {},
          'dependency_overrides': yamlMap['dependency_overrides'] ?? {},
        };
        isLoading = false;
      });
    }
  }

  Future<String> getLatestVersion(String packageName) async {
    final response =
        await http.get(Uri.parse('https://pub.dev/api/packages/$packageName'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['latest']['version'];
    }
    return 'Unknown';
  }

  Future<void> upgradeDependency(
      String packagePath, String packageName, String dependencyType) async {
    final pubspecFile = File(
        '$selectedDirectory${Platform.pathSeparator}$packagePath${Platform.pathSeparator}pubspec.yaml');
    if (await pubspecFile.exists()) {
      final content = await pubspecFile.readAsString();
      final editor = YamlEditor(content);

      final latestVersion = await getLatestVersion(packageName);
      if (latestVersion != 'Unknown') {
        editor.update([dependencyType, packageName], '^$latestVersion');
        await pubspecFile.writeAsString(editor.toString());
        await fetchDependencies(packagePath);
      }
    }
  }

  Future<void> upgradeAllDependencies(String packagePath) async {
    final pubspecFile = File(
        '$selectedDirectory${Platform.pathSeparator}$packagePath${Platform.pathSeparator}pubspec.yaml');
    if (await pubspecFile.exists()) {
      final content = await pubspecFile.readAsString();
      final editor = YamlEditor(content);

      for (var dependencyType in [
        'dependencies',
        'dev_dependencies',
        'dependency_overrides'
      ]) {
        if (dependencies[dependencyType] != null) {
          for (var packageName in dependencies[dependencyType].keys) {
            final latestVersion = await getLatestVersion(packageName);
            if (latestVersion != 'Unknown') {
              editor.update([dependencyType, packageName], '^$latestVersion');
            }
          }
        }
      }

      await pubspecFile.writeAsString(editor.toString());
      await fetchDependencies(packagePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dependency Manager'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            ElevatedButton(
              onPressed: pickDirectory,
              child: const Text('Open Folder'),
            ),
            const SizedBox(height: 20),
            selectedDirectory != null
                ? Text('Selected Directory: $selectedDirectory')
                : const Text('No directory selected'),
            const SizedBox(height: 20),
            isLoading
                ? const CircularProgressIndicator()
                : Expanded(
                    child: flutterPackages.isNotEmpty
                        ? ListView.builder(
                            itemCount: flutterPackages.length,
                            itemBuilder: (context, index) {
                              final package = flutterPackages[index];
                              return ListTile(
                                title: Text(package),
                                onTap: () => fetchDependencies(package),
                              );
                            },
                          )
                        : const Text('No Flutter packages found.'),
                  ),
            const SizedBox(height: 20),
            dependencies.isNotEmpty
                ? Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...[
                          'dependencies',
                          'dev_dependencies',
                          'dependency_overrides'
                        ].map((depType) {
                          if (dependencies[depType].isEmpty) return Container();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$depType:',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              ...dependencies[depType].keys.map((dep) {
                                return FutureBuilder<String>(
                                  future: getLatestVersion(dep),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return ListTile(
                                        title: Text(dep),
                                        subtitle: const Text(
                                            'Fetching latest version...'),
                                      );
                                    } else {
                                      return ListTile(
                                        title: Text(dep),
                                        subtitle: Text(
                                            'Current: ${dependencies[depType][dep]}, Latest: ${snapshot.data}'),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.refresh),
                                          onPressed: () {
                                            final packagePath =
                                                selectedDirectory!
                                                    .split(
                                                        Platform.pathSeparator)
                                                    .last;
                                            upgradeDependency(
                                                packagePath, dep, depType);
                                          },
                                        ),
                                      );
                                    }
                                  },
                                );
                              }).toList(),
                            ],
                          );
                        }),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: () {
                            final packagePath = selectedDirectory!
                                .split(Platform.pathSeparator)
                                .last;
                            upgradeAllDependencies(packagePath);
                          },
                          child: const Text('Upgrade All Dependencies'),
                        ),
                      ],
                    ),
                  )
                : Container(),
          ],
        ),
      ),
    );
  }
}
