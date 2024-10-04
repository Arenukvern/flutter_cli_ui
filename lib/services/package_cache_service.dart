import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PackageCacheService {
  static const String _cacheKey = 'package_versions_cache';

  Future<String?> getCachedVersion(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheString = prefs.getString(_cacheKey);
    if (cacheString != null) {
      final cache = json.decode(cacheString) as Map<String, dynamic>;
      final cachedPackage = cache[packageName];
      if (cachedPackage != null) {
        final cacheTime = DateTime.parse(cachedPackage['time']);
        if (DateTime.now().difference(cacheTime).inDays < 1) {
          return cachedPackage['version'];
        }
      }
    }
    return null;
  }

  Future<void> cacheVersion(String packageName, String version) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheString = prefs.getString(_cacheKey);
    final cache = cacheString != null
        ? json.decode(cacheString) as Map<String, dynamic>
        : <String, dynamic>{};
    cache[packageName] = {
      'version': version,
      'time': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_cacheKey, json.encode(cache));
  }
}
