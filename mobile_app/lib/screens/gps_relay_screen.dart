import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../services/ble_gps_service.dart';
import '../services/firebase_service.dart';
import '../widgets/connection_banner.dart';

/// Patient phone app — connects to wristband and relays GPS over BLE.
/// Vitals/alerts are forwarded to Firebase for the caretaker (main) app.
class GpsRelayScreen extends StatefulWidget {
  const GpsRelayScreen({super.key, required this.device});

  final BluetoothDevice device;

  @override
  State<GpsRelayScreen> createState() => _GpsRelayScreenState();
}

class _GpsRelayScreenState extends State<GpsRelayScreen> {
  late BleGpsService _ble;
  bool _connecting = true;
  String? _error;
  bool _gpsOk = false;
  int _hr = 0;
  DateTime? _lastGpsSend;

  @override
  void initState() {
    super.initState();
    _ble = BleGpsService(
      onAlert: _onAlert,
      onSensorData: _onSensor,
    );
    _connect();
  }

  Future<void> _connect() async {
    try {
      await _ble.connect(widget.device);
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = '$e';
        });
      }
    }
  }

  void _onAlert(Map<String, dynamic> data) {
    FirebaseService.logSeizureAlert(data);
  }

  void _onSensor(Map<String, dynamic> data) {
    FirebaseService.logVitals(data);
    if (!mounted) return;
    setState(() {
      _gpsOk = data['gpsOk'] == true;
      _hr = (data['hr'] as num?)?.toInt() ?? 0;
    });
  }

  Future<void> _sendGpsNow() async {
    await _ble.sendGpsNow();
    if (mounted) setState(() => _lastGpsSend = DateTime.now());
  }

  @override
  void dispose() {
    _ble.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050A07),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'GPS Relay',
          style: TextStyle(color: Color(0xFF00FF9D), fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF00FF9D)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConnectionBanner(connected: _ble.connected, gpsOk: _gpsOk),
          if (_connecting)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF00FF9D)),
              ),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, style: const TextStyle(color: Color(0xFFFF4D6D))),
                ),
              ),
            )
          else
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.location_on, size: 64, color: Color(0xFF00FF9D)),
                    const SizedBox(height: 16),
                    const Text(
                      'Keep this app open on the patient phone',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'GPS is sent to the wristband every 10 seconds over Bluetooth. '
                      'The caretaker app receives alerts and location via Firebase.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    _row('Wristband', _ble.connected ? 'Connected' : 'Disconnected'),
                    _row('GPS on band', _gpsOk ? 'Active' : 'Waiting for fix…'),
                    _row('Heart rate', _hr > 0 ? '$_hr BPM' : '—'),
                    if (_lastGpsSend != null)
                      _row('Last GPS push', _lastGpsSend!.toLocal().toString().substring(11, 19)),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _ble.connected ? _sendGpsNow : null,
                      icon: const Icon(Icons.my_location),
                      label: const Text('Send GPS now'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF00FF9D),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(value, style: const TextStyle(color: Color(0xFFE8F5E8), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
