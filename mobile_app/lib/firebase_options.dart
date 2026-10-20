import 'package:firebase_core/firebase_core.dart';

/// Fallback so the elder APK can start Firebase even if the Android plugin misses google-services.json.
class DefaultFirebaseOptions {
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBWYq6X9zfuvNiz0RAcz-pooqsIjh9dc7U',
    appId: '1:574358570796:android:8a5323b86432ee93b88e89',
    messagingSenderId: '574358570796',
    projectId: 'neuroguard-df097',
    databaseURL: 'https://neuroguard-df097-default-rtdb.firebaseio.com',
    storageBucket: 'neuroguard-df097.firebasestorage.app',
  );
}
