import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'models/dependency.dart';
import 'services/dependency_service.dart';
import 'services/file_service.dart';
import 'widgets/dependencies_view.dart';
import 'widgets/package_list.dart';

class DependencyManager extends StatefulWidget {
  const DependencyManager({super.key});

  @override
  _DependencyManagerState createState() => _DependencyManagerState();
}

class _DependencyManagerState extends State<DependencyManager> {
  final DependencyService _dependencyService = DependencyService();
  final FileService _fileService = FileService();
  String? selectedDirectory;
  List<String> flutterPackages = [];
  List<Dependency> dependencies = [];
  bool isLoading = false;
  bool isFetchingLatestVersions = false;
  double _dividerPosition = 0.5;
  String? _selectedPackage;
  StreamSubscription<Dependency>? _dependencySubscription;
  final TextEditingController _conflictController = TextEditingController();

  Future<void> pickDirectory() async {
    final directory = await _fileService.pickDirectory();
    if (directory != null) {
      setState(() {
        selectedDirectory = directory;
        _dependencyService.selectedDirectory = directory; // Add this line
        flutterPackages = [];
        dependencies = [];
      });
      await scanPackages();
    }
  }

  Future<void> scanPackages() async {
    setState(() {
      isLoading = true;
      flutterPackages = [];
    });

    try {
      final packages =
          await _fileService.scanFlutterPackages(selectedDirectory!);
      setState(() {
        flutterPackages = packages;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error scanning packages: ${e.toString()}')),
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
      dependencies = [];
    });

    try {
      // Fetch local dependencies
      final localDeps = await _dependencyService.fetchLocalDependencies(
          selectedDirectory!, packagePath);
      setState(() {
        dependencies = localDeps;
        isLoading = false;
        isFetchingLatestVersions = true;
      });

      // Fetch latest versions
      _dependencySubscription?.cancel();
      _dependencySubscription =
          _dependencyService.fetchLatestVersions(localDeps).listen(
        (updatedDep) {
          setState(() {
            final index =
                dependencies.indexWhere((d) => d.name == updatedDep.name);
            if (index != -1) {
              dependencies[index] = updatedDep;
            }
          });
        },
        onDone: () {
          setState(() {
            isFetchingLatestVersions = false;
          });
        },
        onError: (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error fetching latest versions: $error')),
          );
          setState(() {
            isFetchingLatestVersions = false;
          });
        },
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching dependencies: $error')),
      );
      setState(() {
        isLoading = false;
        isFetchingLatestVersions = false;
      });
    }
  }

  Future<void> upgradeDependency(
      String packagePath, String packageName, String dependencyType) async {
    try {
      await _dependencyService.upgradeDependency(
          selectedDirectory!, packagePath, packageName, dependencyType);
      await fetchDependencies(packagePath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully upgraded $packageName')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error upgrading $packageName: ${e.toString()}')),
      );
    }
  }

  Future<void> upgradeAllDependencies(String packagePath) async {
    try {
      await _dependencyService.upgradeAllDependencies(
          selectedDirectory!, packagePath);
      await fetchDependencies(packagePath);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Successfully upgraded all dependencies')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error upgrading dependencies: ${e.toString()}')),
      );
    }
  }

  Future<void> runPubGet(String packagePath) async {
    try {
      await _dependencyService.runPubGet(selectedDirectory!, packagePath);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Successfully ran pub get')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error running pub get: ${e.toString()}')),
      );
    }
  }

  @override
  void dispose() {
    _dependencySubscription?.cancel();
    super.dispose();
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
                  child: PackageList(
                    packages: flutterPackages,
                    isLoading: isLoading,
                    selectedPackage: _selectedPackage,
                    onPackageSelected: (package) {
                      setState(() {
                        _selectedPackage = package;
                      });
                      fetchDependencies(package);
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
                  ),
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
                  child: DependenciesView(
                    dependencies: dependencies,
                    selectedPackage: _selectedPackage,
                    onUpgradeAll: () =>
                        upgradeAllDependencies(_selectedPackage!),
                    onRunPubGet: () => runPubGet(_selectedPackage!),
                    onUpgradeDependency: (dep, depType) =>
                        upgradeDependency(_selectedPackage!, dep, depType),
                    isLoading: isLoading,
                    isFetchingLatestVersions: isFetchingLatestVersions,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('How to Resolve Conflicts'),
                    content: const Text(
                        '1. Run "flutter pub get" in your terminal.\n'
                        '2. If there are conflicts, copy the error message.\n'
                        '3. Click the "Resolve Conflicts" button and paste the message.\n'
                        '4. Click "Resolve" to automatically update your pubspec.yaml.\n'
                        '5. Run "flutter pub get" again to apply the changes.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Got it'),
                      ),
                    ],
                  );
                },
              );
            },
            heroTag: null,
            child: const Icon(Icons.help_outline),
          ),
          const SizedBox(width: 10),
          FloatingActionButton(
            onPressed: _showConflictDialog,
            tooltip: 'Resolve Conflicts',
            heroTag: null,
            child: const Icon(Icons.warning_amber_rounded),
          ),
        ],
      ),
    );
  }

  void _showConflictDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Resolve Conflicts'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Paste the conflict message from pub get:'),
              const SizedBox(height: 10),
              TextField(
                controller: _conflictController,
                maxLines: 5,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _resolveConflicts,
              child: const Text('Resolve'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _resolveConflicts() async {
    if (_selectedPackage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a package first')),
      );
      return;
    }

    final conflictMessage = _conflictController.text;
    if (conflictMessage.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a conflict message')),
      );
      return;
    }

    try {
      await _dependencyService.resolveConflicts(
          _selectedPackage!, conflictMessage);
      Navigator.pop(context);

      // Show an animated success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Conflicts resolved. Please run pub get again.')
              .animate()
              .fadeIn(duration: 300.ms),
          action: SnackBarAction(
            label: 'Copy pubspec.yaml',
            onPressed: () async {
              final pubspecContent =
                  await _dependencyService.getPubspecContent(_selectedPackage!);
              await Clipboard.setData(ClipboardData(text: pubspecContent));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('pubspec.yaml copied to clipboard')),
              );
            },
          ),
        ),
      );

      await fetchDependencies(_selectedPackage!);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error resolving conflicts: ${e.toString()}')),
      );
    }
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
