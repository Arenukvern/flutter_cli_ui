import 'dart:async';

import 'package:flutter/material.dart';

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
  Map<String, Map<String, Dependency>> dependencies = {
    'dependencies': {},
    'dev_dependencies': {},
    'dependency_overrides': {},
  };
  bool isLoading = false;
  bool isFetchingLatestVersions = false;
  double _dividerPosition = 0.5;
  String? _selectedPackage;
  StreamSubscription<Dependency>? _dependencySubscription;

  Future<void> pickDirectory() async {
    final directory = await _fileService.pickDirectory();
    if (directory != null) {
      setState(() {
        selectedDirectory = directory;
        _dependencyService.selectedDirectory = directory;
        flutterPackages = [];
        dependencies = {
          'dependencies': {},
          'dev_dependencies': {},
          'dependency_overrides': {},
        };
        _selectedPackage = null;
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
      dependencies = {
        'dependencies': {},
        'dev_dependencies': {},
        'dependency_overrides': {},
      };
    });

    try {
      final localDeps = await _dependencyService.fetchLocalDependencies(
          selectedDirectory!, packagePath);
      setState(() {
        dependencies = localDeps;
        isLoading = false;
        isFetchingLatestVersions = true;
      });

      _dependencySubscription?.cancel();
      _dependencySubscription =
          _dependencyService.fetchLatestVersions(dependencies).listen(
        (updatedDep) {
          setState(() {
            dependencies[updatedDep.type]![updatedDep.name] = updatedDep;
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
      String packageName, String dependencyType) async {
    if (_selectedPackage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a package first')),
      );
      return;
    }

    try {
      await _dependencyService.upgradeDependency(
          selectedDirectory!, _selectedPackage!, packageName, dependencyType);
      await fetchDependencies(_selectedPackage!);
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

  Future<void> _resolveConflicts(String conflictMessage) async {
    if (_selectedPackage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a package first')),
      );
      return;
    }

    try {
      await _dependencyService.resolveConflicts(
          _selectedPackage!, conflictMessage);
      await fetchDependencies(_selectedPackage!);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Conflicts resolved. Please run pub get again.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error resolving conflicts: ${e.toString()}')),
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
            padding: const EdgeInsets.all(8.0),
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
                    onUpgradeAll: () => _selectedPackage != null
                        ? upgradeAllDependencies(_selectedPackage!)
                        : null,
                    onRunPubGet: () => _selectedPackage != null
                        ? runPubGet(_selectedPackage!)
                        : null,
                    onUpgradeDependency: upgradeDependency,
                    isLoading: isLoading,
                    isFetchingLatestVersions: isFetchingLatestVersions,
                    onResolveConflicts: _resolveConflicts,
                    dependencyService: _dependencyService,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
