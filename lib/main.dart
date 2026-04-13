import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'database_helper.dart';
import 'vault_logic.dart';

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await VaultDatabase.init();

  const windowOptions = WindowOptions(
    size: Size(420, 640),
    center: true,
    title: 'NullFiles',
    minimumSize: Size(420, 640),
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAlwaysOnTop(true);
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const StealthApp());
}

class StealthApp extends StatelessWidget {
  const StealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scrollBehavior: MyCustomScrollBehavior(),
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: const ColorScheme.dark(
          primary: Colors.blueAccent,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WindowListener {
  bool _isAuthenticated = false;
  bool _isFirstTime = false;
  bool _isBusy = false;
  bool _autoLockOnClose = true;

  int _itemCount = 0;
  String _totalSize = '0 B';
  String _vaultStatus = 'UNKNOWN';

  List<VaultRecord> _vaultContent = [];

  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  final TextEditingController _passController = TextEditingController();

  String get _appDirPath => Directory.current.path;
  String get _rootDirPath => Directory.current.parent.path;
  String get _dbPath => p.join(_appDirPath, 'vault_index.db');
  String get _driveLetter => p.rootPrefix(_rootDirPath).toUpperCase();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    _checkVaultStatus();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _passController.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (_isAuthenticated && !_isBusy) {
      if (_autoLockOnClose) {
        try {
          await VaultLogic.lockEverything(
            rootPath: _rootDirPath,
            appDirPath: _appDirPath,
          );
        } catch (_) {}
      }

      await VaultDatabase.close();
    }

    await windowManager.destroy();
  }

  Future<void> _checkVaultStatus() async {
    final exists = await File(_dbPath).exists();

    if (!mounted) return;
    setState(() {
      _isFirstTime = !exists;
    });
  }

  Future<void> _refreshVaultStats() async {
    final files = await VaultDatabase.getFiles();
    int totalBytes = 0;

    for (final f in files) {
      totalBytes += f.fileSize;
    }

    String status = 'EMPTY';

    try {
      final hasContent = await VaultLogic.hasVaultContent();
      final locked = await VaultLogic.isVaultLocked(
        appDirPath: _appDirPath,
      );

      if (!hasContent) {
        status = 'EMPTY';
      } else if (locked) {
        status = 'LOCKED';
      } else {
        status = 'PARTIAL';
      }
    } catch (_) {
      status = 'UNKNOWN';
    }

    if (!mounted) return;
    setState(() {
      _vaultContent = files;
      _itemCount = files.length;
      _totalSize = _formatBytes(totalBytes);
      _vaultStatus = status;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (math.log(bytes) / math.log(1024)).floor();
    if (i >= suffixes.length) i = suffixes.length - 1;
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
      ),
    );
  }

  String _formatOperationResult(
    String action,
    VaultOperationResult result,
  ) {
    return '$action • OK ${result.succeeded} • Skipped ${result.skipped} • Failed ${result.failed}';
  }

  Future<void> _login() async {
    final inputPass = _passController.text.trim();
    if (inputPass.isEmpty || _isBusy) return;

    setState(() => _isBusy = true);

    try {
      await VaultDatabase.openVault(
        password: inputPass,
        databasePath: _dbPath,
      );

      await _refreshVaultStats();

      if (!mounted) return;
      setState(() {
        _isAuthenticated = true;
        _isFirstTime = false;
      });
    } catch (_) {
      _showSnack('⚠️ Invalid Master Key', Colors.orange);
    } finally {
      _passController.clear();
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _runHealthCheck() async {
    if (_isBusy) return;

    setState(() => _isBusy = true);
    Map<String, int> results = {};

    try {
      results = await VaultLogic.checkHealth(
        appDirPath: _appDirPath,
      );
    } catch (e) {
      _showSnack('⚠️ Health check failed: $e', Colors.redAccent);
      return;
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }

    if (!mounted) return;

    final healthy = results['healthy'] ?? 0;
    final missing = results['missing'] ?? 0;
    final wrongType = results['wrongType'] ?? 0;
    final sizeMismatch = results['sizeMismatch'] ?? 0;
    final readErrors = results['readErrors'] ?? 0;
    final orphanedHiddenItems = results['orphanedHiddenItems'] ?? 0;
    final total = results['total'] ?? 0;

    final issues =
        missing + wrongType + sizeMismatch + readErrors + orphanedHiddenItems;
    final isHealthy = issues == 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        title: Row(
          children: [
            Icon(
              isHealthy ? Icons.verified_user : Icons.warning_amber_rounded,
              color: isHealthy ? Colors.greenAccent : Colors.orangeAccent,
            ),
            const SizedBox(width: 10),
            const Text('Vault Integrity'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _healthRow('Total Records', '$total'),
            _healthRow('Healthy', '$healthy'),
            _healthRow('Missing', '$missing'),
            _healthRow('Wrong Type', '$wrongType'),
            _healthRow('Size Mismatch', '$sizeMismatch'),
            _healthRow('Read Errors', '$readErrors'),
            _healthRow('Orphaned Hidden Items', '$orphanedHiddenItems'),
            const SizedBox(height: 14),
            Text(
              isHealthy
                  ? 'No integrity issues detected.'
                  : 'Potential issues were detected in the vault.',
              style: TextStyle(
                color: isHealthy ? Colors.greenAccent : Colors.orangeAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          if (missing > 0)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _purgeMissingEntries();
              },
              child: const Text('Purge Missing'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLockPreview() async {
    if (_isBusy) return;

    setState(() => _isBusy = true);

    Map<String, List<String>> preview = {};
    try {
      preview = await VaultLogic.previewLock(
        rootPath: _rootDirPath,
        appDirPath: _appDirPath,
      );
    } catch (e) {
      _showSnack('⚠️ Preview failed: $e', Colors.redAccent);
      return;
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }

    if (!mounted) return;

    final candidates = preview['candidates'] ?? [];
    final excluded = preview['excluded'] ?? [];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        title: const Text('Protect Preview'),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Candidates: ${candidates.length}'),
                const SizedBox(height: 8),
                ...candidates.take(12).map((e) => Text('• $e')),
                if (candidates.length > 12)
                  Text('… and ${candidates.length - 12} more'),
                const SizedBox(height: 16),
                Text('Excluded: ${excluded.length}'),
                const SizedBox(height: 8),
                ...excluded.take(8).map((e) => Text('• $e')),
                if (excluded.length > 8)
                  Text('… and ${excluded.length - 8} more'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _lockVault();
            },
            child: const Text('Protect All'),
          ),
        ],
      ),
    );
  }

  Future<void> _lockVault() async {
    if (_isBusy) return;

    setState(() => _isBusy = true);

    try {
      final result = await VaultLogic.lockEverything(
        rootPath: _rootDirPath,
        appDirPath: _appDirPath,
      );

      await _refreshVaultStats();

      final hasProblems = result.failed > 0 || result.skipped > 0;
      _showSnack(
        _formatOperationResult('🔒 Protect complete', result),
        hasProblems ? Colors.orangeAccent : Colors.blueAccent,
      );
    } catch (e) {
      _showSnack('⚠️ Error: $e', Colors.redAccent);
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _showRestoreAllOptions() async {
    if (_isBusy) return;

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        title: const Text('Restore All'),
        content: const Text(
          'Choose how to handle destination conflicts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'skip'),
            child: const Text('Skip Conflicts'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'rename'),
            child: const Text('Rename On Conflict'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'overwrite'),
            child: const Text('Overwrite'),
          ),
        ],
      ),
    );

    if (choice == null || choice == 'cancel') return;

    await _unlockVault(
      overwriteExisting: choice == 'overwrite',
      renameOnConflict: choice == 'rename',
    );
  }

  Future<void> _unlockVault({
    bool overwriteExisting = false,
    bool renameOnConflict = false,
  }) async {
    if (_isBusy) return;

    setState(() => _isBusy = true);

    try {
      final result = await VaultLogic.unlockEverything(
        rootPath: _rootDirPath,
        appDirPath: _appDirPath,
        overwriteExisting: overwriteExisting,
        renameOnConflict: renameOnConflict,
      );

      await _refreshVaultStats();

      final hasProblems = result.failed > 0 || result.skipped > 0;
      _showSnack(
        _formatOperationResult('🔓 Restore complete', result),
        hasProblems ? Colors.orangeAccent : Colors.greenAccent,
      );
    } catch (e) {
      _showSnack('⚠️ Error: $e', Colors.redAccent);
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _unlockSingle(VaultRecord file) async {
    if (_isBusy) return;

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        title: Text('Restore "${file.realName}"'),
        content: const Text('Choose how to handle conflicts for this item.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'skip'),
            child: const Text('Skip'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'rename'),
            child: const Text('Rename'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'overwrite'),
            child: const Text('Overwrite'),
          ),
        ],
      ),
    );

    if (choice == null || choice == 'cancel') return;

    setState(() => _isBusy = true);

    try {
      final result = await VaultLogic.unlockSelected(
        rootPath: _rootDirPath,
        appDirPath: _appDirPath,
        selectedFiles: [file],
        overwriteExisting: choice == 'overwrite',
        renameOnConflict: choice == 'rename',
      );

      await _refreshVaultStats();

      if (result.succeeded == 1) {
        _showSnack('🔓 Restored: ${file.realName}', Colors.greenAccent);
      } else if (result.skipped == 1) {
        _showSnack('⚠️ Skipped: ${file.realName}', Colors.orangeAccent);
      } else {
        _showSnack('⚠️ Failed: ${file.realName}', Colors.redAccent);
      }
    } catch (e) {
      _showSnack('⚠️ Error: $e', Colors.redAccent);
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _toggleEncryption(VaultRecord file) async {
    if (_isBusy) return;

    setState(() => _isBusy = true);

    try {
      final filePath = p.join(
        _appDirPath,
        VaultLogic.hiddenFolderName,
        file.fakeName,
      );

      if (!file.isContentEncrypted) {
        await VaultDatabase.encryptRecursive(filePath);
        _showSnack('🔐 Encrypted: ${file.realName}', Colors.blueAccent);
      } else {
        await VaultDatabase.decryptRecursive(filePath);
        _showSnack('🔓 Decrypted: ${file.realName}', Colors.orangeAccent);
      }

      final db = await VaultDatabase.database;
      int newSize = file.fileSize;

      if (!file.isDirectory) {
        newSize = await File(filePath).length();
      }

      await db.update(
        'vault_files',
        {
          'is_content_encrypted': file.isContentEncrypted ? 0 : 1,
          'file_size': newSize,
        },
        where: 'fake_name = ?',
        whereArgs: [file.fakeName],
      );

      await _refreshVaultStats();
    } catch (e) {
      _showSnack('⚠️ Error: $e', Colors.redAccent);
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _showMaintenanceMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF171717),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.preview_outlined),
              title: const Text('Preview Protect All'),
              onTap: () => Navigator.pop(context, 'preview'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Reveal Hidden Folder'),
              onTap: () => Navigator.pop(context, 'reveal'),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Rehide Hidden Folder'),
              onTap: () => Navigator.pop(context, 'rehide'),
            ),
            ListTile(
              leading: const Icon(Icons.find_in_page_outlined),
              title: const Text('Find Orphaned Hidden Items'),
              onTap: () => Navigator.pop(context, 'orphans'),
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('Purge Missing DB Entries'),
              onTap: () => Navigator.pop(context, 'purge'),
            ),
          ],
        ),
      ),
    );

    switch (choice) {
      case 'preview':
        await _showLockPreview();
        break;
      case 'reveal':
        await _revealHiddenFolder();
        break;
      case 'rehide':
        await _rehideHiddenFolder();
        break;
      case 'orphans':
        await _showOrphanedItems();
        break;
      case 'purge':
        await _purgeMissingEntries();
        break;
    }
  }

