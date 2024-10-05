import 'package:pub_semver/pub_semver.dart';

/// Represents a single dependency in a Flutter package.
class Dependency {
  final String id;
  final String name;

  /// The current version of the dependency.
  final String currentVersion;

  /// The latest available version of the dependency.
  final String latestVersion;

  /// The type of dependency (e.g., 'dependencies', 'dev_dependencies', 'dependency_overrides').
  final String type;

  /// Whether the dependency is versioned or not.
  final bool isVersioned;

  /// Whether the dependency is an SDK or not.
  final bool isSdk;

  /// Constructs a [Dependency] instance.
  const Dependency({
    required this.id,
    required this.name,
    required this.currentVersion,
    required this.latestVersion,
    required this.type,
    required this.isVersioned,
    this.isSdk = false,
  });

  /// Checks if the dependency is outdated.
  bool get isOutdated {
    if (!isVersioned || latestVersion == 'Unknown') return false;
    try {
      final current = VersionConstraint.parse(currentVersion);
      final latest = Version.parse(latestVersion);
      return !current.allows(latest);
    } catch (e) {
      return false;
    }
  }

  /// Creates a copy of this dependency with the specified properties.
  Dependency copyWith({
    String? name,
    String? currentVersion,
    String? latestVersion,
    String? type,
    bool? isVersioned,
    bool? isSdk,
  }) {
    return Dependency(
      id: id,
      name: name ?? this.name,
      currentVersion: currentVersion ?? this.currentVersion,
      latestVersion: latestVersion ?? this.latestVersion,
      type: type ?? this.type,
      isVersioned: isVersioned ?? this.isVersioned,
      isSdk: isSdk ?? this.isSdk,
    );
  }
}
