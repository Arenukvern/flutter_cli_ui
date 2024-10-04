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

  Future<Map<String, dynamic>> fetchDependencies(
      String selectedDirectory, String packagePath) async {
    final fullPath = path.join(selectedDirectory, packagePath);
    final pubspecFile = File(path.join(fullPath, 'pubspec.yaml'));

    if (await pubspecFile.exists()) {
      final content = await pubspecFile.readAsString();
      final yamlMap = loadYaml(content);
      return {
        'dependencies': yamlMap['dependencies'] ?? {},
        'dev_dependencies': yamlMap['dev_dependencies'] ?? {},
        'dependency_overrides': yamlMap['dependency_overrides'] ?? {},
      };
    } else {
      throw Exception('pubspec.yaml not found at path: ${pubspecFile.path}');
    }
  }

  Future<String> getLatestVersion(String packageName) async {
    final cachedVersion = await _cacheService.getCachedVersion(packageName);
    if (cachedVersion != null) {
      return cachedVersion;
    }

    final response =
        await http.get(Uri.parse('https://pub.dev/api/packages/$packageName'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final latestVersion = data['latest']['version'];
      await _cacheService.cacheVersion(packageName, latestVersion);
      return latestVersion;
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

      final latestVersion = await getLatestVersion(packageName);
      if (latestVersion != 'Unknown') {
        editor.update([dependencyType, packageName], '^$latestVersion');
        await pubspecFile.writeAsString(editor.toString());
      } else {
        throw Exception('Unable to fetch latest version for $packageName');
      }
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
          await fetchDependencies(selectedDirectory, packagePath);
      for (var dependencyType in [
        'dependencies',
        'dev_dependencies',
        'dependency_overrides'
      ]) {
        if (dependencies[dependencyType] != null) {
          for (var packageName in dependencies[dependencyType].keys) {
            final latestVersion = await getLatestVersion(packageName);
            if (latestVersion != 'Unknown') {
              editor.update([dependencyType, packageName], '^$latestVersion');
            }
          }
        }
      }

      await pubspecFile.writeAsString(editor.toString());
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

  Stream<Dependency> fetchDependenciesStream(
      String selectedDirectory, String packagePath) async* {
    final deps = await fetchDependencies(selectedDirectory, packagePath);
    for (final depType in deps.keys) {
      for (final entry in deps[depType].entries) {
        yield Dependency(
          name: entry.key,
          currentVersion: entry.value.toString(),
          latestVersion: 'Loading...',
          type: depType,
        );
        final latestVersion = await getLatestVersion(entry.key);
        yield Dependency(
          name: entry.key,
          currentVersion: entry.value.toString(),
          latestVersion: latestVersion,
          type: depType,
        );
      }
    }
  }
}
