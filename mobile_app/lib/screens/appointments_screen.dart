import 'package:flutter/material.dart';

import '../services/ble_gps_service.dart';
import '../services/care_service.dart';

class AppointmentsScreen extends StatelessWidget {
  const AppointmentsScreen({super.key, required this.care, required this.ble});

  final Map<String, dynamic> care;
  final BleGpsService ble;

  @override
  Widget build(BuildContext context) {
    final a = Map<String, dynamic>.from(care['appointment'] as Map? ?? {});
    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D3557),
        title: const Text('Appointments', style: TextStyle(fontSize: 22)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${a['doctor'] ?? 'Dr. Rao'}',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('${a['hospital'] ?? 'City Clinic'}\n${a['when'] ?? 'Tomorrow 11:30 AM'}',
                style: const TextStyle(fontSize: 24, height: 1.4)),
            const Spacer(),
            SizedBox(
              height: 80,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1D3557), textStyle: const TextStyle(fontSize: 22)),
                onPressed: () => ble.sendRemind('REMIND:APPT'),
                child: const Text('Buzz my band'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(textStyle: const TextStyle(fontSize: 22)),
                onPressed: CareService.callFamily,
                child: const Text('Call family about this'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
