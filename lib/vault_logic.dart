import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'database_helper.dart';

class VaultOperationResult {
  final int processed;
  final int succeeded;
  final int failed;
  final int skipped;
  final List<String> failedItems;
  final List<String> skippedItems;

  const VaultOperationResult({
    required this.processed,
    required this.succeeded,
    required this.failed,
    required this.skipped,
    required this.failedItems,
    required this.skippedItems,
  });
}

class VaultLogic {
  static const String hiddenFolderName = '.sys_data';

  static const List<String> excludedExtensions = [
    '.lnk',
    '.url',
    '.tmp',
    '.temp',
  ];

  static const List<String> excludedNames = [
    'System Volume Information',
    r'$RECYCLE.BIN',
    'desktop.ini',
    'thumbs.db',
    'autorun.inf',
  ];

  static Future<Map<String, int>> checkHealth({
    required String appDirPath,
  }) async {
    final files = await VaultDatabase.getFiles();
    final hiddenDir = Directory(p.join(appDirPath, hiddenFolderName));

    int healthy = 0;
    int missing = 0;
    int wrongType = 0;
    int sizeMismatch = 0;
    int readErrors = 0;
    int orphanedHiddenItems = 0;

    if (!await hiddenDir.exists()) {
      return {
        'healthy': 0,
        'missing': files.length,
        'wrongType': 0,
        'sizeMismatch': 0,
        'readErrors': 0,
        'orphanedHiddenItems': 0,
        'total': files.length,
      };
    }

    final indexedFakeNames = files.map((f) => f.fakeName).toSet();

    try {
      final physicalItems = await hiddenDir.list(
        recursive: false,
        followLinks: false,
      ).toList();

      for (final item in physicalItems) {
        final name = p.basename(item.path);
        if (!indexedFakeNames.contains(name)) {
          orphanedHiddenItems++;
        }
      }
    } catch (_) {
      readErrors++;
    }

    for (final file in files) {
      final itemPath = p.join(hiddenDir.path, file.fakeName);
      final fileRef = File(itemPath);
      final dirRef = Directory(itemPath);

      try {
        final fileExists = await fileRef.exists();
        final dirExists = await dirRef.exists();

        if (!fileExists && !dirExists) {
          missing++;
          continue;
        }

        if (file.isDirectory && !dirExists) {
          wrongType++;
          continue;
        }

        if (!file.isDirectory && !fileExists) {
          wrongType++;
          continue;
        }

        if (!file.isDirectory) {
          final currentSize = await fileRef.length();

          if (!file.isContentEncrypted && currentSize != file.fileSize) {
            sizeMismatch++;
            continue;
          }
        }

        healthy++;
      } catch (_) {
        readErrors++;
      }
    }

    return {
      'healthy': healthy,
      'missing': missing,
      'wrongType': wrongType,
      'sizeMismatch': sizeMismatch,
      'readErrors': readErrors,
      'orphanedHiddenItems': orphanedHiddenItems,
      'total': files.length,
    };
  }

  static Future<void> _validatePaths({
    required String rootPath,
    required String appDirPath,
  }) async {
    final rootDir = Directory(rootPath);
    final appDir = Directory(appDirPath);

    if (!await rootDir.exists()) {
      throw Exception('Root path does not exist: $rootPath');
    }

    if (!await appDir.exists()) {
      throw Exception('App directory does not exist: $appDirPath');
    }

    final normalizedRoot = p.normalize(p.absolute(rootDir.path));
    final normalizedApp = p.normalize(p.absolute(appDir.path));

    final appInsideRoot = p.isWithin(normalizedRoot, normalizedApp);
    final appIsDirectChild = p.dirname(normalizedApp) == normalizedRoot;

    if (!appInsideRoot && !appIsDirectChild) {
      throw Exception(
        'App directory is not located inside the selected root.',
      );
    }
  }

  static Future<bool> hasVaultContent() async {
    final files = await VaultDatabase.getFiles();
    return files.isNotEmpty;
  }

