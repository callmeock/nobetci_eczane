import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'pages/root_home.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp, // sadece dikey
    // Eğer telefonu ters çevrilmiş dikeyde de kullanılsın dersen:
    // DeviceOrientation.portraitDown,
  ]);

  // ⏰ Lokal zaman dilimini ayarla (Türkiye için)
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
