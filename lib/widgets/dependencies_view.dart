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
    return Card(
      margin: const EdgeInsets.all(8),
      child: isLoading
          ? const Center(child: CircularProgressIndicator())
          : dependencies.isNotEmpty
              ? ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed:
                                selectedPackage != null ? onUpgradeAll : null,
                            child: const Text('Upgrade All Dependencies'),
                          ),
                          ElevatedButton(
                            onPressed:
                                selectedPackage != null ? onRunPubGet : null,
                            child: const Text('Run pub get'),
                          ),
                        ],
                      ),
                    ),
                    if (isFetchingLatestVersions)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('Fetching latest versions...'),
                      ),
                    ..._buildDependencyLists(),
                  ],
                )
              : const Center(
                  child: Text('Select a package to view dependencies')),
    );
  }

  /// Builds the list of dependencies grouped by type.
  List<Widget> _buildDependencyLists() {
    final groupedDependencies = <String, List<Dependency>>{};
    for (final dep in dependencies) {
      groupedDependencies.putIfAbsent(dep.type, () => []).add(dep);
    }

    return groupedDependencies.entries.map((entry) {
      final depType = entry.key;
      final deps = entry.value;
      if (deps.isEmpty) return Container();

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
          ..._sortDependencies()
              .where((dep) => dep.type == depType)
              .map(_buildDependencyTile),
        ],
      );
    }).toList();
  }

  /// Builds a [ListTile] for a single dependency.
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
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => onUpgradeDependency(dep.name, dep.type),
            ),
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
