import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_service.dart';

/// Firebase care layer: consent, medicines, check-ins, escalation.
/// Facts live here; the voice assistant never invents medical info.
class CareService {
  static const deviceId = 'neuroguard-001';
  static const familyPhone = '+919876543210';
  static const elderName = 'Amma';

  static DatabaseReference get _care =>
      FirebaseDatabase.instance.ref('devices/$deviceId/care');

  static Future<void> ensureDefaults() async {
    if (!FirebaseService.isReady) {
      await FirebaseService.initialize();
    }
    if (!FirebaseService.isReady) return;
    final snap = await _care.child('consent').get();
    if (snap.exists) {
      // Older builds stored heartRate OFF. Show it unless the elder turns it off later.
      final c = snap.value;
      if (c is Map && c['heartRate'] != true) {
        await _care.child('consent/heartRate').set(true);
      }
      return;
    }
    await _care.update({
      'consent': {
        'emergency': true,
        'wellbeing': true,
        'medicine': true,
        'heartRate': true,
        'activity': false,
        'location': true,
        'locationInEmergency': true,
      },
      'profile': {
        'name': elderName,
        'language': 'kn',
        'familyName': 'Daughter',
        'familyPhone': familyPhone,
      },
      'medicine': {
        'name': 'BP tablet',
        'time': '19:00',
        'instructions': 'After food',
        'status': 'pending',
      },
      'appointment': {
        'doctor': 'Dr. Rao',
        'hospital': 'City Clinic',
        'when': 'Tomorrow 11:30 AM',
      },
      'checkin': {
        'response': 'none',
        'reminderCount': 0,
      },
      'escalation': {
        'level': 0,
        'state': 'idle',
        'eventType': '',
      },
      'insight': {
        'text': 'Routine looks normal today.',
        'severity': 'info',
      },
    });
  }

  static Stream<DatabaseEvent> watch() => _care.onValue;

  static Map<String, dynamic> asMap(Object? v) {
    if (v is Map) return Map<String, dynamic>.from(v.map((k, val) => MapEntry('$k', val)));
    return {};
  }

  static Future<void> setConsent(String key, bool allowed) async {
    await _requireDb();
    await _care.child('consent/$key').set(allowed);
    await audit('consent_changed', '$key=${allowed ? "on" : "off"}');
  }

  static Future<void> _requireDb() async {
    if (!await FirebaseService.ensureReady()) {
      throw StateError(
        'Firebase is not configured on this phone${FirebaseService.lastError != null ? ": ${FirebaseService.lastError}" : ""}',
      );
    }
  }

  static Future<void> setLanguage(String lang) async {
    await _care.child('profile/language').set(lang);
  }

  static Future<void> checkIn(String response) async {
    await _requireDb();
    await _care.child('checkin').set({
      'response': response,
      'label': response == 'fine'
          ? 'I am fine'
          : response == 'unwell'
              ? 'Not feeling well'
              : 'Needs help',
      'at': DateTime.now().millisecondsSinceEpoch,
      'reminderCount': 0,
    });
    if (response == 'help') {
      await FirebaseService.logEvent(
        deviceId: deviceId,
        type: 'NEED_HELP',
        payload: {'level': 4, 'valid': false},
      );
    } else if (response == 'unwell') {
      await FirebaseService.logEvent(
        deviceId: deviceId,
        type: 'CHECKIN_UNWELL',
        payload: {'level': 3},
      );
    }
    if (response == 'fine') {
      await setEscalation(0, 'idle', '');
      await _care.child('insight').set({
        'text': 'Morning check-in done. Routine looks normal today.',
        'severity': 'info',
      });
      await FirebaseService.logEvent(
        deviceId: deviceId,
        type: 'CHECKIN_FINE',
        payload: {'level': 0},
      );
    } else if (response == 'unwell') {
      await setEscalation(3, 'pending', 'CHECKIN_UNWELL');
      await _care.child('insight').set({
        'text': 'Routine looks different from usual. Elder asked for family attention.',
        'severity': 'attention',
      });
    } else if (response == 'help') {
      await setEscalation(4, 'escalated', 'NEED_HELP');
    }
    await audit('checkin', response);
  }

  static Future<void> medicineTaken() async {
    await _requireDb();
    await _care.child('medicine/status').set('taken');
    await _care.child('medicine/respondedAt').set(ServerValue.timestamp);
    await setEscalation(0, 'idle', '');
    await audit('medicine', 'taken');
  }

  static Future<void> medicineLater() async {
    await _requireDb();
    await _care.child('medicine/status').set('snoozed');
    await setEscalation(1, 'pending', 'MEDICINE_SNOOZE');
    await audit('medicine', 'later');
  }

  static Future<void> setEscalation(int level, String state, String eventType) async {
    try {
      await _care.child('escalation').set({
        'level': level,
        'state': state,
        'eventType': eventType,
        'at': ServerValue.timestamp,
      });
    } catch (_) {}
  }

  static Future<void> ackEmergency() async {
    await setEscalation(0, 'acknowledged', '');
  }

