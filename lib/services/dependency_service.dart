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

      void addDependencies(String type, Map<dynamic, dynamic> deps) {
        deps.forEach((key, value) {
          dependencies.add(Dependency(
            name: key.toString(),
            currentVersion: value is String
                ? value
                : value['version']?.toString() ?? 'Unknown',
            latestVersion: 'Loading...',
            type: type,
          ));
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
      final latestVersion = await getLatestVersion(dep.name);
      yield dep.copyWith(latestVersion: latestVersion);
    }
  }

  Future<String> getLatestVersion(String packageName) async {
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
          await fetchLocalDependencies(selectedDirectory, packagePath);
      for (var dep in dependencies) {
        final latestVersion = await getLatestVersion(dep.name);
        if (latestVersion != 'Unknown') {
          editor.update([dep.type, dep.name], '^$latestVersion');
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
}
