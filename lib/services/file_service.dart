import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

class FileService {
  Future<String?> pickDirectory() async {
    return await FilePicker.platform.getDirectoryPath();
  }

  Future<List<String>> scanFlutterPackages(String directory) async {
    List<String> flutterPackages = [];
    final dir = Directory(directory);
    final list = dir.listSync(recursive: true, followLinks: false);
    for (var entity in list) {
      if (entity is File &&
          entity.path.endsWith('pubspec.yaml') &&
          !(entity.statSync().type == FileSystemEntityType.link)) {
        final relativePath = path.relative(entity.parent.path, from: directory);
        flutterPackages.add(relativePath);
      }
    }
    return flutterPackages;
  }
}
