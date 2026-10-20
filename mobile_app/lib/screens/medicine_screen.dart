import 'package:flutter/material.dart';

import '../services/ble_gps_service.dart';
import '../services/care_service.dart';

class MedicineScreen extends StatelessWidget {
  const MedicineScreen({super.key, required this.care, required this.ble});

  final Map<String, dynamic> care;
  final BleGpsService ble;

  @override
  Widget build(BuildContext context) {
    final med = Map<String, dynamic>.from(care['medicine'] as Map? ?? {});
    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D6A4F),
        title: const Text('Medicine', style: TextStyle(fontSize: 22)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Take ${med['name'] ?? 'BP tablet'} at ${med['time'] ?? '19:00'}.',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.3),
            ),
            const SizedBox(height: 8),
            Text('${med['instructions'] ?? ''}', style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 8),
            Text('Status: ${med['status'] ?? 'pending'}', style: const TextStyle(fontSize: 18)),
            const Spacer(),
            _action(context, 'TAKEN', const Color(0xFF2D6A4F), () async {
              await CareService.medicineTaken();
              if (context.mounted) Navigator.pop(context);
            }),
            const SizedBox(height: 12),
            _action(context, 'REMIND ME LATER', const Color(0xFF7B4B2A), () async {
              await CareService.medicineLater();
              await ble.sendRemind('REMIND:MED');
              if (context.mounted) Navigator.pop(context);
            }),
          ],
        ),
      ),
    );
  }

  Widget _action(BuildContext context, String label, Color color, VoidCallback onTap) {
    return SizedBox(
      height: 80,
      child: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: color, textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        onPressed: onTap,
        child: Text(label),
      ),
    );
  }
}