  static Future<bool> isVaultEmpty() async {
    final files = await VaultDatabase.getFiles();
    return files.isEmpty;
  }

  static Future<bool> isVaultLocked({
    required String appDirPath,
  }) async {
    final hiddenDir = Directory(p.join(appDirPath, hiddenFolderName));
    if (!await hiddenDir.exists()) return false;

    final files = await VaultDatabase.getFiles();
    return files.isNotEmpty;
  }

  static Future<Map<String, List<String>>> previewLock({
    required String rootPath,
    required String appDirPath,
  }) async {
    await _validatePaths(
      rootPath: rootPath,
      appDirPath: appDirPath,
    );

    final rootDir = Directory(rootPath);
    final appDir = Directory(appDirPath);

    final String ownExecutablePath = p.canonicalize(
      Platform.resolvedExecutable,
    );

    final appDirName = p.basename(appDir.path);
    const dbName = 'vault_index.db';

    final entities = await rootDir.list(
      recursive: false,
      followLinks: false,
    ).toList();

    final candidates = <String>[];
    final excluded = <String>[];

    for (final entity in entities) {
      final absolutePath = p.canonicalize(entity.path);
      final name = p.basename(entity.path);
      final ext = p.extension(entity.path).toLowerCase();

      if (_shouldExcludeEntity(
        name: name,
        ext: ext,
        appDirName: appDirName,
        dbName: dbName,
        absolutePath: absolutePath,
        ownExecutablePath: ownExecutablePath,
      )) {
        excluded.add(name);
      } else {
        candidates.add(name);
      }
    }

    return {
      'candidates': candidates,
      'excluded': excluded,
    };
  }

  static Future<List<FileSystemEntity>> getRootCandidates({
    required String rootPath,
    required String appDirPath,
  }) async {
    await _validatePaths(
      rootPath: rootPath,
      appDirPath: appDirPath,
    );

    final rootDir = Directory(rootPath);
    final appDir = Directory(appDirPath);

    final String ownExecutablePath = p.canonicalize(
      Platform.resolvedExecutable,
    );

    final appDirName = p.basename(appDir.path);
    const dbName = 'vault_index.db';

    final entities = await rootDir.list(
      recursive: false,
      followLinks: false,
    ).toList();

    return entities.where((entity) {
      final absolutePath = p.canonicalize(entity.path);
      final name = p.basename(entity.path);
      final ext = p.extension(entity.path).toLowerCase();

      return !_shouldExcludeEntity(
        name: name,
        ext: ext,
        appDirName: appDirName,
        dbName: dbName,
        absolutePath: absolutePath,
        ownExecutablePath: ownExecutablePath,
      );
    }).toList();
  }

  static Future<VaultOperationResult> lockEverything({
    required String rootPath,
    required String appDirPath,
    bool encryptContent = false,
  }) async {
    final candidates = await getRootCandidates(
      rootPath: rootPath,
      appDirPath: appDirPath,
    );

    return lockSelectedEntities(
      rootPath: rootPath,
      appDirPath: appDirPath,
      selectedEntities: candidates,
      encryptContent: encryptContent,
    );
  }