  Future<void> _revealHiddenFolder() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    try {
      await VaultLogic.revealHiddenFolder(
        appDirPath: _appDirPath,
      );
      _showSnack('📂 Hidden folder revealed', Colors.blueAccent);
    } catch (e) {
      _showSnack('⚠️ Reveal failed: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _rehideHiddenFolder() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    try {
      await VaultLogic.rehideHiddenFolder(
        appDirPath: _appDirPath,
      );
      _showSnack('🙈 Hidden folder rehiden', Colors.blueAccent);
    } catch (e) {
      _showSnack('⚠️ Rehide failed: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _showOrphanedItems() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    List<String> orphaned = [];

    try {
      orphaned = await VaultLogic.findOrphanedHiddenItems(
        appDirPath: _appDirPath,
      );
    } catch (e) {
      _showSnack('⚠️ Failed to scan orphaned items: $e', Colors.redAccent);
      return;
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        title: Text('Orphaned Hidden Items (${orphaned.length})'),
        content: SizedBox(
          width: 340,
          child: orphaned.isEmpty
              ? const Text('No orphaned hidden items found.')
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: orphaned.map((e) => Text('• $e')).toList(),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _purgeMissingEntries() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    try {
      final purged = await VaultLogic.purgeMissingEntries(
        appDirPath: _appDirPath,
      );
      await _refreshVaultStats();
      _showSnack('🧹 Purged missing entries: $purged', Colors.orangeAccent);
    } catch (e) {
      _showSnack('⚠️ Purge failed: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _closeVault() async {
    await VaultDatabase.close();

    if (!mounted) return;

    setState(() {
      _isAuthenticated = false;
      _vaultContent = [];
      _itemCount = 0;
      _totalSize = '0 B';
      _vaultStatus = 'UNKNOWN';
    });

    await _checkVaultStatus();
  }

  Color _statusColor() {
    switch (_vaultStatus) {
      case 'LOCKED':
        return Colors.greenAccent;
      case 'EMPTY':
        return Colors.orangeAccent;
      case 'PARTIAL':
        return Colors.orangeAccent;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 140),
              child: _isAuthenticated ? _buildDashboard() : _buildLogin(),
            ),
            if (_isAuthenticated) _buildDraggableExplorer(),
            if (_isBusy) _buildBusyOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildLogin() {
    return Center(
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isFirstTime ? Icons.lock_reset : Icons.shield_outlined,
                size: 80,
                color: _isFirstTime ? Colors.orangeAccent : Colors.blueAccent,
              ),
              const SizedBox(height: 20),
              Text(
                _isFirstTime ? 'INITIALIZE VAULT' : 'RESTRICTED ACCESS',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 25),
              TextField(
                controller: _passController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Master Key',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.vpn_key),
                ),
                onSubmitted: (_) => _login(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: _isBusy ? null : _login,
                  child: Text(_isFirstTime ? 'SETUP / UNLOCK' : 'UNLOCK'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.lock_open,
                color: Colors.greenAccent,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Drive $_driveLetter',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Status: $_vaultStatus',
                      style: TextStyle(
                        color: _statusColor(),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Health Check',
                onPressed: _isBusy ? null : _runHealthCheck,
                icon: const Icon(
                  Icons.health_and_safety_outlined,
                  color: Colors.blueAccent,
                ),
              ),
              IconButton(
                tooltip: 'Maintenance',
                onPressed: _isBusy ? null : _showMaintenanceMenu,
                icon: const Icon(
                  Icons.build_circle_outlined,
                  color: Colors.orangeAccent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              _infoRow('PROTECTED ITEMS', _itemCount.toString()),
              const SizedBox(height: 10),
              _infoRow('ROOT PAYLOAD', _totalSize),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              Expanded(
                child: _actionButton(
                  'RESTORE ALL',
                  Icons.settings_backup_restore,
                  Colors.blue,
                  _showRestoreAllOptions,
                ),
              ),
              Container(
                width: 1,
                height: 56,
                color: Colors.white10,
              ),
              Expanded(
                child: _actionButton(
                  'PROTECT ALL',
                  Icons.security,
                  Colors.redAccent,
                  _showLockPreview,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white10),
          ),
          child: const Column(
            children: [
              Text(
                'Click or drag up to manage files',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                ),
              ),
              SizedBox(height: 4),
              Icon(
                Icons.keyboard_arrow_up,
                color: Colors.grey,
                size: 18,
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white10),
          ),
          child: SwitchListTile(
            value: _autoLockOnClose,
            onChanged: _isBusy
                ? null
                : (value) {
                    setState(() {
                      _autoLockOnClose = value;
                    });
                  },
            title: const Text(
              'Auto-lock on close',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              _autoLockOnClose
                  ? 'Files will be protected automatically on app close'
                  : 'App will close without auto-protecting files',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
            activeColor: Colors.blueAccent,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isBusy ? null : _closeVault,
            icon: const Icon(Icons.power_settings_new),
            label: const Text('CLOSE VAULT'),
          ),
        ),
      ],
    );
  }

  Widget _buildDraggableExplorer() {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.12,
      minChildSize: 0.12,
      maxChildSize: 0.78,
      snap: true,
      snapSizes: const [0.12, 0.35, 0.78],
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF161616),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  final size = _sheetController.size;
                  if (size < 0.2) {
                    _sheetController.animateTo(
                      0.35,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  } else if (size < 0.5) {
                    _sheetController.animateTo(
                      0.78,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  } else {
                    _sheetController.animateTo(
                      0.12,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeIn,
                    );
                  }
                },
                child: Container(
                  width: double.infinity,
                  color: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'VAULT EXPLORER • ${_vaultContent.length} items',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _vaultContent.isEmpty
                    ? const Center(
                        child: Text(
                          'Vault is empty',
                          style: TextStyle(color: Colors.white38),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        itemCount: _vaultContent.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: Colors.white10, height: 1),
                        itemBuilder: (context, index) {
                          final file = _vaultContent[index];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              file.isDirectory
                                  ? Icons.folder_rounded
                                  : Icons.insert_drive_file_rounded,
                              size: 18,
                              color: Colors.white38,
                            ),
                            title: Text(
                              file.realName,
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              _formatBytes(file.fileSize),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white24,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: file.isContentEncrypted
                                      ? 'Decrypt content'
                                      : 'Encrypt content',
                                  icon: Icon(
                                    file.isContentEncrypted
                                        ? Icons.lock
                                        : Icons.lock_open_outlined,
                                    size: 16,
                                    color: file.isContentEncrypted
                                        ? Colors.blueAccent
                                        : Colors.white24,
                                  ),
                                  onPressed: _isBusy
                                      ? null
                                      : () => _toggleEncryption(file),
                                ),
                                IconButton(
                                  tooltip: 'Restore item',
                                  icon: const Icon(
                                    Icons.unarchive,
                                    color: Colors.greenAccent,
                                    size: 18,
                                  ),
                                  onPressed: _isBusy
                                      ? null
                                      : () => _unlockSingle(file),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.grey,
            letterSpacing: 1,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            color: Colors.blueAccent,
          ),
        ),
      ],
    );
  }

  Widget _healthRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              color: Colors.blueAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    String title,
    IconData icon,
    Color color,
    Future<void> Function() action,
  ) {
    return InkWell(
      onTap: _isBusy ? null : action,
      borderRadius: BorderRadius.circular(15),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, size: 35, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusyOverlay() {
    return IgnorePointer(
      child: Container(
        color: Colors.black.withOpacity(0.15),
        child: const Center(
          child: SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      ),
    );
  }
}
