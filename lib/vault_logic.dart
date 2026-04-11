import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'database_helper.dart';

class VaultLogic {
  static const String hiddenFolderName = '.sys_data';
  static const List<String> excludedExtensions = [
    '.lnk',
    '.url',
  ];

  static Future<void> lockEverything({
    required String rootPath,
    required String appDirPath,
  }) async {
    final rootDir = Directory(rootPath);
    final appDir = Directory(appDirPath);
    final hiddenDir = Directory(
      p.join(appDir.path, hiddenFolderName),
    );

    final String ownExecutablePath = p.canonicalize(Platform.resolvedExecutable);

    if (!await hiddenDir.exists()) {
      await hiddenDir.create(recursive: true);
      await _hideDirectory(hiddenDir.path);
    }

    final entities = await rootDir.list(
      recursive: false,
      followLinks: false,
    ).toList();

    final appDirName = p.basename(appDir.path);
    final dbName = 'vault_index.db';

    for (final entity in entities) {
      final absolutePath = p.canonicalize(entity.path);
      final name = p.basename(entity.path);
      final ext = p.extension(entity.path).toLowerCase();

      if (name == appDirName ||
          name == hiddenFolderName ||
          name == dbName ||
          absolutePath == ownExecutablePath || 
          excludedExtensions.contains(ext)) {
        continue;
      }

      final fakeName = _generateRandomFakeName(
        isDirectory: entity is Directory,
      );

      final destination = p.join(
        hiddenDir.path,
        fakeName,
      );

      bool moved = false;

      try {
        int size = 0;
        final isDir = entity is Directory;

        if (entity is File) {
          size = await entity.length();
        }

        await entity.rename(destination);
        moved = true;

        await VaultDatabase.registerFile(
          VaultRecord(
            fakeName: fakeName,
            realName: name,
            relativePath: name,
            isDirectory: isDir,
            fileSize: size,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      } catch (e) {
        if (moved) {
          try {
            final rollbackPath = p.join(rootDir.path, name);

            if (entity is Directory) {
              await Directory(destination).rename(rollbackPath);
            } else {
              await File(destination).rename(rollbackPath);
            }
          } catch (_) {}
        }

        stderr.writeln('Lock error on $name: $e');
      }
    }
  }

  static Future<void> unlockEverything({
    required String rootPath,
    required String appDirPath,
    bool overwriteExisting = false,
  }) async {
    final rootDir = Directory(rootPath);
    final appDir = Directory(appDirPath);
    final hiddenDir = Directory(
      p.join(appDir.path, hiddenFolderName),
    );

    final files = await VaultDatabase.getFiles();

    for (final file in files) {
      final source = p.join(
        hiddenDir.path,
        file.fakeName,
      );

      final destination = p.join(
        rootDir.path,
        file.relativePath,
      );

      try {
        final exists = await File(source).exists() ||
            await Directory(source).exists();

        if (!exists) {
          stderr.writeln(
            'Missing hidden file: ${file.fakeName}',
          );
          continue;
        }

        final destExists = await File(destination).exists() ||
            await Directory(destination).exists();

        if (destExists && !overwriteExisting) {
          stderr.writeln(
            'Destination already exists: $destination',
          );
          continue;
        }

        final destDir = Directory(
          p.dirname(destination),
        );

        if (!await destDir.exists()) {
          await destDir.create(recursive: true);
        }

        if (file.isDirectory) {
          await Directory(source).rename(destination);
        } else {
          await File(source).rename(destination);
        }

        await VaultDatabase.removeFileByFakeName(
          file.fakeName,
        );
      } catch (e) {
        stderr.writeln(
          'Unlock error on ${file.realName}: $e',
        );
      }
    }
  }

  static String _generateRandomFakeName({
    required bool isDirectory,
  }) {
    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    final token = base64UrlEncode(bytes).replaceAll('=', '');

    return isDirectory ? 'dir_$token' : 'blob_$token';
  }

  static Future<void> _hideDirectory(String path) async {
    if (!Platform.isWindows) return;

    try {
      await Process.run(
        'attrib',
        ['+h', '+s', path],
      );
    } catch (_) {}
  }
}