  static Future<VaultOperationResult> lockSelectedEntities({
    required String rootPath,
    required String appDirPath,
    required List<FileSystemEntity> selectedEntities,
    bool encryptContent = false,
  }) async {
    await _validatePaths(
      rootPath: rootPath,
      appDirPath: appDirPath,
    );

    final rootDir = Directory(rootPath);
    final appDir = Directory(appDirPath);
    final hiddenDir = Directory(p.join(appDir.path, hiddenFolderName));

    if (!await hiddenDir.exists()) {
      await hiddenDir.create(recursive: true);
      await _hideDirectory(hiddenDir.path);
    }

    int processed = 0;
    int succeeded = 0;
    int failed = 0;
    int skipped = 0;
    final failedItems = <String>[];
    final skippedItems = <String>[];

    for (final entity in selectedEntities) {
      processed++;

      final name = p.basename(entity.path);
      final destination = p.join(
        hiddenDir.path,
        _generateRandomFakeName(isDirectory: entity is Directory),
      );

      bool moved = false;
      bool contentEncrypted = false;

      try {
        int size = 0;
        final isDir = entity is Directory;

        if (!await _entityExists(entity.path)) {
          skipped++;
          skippedItems.add(name);
          _log('LOCK_SKIP missing source: $name');
          continue;
        }

        if (entity is File) {
          size = await entity.length();
        }

        await entity.rename(destination);
        moved = true;

        if (encryptContent) {
          if (isDir) {
            await VaultDatabase.encryptRecursive(destination);
          } else {
            await VaultDatabase.encryptFileContent(destination);
            size = await File(destination).length();
          }
          contentEncrypted = true;
        }

        await VaultDatabase.registerFile(
          VaultRecord(
            fakeName: p.basename(destination),
            realName: name,
            relativePath: name,
            isDirectory: isDir,
            fileSize: size,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            isContentEncrypted: contentEncrypted,
          ),
        );

        succeeded++;
      } catch (e) {
        failed++;
        failedItems.add(name);

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

        _log('LOCK_FAIL $name: $e');
      }
    }

    return VaultOperationResult(
      processed: processed,
      succeeded: succeeded,
      failed: failed,
      skipped: skipped,
      failedItems: failedItems,
      skippedItems: skippedItems,
    );
  }

  static Future<List<String>> getUnlockConflicts({
    required String rootPath,
    required List<VaultRecord> selectedFiles,
  }) async {
    final conflicts = <String>[];

    for (final file in selectedFiles) {
      final destination = p.join(rootPath, file.relativePath);
      if (await _entityExists(destination)) {
        conflicts.add(file.relativePath);
      }
    }

    return conflicts;
  }

  static Future<VaultOperationResult> unlockSelected({
    required String rootPath,
    required String appDirPath,
    required List<VaultRecord> selectedFiles,
    bool overwriteExisting = false,
    bool renameOnConflict = false,
  }) async {
    await _validatePaths(
      rootPath: rootPath,
      appDirPath: appDirPath,
    );

    final rootDir = Directory(rootPath);
    final appDir = Directory(appDirPath);
    final hiddenDir = Directory(p.join(appDir.path, hiddenFolderName));

    int processed = 0;
    int succeeded = 0;
    int failed = 0;
    int skipped = 0;
    final failedItems = <String>[];
    final skippedItems = <String>[];

    for (final file in selectedFiles) {
      processed++;

      final source = p.join(hiddenDir.path, file.fakeName);
      String destination = p.join(rootDir.path, file.relativePath);

      try {
        final exists = await _entityExists(source);

        if (!exists) {
          skipped++;
          skippedItems.add(file.realName);
          _log('UNLOCK_SKIP missing hidden item: ${file.fakeName}');
          continue;
        }

        final destExists = await _entityExists(destination);

        if (destExists && !overwriteExisting && !renameOnConflict) {
          skipped++;
          skippedItems.add(file.realName);
          _log('UNLOCK_SKIP conflict: $destination');
          continue;
        }

        if (destExists && !overwriteExisting && renameOnConflict) {
          destination = await _findAvailablePath(destination);
        }

        final destDir = Directory(p.dirname(destination));
        if (!await destDir.exists()) {
          await destDir.create(recursive: true);
        }

        if (file.isContentEncrypted) {
          if (file.isDirectory) {
            await VaultDatabase.decryptRecursive(source);
          } else {
            await VaultDatabase.decryptFileContent(source);
          }
        }

        if (file.isDirectory) {
          await Directory(source).rename(destination);
        } else {
          final destFile = File(destination);
          if (await destFile.exists() && overwriteExisting) {
            await destFile.delete();
          }
          await File(source).rename(destination);
        }

        await VaultDatabase.removeFileByFakeName(file.fakeName);
        succeeded++;
      } catch (e) {
        failed++;
        failedItems.add(file.realName);
        _log('UNLOCK_FAIL ${file.realName}: $e');
      }
    }

    return VaultOperationResult(
      processed: processed,
      succeeded: succeeded,
      failed: failed,
      skipped: skipped,
      failedItems: failedItems,
      skippedItems: skippedItems,
    );
  }

