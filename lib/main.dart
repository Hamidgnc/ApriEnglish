// ApriEnglish: uygulamanın giriş noktası ve teması.

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'ekranlar/ana_sayfa.dart';
import 'servisler/bildirim.dart';
import 'servisler/efekt.dart';
import 'tema.dart';

// main artık async: uygulama açılmadan önce bildirim sistemini hazırlıyoruz
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  await bildirimler.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  Efekt.hazirla(); // sesleri arka planda belleğe yükle (await yok: açılışı bekletmesin)
  runApp(const KelimeUygulamasi());
}

class KelimeUygulamasi extends StatelessWidget {
  const KelimeUygulamasi({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ApriEnglish',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Nunito', // pubspec.yaml'da tanımladığımız yazı tipi
        colorScheme: ColorScheme.fromSeed(
          seedColor: kTuruncu,
          brightness: Brightness.dark, // koyu tema: yazılar otomatik açık renk olur
          primary: kTuruncu,
          onPrimary: const Color(0xFF1A0E05),
          surface: kZemin,
          onSurface: kYazi,
        ),
        scaffoldBackgroundColor: kZemin,
        appBarTheme: const AppBarTheme(
          backgroundColor: kZemin,
          foregroundColor: kYazi,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: kYazi,
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: kZemin,
          indicatorColor: kVurguZemin,
          surfaceTintColor: Colors.transparent,
        ),
        dialogTheme: const DialogThemeData(backgroundColor: kKart),
      ),
      home: const AnaSayfa(),
    );
  }
}
