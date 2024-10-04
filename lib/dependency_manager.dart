import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import 'models/dependency.dart';
import 'services/dependency_service.dart';
import 'services/file_service.dart';
import 'widgets/dependencies_view.dart';
import 'widgets/package_list.dart';
import 'widgets/upgrade_review_dialog.dart';

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
  final MethodChannel _channel =
      const MethodChannel('com.example.dependency_manager/permissions');
  bool _hasElevatedPermissions = false;
  String? _helperPath;

  Future<void> pickDirectory() async {
    final directory = await _fileService.pickDirectory();
    if (directory != null) {
      setState(() {
        selectedDirectory = directory;
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
    if (_helperPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Helper tool not initialized')),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final result = await Process.run(
        _helperPath!,
        ['pub', 'get'],
        workingDirectory: '$selectedDirectory/$packagePath',
      );

      if (result.exitCode == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully ran pub get')),
        );
      } else {
        throw Exception(result.stderr);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error running pub get: ${e.toString()}')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> upgradeAndResolveConflicts(String packagePath) async {
    setState(() {
      isLoading = true;
    });

    try {
      final result = await _dependencyService.upgradeAndResolveConflicts(
        selectedDirectory!,
        packagePath,
      );

      // Show the review dialog
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => UpgradeReviewDialog(
          changes: result['changes'] as Map<String, Map<String, String>>,
          messages: result['messages'] as List<String>,
        ),
      );

      if (approved == true) {
        // Apply changes if approved
        await fetchDependencies(packagePath);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dependencies upgraded successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upgrade cancelled')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error upgrading dependencies: ${e.toString()}')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _requestElevatedPermissions();
    _initializeHelperPath();
  }

  Future<void> _requestElevatedPermissions() async {
    try {
      final bool result =
          await _channel.invokeMethod('requestElevatedPermissions');
      setState(() {
        _hasElevatedPermissions = result;
      });
    } on PlatformException catch (e) {
      print("Failed to get permissions: '${e.message}'.");
    }
  }

  Future<void> _initializeHelperPath() async {
    try {
      final result = await const MethodChannel('flutter/platform')
          .invokeMethod<String>('getApplicationSupportDirectory');
      if (result != null) {
        _helperPath = path.join(result, 'FlutterHelper');
        // Copy the helper tool to the application support directory
        await _copyHelperTool();
      }
    } catch (e) {
      print('Failed to get application support directory: $e');
    }
  }

  Future<void> _copyHelperTool() async {
    final bundle = await rootBundle.load('assets/macos/FlutterHelper');
    final bytes = bundle.buffer.asUint8List();
    final file = File(_helperPath!);
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    await Process.run('chmod', ['+x', _helperPath!]);
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
                      child: const VerticalDivider(thickness: 1, width: 1),
                    ),
                  ),
                ),
                LayoutId(
                  id: 'right',
                  child: DependenciesView(
                    dependencies: dependencies,
                    selectedPackage: _selectedPackage,
                    isLoading: isLoading,
                    isFetchingLatestVersions: isFetchingLatestVersions,
                    onUpgradeAll: _selectedPackage != null
                        ? () => upgradeAllDependencies(_selectedPackage!)
                        : null,
                    onUpgradeDependency: (dependency) async {
                      if (_selectedPackage != null) {
                        await upgradeDependency(
                          _selectedPackage!,
                          dependency.name,
                          dependency.type,
                        );
                      }
                    },
                    onRunPubGet: _selectedPackage != null
                        ? () => runPubGet(_selectedPackage!)
                        : null,
                    onUpgradeAndResolveConflicts: _selectedPackage != null
                        ? () => upgradeAndResolveConflicts(_selectedPackage!)
                        : null,
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
