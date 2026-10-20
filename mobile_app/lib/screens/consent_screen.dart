import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../services/care_service.dart';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key, this.care = const {}});

  final Map<String, dynamic> care;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  Map<String, dynamic> _care = {};
  StreamSubscription<DatabaseEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _care = widget.care;
    _sub = CareService.watch().listen((e) {
      if (mounted) setState(() => _care = CareService.asMap(e.snapshot.value));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Map<String, dynamic>.from(_care['consent'] as Map? ?? {});
    bool on(String k, {bool d = false}) => c[k] == true || (c[k] == null && d);

    Widget tile(String key, String title, String hint, {bool def = false}) {
      final v = on(key, d: def);
      return SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        title: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        subtitle: Text(hint, style: const TextStyle(fontSize: 16)),
        value: v,
        onChanged: (nv) => CareService.setConsent(key, nv),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B4332),
        title: const Text('My privacy', style: TextStyle(fontSize: 22)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'You control what family sees. Emergency rules are visible — not a hidden backdoor.',
            style: TextStyle(fontSize: 18, height: 1.4),
          ),
          tile('emergency', 'Emergency alerts', 'ON by default', def: true),
          tile('wellbeing', 'Daily wellbeing', 'Check-ins', def: true),
          tile('medicine', 'Medicine adherence', 'Taken / missed', def: true),
          tile('heartRate', 'Heart-rate data', 'Shown to family unless you turn it off', def: true),
          tile('activity', 'Detailed activity history', 'OFF by default'),
          tile('location', 'Location always', 'OFF by default'),
          tile('locationInEmergency', 'Location in emergencies only', 'Ask at onboarding', def: true),
          const SizedBox(height: 12),
          const Text('Raw sensor data is never sent to family.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
