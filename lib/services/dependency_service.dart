import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../models/dependency.dart';
import 'package_cache_service.dart';

class DependencyService {
  final PackageCacheService _cacheService = PackageCacheService();
  String? selectedDirectory;
  final _uuid = const Uuid();

  Future<Map<String, Map<String, Dependency>>> fetchLocalDependencies(
      String selectedDirectory, String packagePath) async {
    final fullPath = path.join(selectedDirectory, packagePath);
    final pubspecFile = File(path.join(fullPath, 'pubspec.yaml'));

    if (await pubspecFile.exists()) {
      final content = await pubspecFile.readAsString();
      final yamlMap = loadYaml(content);
      final dependencies = <String, Dependency>{};
      final devDependencies = <String, Dependency>{};
      final dependencyOverrides = <String, Dependency>{};

      void addDependency(String name, dynamic value, String type,
          Map<String, Dependency> targetMap) {
        final versionInfo = _parseVersionInfo(value);
        targetMap[name] = Dependency(
          id: _uuid.v4(),
          name: name,
          currentVersion: versionInfo.version,
          latestVersion: versionInfo.isVersioned ? 'Loading...' : 'N/A',
          type: type,
          isVersioned: versionInfo.isVersioned,
          isSdk: type == 'sdk',
        );
      }

      // Add Dart SDK dependency
      final dartSdkVersion = yamlMap['environment']?['sdk'];
      if (dartSdkVersion != null) {
        addDependency('Dart SDK', dartSdkVersion, 'sdk', dependencies);
      }

      // Add Flutter SDK dependency
      final flutterSdkVersion = yamlMap['dependencies']?['flutter']?['sdk'];
      if (flutterSdkVersion != null) {
        addDependency('Flutter SDK', flutterSdkVersion, 'sdk', dependencies);
      }

      void addDependencies(String type, Map<dynamic, dynamic> deps,
          Map<String, Dependency> targetMap) {
        deps.forEach((key, value) {
          if (key != 'flutter' || type != 'dependencies') {
            addDependency(key.toString(), value, type, targetMap);
          }
        });
      }

      addDependencies(
          'dependencies', yamlMap['dependencies'] ?? {}, dependencies);
      addDependencies('dev_dependencies', yamlMap['dev_dependencies'] ?? {},
          devDependencies);
      addDependencies('dependency_overrides',
          yamlMap['dependency_overrides'] ?? {}, dependencyOverrides);

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
      Map<String, Map<String, Dependency>> dependencies) async* {
    for (final depMap in dependencies.values) {
      for (final dep in depMap.values) {
        if (dep.isVersioned) {
          final latestVersion = await getLatestVersion(dep.name, dep.isSdk);
          yield dep.copyWith(latestVersion: latestVersion);
        } else {
          yield dep;
        }
      }
    }
  }

  Future<String> getLatestVersion(String packageName, bool isSdk) async {
    if (isSdk) {
      if (packageName == 'Dart SDK') {
        return await _getLatestDartSdkVersion();
      } else if (packageName == 'Flutter SDK') {
        return await _getLatestFlutterSdkVersion();
      }
    }

    final cachedVersion = await _cacheService.getCachedVersion(packageName);
    if (cachedVersion != null) {
      return cachedVersion;
    }

    try {
      final response = await http
          .get(Uri.parse('https://pub.dev/api/packages/$packageName'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestVersion = data['latest']['version'];
        await _cacheService.cacheVersion(packageName, latestVersion);
        return latestVersion;
      }
    } catch (e) {
      print('Error fetching latest version for $packageName: $e');
    }
    return 'Unknown';
  }

  Future<String> _getLatestDartSdkVersion() async {
    try {
      final response = await http.get(Uri.parse(
          'https://api.github.com/repos/dart-lang/sdk/releases/latest'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['tag_name'].replaceAll('v', '');
      }
    } catch (e) {
      print('Error fetching latest Dart SDK version: $e');
    }
    return 'Unknown';
  }

  Future<String> _getLatestFlutterSdkVersion() async {
    try {
      final response = await http.get(Uri.parse(
          'https://api.github.com/repos/flutter/flutter/releases/latest'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['tag_name'].replaceAll('v', '');
      }
    } catch (e) {
      print('Error fetching latest Flutter SDK version: $e');
    }
    return 'Unknown';
  }

  Future<void> upgradeDependency(String selectedDirectory, String packagePath,
      String packageName, String dependencyType) async {
    final fullPath = path.join(selectedDirectory, packagePath);
    final pubspecFile = File(path.join(fullPath, 'pubspec.yaml'));

    if (await pubspecFile.exists()) {
      final content = await pubspecFile.readAsString();
      final editor = YamlEditor(content);

      if (packageName == 'Dart SDK') {
        final latestVersion = await _getLatestDartSdkVersion();
        if (latestVersion != 'Unknown') {
          editor.update(['environment', 'sdk'], '^$latestVersion');
        }
      } else if (packageName == 'Flutter SDK') {
        final latestVersion = await _getLatestFlutterSdkVersion();
        if (latestVersion != 'Unknown') {
          editor.update(['dependencies', 'flutter', 'sdk'], 'flutter');
        }
      } else {
        final currentValue = editor.parseAt([dependencyType, packageName]);
        if (_isVersionedDependency(currentValue)) {
          final latestVersion = await getLatestVersion(packageName, false);
          if (latestVersion != 'Unknown') {
            editor.update([dependencyType, packageName], '^$latestVersion');
          } else {
            throw Exception('Unable to fetch latest version for $packageName');
          }
        } else {
          throw Exception(
              'Cannot upgrade non-versioned dependency: $packageName');
        }
      }

      await pubspecFile.writeAsString(editor.toString());
    } else {
      throw Exception('pubspec.yaml not found at path: ${pubspecFile.path}');
    }
  }

  Future<void> upgradeAllDependencies(
      String selectedDirectory, String packagePath) async {
    final fullPath = path.join(selectedDirectory, packagePath);
    final pubspecFile = File(path.join(fullPath, 'pubspec.yaml'));
    if (await pubspecFile.exists()) {
      final content = await pubspecFile.readAsString();
      final editor = YamlEditor(content);

      final dependencies =
          await fetchLocalDependencies(selectedDirectory, packagePath);
      for (var depMap in dependencies.values) {
        for (var dep in depMap.values) {
          if (dep.isVersioned && !dep.isSdk) {
            final latestVersion = await getLatestVersion(dep.name, dep.isSdk);
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

  Future<void> runPubGet(String selectedDirectory, String packagePath) async {
    final fullPath = path.join(selectedDirectory, packagePath);
    final result = await Process.run('flutter', ['pub', 'get'],
        workingDirectory: fullPath);

    if (result.exitCode != 0) {
      throw Exception(result.stderr);
    }
  }

  _VersionInfo _parseVersionInfo(dynamic value) {
    if (value is String) {
      return _VersionInfo(value, true);
    } else if (value is Map) {
      if (value.containsKey('sdk') ||
          value.containsKey('path') ||
          value.containsKey('git')) {
        return _VersionInfo(value.toString(), false);
      } else if (value.containsKey('version')) {
        return _VersionInfo(value['version'], true);
      }
    }
    return _VersionInfo('Unknown', false);
  }

  bool _isVersionedDependency(dynamic value) {
    return _parseVersionInfo(value).isVersioned;
  }

  Future<void> resolveConflicts(
      String packagePath, String conflictMessage) async {
    if (selectedDirectory == null) {
      throw Exception('No directory selected');
    }

    final fullPath = path.join(selectedDirectory!, packagePath);
    final pubspecFile = File(path.join(fullPath, 'pubspec.yaml'));

    if (await pubspecFile.exists()) {
      final content = await pubspecFile.readAsString();
      final yamlEditor = YamlEditor(content);

      // Parse the conflict message to identify conflicting packages
      final conflictingPackages = _parseConflictMessage(conflictMessage);

      // Add conflicting packages to dependency_overrides
      for (final package in conflictingPackages) {
        yamlEditor
            .update(['dependency_overrides', package.name], package.version);
      }

      // Write the updated pubspec.yaml
      await pubspecFile.writeAsString(yamlEditor.toString());
    } else {
      throw Exception('pubspec.yaml not found at path: ${pubspecFile.path}');
    }
  }

  List<ConflictingPackage> _parseConflictMessage(String message) {
    final conflictingPackages = <ConflictingPackage>[];
    final lines = message.split('\n');

    for (final line in lines) {
      // Look for lines that contain package versions, ignoring the word "version" if present
      final match = RegExp(r'(\w+)(?:\s+version)?:\s+(\^?\d+\.\d+\.\d+)')
          .firstMatch(line);
      if (match != null) {
        final packageName = match.group(1)!;
        final version = match.group(2)!;
        conflictingPackages
            .add(ConflictingPackage(name: packageName, version: version));
      }
    }

    // If we couldn't find any conflicts, try to parse the error message
    if (conflictingPackages.isEmpty) {
      final errorMatches =
          RegExp(r'(\w+) from (\w+) depends on (\w+) (\^?\d+\.\d+\.\d+)')
              .allMatches(message);
      for (final match in errorMatches) {
        final packageName = match.group(3)!;
        final version = match.group(4)!;
        conflictingPackages
            .add(ConflictingPackage(name: packageName, version: version));
      }
    }

    return conflictingPackages;
  }

  Future<String> getPubspecContent(String packagePath) async {
    if (selectedDirectory == null) {
      throw Exception('No directory selected');
    }

    final fullPath = path.join(selectedDirectory!, packagePath);
    final pubspecFile = File(path.join(fullPath, 'pubspec.yaml'));

    if (await pubspecFile.exists()) {
      return await pubspecFile.readAsString();
    } else {
      throw Exception('pubspec.yaml not found at path: ${pubspecFile.path}');
    }
  }
}

class ConflictingPackage {
  final String name;
  final String version;

  ConflictingPackage({required this.name, required this.version});
}

class _VersionInfo {
  final String version;
  final bool isVersioned;

  _VersionInfo(this.version, this.isVersioned);
}
