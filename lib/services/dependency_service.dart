import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DependencyService {
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

  Future<Map<String, String>> fetchLatestVersions(
      Map<String, dynamic> dependencies) async {
    Map<String, String> latestVersions = {};
    for (var depType in dependencies.keys) {
      for (var dep in dependencies[depType].keys) {
        latestVersions[dep] = await getLatestVersion(dep);
      }
    }
    return latestVersions;
  }

  Future<String> getLatestVersion(String packageName) async {
    final response =
        await http.get(Uri.parse('https://pub.dev/api/packages/$packageName'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['latest']['version'];
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
}
