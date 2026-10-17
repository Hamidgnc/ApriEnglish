// Günlük hatırlatma bildirimleri.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

// Telefonun bildirim sistemi
final FlutterLocalNotificationsPlugin bildirimler = FlutterLocalNotificationsPlugin();

// Her gün aynı saatte hatırlatma kurar (kapalıysa hepsini iptal eder)
Future<void> bildirimiAyarla(bool acik, int saat, int dakika) async {
  await bildirimler.cancelAll();
  if (!acik) return;
  // Android 13 ve sonrası: kullanıcıdan bildirim izni iste
  final android = bildirimler.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.requestNotificationsPermission();

  final simdi = DateTime.now();
  var zaman = DateTime(simdi.year, simdi.month, simdi.day, saat, dakika);
  if (!zaman.isAfter(simdi)) zaman = zaman.add(const Duration(days: 1));

  await bildirimler.zonedSchedule(
    id: 1,
    title: 'ApriEnglish',
    body: 'Kayısıların seni bekliyor! Bugünkü hedefine başla.',
    scheduledDate: tz.TZDateTime.from(zaman, tz.UTC),
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'gunluk',
        'Günlük hatırlatma',
        channelDescription: 'Her gün kelime çalışmayı hatırlatır',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    matchDateTimeComponents: DateTimeComponents.time, // her gün tekrarla
  );
}

// Sadece bildirim iznini ister (tanıtımda, hatırlatma seçilince)
Future<void> bildirimIzniIste() async {
  final android = bildirimler.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.requestNotificationsPermission();
}

// Hemen bir deneme bildirimi gösterir
Future<void> denemeBildirimi() async {
  final android = bildirimler.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.requestNotificationsPermission();
  await bildirimler.show(
    id: 2,
    title: 'ApriEnglish',
    body: 'Bildirimler çalışıyor!',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'gunluk',
        'Günlük hatırlatma',
        channelDescription: 'Her gün kelime çalışmayı hatırlatır',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}
