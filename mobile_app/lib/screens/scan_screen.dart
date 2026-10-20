import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../constants/ble_uuids.dart';
import '../services/permissions_service.dart';
import 'elder_home_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<ScanResult> _results = [];
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() {
      _error = null;
      _scanning = true;
      _results = [];
    });

    final ok = await PermissionsService.ensureBleAndLocation();
    if (!ok) {
      setState(() {
        _error = 'Bluetooth and location permissions required';
        _scanning = false;
      });
      return;
    }

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
    FlutterBluePlus.scanResults.listen((list) {
      if (!mounted) return;
      setState(() {
        _results = list.where((r) {
          final name = r.device.platformName.toLowerCase();
          final adv = r.advertisementData.advName.toLowerCase();
          final target = BleUuids.deviceName.toLowerCase();
          return name.contains(target) ||
              adv.contains(target) ||
              r.advertisementData.serviceUuids
                  .map((u) => u.toString().toLowerCase())
                  .contains(BleUuids.service.toLowerCase());
        }).toList();
      });
    });

    await Future.delayed(const Duration(seconds: 8));
    await FlutterBluePlus.stopScan();
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connect(BluetoothDevice device) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ElderHomeScreen(device: device)),
    );
    _startScan();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B4332),
        title: const Text('CAREBand — connect band'),
        actions: [
          IconButton(
            icon: _scanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00FF9D)),
                  )
                : const Icon(Icons.refresh, color: Color(0xFF00FF9D)),
            onPressed: _scanning ? null : _startScan,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: Color(0xFF9B1C1C), fontSize: 18)),
            ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _scanning ? 'Scanning for CAREBand / NeuroGuard…' : 'No device found. Power on the ESP32.',
                      style: const TextStyle(fontSize: 18, color: Color(0xFF3D4A40)),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final r = _results[i];
                      return ListTile(
                        title: Text(
                          r.device.platformName.isNotEmpty
                              ? r.device.platformName
                              : BleUuids.deviceName,
                          style: const TextStyle(fontSize: 20, color: Colors.black),
                        ),
                        subtitle: Text(r.device.remoteId.str),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _connect(r.device),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 64,
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ElderHomeScreen()),
                  );
                },
                child: const Text('Continue without band (demo)', style: TextStyle(fontSize: 18)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
