import 'package:pub_semver/pub_semver.dart';

/// Represents a single dependency in a Flutter package.
class Dependency {
  /// The name of the dependency.
  final String name;

  /// The current version of the dependency.
  final String currentVersion;

  /// The latest available version of the dependency.
  final String latestVersion;

  /// The type of dependency (e.g., 'dependencies', 'dev_dependencies', 'dependency_overrides').
  final String type;

  /// Constructs a [Dependency] instance.
  const Dependency({
    required this.name,
    required this.currentVersion,
    required this.latestVersion,
    required this.type,
  });

  /// Checks if the dependency is outdated.
  bool get isOutdated {
    try {
      final current = Version.parse(currentVersion.replaceAll('^', ''));
      final latest = Version.parse(latestVersion);
      return latest > current;
    } catch (e) {
      // If we can't parse the versions, we'll assume it's not outdated
      // This can happen with git dependencies or other non-standard version strings
      return false;
    }
  }

  /// Creates a copy of this dependency with the specified properties.
  Dependency copyWith({
    String? name,
    String? currentVersion,
    String? latestVersion,
    String? type,
  }) {
    return Dependency(
      name: name ?? this.name,
      currentVersion: currentVersion ?? this.currentVersion,
      latestVersion: latestVersion ?? this.latestVersion,
      type: type ?? this.type,
    );
  }
}
