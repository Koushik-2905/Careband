import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../services/ble_gps_service.dart';
import '../services/care_service.dart';
import '../services/firebase_service.dart';
import 'appointments_screen.dart';
import 'assistant_screen.dart';
import 'band_status_screen.dart';
import 'checkin_screen.dart';
import 'consent_screen.dart';
import 'medicine_screen.dart';

/// Large-button elder home. BLE GPS relay stays connected in the background.
class ElderHomeScreen extends StatefulWidget {
  const ElderHomeScreen({super.key, this.device});

  final BluetoothDevice? device;

  @override
  State<ElderHomeScreen> createState() => _ElderHomeScreenState();
}

class _ElderHomeScreenState extends State<ElderHomeScreen> {
  late BleGpsService _ble;
  bool _connected = false;
  String? _error;
  Map<String, dynamic> _care = {};
  Map<String, dynamic> _lastVitals = {};
  StreamSubscription<DatabaseEvent>? _careSub;

  @override
  void initState() {
    super.initState();
    _ble = BleGpsService(
      onAlert: _onAlert,
      onSensorData: (data) {
        _lastVitals = data;
        if (mounted) setState(() {});
        FirebaseService.logVitals(data);
      },
    );
    _boot();
  }

  Future<void> _boot() async {
    await FirebaseService.ensureReady();
    await CareService.ensureDefaults();
    if (mounted) setState(() {});
    _careSub = CareService.watch().listen((e) {
      if (!mounted) return;
      setState(() => _care = CareService.asMap(e.snapshot.value));
    });
    if (widget.device == null) return;
    try {
      await _ble.connect(widget.device!);
      if (mounted) setState(() => _connected = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _onAlert(Map<String, dynamic> data) {
    final merged = Map<String, dynamic>.from(data);
    final lat = (merged['lat'] as num?)?.toDouble() ?? 0;
    final lng = (merged['lng'] as num?)?.toDouble() ?? 0;
    if (lat.abs() < 0.0001 && lng.abs() < 0.0001) {
      merged['lat'] = _lastVitals['lat'];
      merged['lng'] = _lastVitals['lng'];
      merged['valid'] = true;
      merged['locSrc'] = 'phone';
    }
    FirebaseService.logSeizureAlert(merged);
    final type = '${merged['type'] ?? 'SEIZURE_SUSPECTED'}';
    CareService.setEscalation(4, 'escalated', type);
    if (!mounted) return;
    final hr = (merged['hr'] as num?)?.toInt() ?? (_lastVitals['hr'] as num?)?.toInt() ?? 0;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF9B1C1C),
        title: const Text('Possible event', style: TextStyle(color: Colors.white, fontSize: 24)),
        content: Text(
          'Family is being notified.\nHeart rate: ${hr > 0 ? "$hr BPM" : "—"}\nIf you are okay, press the band button.',
          style: const TextStyle(color: Colors.white, fontSize: 20, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.white, fontSize: 20)),
          ),
        ],
      ),
    );
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  void dispose() {
    _careSub?.cancel();
    _ble.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B4332),
        foregroundColor: Colors.white,
        title: const Text('CAREBand', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Privacy',
            icon: const Icon(Icons.privacy_tip_outlined, size: 28),
            onPressed: () => _open(ConsentScreen(care: _care)),
          ),
          IconButton(
            tooltip: 'Band / GPS',
            icon: Icon(_connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled, size: 28),
            onPressed: () => _open(BandStatusScreen(ble: _ble, error: _error)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.large(
        backgroundColor: const Color(0xFF1B4332),
        onPressed: () => _open(AssistantScreen(care: _care, ble: _ble)),
        child: const Icon(Icons.mic, size: 40, color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _connected
                    ? 'Band connected'
                    : 'Connect the band from the Bluetooth icon, or use demo buttons',
                style: const TextStyle(fontSize: 16, color: Color(0xFF3D4A40)),
              ),
              const SizedBox(height: 8),
              _vitalsStrip(),
              const SizedBox(height: 8),
              Expanded(
                child: _BigButton(
                  label: 'MEDICINE',
                  kn: 'ಮಾತ್ರೆ',
                  color: const Color(0xFF2D6A4F),
                  icon: Icons.medication,
                  onTap: () => _open(MedicineScreen(care: _care, ble: _ble)),
                ),
              ),
              Expanded(
                child: _BigButton(
                  label: 'APPOINTMENTS',
                  kn: 'ಡಾಕ್ಟರ್ ಭೇಟಿ',
                  color: const Color(0xFF1D3557),
                  icon: Icons.event,
                  onTap: () => _open(AppointmentsScreen(care: _care, ble: _ble)),
                ),
              ),
              Expanded(
                child: _BigButton(
                  label: 'HOW I FEEL',
                  kn: 'ನಾನು ಹೇಗಿದ್ದೇನೆ',
                  color: const Color(0xFF7B4B2A),
                  icon: Icons.favorite,
                  onTap: () => _open(CheckinScreen(ble: _ble)),
                ),
              ),
              Expanded(
                child: _BigButton(
                  label: 'CALL FAMILY',
                  kn: 'ಕುಟುಂಬಕ್ಕೆ ಕರೆ',
                  color: const Color(0xFF3A5A40),
                  icon: Icons.call,
                  onTap: CareService.callFamily,
                ),
              ),
              Expanded(
                child: _BigButton(
                  label: 'EMERGENCY',
                  kn: 'ತುರ್ತು',
                  color: const Color(0xFF9B1C1C),
                  icon: Icons.sos,
                  onTap: () async {
                    try {
                      await CareService.demoPossibleEvent(
                        'SOS',
                        lat: (_lastVitals['lat'] as num?)?.toDouble(),
                        lng: (_lastVitals['lng'] as num?)?.toDouble(),
                        hr: (_lastVitals['hr'] as num?)?.toInt() ?? 0,
                      );
                      await _ble.sendRemind('SOS');
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Emergency sent to family')),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Emergency failed: $e')),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vitalsStrip() {
    final hr = (_lastVitals['hr'] as num?)?.toInt() ?? 0;
    final state = (_lastVitals['state'] as num?)?.toInt() ?? 0;
    final gpsOk = _lastVitals['gpsOk'] == true;
    const labels = ['Monitoring', 'Possible event', 'Alert sent', 'Cancelled'];
    final status = (state >= 0 && state < labels.length) ? labels[state] : '—';
    final fb = FirebaseService.isReady ? 'Cloud ON' : 'Cloud OFF';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1B4332)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(hr > 0 ? '$hr BPM' : 'BPM —',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text(status, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(gpsOk ? 'GPS on band' : 'GPS waiting', style: const TextStyle(fontSize: 14)),
              Text(fb, style: TextStyle(fontSize: 14, color: FirebaseService.isReady ? Colors.green[800] : Colors.red[800])),
            ],
          ),
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.kn,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String kn;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 40),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          )),
                      Text(kn, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
