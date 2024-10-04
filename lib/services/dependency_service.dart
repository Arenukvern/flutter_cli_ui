import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../models/dependency.dart';
import 'package_cache_service.dart';

class DependencyService {
  final PackageCacheService _cacheService = PackageCacheService();

  Future<List<Dependency>> fetchLocalDependencies(
      String selectedDirectory, String packagePath) async {
    final fullPath = path.join(selectedDirectory, packagePath);
    final pubspecFile = File(path.join(fullPath, 'pubspec.yaml'));

    if (await pubspecFile.exists()) {
      final content = await pubspecFile.readAsString();
      final yamlMap = loadYaml(content);
      final dependencies = <Dependency>[];

      // Add Dart SDK dependency
      final dartSdkVersion = yamlMap['environment']?['sdk'];
      if (dartSdkVersion != null) {
        dependencies.add(Dependency(
          name: 'Dart SDK',
          currentVersion: dartSdkVersion,
          latestVersion: 'Loading...',
          type: 'sdk',
          isVersioned: true,
          isSdk: true,
        ));
      }

      // Add Flutter SDK dependency
      final flutterSdkVersion = yamlMap['dependencies']?['flutter']?['sdk'];
      if (flutterSdkVersion != null) {
        dependencies.add(Dependency(
          name: 'Flutter SDK',
          currentVersion: flutterSdkVersion,
          latestVersion: 'Loading...',
          type: 'sdk',
          isVersioned: true,
          isSdk: true,
        ));
      }

      void addDependencies(String type, Map<dynamic, dynamic> deps) {
        deps.forEach((key, value) {
          if (key != 'flutter' || type != 'dependencies') {
            final versionInfo = _parseVersionInfo(value);
            dependencies.add(Dependency(
              name: key.toString(),
              currentVersion: versionInfo.version,
              latestVersion: versionInfo.isVersioned ? 'Loading...' : 'N/A',
              type: type,
              isVersioned: versionInfo.isVersioned,
            ));
          }
        });
      }

      addDependencies('dependencies', yamlMap['dependencies'] ?? {});
      addDependencies('dev_dependencies', yamlMap['dev_dependencies'] ?? {});
      addDependencies(
          'dependency_overrides', yamlMap['dependency_overrides'] ?? {});

      return dependencies;
    } else {
      throw Exception('pubspec.yaml not found at path: ${pubspecFile.path}');
    }
  }

  Stream<Dependency> fetchLatestVersions(List<Dependency> dependencies) async* {
    for (final dep in dependencies) {
      if (dep.isVersioned) {
        final latestVersion = await getLatestVersion(dep.name, dep.isSdk);
        yield dep.copyWith(latestVersion: latestVersion);
      } else {
        yield dep;
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
      for (var dep in dependencies) {
        if (dep.isVersioned && !dep.isSdk) {
          final latestVersion = await getLatestVersion(dep.name, dep.isSdk);
          if (latestVersion != 'Unknown') {
            editor.update([dep.type, dep.name], '^$latestVersion');
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

  Future<void> upgradeAndResolveConflicts(
      String selectedDirectory, String packagePath) async {
    final fullPath = path.join(selectedDirectory, packagePath);
    final pubspecFile = File(path.join(fullPath, 'pubspec.yaml'));

    if (await pubspecFile.exists()) {
      // Step 1: Upgrade all dependencies to their latest versions
      await upgradeAllDependencies(selectedDirectory, packagePath);

      // Step 2: Try to run pub get
      try {
        await runPubGet(selectedDirectory, packagePath);
      } catch (e) {
        // Step 3: If pub get fails, parse the error message to identify conflicting packages
        final conflictingPackages = _parseConflictingPackages(e.toString());

        // Step 4: For each conflicting package, add it to dependency_overrides with a higher constraint
        final content = await pubspecFile.readAsString();
        final editor = YamlEditor(content);

        for (final package in conflictingPackages) {
          final latestVersion = await getLatestVersion(package, false);
          editor.update(['dependency_overrides', package], '^$latestVersion');
        }

        // Step 5: Write the updated pubspec.yaml
        await pubspecFile.writeAsString(editor.toString());

        // Step 6: Try to run pub get again
        await runPubGet(selectedDirectory, packagePath);
      }
    } else {
      throw Exception('pubspec.yaml not found at path: ${pubspecFile.path}');
    }
  }

  List<String> _parseConflictingPackages(String errorMessage) {
    // This is a simple implementation. You might need to adjust it based on the actual error message format.
    final regex = RegExp(r'Because (\w+) [^,]*, (\w+) ');
    final matches = regex.allMatches(errorMessage);
    final conflictingPackages =
        matches.expand((m) => [m.group(1), m.group(2)]).toSet().toList();
    return conflictingPackages.where((p) => p != null).cast<String>().toList();
  }
}

class _VersionInfo {
  final String version;
  final bool isVersioned;

  _VersionInfo(this.version, this.isVersioned);
}
