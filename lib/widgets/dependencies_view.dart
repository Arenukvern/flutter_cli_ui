import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/dependency.dart';

/// A widget that displays a list of dependencies for a Flutter package.
class DependenciesView extends StatelessWidget {
  /// The list of dependencies to display.
  final List<Dependency> dependencies;

  /// The currently selected package.
  final String? selectedPackage;

  /// Callback function to upgrade all dependencies.
  final VoidCallback onUpgradeAll;

  /// Callback function to run 'pub get'.
  final VoidCallback onRunPubGet;

  /// Callback function to upgrade a single dependency.
  final Function(String, String) onUpgradeDependency;

  /// Whether the dependencies are currently being loaded.
  final bool isLoading;

  /// Whether the latest versions are currently being fetched.
  final bool isFetchingLatestVersions;

  /// Constructs a [DependenciesView] widget.
  const DependenciesView({
    super.key,
    required this.dependencies,
    required this.selectedPackage,
    required this.onUpgradeAll,
    required this.onRunPubGet,
    required this.onUpgradeDependency,
    required this.isLoading,
    required this.isFetchingLatestVersions,
  });

  /// Sorts the dependencies by outdated status and name.
  List<Dependency> _sortDependencies() {
    return List<Dependency>.from(dependencies)
      ..sort((a, b) {
        if (a.isOutdated && !b.isOutdated) return -1;
        if (!a.isOutdated && b.isOutdated) return 1;
        return a.name.compareTo(b.name);
      });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (dependencies.isEmpty) {
      return const Center(child: Text('No dependencies found.'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Dependencies for $selectedPackage',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: onUpgradeAll,
                    child: const Text('Upgrade All'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: onRunPubGet,
                    child: const Text('Run pub get'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              _buildSdkSection(),
              _buildDependencySection('dependencies'),
              _buildDependencySection('dev_dependencies'),
              _buildDependencySection('dependency_overrides'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSdkSection() {
    final sdkDependencies = dependencies.where((dep) => dep.isSdk).toList();
    if (sdkDependencies.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            'SDK Versions:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        ...sdkDependencies.map(_buildDependencyTile),
      ],
    );
  }

  Widget _buildDependencySection(String depType) {
    final deps =
        dependencies.where((dep) => dep.type == depType && !dep.isSdk).toList();
    if (deps.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            '$depType:',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        ...deps.map(_buildDependencyTile),
      ],
    );
  }

  Widget _buildDependencyTile(Dependency dep) {
    return ListTile(
      title: Text(dep.name),
      subtitle: Text(
        'Current: ${dep.currentVersion}, Latest: ${dep.latestVersion}',
        style: TextStyle(
          color: dep.isOutdated ? Colors.red : null,
          fontWeight: dep.isOutdated ? FontWeight.bold : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dep.latestVersion == 'Loading...')
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (dep.isVersioned)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => onUpgradeDependency(dep.name, dep.type),
            ),
          if (!dep.isSdk)
            IconButton(
              icon: const Icon(Icons.open_in_new),
              onPressed: () {
                launchUrl(Uri.parse('https://pub.dev/packages/${dep.name}'));
              },
            ),
        ],
      ),
    );
  }
}
