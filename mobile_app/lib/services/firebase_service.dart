import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../firebase_options.dart';
import 'relay_service.dart';

class FirebaseService {
  static bool _initialized = false;
  static String? lastError;

  static Future<bool> initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        try {
          await Firebase.initializeApp();
        } catch (_) {
          await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
        }
      }
      _initialized = true;
      lastError = null;
      try {
        await FirebaseMessaging.instance.requestPermission();
      } catch (_) {}
      return true;
    } catch (e) {
      _initialized = false;
      lastError = '$e';
      return false;
    }
  }

  static bool get isReady => _initialized;

  static Future<bool> ensureReady() async {
    if (_initialized) return true;
    return initialize();
  }

  static int? _lastVitalsState;
  static DateTime? _lastVitalsPush;
  static DateTime? _lastBackupAlert;

  static Future<void> logEvent({
    required String deviceId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    if (!await ensureReady()) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final body = {
      'type': type,
      'ts': ts,
      ...payload,
    };
    final eventsRef = FirebaseDatabase.instance.ref('devices/$deviceId/events').push();
    await eventsRef.set(body);
    final loud = type != 'CHECKIN_UNWELL' &&
        type != 'CHECKIN_FINE' &&
        type != 'MEDICINE_SNOOZE' &&
        type != 'MEDICINE_TAKEN';
    if (loud) {
      await FirebaseDatabase.instance.ref('devices/$deviceId/activeAlert').set({
        ...body,
        'id': eventsRef.key,
      });
    }
  }

  static Future<void> logSeizureAlert(Map<String, dynamic> alert) async {
    _lastBackupAlert = DateTime.now();
    final payload = Map<String, dynamic>.from(alert)..remove('ts');
    if (alert['valid'] == true) payload['locSrc'] = payload['locSrc'] ?? 'phone';
    final type = '${alert['type'] ?? 'SEIZURE_SUSPECTED'}';
    if (await ensureReady()) {
      await logEvent(
        deviceId: 'neuroguard-001',
        type: type,
        payload: payload,
      );
    } else {
      await RelayService.pushAlert({
        'type': type,
        ...payload,
      });
    }
  }

  static Future<void> logVitals(Map<String, dynamic> data) async {
    if (!await ensureReady()) {
      await RelayService.pushVitals(data);
      return;
    }
    final state = (data['state'] as num?)?.toInt();
    final prevState = _lastVitalsState;
    final stateChanged = state != null && state != prevState;
    final now = DateTime.now();
    if (!stateChanged &&
        _lastVitalsPush != null &&
        now.difference(_lastVitalsPush!) < const Duration(seconds: 2)) {
      return;
    }
    _lastVitalsPush = now;
    _lastVitalsState = state;
    await FirebaseDatabase.instance.ref('devices/neuroguard-001/vitals').set({
      'state': data['state'],
      'hr': data['hr'],
      'conf': data['conf'],
      'ml': data['ml'],
      'gpsOk': data['gpsOk'],
      'lat': data['lat'],
      'lng': data['lng'],
      'locSrc': data['locSrc'],
      'ts': ServerValue.timestamp,
    });

    if (state == 2 && prevState != null && prevState != 2) {
      if (_lastBackupAlert != null && now.difference(_lastBackupAlert!) < const Duration(seconds: 20)) {
        return;
      }
      _lastBackupAlert = now;
      await logSeizureAlert({
        'type': data['evt'] ?? 'SEIZURE_SUSPECTED',
        'conf': ((data['conf'] as num?)?.toDouble() ?? 0) > 1
            ? (data['conf'] as num).round()
            : (((data['conf'] as num?)?.toDouble() ?? 0) * 100).round(),
        'hr': data['hr'],
        'lat': data['lat'],
        'lng': data['lng'],
        'valid': data['gpsOk'] == true,
        'locSrc': data['locSrc'] ?? 'phone',
      });
    }
  }
}