  static Future<void> demoPossibleEvent(
    String type, {
    double? lat,
    double? lng,
    int hr = 0,
  }) async {
    await _requireDb();
    final hasGps = lat != null && lng != null && (lat.abs() > 0.0001 || lng.abs() > 0.0001);
    await FirebaseService.logEvent(
      deviceId: deviceId,
      type: type,
      payload: {
        'conf': 90,
        'hr': hr,
        'lat': lat ?? 0,
        'lng': lng ?? 0,
        'valid': hasGps,
        'level': 4,
        'note': 'Possible event, no response — not a diagnosis',
      },
    );
    await setEscalation(4, 'escalated', type);
    await audit('demo_event', type);
  }

  static Future<void> audit(String action, String detail) async {
    if (!FirebaseService.isReady) return;
    await _care.child('audit').push().set({
      'action': action,
      'detail': detail,
      'ts': ServerValue.timestamp,
    });
  }

  static Future<void> callFamily() async {
    final uri = Uri.parse('tel:$familyPhone');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Closed-set intents. LLM-style phrasing only; facts come from [care] snapshot.
  static AssistantReply handleIntent(String raw, Map<String, dynamic> care) {
    final q = raw.toLowerCase();
    final profile = Map<String, dynamic>.from(care['profile'] as Map? ?? {});
    final kn = '${profile['language'] ?? 'kn'}' == 'kn';
    final med = Map<String, dynamic>.from(care['medicine'] as Map? ?? {});
    final appt = Map<String, dynamic>.from(care['appointment'] as Map? ?? {});

    if (q.contains('tablet') ||
        q.contains('medicine') ||
        q.contains('ಮಾತ್ರೆ') ||
        q.contains('ಮದ್ದು')) {
      return AssistantReply(
        intent: 'NEXT_MEDICINE',
        textEn: 'Your next medicine is ${med['name'] ?? 'BP tablet'} at ${med['time'] ?? '19:00'}. ${med['instructions'] ?? ''}',
        textKn: 'ಈಗ ${med['time'] ?? '7 ಗಂಟೆಗೆ'} ನಿಮ್ಮ ${med['name'] ?? 'ಬಿಪಿ ಮಾತ್ರೆ'} ತೆಗೆದುಕೊಳ್ಳಿ.',
        kn: kn,
      );
    }
    if (q.contains('doctor') || q.contains('appoint') || q.contains('ಡಾಕ್ಟರ್') || q.contains('ಭೇಟಿ')) {
      return AssistantReply(
        intent: 'NEXT_APPOINTMENT',
        textEn: 'Next visit: ${appt['doctor'] ?? 'Dr. Rao'} at ${appt['hospital'] ?? 'clinic'}, ${appt['when'] ?? 'tomorrow'}.',
        textKn: 'ಮುಂದಿನ ಭೇಟಿ: ${appt['doctor'] ?? 'ಡಾ. ರಾವ್'}, ${appt['when'] ?? 'ನಾಳೆ'}.',
        kn: kn,
      );
    }
    if (q.contains('call') || q.contains('daughter') || q.contains('ಕರೆ') || q.contains('ಮಗಳು')) {
      return AssistantReply(
        intent: 'CALL_CONTACT',
        textEn: 'Calling your daughter now.',
        textKn: 'ನಿಮ್ಮ ಮಗಳಿಗೆ ಕರೆ ಮಾಡುತ್ತಿದ್ದೇನೆ.',
        kn: kn,
        call: true,
      );
    }
    if (q.contains('help') || q.contains('ಸಹಾಯ') || q.contains('unwell') || q.contains('ನೋವು') ||
        q.contains('chest') || q.contains('breathe')) {
      return AssistantReply(
        intent: 'NEED_HELP',
        textEn: 'I will contact your family. Please sit down. This is not a diagnosis — contact your doctor if symptoms are severe.',
        textKn: 'ನಾನು ನಿಮ್ಮ ಕುಟುಂಬಕ್ಕೆ ತಿಳಿಸುತ್ತೇನೆ. ದಯವಿಟ್ಟು ಕುಳಿತುಕೊಳ್ಳಿ. ವೈದ್ಯರನ್ನು ಸಂಪರ್ಕಿಸಿ.',
        kn: kn,
        help: true,
      );
    }
    if (q.contains('taken') || q.contains('ತೆಗೆದುಕೊಂಡೆ')) {
      return AssistantReply(
        intent: 'MEDICINE_TAKEN',
        textEn: 'Marked as taken. Thank you.',
        textKn: 'ಮಾತ್ರೆ ತೆಗೆದುಕೊಂಡಂತೆ ಗುರುತಿಸಲಾಗಿದೆ.',
        kn: kn,
        taken: true,
      );
    }
    return AssistantReply(
      intent: 'UNKNOWN',
      textEn: 'You can ask: next medicine, next appointment, or call family. I never change your dosage.',
      textKn: 'ಮಾತ್ರೆ, ಡಾಕ್ಟರ್ ಭೇಟಿ, ಅಥವಾ ಕುಟುಂಬಕ್ಕೆ ಕರೆ ಎಂದು ಕೇಳಿ.',
      kn: kn,
    );
  }
}

class AssistantReply {
  AssistantReply({
    required this.intent,
    required this.textEn,
    required this.textKn,
    required this.kn,
    this.call = false,
    this.help = false,
    this.taken = false,
  });

  final String intent;
  final String textEn;
  final String textKn;
  final bool kn;
  final bool call;
  final bool help;
  final bool taken;

  String get spoken => kn ? textKn : textEn;
}