  static Future<VaultOperationResult> unlockEverything({
    required String rootPath,
    required String appDirPath,
    bool overwriteExisting = false,
    bool renameOnConflict = false,
  }) async {
    final files = await VaultDatabase.getFiles();

    return unlockSelected(
      rootPath: rootPath,
      appDirPath: appDirPath,
      selectedFiles: files,
      overwriteExisting: overwriteExisting,
      renameOnConflict: renameOnConflict,
    );
  }

  static Future<List<String>> findOrphanedHiddenItems({
    required String appDirPath,
  }) async {
    final hiddenDir = Directory(p.join(appDirPath, hiddenFolderName));
    if (!await hiddenDir.exists()) return [];

    final dbFiles = await VaultDatabase.getFiles();
    final indexedFakeNames = dbFiles.map((f) => f.fakeName).toSet();

    final orphaned = <String>[];
    final physicalItems = await hiddenDir.list(
      recursive: false,
      followLinks: false,
    ).toList();

    for (final item in physicalItems) {
      final name = p.basename(item.path);
      if (!indexedFakeNames.contains(name)) {
        orphaned.add(name);
      }
    }

    return orphaned;
  }

  static Future<int> purgeMissingEntries({
    required String appDirPath,
  }) async {
    final hiddenDir = Directory(p.join(appDirPath, hiddenFolderName));
    final files = await VaultDatabase.getFiles();

    int purged = 0;

    for (final file in files) {
      final itemPath = p.join(hiddenDir.path, file.fakeName);
      final exists = await _entityExists(itemPath);

      if (!exists) {
        await VaultDatabase.removeFileByFakeName(file.fakeName);
        purged++;
      }
    }

    return purged;
  }

  static Future<void> revealHiddenFolder({
    required String appDirPath,
  }) async {
    if (!Platform.isWindows) return;

    final hiddenPath = p.join(appDirPath, hiddenFolderName);
    if (!await Directory(hiddenPath).exists()) return;

    try {
      await Process.run('attrib', ['-h', '-s', hiddenPath]);
    } catch (e) {
      _log('REVEAL_FAIL $hiddenPath: $e');
    }
  }

  static Future<void> rehideHiddenFolder({
    required String appDirPath,
  }) async {
    final hiddenPath = p.join(appDirPath, hiddenFolderName);
    if (!await Directory(hiddenPath).exists()) return;
    await _hideDirectory(hiddenPath);
  }

  static bool _shouldExcludeEntity({
    required String name,
    required String ext,
    required String appDirName,
    required String dbName,
    required String absolutePath,
    required String ownExecutablePath,
  }) {
    if (name == appDirName ||
        name == hiddenFolderName ||
        name == dbName ||
        absolutePath == ownExecutablePath ||
        excludedExtensions.contains(ext)) {
      return true;
    }

    if (excludedNames.any(
      (excluded) => excluded.toLowerCase() == name.toLowerCase(),
    )) {
      return true;
    }

    if (name.startsWith('~')) {
      return true;
    }

    return false;
  }

  static Future<bool> _entityExists(String path) async {
    return await File(path).exists() || await Directory(path).exists();
  }

  static Future<String> _findAvailablePath(String originalPath) async {
    if (!await _entityExists(originalPath)) {
      return originalPath;
    }

    final dir = p.dirname(originalPath);
    final baseName = p.basenameWithoutExtension(originalPath);
    final ext = p.extension(originalPath);

    int counter = 1;
    while (true) {
      final candidate = p.join(
        dir,
        '$baseName (restored $counter)$ext',
      );

      if (!await _entityExists(candidate)) {
        return candidate;
      }

      counter++;
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
      await Process.run('attrib', ['+h', '+s', path]);
    } catch (e) {
      _log('HIDE_FAIL $path: $e');
    }
  }

  static void _log(String message) {
    stderr.writeln('[VaultLogic] $message');
  }
}
