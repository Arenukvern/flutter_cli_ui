// ignore_for_file: avoid_dynamic_calls, avoid_annotating_with_dynamic, lines_longer_than_80_chars, avoid_catches_without_on_clauses

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_cli_ui/models/dependency.dart';
import 'package:flutter_cli_ui/services/package_cache_service.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

class DependencyService {
  final PackageCacheService _cacheService = PackageCacheService();
  String? selectedDirectory;
  final _uuid = const Uuid();

  Future<Map<String, Map<String, Dependency>>> fetchLocalDependencies(
    final String selectedDirectory,
    final String packagePath,
  ) async {
    final fullPath = path.join(selectedDirectory, packagePath);
    final pubspecFile = File(path.join(fullPath, 'pubspec.yaml'));

    if (pubspecFile.existsSync()) {
      final content = await pubspecFile.readAsString();
      final yamlMap = loadYaml(content);
      final dependencies = <String, Dependency>{};
      final devDependencies = <String, Dependency>{};
      final dependencyOverrides = <String, Dependency>{};

      void addDependency(
        final String name,
        final value,
        final String type,
        final Map<String, Dependency> targetMap,
      ) {
        final versionInfo = _parseVersionInfo(value);
        final isSdkDep = type == 'sdk';
        targetMap[name] = Dependency(
          id: _uuid.v4(),
          name: name,
          currentVersion: versionInfo.version,
          latestVersion: isSdkDep
              ? 'N/A'
              : (versionInfo.isVersioned ? 'Loading...' : 'N/A'),
          type: type,
          isVersioned: !isSdkDep && versionInfo.isVersioned,
          isSdk: isSdkDep,
        );
      }

      // Add Dart SDK dependency
      final dartSdkVersion = yamlMap['environment']?['sdk'];
      if (dartSdkVersion != null) {
        addDependency('Dart SDK', dartSdkVersion, 'sdk', dependencies);
      }

      // Add Flutter SDK dependency
      final flutterSdkVersion = yamlMap['environment']?['flutter'];
      if (flutterSdkVersion != null) {
        addDependency('Flutter SDK', flutterSdkVersion, 'sdk', dependencies);
      }

      void addDependencies(
        final String type,
        final Map<dynamic, dynamic> deps,
        final Map<String, Dependency> targetMap,
      ) {
        deps.forEach((final key, final value) {
          if (key != 'flutter' || type != 'dependencies') {
            addDependency(key.toString(), value, type, targetMap);
          }
        });
      }

      addDependencies(
        'dependencies',
        yamlMap['dependencies'] ?? {},
        dependencies,
      );
      addDependencies(
        'dev_dependencies',
        yamlMap['dev_dependencies'] ?? {},
        devDependencies,
      );
      addDependencies(
        'dependency_overrides',
        yamlMap['dependency_overrides'] ?? {},
        dependencyOverrides,
      );

      return {
        'dependencies': dependencies,
        'dev_dependencies': devDependencies,
        'dependency_overrides': dependencyOverrides,
      };
    } else {
      throw Exception('pubspec.yaml not found at path: ${pubspecFile.path}');
    }
  }

  Stream<Dependency> fetchLatestVersions(
    final Map<String, Map<String, Dependency>> dependencies,
  ) async* {
    for (final depMap in {...dependencies}.values) {
      for (final dep in depMap.values) {
        if (dep.isVersioned && !dep.isSdk) {
          final latestVersion = await getLatestVersion(
            dep.name,
            isSdk: dep.isSdk,
          );
          yield dep.copyWith(latestVersion: latestVersion);
        } else {
          yield dep;
        }
      }
    }
  }

