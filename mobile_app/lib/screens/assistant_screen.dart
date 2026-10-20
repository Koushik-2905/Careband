import 'package:flutter/material.dart';

import '../services/ble_gps_service.dart';
import '../services/care_service.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, required this.care, required this.ble});

  final Map<String, dynamic> care;
  final BleGpsService ble;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _ctl = TextEditingController();
  String _reply = 'Ask for medicine, appointment, or call family.\nಮಾತ್ರೆ / ಭೇಟಿ / ಕರೆ';

  Future<void> _run(String q) async {
    final r = CareService.handleIntent(q, widget.care);
    setState(() => _reply = r.spoken);
    if (r.taken) await CareService.medicineTaken();
    if (r.help) await CareService.checkIn('help');
    if (r.call) await CareService.callFamily();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B4332),
        title: const Text('Care assistant', style: TextStyle(fontSize: 22)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_reply, style: const TextStyle(fontSize: 24, height: 1.35)),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('Next medicine', 'ಯಾವ ಮಾತ್ರೆ'),
                _chip('Next appointment', 'ಡಾಕ್ಟರ್ ಭೇಟಿ'),
                _chip('Call daughter', 'ಮಗಳಿಗೆ ಕರೆ'),
                _chip('I need help', 'ಸಹಾಯ'),
              ],
            ),
            const Spacer(),
            TextField(
              controller: _ctl,
              style: const TextStyle(fontSize: 22),
              decoration: const InputDecoration(
                hintText: 'Type or paste what you would say…',
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1B4332), textStyle: const TextStyle(fontSize: 22)),
                onPressed: () => _run(_ctl.text),
                child: const Text('Ask'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String en, String kn) {
    return ActionChip(
      label: Text('$en\n$kn', textAlign: TextAlign.center),
      onPressed: () => _run('$en $kn'),
    );
  }
}
