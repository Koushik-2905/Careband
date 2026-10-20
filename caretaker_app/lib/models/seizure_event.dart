class SeizureEvent {
  final String id;
  final String type;
  final int conf;
  final int hr;
  final double lat;
  final double lng;
  final bool valid;
  final DateTime when;
  final String locSrc;
  final int level;

  SeizureEvent({
    required this.id,
    this.type = 'SEIZURE_SUSPECTED',
    required this.conf,
    required this.hr,
    required this.lat,
    required this.lng,
    required this.valid,
    required this.when,
    this.locSrc = 'none',
    this.level = 4,
  });

  String get title {
    switch (type) {
      case 'FALL_SUSPECTED':
        return 'Possible fall, no response';
      case 'SOS':
        return 'SOS — elder asked for help';
      case 'NEED_HELP':
        return 'Elder tapped I NEED HELP';
      case 'CHECKIN_UNWELL':
        return 'Check-in: not feeling well';
      default:
        return 'Possible seizure-like event';
    }
  }

  factory SeizureEvent.fromSnapshot(String id, Map<dynamic, dynamic> m) {
    final ts = m['ts'];
    DateTime when = DateTime.now();
    if (ts is num) when = DateTime.fromMillisecondsSinceEpoch(ts.toInt());

    final lat = (m['lat'] as num?)?.toDouble() ?? 0;
    final lng = (m['lng'] as num?)?.toDouble() ?? 0;
    final validFlag = m['valid'] == true || m['valid'] == 1 || m['valid'] == 'true';

    return SeizureEvent(
      id: id,
      type: m['type']?.toString() ?? 'SEIZURE_SUSPECTED',
      level: (m['level'] as num?)?.toInt() ?? 4,
      conf: (m['conf'] as num?)?.toInt() ?? 0,
      hr: (m['hr'] as num?)?.toInt() ?? 0,
      lat: lat,
      lng: lng,
      valid: validFlag || lat.abs() > 0.0001 || lng.abs() > 0.0001,
      when: when,
      locSrc: m['locSrc']?.toString() ?? 'none',
    );
  }

  String get mapsUrl => 'https://maps.google.com/?q=$lat,$lng';

  SeizureEvent copyWithLocation(bool allowed) {
    if (allowed) return this;
    return SeizureEvent(
      id: id,
      type: type,
      conf: conf,
      hr: hr,
      lat: 0,
      lng: 0,
      valid: false,
      when: when,
      locSrc: 'hidden',
      level: level,
    );
  }
}
