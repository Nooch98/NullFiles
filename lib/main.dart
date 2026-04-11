import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'dart:math' as math;
import 'package:window_manager/window_manager.dart';

import 'database_helper.dart';
import 'vault_logic.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await VaultDatabase.init();

  const windowOptions = WindowOptions(
    size: Size(360, 500),
    center: true,
    title: 'NullFiles',
    minimumSize: Size(360, 500),
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
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: const ColorScheme.dark(
          primary: Colors.blueAccent,
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

class _MainScreenState extends State<MainScreen> {
  bool _isAuthenticated = false;
  bool _isFirstTime = false;
  bool _isBusy = false;
  int _itemCount = 0;
  String _totalSize = "0 B";

  final TextEditingController _passController = TextEditingController();

  String get _appDirPath => Directory.current.path;
  String get _rootDirPath => Directory.current.parent.path;
  String get _dbPath => p.join(_appDirPath, 'vault_index.db');
  String get _driveLetter => p.rootPrefix(_rootDirPath).toUpperCase();

  @override
  void initState() {
    super.initState();
    _checkVaultStatus();
  }

  @override
  void dispose() {
    _passController.dispose();
    super.dispose();
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
    for (var f in files) {
      totalBytes += f.fileSize;
    }

    if (!mounted) return;
    setState(() {
      _itemCount = files.length;
      _totalSize = _formatBytes(totalBytes);
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (math.log(bytes) / math.log(1024)).floor();
    if (i >= suffixes.length) i = suffixes.length - 1;
    if (i < 0) i = 0;
    return "${(bytes / math.pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}";
  }

  static double MathLog(num x) => double.parse(x.toString()) > 0 ?  (x == 1 ? 0 :  (x.toDouble() < 1 ?  -1 * (1 / x.toDouble()) :  x.toDouble())) : 0;
  double MathPow(num x, num y) {
    double res = 1;
    for (int i = 0; i < y; i++) { res *= x; }
    return res;
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
    } catch (e) {
      if (!mounted) return;
      _showSnack('⚠️ Invalid master key or corrupted vault', Colors.orange);
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
      _showSnack('🔒 HIDE completed: $_itemCount items protected', Colors.blueAccent);
    } catch (e) {
      _showSnack('⚠️ Hide failed: $e', Colors.redAccent);
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
      _showSnack('🔓 SHOW completed: All files restored', Colors.greenAccent);
    } catch (e) {
      _showSnack('⚠️ Show failed: $e', Colors.redAccent);
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
      body: Padding(
        padding: const EdgeInsets.all(30),
        child: _isAuthenticated ? _buildDashboard() : _buildLogin(),
      ),
    );
  }

  Widget _buildLogin() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          _isFirstTime ? Icons.lock_reset : Icons.shield_outlined,
          size: 80,
          color: _isFirstTime ? Colors.orangeAccent : Colors.blueAccent,
        ),
        const SizedBox(height: 20),
        Text(
          _isFirstTime ? 'INITIALIZE VAULT' : 'RESTRICTED ACCESS',
          style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1),
        ),
        const SizedBox(height: 10),
        Text("Target: $_driveLetter", style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 25),
        TextField(
          controller: _passController,
          obscureText: true,
          enabled: !_isBusy,
          decoration: InputDecoration(
            labelText: _isFirstTime ? 'Create Master Key' : 'Enter Master Key',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.vpn_key),
          ),
          onSubmitted: (_) => _login(),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 45,
          child: ElevatedButton(
            onPressed: _isBusy ? null : _login,
            child: _isBusy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_isFirstTime ? 'SETUP VAULT' : 'UNLOCK'),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboard() {
    return Column(
      children: [
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(Icons.lock_open, color: Colors.greenAccent, size: 24),
            Text(_driveLetter, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ],
        ),
        const Divider(color: Colors.white10, height: 30),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              _infoRow("PROTECTED ITEMS", _itemCount.toString()),
              const SizedBox(height: 10),
              _infoRow("ROOT PAYLOAD", _totalSize),
              const SizedBox(height: 10),
              _infoRow("ALGORITHM", "AES-256-GCM"),
            ],
          ),
        ),
        
        const Spacer(),
        
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _actionButton('SHOW', Icons.visibility, Colors.blue, _unlockVault),
            _actionButton('HIDE', Icons.visibility_off, Colors.red, _lockVault),
          ],
        ),
        
        const Spacer(),
        
        if (_isBusy) 
          const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: LinearProgressIndicator(),
          ),

        TextButton.icon(
          onPressed: _isBusy ? null : _closeVault,
          icon: const Icon(Icons.power_settings_new),
          label: const Text('CLOSE VAULT'),
          style: TextButton.styleFrom(foregroundColor: Colors.grey),
        ),
      ],
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
        child: Column(
          children: [
            Icon(icon, size: 45, color: color),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}
