import 'package:flutter/material.dart';

import '../services/ble_gps_service.dart';
import '../services/care_service.dart';

class BandStatusScreen extends StatefulWidget {
  const BandStatusScreen({super.key, required this.ble, this.error});

  final BleGpsService ble;
  final String? error;

  @override
  State<BandStatusScreen> createState() => _BandStatusScreenState();
}

class _BandStatusScreenState extends State<BandStatusScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B4332),
        title: const Text('Band & GPS', style: TextStyle(fontSize: 22)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.ble.connected ? 'Wristband connected' : 'Wristband not connected',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text(
              'Keep this app open. GPS is sent to the band every 10 seconds. The caretaker app gets alerts over Firebase — not a tracking dashboard.',
              style: TextStyle(fontSize: 18, height: 1.4),
            ),
            if (widget.error != null) ...[
              const SizedBox(height: 16),
              Text(widget.error!, style: const TextStyle(color: Color(0xFF9B1C1C), fontSize: 16)),
            ],
            const Spacer(),
            SizedBox(
              height: 64,
              child: OutlinedButton(
                onPressed: () => CareService.demoPossibleEvent('FALL_SUSPECTED'),
                child: const Text('Demo: possible fall (stage)', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 72,
              child: FilledButton(
                onPressed: widget.ble.connected
                    ? () async {
                        await widget.ble.sendGpsNow();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GPS sent')));
                        }
                      }
                    : null,
                child: const Text('Send GPS now', style: TextStyle(fontSize: 22)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