  Future<String> getLatestVersion(
    final String packageName, {
    required final bool isSdk,
  }) async {
    // SDK versions are not fetched
    if (isSdk) {
      return 'N/A';
    }

    final cachedVersion = await _cacheService.getCachedVersion(packageName);
    if (cachedVersion != null) {
      print('Using cached version for $packageName: $cachedVersion');
      return cachedVersion;
    }

    try {
      print('Fetching latest version for $packageName from pub.dev...');
      final response = await http
          .get(
            Uri.parse('https://pub.dev/api/packages/$packageName'),
            headers: {'Accept': 'application/vnd.pub.v2+json'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latest = data['latest'];
        if (latest != null && latest['version'] != null) {
          final latestVersion = latest['version'].toString();
          await _cacheService.cacheVersion(packageName, latestVersion);
          print('Fetched version for $packageName: $latestVersion');
          return latestVersion;
        }
      }
    } catch (e) {
      print('Error fetching latest version for $packageName: $e');
    }
    return 'Unknown';
  }

  Future<void> upgradeDependency(
    final String selectedDirectory,
    final String packagePath,
    final String packageName,
    final String dependencyType,
  ) async {
    final fullPath = path.join(selectedDirectory, packagePath);
    final pubspecFile = File(path.join(fullPath, 'pubspec.yaml'));

    if (pubspecFile.existsSync()) {
      final content = await pubspecFile.readAsString();
      final editor = YamlEditor(content);

      if (packageName == 'Dart SDK' || packageName == 'Flutter SDK') {
        throw Exception(
          'SDK versions cannot be upgraded through this interface. Please update your pubspec.yaml environment constraints manually.',
        );
      } else {
        final currentValue = editor.parseAt([dependencyType, packageName]);
        if (_isVersionedDependency(currentValue.value)) {
          final latestVersion = await getLatestVersion(
            packageName,
            isSdk: false,
          );
          if (latestVersion != 'Unknown') {
            editor.update([dependencyType, packageName], '^$latestVersion');
          } else {
            throw Exception('Unable to fetch latest version for $packageName');
          }
        } else {
          throw Exception(
            'Cannot upgrade non-versioned dependency: $packageName',
          );
        }
      }

      await pubspecFile.writeAsString(editor.toString());
    } else {
      throw Exception('pubspec.yaml not found at path: ${pubspecFile.path}');
    }
  }

  Future<void> upgradeAllDependencies(
    final String selectedDirectory,
    final String packagePath,
  ) async {
    final fullPath = path.join(selectedDirectory, packagePath);
    final pubspecFile = File(path.join(fullPath, 'pubspec.yaml'));
    if (pubspecFile.existsSync()) {
      final content = await pubspecFile.readAsString();
      final editor = YamlEditor(content);

      final dependencies = await fetchLocalDependencies(
        selectedDirectory,
        packagePath,
      );
      for (final depMap in dependencies.values) {
        for (final dep in depMap.values) {
          if (dep.isVersioned && !dep.isSdk) {
            final latestVersion = await getLatestVersion(
              dep.name,
              isSdk: dep.isSdk,
            );
            if (latestVersion != 'Unknown') {
              editor.update([dep.type, dep.name], '^$latestVersion');
            }
          }
        }
      }

      await pubspecFile.writeAsString(editor.toString());
    } else {
      throw Exception('pubspec.yaml not found at path: ${pubspecFile.path}');
    }
  }

  Future<void> runPubGet(
    final String selectedDirectory,
    final String packagePath,
  ) async {
    final fullPath = path.join(selectedDirectory, packagePath);
    final result = await Process.run('flutter', [
      'pub',
      'get',
    ], workingDirectory: fullPath);

    if (result.exitCode != 0) {
      throw Exception(result.stderr);
    }
  }

  _VersionInfo _parseVersionInfo(final dynamic value) {
    if (value is String) {
      return _VersionInfo(value, isVersioned: true);
    } else if (value is Map) {
      if (value.containsKey('sdk') ||
          value.containsKey('path') ||
          value.containsKey('git')) {
        return _VersionInfo(value.toString(), isVersioned: false);
      } else if (value.containsKey('version')) {
        return _VersionInfo(value['version'], isVersioned: true);
      }
    }
    return _VersionInfo('Unknown', isVersioned: false);
  }

  bool _isVersionedDependency(final dynamic value) =>
      _parseVersionInfo(value).isVersioned;

  Future<void> resolveConflicts(
    final String packagePath,
    final String conflictMessage,
  ) async {
    if (selectedDirectory == null) {
      throw Exception('No directory selected');
    }

    final fullPath = path.join(selectedDirectory!, packagePath);
    final pubspecFile = File(path.join(fullPath, 'pubspec.yaml'));

    if (pubspecFile.existsSync()) {
      final content = await pubspecFile.readAsString();
      final yamlEditor = YamlEditor(content);

      // Parse the conflict message to identify conflicting packages
      final conflictingPackages = _parseConflictMessage(conflictMessage);

      // Add conflicting packages to dependency_overrides
      for (final package in conflictingPackages) {
        yamlEditor.update([
          'dependency_overrides',
          package.name,
        ], package.version);
      }

      // Write the updated pubspec.yaml
      await pubspecFile.writeAsString(yamlEditor.toString());
    } else {
      throw Exception('pubspec.yaml not found at path: ${pubspecFile.path}');
    }
  }

  List<ConflictingPackage> _parseConflictMessage(final String message) {
    final conflictingPackages = <ConflictingPackage>[];
    final lines = message.split('\n');

    for (final line in lines) {
      // Look for lines that contain package versions, ignoring the word
      // "version" if present
      final match = RegExp(
        r'(\w+)(?:\s+version)?:\s+(\^?\d+\.\d+\.\d+)',
      ).firstMatch(line);
      if (match != null) {
        final packageName = match.group(1)!;
        final version = match.group(2)!;
        conflictingPackages.add(
          ConflictingPackage(name: packageName, version: version),
        );
      }
    }

    // If we couldn't find any conflicts, try to parse the error message
    if (conflictingPackages.isEmpty) {
      final errorMatches = RegExp(
        r'(\w+) from (\w+) depends on (\w+) (\^?\d+\.\d+\.\d+)',
      ).allMatches(message);
      for (final match in errorMatches) {
        final packageName = match.group(3)!;
        final version = match.group(4)!;
        conflictingPackages.add(
          ConflictingPackage(name: packageName, version: version),
        );
      }
    }

    return conflictingPackages;
  }

  Future<String> getPubspecContent(final String packagePath) {
    if (selectedDirectory == null) {
      throw Exception('No directory selected');
    }

    final fullPath = path.join(selectedDirectory!, packagePath);
    final pubspecFile = File(path.join(fullPath, 'pubspec.yaml'));

    if (pubspecFile.existsSync()) {
      return pubspecFile.readAsString();
    } else {
      throw Exception('pubspec.yaml not found at path: ${pubspecFile.path}');
    }
  }
}

class ConflictingPackage {
  ConflictingPackage({required this.name, required this.version});
  final String name;
  final String version;
}

class _VersionInfo {
  _VersionInfo(this.version, {required this.isVersioned});
  final String version;
  final bool isVersioned;
}
