import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  static const platform =
      MethodChannel('com.example.flutter_cli_ui/permissions');

  double _dividerPosition = 0.5;
  String? _selectedPackage;

  Future<bool> requestPermission() async {
    try {
      final bool result = await platform.invokeMethod('requestPermission');
      return result;
    } on PlatformException catch (e) {
      print("Failed to request permission: '${e.message}'.");
      return false;
    }
  }

  Future<void> pickDirectory() async {
    // Use FilePicker for other platforms
    try {
      String? directory = await FilePicker.platform.getDirectoryPath();
      if (directory != null) {
        setState(() {
          selectedDirectory = directory;
          flutterPackages = [];
          dependencies = {};
        });
        await scanPackages();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error accessing directory: $e')),
      );
    }
  }

  Future<void> scanPackages() async {
    setState(() {
      isLoading = true;
      flutterPackages = [];
    });

    try {
      final dir = Directory(selectedDirectory!);
      final list = dir.listSync(recursive: true, followLinks: false);
      for (var entity in list) {
        if (entity is File &&
            entity.path.endsWith('pubspec.yaml') &&
            !(entity.statSync().type == FileSystemEntityType.link)) {
          final package = entity.parent.path.split(Platform.pathSeparator).last;
          setState(() {
            flutterPackages.add(package);
          });
        }
      }
    } on FileSystemException catch (e) {
      print("Error accessing directory: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error accessing directory: ${e.message}')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> fetchDependencies(String packagePath) async {
    setState(() {
      isLoading = true;
      dependencies = {};
    });

    final String fullPath;
    if (packagePath == selectedDirectory!.split(Platform.pathSeparator).last) {
      fullPath = selectedDirectory!;
    } else {
      fullPath = '$selectedDirectory${Platform.pathSeparator}$packagePath';
    }

    final pubspecFile = File('$fullPath${Platform.pathSeparator}pubspec.yaml');

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
    } else {
      setState(() {
        isLoading = false;
      });
      print('pubspec.yaml not found at path: ${pubspecFile.path}');
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: pickDirectory,
                  child: const Text('Open Folder'),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: selectedDirectory != null
                      ? Text('Selected Directory: $selectedDirectory')
                      : const Text('No directory selected'),
                ),
              ],
            ),
          ),
          Expanded(
            child: CustomMultiChildLayout(
              delegate: _PanelLayoutDelegate(_dividerPosition),
              children: [
                LayoutId(
                  id: 'left',
                  child: _buildPackagesList(),
                ),
                LayoutId(
                  id: 'divider',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _dividerPosition +=
                              details.delta.dx / context.size!.width;
                          _dividerPosition = _dividerPosition.clamp(0.1, 0.9);
                        });
                      },
                      child: const VerticalDivider(width: 8, thickness: 8),
                    ),
                  ),
                ),
                LayoutId(
                  id: 'right',
                  child: _buildDependenciesView(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackagesList() {
    return Card(
      margin: const EdgeInsets.all(8),
      child: isLoading
          ? const Center(child: CircularProgressIndicator())
          : flutterPackages.isNotEmpty
              ? ReorderableListView.builder(
                  itemCount: flutterPackages.length,
                  itemBuilder: (context, index) {
                    final package = flutterPackages[index];
                    return ListTile(
                      key: ValueKey(package),
                      title: Text(package),
                      selected: package == _selectedPackage,
                      onTap: () {
                        setState(() {
                          _selectedPackage = package;
                        });
                        fetchDependencies(package);
                      },
                    );
                  },
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (oldIndex < newIndex) {
                        newIndex -= 1;
                      }
                      final item = flutterPackages.removeAt(oldIndex);
                      flutterPackages.insert(newIndex, item);
                    });
                  },
                )
              : const Center(child: Text('No Flutter packages found.')),
    );
  }

  Widget _buildDependenciesView() {
    return Card(
      margin: const EdgeInsets.all(8),
      child: dependencies.isNotEmpty
          ? ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton(
                    onPressed: _selectedPackage != null
                        ? () => upgradeAllDependencies(_selectedPackage!)
                        : null,
                    child: const Text('Upgrade All Dependencies'),
                  ),
                ),
                ...['dependencies', 'dev_dependencies', 'dependency_overrides']
                    .map((depType) {
                  if (dependencies[depType].isEmpty) return Container();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text('$depType:',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      ...dependencies[depType].keys.map((dep) {
                        return FutureBuilder<String>(
                          future: getLatestVersion(dep),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return ListTile(
                                title: Text(dep),
                                subtitle:
                                    const Text('Fetching latest version...'),
                              );
                            } else {
                              return ListTile(
                                title: Text(dep),
                                subtitle: Text(
                                    'Current: ${dependencies[depType][dep]}, Latest: ${snapshot.data}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.refresh),
                                  onPressed: () {
                                    upgradeDependency(
                                        _selectedPackage!, dep, depType);
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
              ],
            )
          : const Center(child: Text('Select a package to view dependencies')),
    );
  }
}

class _PanelLayoutDelegate extends MultiChildLayoutDelegate {
  _PanelLayoutDelegate(this.dividerPosition);

  final double dividerPosition;

  @override
  void performLayout(Size size) {
    const dividerWidth = 8.0;
    final leftWidth = (size.width * dividerPosition).clamp(
      size.width * 0.1,
      size.width * 0.9,
    );

    layoutChild(
        'left', BoxConstraints.tightFor(width: leftWidth, height: size.height));
    positionChild('left', Offset.zero);

    layoutChild('divider',
        BoxConstraints.tightFor(width: dividerWidth, height: size.height));
    positionChild('divider', Offset(leftWidth, 0));

    final rightWidth = size.width - leftWidth - dividerWidth;
    layoutChild('right',
        BoxConstraints.tightFor(width: rightWidth, height: size.height));
    positionChild('right', Offset(leftWidth + dividerWidth, 0));
  }

  @override
  bool shouldRelayout(_PanelLayoutDelegate oldDelegate) {
    return dividerPosition != oldDelegate.dividerPosition;
  }
}
