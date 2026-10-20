import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../constants/device_config.dart';
import '../models/patient_vitals.dart';
import '../models/seizure_event.dart';

typedef VitalsCallback = void Function(PatientVitals vitals);
typedef AlertCallback = void Function(SeizureEvent event);
typedef CareCallback = void Function(Map<String, dynamic> care);

class FirebaseCaretakerService {
  static bool _initialized = false;
  static String? _lastLiveAlertId;
  static StreamSubscription<DatabaseEvent>? _vitalsSub;
  static StreamSubscription<DatabaseEvent>? _eventsSub;
  static StreamSubscription<DatabaseEvent>? _careSub;
  static StreamSubscription<DatabaseEvent>? _activeSub;

  static Future<bool> initialize() async {
    try {
      await Firebase.initializeApp();
      _initialized = true;
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
      );
      await FirebaseMessaging.instance.subscribeToTopic('caretaker_$deviceId');
      return true;
    } catch (e) {
      _initialized = false;
      return false;
    }
  }

  static bool get isReady => _initialized;

  static Map<String, dynamic> mapOf(Object? v) {
    if (v is Map) {
      return Map<String, dynamic>.from(v.map((k, val) => MapEntry('$k', val)));
    }
    return {};
  }

  static bool _isQuiet(String type) {
    return type == 'CHECKIN_UNWELL' ||
        type == 'CHECKIN_FINE' ||
        type == 'MEDICINE_SNOOZE' ||
        type == 'MEDICINE_TAKEN';
  }

  static bool _isRecent(DateTime when, DateTime started) {
    return when.isAfter(started.subtract(const Duration(seconds: 20)));
  }

  static void listen({
    required VitalsCallback onVitals,
    required AlertCallback onNewAlert,
    CareCallback? onCare,
    AlertCallback? onHistory,
  }) {
    if (!_initialized) return;

    _vitalsSub?.cancel();
    _eventsSub?.cancel();
    _careSub?.cancel();
    _activeSub?.cancel();

    final started = DateTime.now();
    var firstVitals = true;
    var lastState = -1;

    if (onCare != null) {
      _careSub = FirebaseDatabase.instance.ref(carePath).onValue.listen((e) {
        onCare(mapOf(e.snapshot.value));
      });
    }

    _vitalsSub = FirebaseDatabase.instance.ref(vitalsPath).onValue.listen((e) {
      final v = PatientVitals.fromMap(e.snapshot.value as Map<dynamic, dynamic>?);
      onVitals(v);

      // First snapshot is leftover data. Never treat it as a new attack.
      if (firstVitals) {
        firstVitals = false;
        lastState = v.state;
        return;
      }

      final roseFromIdle = lastState == 0 && (v.state == 1 || v.state == 2);
      lastState = v.state;
      if (!roseFromIdle) return;

      onNewAlert(
        SeizureEvent(
          id: 'vitals-${DateTime.now().millisecondsSinceEpoch}',
          type: 'SEIZURE_SUSPECTED',
          conf: (v.confidence > 1 ? v.confidence : v.confidence * 100).round(),
          hr: v.hr,
          lat: v.lat ?? 0,
          lng: v.lng ?? 0,
          valid: v.gpsOk && v.lat != null && v.lng != null,
          when: DateTime.now(),
          locSrc: v.locSrc,
        ),
      );
    });

    _activeSub = FirebaseDatabase.instance.ref(activeAlertPath).onValue.listen((e) {
      final val = e.snapshot.value;
      if (val is! Map) return;
      final map = Map<dynamic, dynamic>.from(val);
      final event = SeizureEvent.fromSnapshot(
        map['id']?.toString() ?? map['ts']?.toString() ?? 'active',
        map,
      );
      if (event.id == _lastLiveAlertId) return;
      if (!_isRecent(event.when, started)) return;
      if (_isQuiet(event.type)) return;
      _lastLiveAlertId = event.id;
      onNewAlert(event);
    });

    final eventsRef = FirebaseDatabase.instance.ref(eventsPath);
    eventsRef.limitToLast(12).get().then((snap) {
      if (onHistory == null) return;
      for (final child in snap.children) {
        final id = child.key;
        final val = child.value;
        if (id == null || val is! Map) continue;
        onHistory(SeizureEvent.fromSnapshot(id, val));
      }
    });

    _eventsSub = eventsRef.onChildAdded.listen((e) {
      final id = e.snapshot.key;
      final val = e.snapshot.value;
      if (id == null || val is! Map) return;
      final event = SeizureEvent.fromSnapshot(id, val);
      if (!_isRecent(event.when, started)) return;
      if (_isQuiet(event.type)) {
        onHistory?.call(event);
        return;
      }
      if (id == _lastLiveAlertId) return;
      _lastLiveAlertId = id;
      onNewAlert(event);
    });
  }

  static Future<void> ackCare() async {
    if (!_initialized) return;
    await FirebaseDatabase.instance.ref('$carePath/escalation').update({
      'level': 0,
      'state': 'acknowledged',
    });
    await clearActiveAlert();
  }

  static Future<void> clearActiveAlert() async {
    if (!_initialized) return;
    await FirebaseDatabase.instance.ref(activeAlertPath).remove();
  }

  static void dispose() {
    _vitalsSub?.cancel();
    _eventsSub?.cancel();
    _careSub?.cancel();
    _activeSub?.cancel();
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}
