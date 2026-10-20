import 'package:flutter/material.dart';

import '../services/ble_gps_service.dart';
import '../services/care_service.dart';

class CheckinScreen extends StatefulWidget {
  const CheckinScreen({super.key, required this.ble});

  final BleGpsService ble;

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  bool _busy = false;

  Future<void> _submit(String response, String message) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await CareService.checkIn(response);
      if (response == 'unwell') {
        await widget.ble.sendRemind('REMIND:CHECK');
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Saved'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('OK', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7B4B2A),
        title: const Text('How I feel', style: TextStyle(fontSize: 22)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Good morning, how are you feeling?',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.3)),
            const Spacer(),
            if (_busy) const Center(child: CircularProgressIndicator()),
            _btn('I AM FINE', const Color(0xFF2D6A4F), () {
              _submit('fine', 'Saved: I am fine. Family can see this.');
            }),
            const SizedBox(height: 12),
            _btn('NOT FEELING WELL', const Color(0xFFC9A227), () {
              _submit('unwell', 'Saved: not feeling well. Family was notified.');
            }),
            const SizedBox(height: 12),
            _btn('I NEED HELP', const Color(0xFF9B1C1C), () {
              _submit('help', 'Emergency sent to family.');
            }),
          ],
        ),
      ),
    );
  }

  Widget _btn(String label, Color color, VoidCallback onTap) {
    return SizedBox(
      height: 88,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        onPressed: _busy ? null : onTap,
        child: Text(label),
      ),
    );
  }
}
