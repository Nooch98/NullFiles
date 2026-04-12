import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'dart:math' as math;
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
    size: Size(380, 580),
    center: true,
    title: 'NullFiles',
    minimumSize: Size(380, 580),
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
        colorScheme: const ColorScheme.dark(primary: Colors.blueAccent),
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
  int _itemCount = 0;
  String _totalSize = "0 B";
  List<VaultRecord> _vaultContent = [];
  
  final DraggableScrollableController _sheetController = DraggableScrollableController();
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
      await VaultLogic.lockEverything(rootPath: _rootDirPath, appDirPath: _appDirPath);
      await VaultDatabase.close();
    }
    await windowManager.destroy();
  }

  Future<void> _runHealthCheck() async {
    setState(() => _isBusy = true);
    final results = await VaultLogic.checkHealth(appDirPath: _appDirPath);
    setState(() => _isBusy = false);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Vault Integrity"),
        content: Text("Healthy Items: ${results['healthy']}\nMissing Items: ${results['missing']}"),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
      ),
    );
  }

  Future<void> _checkVaultStatus() async {
    final exists = await File(_dbPath).exists();
    if (!mounted) return;
    setState(() => _isFirstTime = !exists);
  }

  Future<void> _refreshVaultStats() async {
    final files = await VaultDatabase.getFiles();
    int totalBytes = 0;
    for (var f in files) {
      totalBytes += f.fileSize;
    }
    if (!mounted) return;
    setState(() {
      _vaultContent = files;
      _itemCount = files.length;
      _totalSize = _formatBytes(totalBytes);
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (math.log(bytes) / math.log(1024)).floor();
    if (i >= suffixes.length) i = suffixes.length - 1;
    return "${(bytes / math.pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}";
  }

  Future<void> _login() async {
    final inputPass = _passController.text.trim();
    if (inputPass.isEmpty || _isBusy) return;
    setState(() => _isBusy = true);
    try {
      await VaultDatabase.openVault(password: inputPass, databasePath: _dbPath);
      await _refreshVaultStats();
      if (!mounted) return;
      setState(() { _isAuthenticated = true; _isFirstTime = false; });
    } catch (e) {
      _showSnack('⚠️ Invalid Master Key', Colors.orange);
    } finally {
      _passController.clear();
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _lockVault() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await VaultLogic.lockEverything(rootPath: _rootDirPath, appDirPath: _appDirPath);
      await _refreshVaultStats();
      _showSnack('🔒 Hide Complete', Colors.blueAccent);
    } catch (e) {
      _showSnack('⚠️ Error: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _unlockVault() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await VaultLogic.unlockEverything(rootPath: _rootDirPath, appDirPath: _appDirPath);
      await _refreshVaultStats();
      _showSnack('🔓 Show Complete', Colors.greenAccent);
    } catch (e) {
      _showSnack('⚠️ Error: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _unlockSingle(VaultRecord file) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await VaultLogic.unlockSelected(rootPath: _rootDirPath, appDirPath: _appDirPath, selectedFiles: [file]);
      await _refreshVaultStats();
      _showSnack('🔓 Restored: ${file.realName}', Colors.greenAccent);
    } catch (e) {
      _showSnack('⚠️ Error: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _toggleEncryption(VaultRecord file) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      final filePath = p.join(_appDirPath, VaultLogic.hiddenFolderName, file.fakeName);
      
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
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _closeVault() async {
    await VaultDatabase.close();
    if (!mounted) return;
    setState(() => _isAuthenticated = false);
    await _checkVaultStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(30),
            child: _isAuthenticated ? _buildDashboard() : _buildLogin(),
          ),
          if (_isAuthenticated) _buildDraggableExplorer(),
        ],
      ),
    );
  }

  Widget _buildLogin() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(_isFirstTime ? Icons.lock_reset : Icons.shield_outlined, size: 80, color: _isFirstTime ? Colors.orangeAccent : Colors.blueAccent),
        const SizedBox(height: 20),
        Text(_isFirstTime ? 'INITIALIZE VAULT' : 'RESTRICTED ACCESS', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
        const SizedBox(height: 25),
        TextField(
          controller: _passController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Master Key', border: OutlineInputBorder(), prefixIcon: Icon(Icons.vpn_key)),
          onSubmitted: (_) => _login(),
        ),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, height: 45, child: ElevatedButton(onPressed: _isBusy ? null : _login, child: const Text("UNLOCK"))),
      ],
    );
  }

  Widget _buildDashboard() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(Icons.lock_open, color: Colors.greenAccent, size: 24),
            Text(_driveLetter, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            IconButton(onPressed: _runHealthCheck, icon: const Icon(Icons.health_and_safety_outlined, size: 20, color: Colors.blueAccent)),
          ],
        ),
        const Divider(color: Colors.white10, height: 30),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)),
          child: Column(
            children: [
              _infoRow("PROTECTED ITEMS", _itemCount.toString()),
              const SizedBox(height: 10),
              _infoRow("ROOT PAYLOAD", _totalSize),
            ],
          ),
        ),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _actionButton('RESTORE ALL', Icons.settings_backup_restore, Colors.blue, _unlockVault),
            _actionButton('PROTECT ALL', Icons.security, Colors.redAccent, _lockVault),
          ],
        ),
        const Spacer(),
        const Text("Click or Drag up to manage files", style: TextStyle(color: Colors.grey, fontSize: 10)),
        const Icon(Icons.keyboard_arrow_up, color: Colors.grey, size: 16),
        const SizedBox(height: 60), 
        TextButton.icon(onPressed: _isBusy ? null : _closeVault, icon: const Icon(Icons.power_settings_new), label: const Text('CLOSE VAULT'), style: TextButton.styleFrom(foregroundColor: Colors.grey)),
      ],
    );
  }

  Widget _buildDraggableExplorer() {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.1,
      minChildSize: 0.1,
      maxChildSize: 0.8,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF161616),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [BoxShadow(color: Colors.black, blurRadius: 20)],
          ),
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  if (_sheetController.size < 0.2) {
                    _sheetController.animateTo(0.8, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                  } else {
                    _sheetController.animateTo(0.1, duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
                  }
                },
                child: Container(
                  width: double.infinity,
                  color: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Column(
                    children: [
                      Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(height: 10),
                      const Text("VAULT EXPLORER", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: _vaultContent.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final file = _vaultContent[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(file.isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_rounded, size: 18, color: Colors.white38),
                      title: Text(file.realName, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(_formatBytes(file.fileSize), style: const TextStyle(fontSize: 10, color: Colors.white24)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: file.isContentEncrypted ? "Decrypt content" : "Encrypt content",
                            icon: Icon(
                              file.isContentEncrypted ? Icons.lock : Icons.lock_open_outlined,
                              size: 16,
                              color: file.isContentEncrypted ? Colors.blueAccent : Colors.white24,
                            ),
                            onPressed: _isBusy ? null : () => _toggleEncryption(file),
                          ),
                          IconButton(
                            tooltip: "Restore item",
                            icon: const Icon(Icons.unarchive, color: Colors.greenAccent, size: 18),
                            onPressed: _isBusy ? null : () => _unlockSingle(file),
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
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 1)),
        Text(value, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Colors.blueAccent)),
      ],
    );
  }

  Widget _actionButton(String title, IconData icon, Color color, Future<void> Function() action) {
    return InkWell(
      onTap: _isBusy ? null : action,
      borderRadius: BorderRadius.circular(15),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, size: 35, color: color),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 9)),
          ],
        ),
      ),
    );
  }
}
