import 'package:url_launcher/url_launcher.dart';

class MapsLauncher {
  static bool hasFix(double lat, double lng) =>
      lat.abs() > 0.0001 || lng.abs() > 0.0001;

  static Future<void> open(double lat, double lng) async {
    if (!hasFix(lat, lng)) return;
    final https = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    try {
      await launchUrl(geo, mode: LaunchMode.externalApplication);
    } catch (_) {
      await launchUrl(https, mode: LaunchMode.externalApplication);
    }
  }
}
