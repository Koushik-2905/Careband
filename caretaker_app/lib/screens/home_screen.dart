import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/device_config.dart';
import '../models/patient_vitals.dart';
import '../models/seizure_event.dart';
import '../services/alarm_service.dart';
import '../services/firebase_caretaker_service.dart';
import '../services/notification_service.dart';
import 'alarm_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _firebaseOk = false;
  PatientVitals? _vitals;
  final List<SeizureEvent> _events = [];
  final Set<String> _acked = {};
  Map<String, dynamic> _care = {};

  bool _share(String key, {bool fallback = false}) {
    final c = _care['consent'];
    if (c is! Map) return fallback;
    return c[key] == true || (c[key] == null && fallback);
  }

  bool _canShowLocation({required bool emergency}) {
    if (_share('location')) return true;
    return emergency && _share('locationInEmergency', fallback: true);
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final ok = await FirebaseCaretakerService.initialize();
    setState(() => _firebaseOk = ok);

    if (!ok) return;

    FirebaseCaretakerService.listen(
      onCare: (c) {
        if (!mounted) return;
        setState(() => _care = c);
      },
      onHistory: (e) {
        if (!mounted) return;
        setState(() {
          if (_events.any((x) => x.id == e.id)) return;
          _events.add(e);
          _events.sort((a, b) => b.when.compareTo(a.when));
        });
      },
      onVitals: (v) {
        if (!mounted) return;
        setState(() => _vitals = v);
      },
      onNewAlert: (e) {
        if (!mounted) return;
        final merged = _withLiveGps(e);
        setState(() {
          if (_events.any((x) => x.id == merged.id)) return;
          _events.insert(0, merged);
        });
        _triggerAlarm(merged);
      },
    );
  }

  SeizureEvent _withLiveGps(SeizureEvent e) {
    final v = _vitals;
    if (e.lat.abs() > 0.0001 || e.lng.abs() > 0.0001) return e;
    if (v?.lat == null || v?.lng == null) return e;
    if (v!.lat!.abs() < 0.0001 && v.lng!.abs() < 0.0001) return e;
    return SeizureEvent(
      id: e.id,
      type: e.type,
      conf: e.conf,
      hr: e.hr > 0 ? e.hr : v.hr,
      lat: v.lat!,
      lng: v.lng!,
      valid: true,
      when: e.when,
      locSrc: v.locSrc,
      level: e.level,
    );
  }

  Future<void> _triggerAlarm(SeizureEvent e) async {
    if (AlarmService.isActive) return;
    if (!mounted) return;
    e = _withLiveGps(e);

    await NotificationService.showSeizureAlert(
      hr: e.hr,
      conf: e.conf,
      hasMap: e.valid,
    );

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlarmScreen(event: e),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  void dispose() {
    FirebaseCaretakerService.dispose();
    AlarmService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _vitals;
    final fmt = DateFormat.Hm();

    return Scaffold(
      backgroundColor: const Color(0xFF050A07),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('CAREBand family', style: TextStyle(color: Color(0xFF00FF9D), fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _banner(
            _firebaseOk
                ? 'Live · Firebase $deviceId · patient GPS app must stay connected'
                : 'Firebase not configured — add google-services.json (see README)',
            ok: _firebaseOk,
          ),
          const SizedBox(height: 12),
          _statusCard(),
          const SizedBox(height: 12),
          _card(
            title: 'Live vitals',
            child: v == null
                ? const Text('Waiting for patient GPS app…', style: TextStyle(color: Colors.white54))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row('Heart rate', v.hr > 0 ? '${v.hr} BPM' : 'Waiting for band…'),
                      _row('Status', v.stateLabel),
                      _row('Confidence', '${(v.confidence > 1 ? v.confidence : v.confidence * 100).toStringAsFixed(0)}%'),
                      _row(
                        'Location',
                        _canShowLocation(emergency: v.state >= 1)
                            ? (v.gpsOk ? '${v.lat?.toStringAsFixed(5)}, ${v.lng?.toStringAsFixed(5)}' : 'Unavailable')
                            : 'Not shared by $elderLabel',
                      ),
                      if (v.locSrc == 'sim' && _canShowLocation(emergency: v.state >= 1))
                        const Text('Approx (SIM cell)', style: TextStyle(color: Colors.amber, fontSize: 12)),
                      if (v.updatedAt != null)
                        Text('Updated ${fmt.format(v.updatedAt!)}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      if (_canShowLocation(emergency: v.state >= 1) && v.lat != null && v.lng != null && (v.lat!.abs() > 0.0001 || v.lng!.abs() > 0.0001)) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse('https://maps.google.com/?q=${v.lat},${v.lng}'),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.map, color: Color(0xFF00FF9D)),
                          label: const Text('Open Google Maps'),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          _card(
            title: 'Alert history',
            child: _events.isEmpty
                ? const Text('No alerts yet', style: TextStyle(color: Colors.white54))
                : Column(
                    children: _events.take(10).map((e) {
                      final acked = _acked.contains(e.id);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${e.title} · ${fmt.format(e.when)}',
                          style: TextStyle(color: acked ? Colors.white54 : Colors.white),
                        ),
                        subtitle: Text('HR ${e.hr} · ${e.conf}%'),
                        trailing: e.valid
                            ? IconButton(
                                icon: const Icon(Icons.map, color: Color(0xFF00B4D8)),
                                onPressed: () => launchUrl(Uri.parse(e.mapsUrl), mode: LaunchMode.externalApplication),
                              )
                            : null,
                        onTap: acked ? null : () => _triggerAlarm(e),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Patient phone must run the Patient GPS app (mobile_app), stay connected over BLE, and keep location on.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _banner(String text, {required bool ok}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFF0D2818) : const Color(0xFF2A1A05),
        border: Border.all(color: ok ? const Color(0xFF00FF9D) : Colors.orange),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(color: ok ? const Color(0xFF00FF9D) : Colors.orange, fontSize: 12)),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1410),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E2A22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Color(0xFF00FF9D), fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  String get elderLabel => '${(_care['profile'] is Map) ? (_care['profile'] as Map)['name'] ?? 'elder' : 'elder'}';

  Widget _statusCard() {
    final esc = Map<String, dynamic>.from(_care['escalation'] as Map? ?? {});
    final med = Map<String, dynamic>.from(_care['medicine'] as Map? ?? {});
    final chk = Map<String, dynamic>.from(_care['checkin'] as Map? ?? {});
    final appt = Map<String, dynamic>.from(_care['appointment'] as Map? ?? {});
    final insight = Map<String, dynamic>.from(_care['insight'] as Map? ?? {});
    final level = (esc['level'] as num?)?.toInt() ?? 0;
    final safe = level < 3;

    return _card(
      title: '$elderLabel   Status: ${safe ? 'SAFE' : 'NEEDS ATTENTION'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_share('wellbeing', fallback: true))
            _row('Today check-in', '${chk['label'] ?? _checkinLabel(chk['response'])}')
          else
            _row('Today check-in', 'Not shared by $elderLabel'),
          if (_share('medicine', fallback: true))
            _row('Medicine', '${med['name'] ?? '—'} · ${med['status'] ?? 'pending'}')
          else
            _row('Medicine', 'Not shared by $elderLabel'),
          _row('Upcoming', '${appt['doctor'] ?? '—'} · ${appt['when'] ?? ''}'),
          if (_share('wellbeing', fallback: true))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${insight['text'] ?? 'Routine looks normal today.'}',
                style: const TextStyle(color: Color(0xFFE8F5E8)),
              ),
            )
          else
            Text('Wellbeing not shared by $elderLabel', style: const TextStyle(color: Colors.white38)),
          const SizedBox(height: 8),
          Text(
            'Permissions: Emergency ${_on('emergency')}  Wellbeing ${_on('wellbeing')}  '
            'Medicine ${_on('medicine')}  Location ${_on('location')}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          if (level >= 3) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => FirebaseCaretakerService.ackCare(),
              child: const Text('Acknowledge'),
            ),
          ],
        ],
      ),
    );
  }

  String _checkinLabel(dynamic raw) {
    switch ('$raw') {
      case 'fine':
        return 'I am fine';
      case 'unwell':
        return 'Not feeling well';
      case 'help':
        return 'Needs help';
      default:
        return 'No check-in yet';
    }
  }

  String _on(String k) => _share(k, fallback: k != 'activity') ? '✔' : '✖';

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: Colors.white70)),
            Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
