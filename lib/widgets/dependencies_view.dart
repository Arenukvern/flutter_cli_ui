// ignore_for_file: lines_longer_than_80_chars, use_build_context_synchronously, avoid_catches_without_on_clauses

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_cli_ui/models/dependency.dart';
import 'package:flutter_cli_ui/services/dependency_service.dart';
import 'package:flutter_cli_ui/widgets/ui_list_tile.dart';
import 'package:url_launcher/url_launcher.dart';

/// A widget that displays a list of dependencies for a Flutter package.
class DependenciesView extends StatelessWidget {
  const DependenciesView({
    required this.dependencies,
    required this.selectedPackage,
    required this.onUpgradeAll,
    required this.onRunPubGet,
    required this.onUpgradeDependency,
    required this.isLoading,
    required this.isFetchingLatestVersions,
    required this.onResolveConflicts,
    required this.dependencyService,
    super.key,
  });

  /// The list of dependencies to display.
  final Map<String, Map<String, Dependency>> dependencies;

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

  /// Callback function to resolve conflicts.
  final Future<void> Function(String) onResolveConflicts;

  /// The DependencyService instance.
  final DependencyService dependencyService;

  /// Sorts the dependencies by outdated status and name.
  List<Dependency> _sortDependencies() {
    final allDependencies = [
      ...dependencies['dependencies']!.values,
      ...dependencies['dev_dependencies']!.values,
      ...dependencies['dependency_overrides']!.values,
    ];
    return allDependencies..sort((final a, final b) {
      if (a.isOutdated && !b.isOutdated) return -1;
      if (!a.isOutdated && b.isOutdated) return 1;
      return a.name.compareTo(b.name);
    });
  }

  @override
  Widget build(final BuildContext context) {
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
          padding: const EdgeInsets.all(8),
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
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () => _showConflictDialog(context),
                    child: const Text('Resolve Conflicts'),
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
              _buildDependencySection(
                'dependencies',
                dependencies['dependencies']!,
              ),
              _buildDependencySection(
                'dev_dependencies',
                dependencies['dev_dependencies']!,
              ),
              _buildDependencySection(
                'dependency_overrides',
                dependencies['dependency_overrides']!,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSdkSection(final List<Dependency> sortedDependencies) {
    final sdkDependencies = sortedDependencies
        .where((final dep) => dep.isSdk)
        .toList();
    if (sdkDependencies.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(8),
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
    final String sectionTitle,
    final Map<String, Dependency> dependencies,
  ) {
    final sectionDependencies = dependencies.values.toList();

    if (sectionDependencies.isEmpty) {
      return const SizedBox.shrink();
    }

    return ExpansionTile(
      key: ValueKey('section_$sectionTitle'),
      title: Text(sectionTitle),
      initiallyExpanded: true,
      children: sectionDependencies.map(_buildDependencyTile).toList(),
    );
  }

  Widget _buildDependencyTile(final Dependency dep) {
    final uniqueKey = '${dep.type}_${dep.name}_${dep.id}';
    return UiListTile(
      key: ValueKey(uniqueKey),
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
                unawaited(
                  launchUrl(Uri.parse('https://pub.dev/packages/${dep.name}')),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _showConflictDialog(final BuildContext context) async {
    final TextEditingController conflictController = TextEditingController();
    bool showHelp = false;

    await showDialog(
      context: context,
      builder: (final context) => StatefulBuilder(
        builder: (final context, final setState) => AlertDialog(
          title: const Text('Resolve Conflicts'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Paste the conflict message from pub get:'),
                  IconButton(
                    icon: Icon(showHelp ? Icons.help : Icons.help_outline),
                    onPressed: () {
                      setState(() {
                        showHelp = !showHelp;
                      });
                    },
                  ),
                ],
              ),
              if (showHelp)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '1. Run "flutter pub get" in your terminal.\n'
                    '2. If there are conflicts, copy the error message.\n'
                    '3. Paste the message in the text field below.\n'
                    '4. Click "Resolve" to automatically update your pubspec.yaml.\n'
                    '5. Run "flutter pub get" again to apply the changes.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: conflictController,
                maxLines: 5,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                unawaited(_resolveConflicts(context, conflictController.text));
              },
              child: const Text('Resolve'),
            ),
          ],
        ),
      ),
    );
    conflictController.dispose();
  }

  Future<void> _resolveConflicts(
    final BuildContext context,
    final String conflictMessage,
  ) async {
    if (selectedPackage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a package first')),
      );
      return;
    }

    if (conflictMessage.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a conflict message')),
      );
      return;
    }

    try {
      await onResolveConflicts(conflictMessage);

      // Show an animated success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Conflicts resolved. Please run pub get again.',
          ).animate().fadeIn(duration: 300.ms),
          action: SnackBarAction(
            label: 'Copy pubspec.yaml',
            onPressed: () async {
              final pubspecContent = await dependencyService.getPubspecContent(
                selectedPackage!,
              );
              await Clipboard.setData(ClipboardData(text: pubspecContent));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('pubspec.yaml copied to clipboard'),
                ),
              );
            },
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error resolving conflicts: $e')));
    }
  }
}
