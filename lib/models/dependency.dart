// ignore_for_file: avoid_catches_without_on_clauses, lines_longer_than_80_chars

import 'package:pub_semver/pub_semver.dart';

/// Represents a single dependency in a Flutter package.
class Dependency {
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

  /// Checks if the dependency is outdated.
  bool get isOutdated {
    if (!isVersioned ||
        latestVersion == 'Unknown' ||
        latestVersion.startsWith('Loading') ||
        latestVersion.startsWith('flutter') ||
        currentVersion.startsWith('Loading') ||
        currentVersion.startsWith('flutter')) {
      return false;
    }
    try {
      // Extract the base version from constraint (remove ^, >=, etc.)
      final baseVersion = _extractBaseVersion(currentVersion);
      final current = Version.parse(baseVersion);
      final latest = Version.parse(latestVersion);
      return latest > current;
    } catch (e) {
      return false;
    }
  }

  /// Creates a copy of this dependency with the specified properties.
  Dependency copyWith({
    final String? name,
    final String? currentVersion,
    final String? latestVersion,
    final String? type,
    final bool? isVersioned,
    final bool? isSdk,
  }) => Dependency(
    id: id,
    name: name ?? this.name,
    currentVersion: currentVersion ?? this.currentVersion,
    latestVersion: latestVersion ?? this.latestVersion,
    type: type ?? this.type,
    isVersioned: isVersioned ?? this.isVersioned,
    isSdk: isSdk ?? this.isSdk,
  );
}

/// Extracts the base version from a version constraint string.
/// Removes constraint operators like ^, >=, >, <, <=, ~, etc.
String _extractBaseVersion(final String versionConstraint) {
  // Remove common constraint operators and keep only the version part
  final constraintOperators = ['^', '>=', '>', '<=', '<', '~', ' '];
  var baseVersion = versionConstraint;

  for (final operator in constraintOperators) {
    if (baseVersion.startsWith(operator)) {
      baseVersion = baseVersion.substring(operator.length);
      break; // Only remove the first matching operator
    }
  }

  return baseVersion.trim();
}
