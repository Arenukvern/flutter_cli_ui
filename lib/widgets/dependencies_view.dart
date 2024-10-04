import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/dependency.dart';
import 'ui_list_tile.dart';

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

  /// Callback function to upgrade and resolve conflicts.
  final VoidCallback onUpgradeAndResolveConflicts;

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
    required this.onUpgradeAndResolveConflicts,
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

    final sortedDependencies = _sortDependencies();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dependencies for $selectedPackage',
                style: Theme.of(context).textTheme.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: onUpgradeAll,
                    child: const Text('Upgrade All'),
                  ),
                  ElevatedButton(
                    onPressed: onRunPubGet,
                    child: const Text('Run pub get'),
                  ),
                  ElevatedButton(
                    onPressed: onUpgradeAndResolveConflicts,
                    child: const Text('Upgrade and Resolve Conflicts'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              _buildSdkSection(sortedDependencies),
              _buildDependencySection('dependencies', sortedDependencies),
              _buildDependencySection('dev_dependencies', sortedDependencies),
              _buildDependencySection(
                  'dependency_overrides', sortedDependencies),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSdkSection(List<Dependency> sortedDependencies) {
    final sdkDependencies =
        sortedDependencies.where((dep) => dep.isSdk).toList();
    if (sdkDependencies.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            'SDK Versions:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        ...sdkDependencies.map(_buildDependencyTile),
      ],
    );
  }

  Widget _buildDependencySection(
      String depType, List<Dependency> sortedDependencies) {
    final deps = sortedDependencies
        .where((dep) => dep.type == depType && !dep.isSdk)
        .toList();
    if (deps.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            '$depType:',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        ...deps.map(_buildDependencyTile),
      ],
    );
  }

  Widget _buildDependencyTile(Dependency dep) {
    return UiListTile(
      title: dep.name,
      subtitle: 'Current: ${dep.currentVersion}, Latest: ${dep.latestVersion}',
      isOutdated: dep.isOutdated,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dep.latestVersion == 'Loading...')
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (dep.isVersioned)
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: () => onUpgradeDependency(dep.name, dep.type),
            ),
          if (!dep.isSdk)
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () {
                launchUrl(Uri.parse('https://pub.dev/packages/${dep.name}'));
              },
            ),
        ],
      ),
    );
  }
}
