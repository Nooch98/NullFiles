import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class VaultRecord {
  final int? id;
  final String fakeName;
  final String realName;
  final String relativePath;
  final bool isDirectory;
  final int fileSize;
  final int createdAt;
  final bool isContentEncrypted;

  const VaultRecord({
    this.id,
    required this.fakeName,
    required this.realName,
    required this.relativePath,
    required this.isDirectory,
    required this.fileSize,
    required this.createdAt,
    this.isContentEncrypted = false,
  });
}

class VaultDatabase {
  static Database? _db;
  static SecretKey? _masterKey;

  static final Cipher _cipher = AesGcm.with256bits();

  static const int schemaVersion = 2;

  static const int argonMemoryKiB = 65536;
  static const int argonIterations = 3;
  static const int argonParallelism = 4;
  static const int keyLength = 32;

  static Future<void> init() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  static Future<void> openVault({
    required String password,
    required String databasePath,
  }) async {
    await init();

    final dir = Directory(p.dirname(databasePath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    _db = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE vault_meta (
              id INTEGER PRIMARY KEY CHECK(id=1),
              salt TEXT NOT NULL,
              password_check TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE vault_files (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              fake_name TEXT NOT NULL UNIQUE,
              enc_real_name TEXT NOT NULL,
              enc_relative_path TEXT NOT NULL,
              is_directory INTEGER NOT NULL,
              file_size INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              is_content_encrypted INTEGER NOT NULL DEFAULT 0
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE vault_files ADD COLUMN is_content_encrypted INTEGER NOT NULL DEFAULT 0');
          }
        },
      ),
    );

    final meta = await _db!.query('vault_meta', limit: 1);

    if (meta.isEmpty) {
      final random = Random.secure();
      final salt = List<int>.generate(16, (_) => random.nextInt(256));

      final keyBytes = await _deriveKey(password, salt);
      _masterKey = SecretKey(keyBytes);

      final passwordCheck = await _encryptString('VAULT_OK_V1');

      await _db!.insert('vault_meta', {
        'id': 1,
        'salt': base64Encode(salt),
        'password_check': passwordCheck,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      return;
    }

    final salt = base64Decode(meta.first['salt'] as String);
    final keyBytes = await _deriveKey(password, salt);
    _masterKey = SecretKey(keyBytes);

    try {
      final check = await _decryptString(meta.first['password_check'] as String);
      if (check != 'VAULT_OK_V1') throw Exception();
    } catch (_) {
      await close();
      throw Exception('Wrong password or corrupted vault.');
    }
  }

  static Future<void> encryptRecursive(String path) async {
    final entity = FileSystemEntity.typeSync(path);
    if (entity == FileSystemEntityType.file) {
      await encryptFileContent(path);
    } else if (entity == FileSystemEntityType.directory) {
      final dir = Directory(path);
      await for (final item in dir.list(recursive: true, followLinks: false)) {
        if (item is File) {
          await encryptFileContent(item.path);
        }
      }
    }
  }

  static Future<void> decryptRecursive(String path) async {
    final entity = FileSystemEntity.typeSync(path);
    if (entity == FileSystemEntityType.file) {
      await decryptFileContent(path);
    } else if (entity == FileSystemEntityType.directory) {
      final dir = Directory(path);
      await for (final item in dir.list(recursive: true, followLinks: false)) {
        if (item is File) {
          await decryptFileContent(item.path);
        }
      }
    }
  }

  static Future<void> encryptFileContent(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();

    final box = await _cipher.encrypt(
      bytes,
      secretKey: _key,
    );

    await file.writeAsBytes(box.concatenation());
  }

  static Future<void> decryptFileContent(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();

    final box = SecretBox.fromConcatenation(
      bytes,
      nonceLength: _cipher.nonceLength,
      macLength: _cipher.macAlgorithm.macLength,
    );

    final clear = await _cipher.decrypt(
      box,
      secretKey: _key,
    );

    await file.writeAsBytes(Uint8List.fromList(clear));
  }

  static Future<List<int>> _deriveKey(String password, List<int> salt) async {
    final algorithm = Argon2id(
      parallelism: argonParallelism,
      memory: argonMemoryKiB,
      iterations: argonIterations,
      hashLength: keyLength,
    );
    final secretKey = await algorithm.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    return secretKey.extractBytes();
  }

  static SecretKey get _key {
    if (_masterKey == null) throw Exception('Vault key not initialized.');
    return _masterKey!;
  }

  static Future<Database> get database async {
    if (_db == null) throw Exception('Vault database not open.');
    return _db!;
  }

  static Future<String> _encryptString(String value) async {
    final box = await _cipher.encrypt(utf8.encode(value), secretKey: _key);
    return base64Encode(box.concatenation());
  }

  static Future<String> _decryptString(String value) async {
    final bytes = base64Decode(value);
    final box = SecretBox.fromConcatenation(
      bytes,
      nonceLength: _cipher.nonceLength,
      macLength: _cipher.macAlgorithm.macLength,
    );
    final clear = await _cipher.decrypt(box, secretKey: _key);
    return utf8.decode(clear);
  }

  static Future<void> registerFile(VaultRecord record) async {
    final db = await database;
    await db.insert('vault_files', {
      'fake_name': record.fakeName,
      'enc_real_name': await _encryptString(record.realName),
      'enc_relative_path': await _encryptString(record.relativePath),
      'is_directory': record.isDirectory ? 1 : 0,
      'file_size': record.fileSize,
      'created_at': record.createdAt,
      'is_content_encrypted': record.isContentEncrypted ? 1 : 0,
    });
  }

  static Future<List<VaultRecord>> getFiles() async {
    final db = await database;
    final rows = await db.query('vault_files', orderBy: 'id ASC');

    final result = <VaultRecord>[];
    for (final row in rows) {
      result.add(
        VaultRecord(
          id: row['id'] as int,
          fakeName: row['fake_name'] as String,
          realName: await _decryptString(row['enc_real_name'] as String),
          relativePath: await _decryptString(row['enc_relative_path'] as String),
          isDirectory: (row['is_directory'] as int) == 1,
          fileSize: row['file_size'] as int,
          createdAt: row['created_at'] as int,
          isContentEncrypted: (row['is_content_encrypted'] as int) == 1,
        ),
      );
    }
    return result;
  }

  static Future<void> removeFileByFakeName(String fakeName) async {
    final db = await database;
    await db.delete('vault_files', where: 'fake_name = ?', whereArgs: [fakeName]);
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
    _masterKey = null;
  }
}
