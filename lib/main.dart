import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'database_helper.dart';
import 'vault_logic.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await VaultDatabase.init();

  const windowOptions = WindowOptions(
    size: Size(350, 450),
    center: true,
    title: 'NullFiles',
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
        scaffoldBackgroundColor: const Color(0xFF121212),
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

  final TextEditingController _passController = TextEditingController();

  String get _appDirPath => Directory.current.path;
  String get _rootDirPath => Directory.current.parent.path;
  String get _dbPath => p.join(_appDirPath, 'vault_index.db');

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

  Future<void> _login() async {
    final inputPass = _passController.text.trim();
    if (inputPass.isEmpty || _isBusy) return;

    setState(() {
      _isBusy = true;
    });

    try {
      await VaultDatabase.openVault(
        password: inputPass,
        databasePath: _dbPath,
      );

      if (!mounted) return;

      setState(() {
        _isAuthenticated = true;
        _isFirstTime = false;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFirstTime
                ? '⚠️ Failed to initialize vault'
                : '⚠️ Invalid master key or corrupted vault',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      _passController.clear();

      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _lockVault() async {
    if (_isBusy) return;

    setState(() {
      _isBusy = true;
    });

    try {
      await VaultLogic.lockEverything(
        rootPath: _rootDirPath,
        appDirPath: _appDirPath,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('HIDE completed successfully'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Hide failed: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _unlockVault() async {
    if (_isBusy) return;

    setState(() {
      _isBusy = true;
    });

    try {
      await VaultLogic.unlockEverything(
        rootPath: _rootDirPath,
        appDirPath: _appDirPath,
        overwriteExisting: false,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SHOW completed successfully'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Show failed: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _closeVault() async {
    await VaultDatabase.close();

    if (!mounted) return;

    setState(() {
      _isAuthenticated = false;
    });

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
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
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
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isFirstTime ? 'SETUP VAULT' : 'UNLOCK'),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboard() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.lock_open,
          color: Colors.greenAccent,
          size: 40,
        ),
        const SizedBox(height: 10),
        const Text(
          'SYSTEM ACTIVE',
          style: TextStyle(
            color: Colors.greenAccent,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _actionButton(
              'SHOW',
              Icons.visibility,
              Colors.blue,
              _unlockVault,
            ),
            _actionButton(
              'HIDE',
              Icons.visibility_off,
              Colors.red,
              _lockVault,
            ),
          ],
        ),
        const SizedBox(height: 50),
        TextButton.icon(
          onPressed: _isBusy ? null : _closeVault,
          icon: const Icon(Icons.power_settings_new),
          label: const Text('CLOSE VAULT'),
        ),
      ],
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
      borderRadius: BorderRadius.circular(10),
      child: Opacity(
        opacity: _isBusy ? 0.5 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 10,
          ),
          child: Column(
            children: [
              Icon(icon, size: 50, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}