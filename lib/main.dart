import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'pages/root_home.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'analytics_helper.dart'; 

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ⭐ Firebase'i doğru projeyle ayağa kaldır
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ⭐ Uygulama açılır açılmaz test eventi yolla
  await AnalyticsHelper.logAppStart();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));

  runApp(const MyApp());
}



class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nöbetçi Eczane',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildTheme(),
      home: const RootHome(),
    );
  }
}
