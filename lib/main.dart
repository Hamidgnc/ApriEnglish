import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'paket.dart'; // hazır kelimeler ayrı dosyada

// Uygulamanın renkleri (koyu tema: gri tonlar + tek vurgu rengi kayısı turuncusu)
const kTuruncu = Color(0xFFF5842C); // ana vurgu: butonlar, halkalar
const kParlakTuruncu = Color(0xFFFF9A4D); // koyu zeminde okunan turuncu yazı
const kZemin = Color(0xFF0E0D0C); // sayfa arka planı
const kKart = Color(0xFF1C1A18); // kartlar, kutular, yazı alanları
const kCizgi = Color(0xFF2A2724); // çerçeveler, boş çubuklar
const kVurguZemin = Color(0xFF2A2016); // seçili şeylerin turuncumsu zemini
const kYazi = Color(0xFFF7F2EC); // ana yazı rengi
const kSoluk = Color(0xFFA39B92); // açıklama yazıları

// YENİ: Telefonun bildirim sistemi
final FlutterLocalNotificationsPlugin bildirimler = FlutterLocalNotificationsPlugin();

// main artık async: uygulama açılmadan önce bildirim sistemini hazırlıyoruz
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  await bildirimler.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  runApp(const KelimeUygulamasi());
}

// YENİ: Her gün aynı saatte hatırlatma kurar (kapalıysa hepsini iptal eder)
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
    title: 'ApriEnglish 🍑',
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

// YENİ: Hemen bir deneme bildirimi gösterir
Future<void> denemeBildirimi() async {
  final android = bildirimler.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.requestNotificationsPermission();
  await bildirimler.show(
    id: 2,
    title: 'ApriEnglish 🍑',
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

class Kelime {
  String ing;
  String anlam;
  int yanlis;
  int seviye; // 0 = ham, 1-2 = yarı olgun, 3 = kurutmada, 4 = kuru kayısı
  String? tekrar; // bir sonraki tekrar günü (yyyy-aa-gg), yoksa null
  String duzey; // A1, A2, B1 ya da Benim (kendi eklediklerin)

  Kelime({
    required this.ing,
    required this.anlam,
    this.yanlis = 0,
    this.seviye = 0,
    this.tekrar,
    this.duzey = 'Benim',
  });

  Map<String, dynamic> toJson() {
    return {
      'ing': ing,
      'anlam': anlam,
      'yanlis': yanlis,
      'seviye': seviye,
      'tekrar': tekrar,
      'duzey': duzey,
    };
  }

  factory Kelime.fromJson(Map<String, dynamic> json) {
    return Kelime(
      ing: json['ing'],
      anlam: json['anlam'],
      yanlis: json['yanlis'],
      seviye: json['seviye'] ?? 0, // eski kayıtlarda seviye yok -> 0
      tekrar: json['tekrar'], // eski kayıtlarda yok -> null
      duzey: json['duzey'] ?? 'Benim', // eski kayıtlarda yok -> Benim
    );
  }
}

// Aşamaya göre kayısı renkleri: [iç (parlak), dış (koyu)]
List<Color> durumRenkleri(int seviye) {
  if (seviye >= 4) return const [Color(0xFFC98A4B), Color(0xFF8A4F22)]; // kuru
  if (seviye == 3) return const [Color(0xFFFFC45C), Color(0xFFEC7020)]; // kurutmada
  if (seviye >= 1) return const [Color(0xFFFFEB8C), Color(0xFFE1BE3C)]; // yarı
  return const [Color(0xFFC8E68C), Color(0xFF82B450)]; // ham
}

String durumAdi(int seviye) {
  if (seviye >= 4) return 'kuru kayısı';
  if (seviye == 3) return 'kurutmada';
  if (seviye >= 1) return 'yarı olgun';
  return 'ham';
}

// Filtre için grup: 0 ham, 1 yarı, 3 kurutmada, 4 kuru
int durumGrubu(int seviye) {
  if (seviye >= 4) return 4;
  if (seviye == 3) return 3;
  if (seviye >= 1) return 1;
  return 0;
}

// Tarih yardımcıları (yyyy-aa-gg)
String tarihMetni(DateTime d) => d.toIso8601String().substring(0, 10);
String bugununTarihi() => tarihMetni(DateTime.now());
String gunSonra(int gun) => tarihMetni(DateTime.now().add(Duration(days: gun)));

// Kodla çizilen kayısı. doluluk: 0 = içi boş, 1 = içi tamamen turuncu
class KayisiCizim extends CustomPainter {
  final Color renk;
  final double doluluk;

  KayisiCizim({required this.renk, this.doluluk = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cizgi = Paint()
      ..color = renk
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round;

    final govde = Rect.fromLTWH(w * 0.05, h * 0.22, w * 0.90, h * 0.74);
    if (doluluk > 0) {
      canvas.drawOval(govde, Paint()..color = renk.withValues(alpha: doluluk));
    }
    canvas.drawOval(govde, cizgi);

    canvas.drawArc(
      Rect.fromLTWH(w * 0.25, h * 0.22, w * 0.32, h * 0.66),
      -pi / 2,
      0.95,
      false,
      cizgi,
    );

    canvas.drawLine(Offset(w * 0.49, h * 0.23), Offset(w * 0.53, h * 0.08), cizgi);

    canvas.save();
    canvas.translate(w * 0.53, h * 0.08);
    canvas.rotate(-0.45);
    canvas.drawOval(Rect.fromLTWH(0, -h * 0.06, w * 0.34, h * 0.12), cizgi);
    canvas.restore();
  }

  @override
  bool shouldRepaint(KayisiCizim old) =>
      old.renk != renk || old.doluluk != doluluk;
}

// YENİ: Bir ders = aynı seviyeden sıradaki 10 kelime
class Ders {
  final String duzey; // A1, A2, B1
  final int no; // 1, 2, 3...
  final String baslik; // "Yiyecek ve içecek" gibi
  final List<Kelime> kelimeler;

  Ders(this.duzey, this.no, this.baslik, this.kelimeler);

  // Kayıtta dersi bu adla tutarız, ör. "A1-3"
  String get kimlik => '$duzey-$no';
}

// YENİ: Ana sayfadaki seri halkası. oran: 0 = boş, 1 = tam dolu
class HalkaCizim extends CustomPainter {
  final double oran;

  HalkaCizim(this.oran);

  @override
  void paint(Canvas canvas, Size size) {
    const kalinlik = 10.0;
    final merkez = Offset(size.width / 2, size.height / 2);
    final yaricap = size.width / 2 - kalinlik / 2;
    final kalem = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kalinlik
      ..strokeCap = StrokeCap.round;
    // Önce gri zemin halkası, sonra üstüne turuncu ilerleme yayı
    canvas.drawCircle(merkez, yaricap, kalem..color = kCizgi);
    if (oran > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: merkez, radius: yaricap),
        -pi / 2, // saat 12 yönünden başla
        2 * pi * oran,
        false,
        kalem..color = kTuruncu,
      );
    }
  }

  @override
  bool shouldRepaint(HalkaCizim old) => old.oran != oran;
}

// YENİ: Ders kartındaki manzara: gökyüzü, güneş, tepeler ve kayısı ağaçları.
// Her seviyenin gökyüzü farklı: A1 gün batımı, A2 öğle, B1 gece.
class ManzaraCizim extends CustomPainter {
  final String duzey;

  ManzaraCizim(this.duzey);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final (List<Color> gok, Color gunes, Color tepe1, Color tepe2) = switch (duzey) {
      'A2' => (
          const [Color(0xFF2F6FA8), Color(0xFF7FB6DA), Color(0xFFE6D3A3)],
          const Color(0xFFFFF1B8),
          const Color(0xFF4F6B3A),
          const Color(0xFF2E3F24),
        ),
      'B1' => (
          const [Color(0xFF0B1030), Color(0xFF1F2A5C), Color(0xFF3E3F7A)],
          const Color(0xFFE9E6D0),
          const Color(0xFF2A2848),
          const Color(0xFF17162B),
        ),
      _ => (
          const [Color(0xFF2B2240), Color(0xFF8E4A58), Color(0xFFE9955A)],
          const Color(0xFFFFCF8A),
          const Color(0xFF5E3437),
          const Color(0xFF33231F),
        ),
    };

    // Gökyüzü: yukarıdan aşağı renk geçişi
    final gokBoya = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: gok,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, gokBoya);

    // Güneş (B1'de ay)
    canvas.drawCircle(Offset(w * 0.74, h * 0.56), w * 0.10, Paint()..color = gunes);

    // Arkadaki sivri dağlar
    final dag = Path()
      ..moveTo(0, h * 0.68)
      ..lineTo(w * 0.18, h * 0.50)
      ..lineTo(w * 0.35, h * 0.63)
      ..lineTo(w * 0.55, h * 0.43)
      ..lineTo(w * 0.77, h * 0.65)
      ..lineTo(w, h * 0.53)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(dag, Paint()..color = tepe1);

    // Öndeki yumuşak tepe
    final tepe = Path()
      ..moveTo(0, h * 0.79)
      ..quadraticBezierTo(w * 0.25, h * 0.69, w * 0.5, h * 0.77)
      ..quadraticBezierTo(w * 0.75, h * 0.84, w, h * 0.74)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(tepe, Paint()..color = tepe2);

    // İki kayısı ağacı
    agac(canvas, Offset(w * 0.18, h * 0.76), w * 0.068);
    agac(canvas, Offset(w * 0.82, h * 0.77), w * 0.058);
  }

  void agac(Canvas canvas, Offset kok, double r) {
    canvas.drawRect(
      Rect.fromLTWH(kok.dx - r * 0.15, kok.dy - r * 0.4, r * 0.3, r * 1.1),
      Paint()..color = const Color(0xFF21160F),
    );
    final tepe = Offset(kok.dx, kok.dy - r);
    canvas.drawCircle(tepe, r, Paint()..color = const Color(0xFF2E4A33));
    final meyve = Paint()..color = kTuruncu;
    canvas.drawCircle(tepe + Offset(-r * 0.4, -r * 0.25), r * 0.18, meyve);
    canvas.drawCircle(tepe + Offset(r * 0.35, r * 0.05), r * 0.18, meyve);
    canvas.drawCircle(tepe + Offset(-r * 0.05, r * 0.4), r * 0.18, meyve);
  }

  @override
  bool shouldRepaint(ManzaraCizim old) => old.duzey != duzey;
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

class AnaSayfa extends StatefulWidget {
  const AnaSayfa({super.key});

  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> {
  static const anahtar = 'kelimeler';

  // YENİ: Seviye adları (Paketler ekranında sırayla gösterilir)
  static const duzeyBilgisi = {
    'A1': 'Başlangıç',
    'A2': 'Temel',
    'B1': 'Orta',
    'Benim': 'Benim kelimelerim',
  };

  List<Kelime> kelimeler = []; // ilk açılışta hazır paketle dolar
  Set<String> seciliDuzeyler = {'A1', 'Benim'}; // YENİ: çalışılan seviyeler
  String aktifDuzey = 'A1'; // YENİ: ana sayfada derslerini gördüğün seviye
  final Random rastgele = Random();
  final FlutterTts ses = FlutterTts();
  bool yuklendi = false;
  int sekme = 0;
  int bugun = 0; // bugün bilinen kelime sayısı
  Profil profil = Profil(); // ad, avatar, hedef, bildirim ayarları
  bool tanitimTamam = true; // YENİ: ilk açılış tanıtımı görüldü mü
  Map<String, int> gecmis = {}; // her gün kaç kelime bilindi (takvim için)
  List<Ders> dersler = []; // YENİ: paketten oluşturulan dersler
  Map<String, int> dersPuanlari = {}; // YENİ: "A1-3" -> kazanılan kayısı (0-3)
  PageController? dersKaydirici; // YENİ: ana sayfadaki ders kartlarını kaydırır

  // Hasat ekranı
  final TextEditingController aramaKutusu = TextEditingController();
  String arama = '';
  int filtre = -1; // -1 hepsi, 0 ham, 1 yarı, 3 kurutmada, 4 kuru

  // Kartlar ekranı
  late Kelime aktif;
  bool onYuz = true;

  // Test ekranı
  // YENİ: Test turu
  static const turUzunlugu = 10;
  String testDurumu = 'secim'; // 'secim' -> 'soru' -> 'sonuc'
  String testModu = 'secmeli'; // 'secmeli', 'yazma', 'dinle'
  bool tersYon = false; // false: İngilizce -> Türkçe, true: Türkçe -> İngilizce
  List<Kelime> turSorulari = [];
  int soruNo = 0;
  int turDogru = 0;
  List<Kelime> turYanlislar = [];
  List<String> siklar = [];
  String dogruSik = '';
  String? secilenSik;
  bool cevaplandi = false;
  bool sonCevapDogru = false;
  final TextEditingController cevapKutusu = TextEditingController();

  // Ekleme ekranı
  final TextEditingController ingKutusu = TextEditingController();
  final TextEditingController trKutusu = TextEditingController();

  @override
  void initState() {
    super.initState();
    ses.setLanguage('en-US');
    ses.setSpeechRate(0.45);
    kelimeleriYukle();
  }

  @override
  void dispose() {
    ses.stop();
    cevapKutusu.dispose();
    ingKutusu.dispose();
    trKutusu.dispose();
    aramaKutusu.dispose();
    dersKaydirici?.dispose();
    super.dispose();
  }

  Future<void> oku(String metin) async {
    await ses.stop();
    await ses.speak(metin);
  }

  Future<void> kelimeleriYukle() async {
    final prefs = SharedPreferencesAsync();
    final metin = await prefs.getString(anahtar);
    if (metin != null) {
      final List<dynamic> liste = jsonDecode(metin);
      kelimeler = liste.map((e) => Kelime.fromJson(e)).toList();
    }
    final gecmisMetni = await prefs.getString('gecmis');
    if (gecmisMetni != null) {
      final Map<String, dynamic> m = jsonDecode(gecmisMetni);
      gecmis = m.map((gun, sayi) => MapEntry(gun, sayi as int));
    }
    // Eski sürümden kalan bugünkü sayıyı da al (migration)
    final eskiTarih = await prefs.getString('tarih');
    final eskiSayi = await prefs.getInt('bugun');
    if (eskiTarih != null && eskiSayi != null && !gecmis.containsKey(eskiTarih)) {
      gecmis[eskiTarih] = eskiSayi;
    }
    final tanitimGoruldu = await prefs.getBool('tanitim') ?? false;
    final profilMetni = await prefs.getString('profil');
    if (profilMetni != null) {
      profil = Profil.fromJson(jsonDecode(profilMetni));
    }
    final duzeyMetni = await prefs.getString('duzeyler');
    if (duzeyMetni != null) {
      seciliDuzeyler = Set<String>.from(jsonDecode(duzeyMetni));
    }
    // YENİ: Hazır paket daha önce eklenmediyse ekle
    final paketSurumu = await prefs.getInt('paket') ?? 0;
    final paketEklendi = paketSurumu < 1;
    if (paketEklendi) {
      paketiEkle();
      await prefs.setInt('paket', 1);
    }
    // YENİ: Ders puanlarını yükle, dersleri kur, kaydırıcıyı sıradaki derste aç
    final puanMetni = await prefs.getString('dersPuanlari');
    if (puanMetni != null) {
      final Map<String, dynamic> m = jsonDecode(puanMetni);
      dersPuanlari = m.map((ders, puan) => MapEntry(ders, puan as int));
    }
    dersleriOlustur();
    // Kayıtlı aktif seviye yoksa açık seviyelerden ilkini al
    aktifDuzey = await prefs.getString('aktifDuzey') ??
        ['A1', 'A2', 'B1'].firstWhere(seciliDuzeyler.contains, orElse: () => 'A1');
    kaydiriciyiKur();
    setState(() {
      bugun = gecmis[bugununTarihi()] ?? 0;
      tanitimTamam = tanitimGoruldu;
      aktif = kelimeSec();
      yuklendi = true;
    });
    if (paketEklendi) kelimeleriKaydet();
  }

  // YENİ: Paketteki kelimeleri listeye ekler. Zaten olanlara dokunmaz,
  // böylece çalıştığın kelimelerin ilerlemesi (seviye, kurutma) korunur.
  void paketiEkle() {
    final mevcut = {for (final k in kelimeler) k.ing: k};
    for (final p in kelimePaketi) {
      final varOlan = mevcut[p[0]];
      if (varOlan == null) {
        kelimeler.add(Kelime(ing: p[0], anlam: p[1], duzey: p[2]));
      } else if (varOlan.duzey == 'Benim') {
        varOlan.duzey = p[2]; // eski kelimen paketteyse seviyesini al
      }
    }
  }

  Future<void> kelimeleriKaydet() async {
    final prefs = SharedPreferencesAsync();
    final metin = jsonEncode(kelimeler.map((k) => k.toJson()).toList());
    await prefs.setString(anahtar, metin);
    await prefs.setString('gecmis', jsonEncode(gecmis));
    await prefs.setString('duzeyler', jsonEncode(seciliDuzeyler.toList()));
    await prefs.setString('dersPuanlari', jsonEncode(dersPuanlari));
    await prefs.setString('aktifDuzey', aktifDuzey);
  }

  // ---------------- Dersler ----------------

  // YENİ: Paketteki sırayla her seviyenin kelimelerini 10'arlı derslere böler.
  // Son parça 5'ten azsa ayrı ders yapmaz, bir önceki derse ekler.
  void dersleriOlustur() {
    final harita = {for (final k in kelimeler) k.ing: k};
    dersler = [];
    for (final duzey in ['A1', 'A2', 'B1']) {
      final liste = [
        for (final p in kelimePaketi)
          if (p[2] == duzey && harita[p[0]] != null) harita[p[0]]!,
      ];
      final basliklar = dersBasliklari[duzey] ?? [];
      for (int i = 0; i < liste.length; i += 10) {
        final parca = liste.sublist(i, min(i + 10, liste.length));
        if (parca.length < 5 && dersler.isNotEmpty && dersler.last.duzey == duzey) {
          dersler.last.kelimeler.addAll(parca);
          continue;
        }
        final no = i ~/ 10 + 1;
        final baslik = no <= basliklar.length ? basliklar[no - 1] : 'Ders $no';
        dersler.add(Ders(duzey, no, baslik, parca));
      }
    }
  }

  // Ana sayfada sadece aktif seviyenin dersleri görünür
  List<Ders> get gorunenDersler =>
      dersler.where((d) => d.duzey == aktifDuzey).toList();

  // Bir seviyede kaç ders var, kaçı bitti (en az 1 kayısı)
  int dersSayisi(String duzey) => dersler.where((d) => d.duzey == duzey).length;
  int bitenDers(String duzey) => dersler
      .where((d) => d.duzey == duzey && (dersPuanlari[d.kimlik] ?? 0) > 0)
      .length;

  // YENİ: Rozete dokununca alttan açılan seviye seçici
  Future<void> duzeySec() async {
    final secilen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: kKart,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Hangi seviyeden ders yapalım?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            for (final d in ['A1', 'A2', 'B1'])
              ListTile(
                onTap: () => Navigator.pop(context, d), // seçilen seviyeyi geri yolla
                leading: CircleAvatar(
                  backgroundColor: d == aktifDuzey ? kTuruncu : kCizgi,
                  child: Text(
                    d,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: d == aktifDuzey ? kZemin : kYazi,
                    ),
                  ),
                ),
                title: Text(
                  duzeyBilgisi[d] ?? d,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${bitenDers(d)} / ${dersSayisi(d)} ders bitti',
                  style: const TextStyle(color: kSoluk),
                ),
                trailing: d == aktifDuzey
                    ? const Icon(Icons.check_rounded, color: kTuruncu)
                    : null,
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (secilen == null || secilen == aktifDuzey) return; // kapatıldı ya da aynısı
    setState(() {
      aktifDuzey = secilen;
      seciliDuzeyler.add(secilen); // ders yaptığın seviye pratikte de açık olsun
      aktif = kelimeSec();
      kaydiriciyiKur();
    });
    kelimeleriKaydet();
  }

  // Henüz bitirilmemiş ilk dersin sırası (hepsi bittiyse sonuncusu)
  int siradakiDers() {
    final liste = gorunenDersler;
    final i = liste.indexWhere((d) => (dersPuanlari[d.kimlik] ?? 0) == 0);
    return i == -1 ? max(0, liste.length - 1) : i;
  }

  // Ders kartlarının kaydırıcısını sıradaki derste açılacak şekilde (yeniden) kurar.
  // Seviyeler değişince de çağırırız, çünkü görünen ders listesi değişir.
  void kaydiriciyiKur() {
    // Eskisini hemen değil, ekran yenilendikten sonra çöpe at:
    // o an hâlâ ekrandaki PageView'a bağlı olabilir.
    final eski = dersKaydirici;
    if (eski != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => eski.dispose());
    }
    dersKaydirici = PageController(
      viewportFraction: 0.86, // yandaki kartın kenarı görünsün
      initialPage: siradakiDers(),
      keepPage: false, // eski sayfa numarasını hatırlamasın
    );
  }

  // Dersteki kelimelerden kaçı en az bir kez bilindi
  int dersteBilinen(Ders d) => d.kelimeler.where((k) => k.seviye >= 1).length;

  // YENİ: Ders sayfasını açar. Ders bitince sayfa sonucu geri yollar,
  // biz de kelimelerin aşamalarını ve dersin kayısı puanını güncelleriz.
  Future<void> dersiBaslat(Ders d) async {
    final sonuc = await Navigator.push<DersSonucu>(
      context,
      MaterialPageRoute(
        builder: (_) => DersSayfasi(ders: d, tumKelimeler: kelimeler, oku: oku),
      ),
    );
    if (sonuc == null || !mounted) return; // ders yarıda bırakıldı
    setState(() {
      sonuc.dogrular.forEach((kelime, dogru) {
        if (dogru) {
          bildi(kelime);
        } else {
          bilemedi(kelime);
        }
      });
      // Tekrar oynanırsa en iyi puan kalır
      dersPuanlari[d.kimlik] = max(dersPuanlari[d.kimlik] ?? 0, sonuc.puan);
      aktif = kelimeSec();
    });
    await kelimeleriKaydet();
    // Kartları sıradaki derse kaydır
    final kaydirici = dersKaydirici;
    if (kaydirici != null && kaydirici.hasClients) {
      kaydirici.animateToPage(
        siradakiDers(),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    }
  }

  // Tekrar zamanı geldi mi? (tarihi yoksa ya da bugün/geçmişteyse evet)
  bool zamaniGeldi(Kelime k) =>
      k.tekrar == null || k.tekrar!.compareTo(bugununTarihi()) <= 0;

  // Kurutmada/kuruda bekleyen kelimeler, zamanı gelene kadar sorulmaz
  bool bekliyor(Kelime k) => k.seviye >= 3 && !zamaniGeldi(k);

  Kelime kelimeSec() {
    // Sadece açık olan seviyelerdeki kelimeler
    final secili = kelimeler.where((k) => seciliDuzeyler.contains(k.duzey)).toList();
    final temel = secili.isEmpty ? kelimeler : secili;
    final hazir = temel.where((k) => !bekliyor(k)).toList();
    final havuz = hazir.isEmpty ? temel : hazir; // hepsi bekliyorsa yine de sor
    final List<Kelime> torba = [];
    for (final k in havuz) {
      // Tekrar zamanı gelen kurutma kelimeleri öncelikli (+3)
      final agirlik = 1 + k.yanlis + (k.seviye >= 3 ? 3 : 0);
      torba.addAll(List.filled(agirlik, k));
    }
    return torba[rastgele.nextInt(torba.length)];
  }

  String turkceKucuk(String metin) {
    return metin.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
  }

  // Bilinen kelime bir aşama ilerler
  void bildi(Kelime k) {
    if (k.yanlis > 0) k.yanlis--;
    if (k.seviye < 2) {
      k.seviye++; // ham -> yarı olgun
    } else if (k.seviye == 2) {
      k.seviye = 3; // olgunlaştı, kurutmaya alındı
      k.tekrar = gunSonra(3);
    } else if (k.seviye == 3) {
      if (zamaniGeldi(k)) {
        k.seviye = 4; // kurutmadan sonra da bildi: kuru kayısı!
        k.tekrar = gunSonra(14);
      }
    } else {
      k.tekrar = gunSonra(30); // kuru kayısı: arada bir kontrol
    }
    bugun++;
    gecmis[bugununTarihi()] = bugun;
  }

  // Bilinmeyen kelime ham hâline döner
  void bilemedi(Kelime k) {
    k.yanlis++;
    k.seviye = 0;
    k.tekrar = null;
  }

  // YENİ: Şimdiye kadarki en uzun seri
  int enUzunSeri() {
    final gunler = gecmis.entries
        .where((e) => e.value > 0)
        .map((e) => DateTime.parse(e.key))
        .toList()
      ..sort();
    int enUzun = 0;
    int simdiki = 0;
    DateTime? onceki;
    for (final g in gunler) {
      if (onceki != null && g.difference(onceki).inDays == 1) {
        simdiki++;
      } else {
        simdiki = 1;
      }
      enUzun = max(enUzun, simdiki);
      onceki = g;
    }
    return enUzun;
  }

  // YENİ: Son 7 günün çalışmasına göre hedef önerisi (sayı, açıklama)
  (int, String) hedefOnerisi() {
    final sayilar = <int>[];
    for (int i = 0; i < 7; i++) {
      final gun = tarihMetni(DateTime.now().subtract(Duration(days: i)));
      final sayi = gecmis[gun] ?? 0;
      if (sayi > 0) sayilar.add(sayi);
    }
    if (sayilar.isEmpty) {
      return (10, 'Yeni başlayanlar için 10 kelime iyi bir başlangıç (yaklaşık 10 dakika).');
    }
    final ortalama = sayilar.reduce((a, b) => a + b) / sayilar.length;
    final oneri = (((ortalama * 1.2) / 5).ceil() * 5).clamp(5, 100).toInt();
    return (
      oneri,
      'Son 7 günde çalıştığın günlerde ortalama ${ortalama.round()} kelime bildin. '
          'Biraz zorlamak için $oneri öneriyoruz.',
    );
  }

  // YENİ: Tanıtım bitince seçimleri uygular ve kaydeder
  Future<void> tanitimBitti(Profil yeni, Set<String> duzeyler) async {
    setState(() {
      profil = yeni;
      seciliDuzeyler = duzeyler;
      tanitimTamam = true;
      aktifDuzey = ['A1', 'A2', 'B1'].firstWhere(duzeyler.contains, orElse: () => 'A1');
      kaydiriciyiKur();
      aktif = kelimeSec();
      onYuz = true;
    });
    final prefs = SharedPreferencesAsync();
    await prefs.setBool('tanitim', true);
    await prefs.setString('profil', jsonEncode(profil.toJson()));
    await kelimeleriKaydet();
    await bildirimiAyarla(profil.bildirim, profil.saat, profil.dakika);
  }

  // YENİ: Hesabım sayfasını açar, Kaydet'e basılırsa yeni profili uygular
  Future<void> hesabiAc() async {
    final (oneri, oneriAciklama) = hedefOnerisi();
    final sonuc = await Navigator.push<Profil>(
      context,
      MaterialPageRoute(
        builder: (_) => HesapSayfasi(
          profil: profil.kopya(),
          oneri: oneri,
          oneriAciklama: oneriAciklama,
          istatistikler: {
            'Toplam kelime': kelimeler.length,
            'Öğrenilen': kelimeler.where((k) => k.seviye >= 3).length,
            'Kuru kayısı': kelimeler.where((k) => k.seviye >= 4).length,
            'Bugün': bugun,
            'Şu anki seri': seriHesapla(),
            'En uzun seri': enUzunSeri(),
          },
        ),
      ),
    );
    if (sonuc == null || !mounted) return; // geri tuşuyla çıkıldı
    setState(() {
      profil = sonuc;
    });
    final prefs = SharedPreferencesAsync();
    await prefs.setString('profil', jsonEncode(profil.toJson()));
    await bildirimiAyarla(profil.bildirim, profil.saat, profil.dakika);
  }

  // Kaç gündür aralıksız çalışılıyor?
  int seriHesapla() {
    var gun = DateTime.now();
    // Bugün henüz çalışmadıysan seri dünden sayılır, bozulmaz
    if ((gecmis[tarihMetni(gun)] ?? 0) == 0) {
      gun = gun.subtract(const Duration(days: 1));
    }
    int seri = 0;
    while ((gecmis[tarihMetni(gun)] ?? 0) > 0) {
      seri++;
      gun = gun.subtract(const Duration(days: 1));
    }
    return seri;
  }

  void kartCevapla(bool biliyordum) {
    setState(() {
      if (biliyordum) {
        bildi(aktif);
      } else {
        bilemedi(aktif);
      }
      aktif = kelimeSec();
      onYuz = true;
    });
    kelimeleriKaydet();
  }

  // ---------------- Test ----------------

  // Ters yönde soru Türkçe, cevap İngilizce olur (Dinle modunda hep İngilizce soru)
  bool tersMi() => tersYon && testModu != 'dinle';
  String soruMetni(Kelime k) => tersMi() ? k.anlam : k.ing;
  String cevapMetni(Kelime k) => tersMi() ? k.ing : k.anlam;
  Kelime get soru => turSorulari[soruNo];

  // 10 farklı kelimeyle yeni bir tur başlatır
  void turBaslat(String mod) {
    final sorular = <Kelime>[];
    int deneme = 0;
    while (sorular.length < turUzunlugu && deneme < 300) {
      final k = kelimeSec();
      if (!sorular.contains(k)) sorular.add(k);
      deneme++;
    }
    setState(() {
      testModu = mod;
      turSorulari = sorular;
      soruNo = 0;
      turDogru = 0;
      turYanlislar = [];
      testDurumu = 'soru';
      soruHazirla();
    });
    if (mod == 'dinle') oku(soru.ing);
  }

  // Bir soruyu hazırlar: şıkları üretir, cevap kutusunu temizler
  void soruHazirla() {
    cevaplandi = false;
    secilenSik = null;
    cevapKutusu.clear();
    if (testModu != 'yazma') {
      dogruSik = cevapMetni(soru);
      siklar = siklariUret(soru);
    }
  }

  // 1 doğru + 3 yanlış şık. Yanlışlar mümkünse aynı seviyeden seçilir.
  List<String> siklariUret(Kelime k) {
    final dogru = cevapMetni(k);
    var adaylar = kelimeler.where((x) => x.ing != k.ing && x.duzey == k.duzey).toList();
    if (adaylar.length < 3) {
      adaylar = kelimeler.where((x) => x.ing != k.ing).toList();
    }
    adaylar.shuffle(rastgele);
    final yanlislar = <String>[];
    for (final x in adaylar) {
      final m = cevapMetni(x);
      if (m != dogru && !yanlislar.contains(m)) yanlislar.add(m);
      if (yanlislar.length == 3) break;
    }
    final hepsi = [dogru, ...yanlislar];
    hepsi.shuffle(rastgele);
    return hepsi;
  }

  // Cevap verildi: kurutma sistemi güncellenir, geri bildirim gösterilir
  void cevapla(bool dogru) {
    setState(() {
      cevaplandi = true;
      sonCevapDogru = dogru;
      if (dogru) {
        turDogru++;
        bildi(soru);
      } else {
        bilemedi(soru);
        turYanlislar.add(soru);
      }
    });
    kelimeleriKaydet();
  }

  void sikSec(String sik) {
    if (cevaplandi) return;
    secilenSik = sik;
    cevapla(sik == dogruSik);
  }

  void yaziKontrol() {
    if (cevaplandi) return;
    final yazilan = cevapKutusu.text.trim();
    if (yazilan.isEmpty) return;
    bool dogru;
    if (tersMi()) {
      dogru = yazilan.toLowerCase() == soru.ing;
    } else {
      // "ışık, hafif" gibi birden fazla anlamdan biri yeterli
      final dogrular = soru.anlam.split(',').map((a) => a.trim());
      dogru = dogrular.contains(turkceKucuk(yazilan));
    }
    cevapla(dogru);
  }

  void sonrakiSoru() {
    if (soruNo + 1 >= turSorulari.length) {
      setState(() {
        testDurumu = 'sonuc';
      });
      return;
    }
    setState(() {
      soruNo++;
      soruHazirla();
    });
    if (testModu == 'dinle') oku(soru.ing);
  }

  void kelimeEkle() {
    final ing = ingKutusu.text.trim().toLowerCase();
    final tr = turkceKucuk(trKutusu.text.trim());
    if (ing.isEmpty || tr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Boş bırakılamaz.')),
      );
      return;
    }
    setState(() {
      kelimeler.removeWhere((k) => k.ing == ing);
      kelimeler.add(Kelime(ing: ing, anlam: tr, duzey: 'Benim'));
      seciliDuzeyler.add('Benim');
      ingKutusu.clear();
      trKutusu.clear();
      dersleriOlustur(); // paketteki bir kelimenin yerine geçtiyse dersler güncellensin
    });
    kelimeleriKaydet();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("'$ing' eklendi!")),
    );
  }

  // YENİ: Bir seviyeyi açar ya da kapatır (en az bir seviye açık kalır)
  void duzeyDegistir(String duzey, bool acik) {
    setState(() {
      if (acik) {
        seciliDuzeyler.add(duzey);
        if (duzey != 'Benim') aktifDuzey = duzey; // yeni açılan seviyenin dersleri gelsin
      } else if (seciliDuzeyler.length > 1) {
        seciliDuzeyler.remove(duzey);
        // Ana sayfadaki seviye kapandıysa açık kalanlardan birine geç
        if (duzey == aktifDuzey) {
          aktifDuzey = ['A1', 'A2', 'B1'].firstWhere(
            seciliDuzeyler.contains,
            orElse: () => 'A1',
          );
        }
      }
      aktif = kelimeSec();
      onYuz = true;
      kaydiriciyiKur();
    });
    kelimeleriKaydet();
  }

  void kelimeSil(Kelime k) {
    if (kelimeler.length <= 1) return;
    setState(() {
      kelimeler.remove(k);
      aktif = kelimeSec();
      dersleriOlustur(); // silinen kelime dersten de çıksın
    });
    kelimeleriKaydet();
  }

  // ---------------- Ekranlar ----------------

  // ===== YENİ: Ana sayfa =====

  Widget anaSayfaEkrani() {
    final liste = gorunenDersler;
    return SafeArea(
      child: Column(
        children: [
          ustSerit(),
          const SizedBox(height: 22),
          seriHalkasi(),
          const SizedBox(height: 14),
          haftaNoktalari(),
          const SizedBox(height: 10),
          // Kalan bütün yükseklik ders kartlarının
          Expanded(
            child: PageView.builder(
              key: ValueKey(aktifDuzey), // seviye değişince kaydırıcı sıfırdan kurulsun
              controller: dersKaydirici,
              itemCount: liste.length,
              itemBuilder: (context, i) => dersKarti(liste[i]),
            ),
          ),
        ],
      ),
    );
  }

  // Üst şerit: seviye rozeti, günlük hedef çubuğu, profil düğmesi
  Widget ustSerit() {
    final hedef = max(1, profil.hedef);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
      child: Row(
        children: [
          // Seviye rozeti: dokununca seviye seçici açılır
          Material(
            color: kCizgi,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: duzeySec,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Text(
                    aktifDuzey,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: kTuruncu,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(
                color: kKart,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Günlük hedef',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      Text(
                        '$bugun / $hedef',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: kSoluk,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: min(1.0, bugun / hedef),
                      minHeight: 6,
                      backgroundColor: kCizgi,
                      color: kTuruncu,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Hesabım',
            onPressed: hesabiAc,
            icon: CircleAvatar(
              radius: 24,
              backgroundColor: kKart,
              child: Text(profil.avatar, style: const TextStyle(fontSize: 24)),
            ),
          ),
        ],
      ),
    );
  }

  // Ortadaki halka: bugünkü hedefe göre dolar, içinde seri yazar
  Widget seriHalkasi() {
    final oran = min(1.0, bugun / max(1, profil.hedef));
    return SizedBox(
      width: 168,
      height: 168,
      child: CustomPaint(
        painter: HalkaCizim(oran),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 30,
                  height: 34,
                  child: CustomPaint(
                    painter: KayisiCizim(renk: kTuruncu, doluluk: 1),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${seriHesapla()}',
                  style: const TextStyle(
                    fontSize: 50,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'GÜNLÜK SERİ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: kSoluk,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Son 7 gün: çalışılan günler dolu turuncu, bugün beyaz çerçeveli
  Widget haftaNoktalari() {
    const harfler = ['P', 'S', 'Ç', 'P', 'C', 'C', 'P']; // Pazartesi..Pazar
    final simdi = DateTime.now();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(7, (i) {
        final gun = simdi.subtract(Duration(days: 6 - i));
        final calisti = (gecmis[tarihMetni(gun)] ?? 0) > 0;
        final bugunMu = i == 6;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: calisti ? kTuruncu : Colors.transparent,
                  border: Border.all(
                    color: calisti ? kTuruncu : (bugunMu ? kYazi : kCizgi),
                    width: 2,
                  ),
                ),
                child: calisti
                    ? const Icon(Icons.check_rounded, size: 18, color: kZemin)
                    : null,
              ),
              const SizedBox(height: 5),
              Text(
                harfler[gun.weekday - 1], // weekday: 1 = Pazartesi
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: kSoluk,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // Büyük yuvarlak ders kartı
  Widget dersKarti(Ders d) {
    final puan = dersPuanlari[d.kimlik] ?? 0;
    final bilinen = dersteBilinen(d);
    return LayoutBuilder(
      builder: (context, alan) {
        // Kart, eldeki alana sığan en büyük daire olsun
        final cap = min(alan.maxWidth - 16, alan.maxHeight - 34);
        return Center(
          child: SizedBox(
            width: cap,
            height: cap + 18,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: 18,
                  child: Container(
                    width: cap,
                    height: cap,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: kKart, width: 6),
                    ),
                    child: ClipOval(
                      child: CustomPaint(
                        painter: ManzaraCizim(d.duzey),
                        child: Column(
                          children: [
                            SizedBox(height: cap * 0.15),
                            Text(
                              '${d.duzey} · Ders ${d.no}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFEBDDEF),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  d.baslik,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // 3 kayısı: kazanılanlar dolu
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(3, (i) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 5),
                                  child: SizedBox(
                                    width: 30,
                                    height: 34,
                                    child: CustomPaint(
                                      painter: KayisiCizim(
                                        renk: i < puan ? kTuruncu : Colors.white,
                                        doluluk: i < puan ? 1 : 0,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                            const Spacer(),
                            SizedBox(
                              width: cap * 0.56,
                              height: 52,
                              child: FilledButton(
                                onPressed: () => dersiBaslat(d),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF1A0E05),
                                  textStyle: const TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                child: Text(puan > 0 ? 'Tekrarla' : 'Devam et'),
                              ),
                            ),
                            SizedBox(height: cap * 0.11),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Üstteki rozet: dersteki kelimelerden kaçını biliyorsun
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: kTuruncu,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '$bilinen / ${d.kelimeler.length} kelime',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1A0E05),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===== Eski ekranlar (sırayla yenilenecek) =====

  Widget hedefSatiri() {
    final hedef = profil.hedef;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (profil.ad.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Merhaba ${profil.ad}! 👋',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: kParlakTuruncu,
              ),
            ),
          ),
        Text(
          bugun >= hedef
              ? 'Bugünkü hedef tamam! 🎉 ($bugun / $hedef)'
              : 'Bugünkü hedef: $bugun / $hedef',
          style: const TextStyle(color: kSoluk, fontSize: 15),
        ),
        const SizedBox(height: 10),
        // Hedef küçükse kayısı dizisi, büyükse ilerleme çubuğu
        if (hedef <= 12)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(hedef, (i) {
              return Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < bugun ? kTuruncu : Colors.transparent,
                  border: Border.all(color: kTuruncu, width: 2.5),
                ),
              );
            }),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: min(1.0, bugun / hedef),
              minHeight: 14,
              backgroundColor: kVurguZemin,
              color: kTuruncu,
            ),
          ),
      ],
    );
  }

  Widget kayisiKart() {
    return GestureDetector(
      onTap: () {
        setState(() {
          onYuz = !onYuz;
        });
      },
      child: Container(
        width: double.infinity,
        height: 400,
        decoration: BoxDecoration(
          color: kKart,
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 240,
                  height: 270,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: onYuz ? 0 : 1),
                    duration: const Duration(milliseconds: 350),
                    builder: (context, v, _) {
                      return CustomPaint(
                        painter: KayisiCizim(renk: kTuruncu, doluluk: v),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(36, 90, 36, 20),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                onYuz ? aktif.ing : aktif.anlam,
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  color: Color.lerp(kTuruncu, Colors.white, v),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => oku(aktif.ing),
              icon: const Icon(Icons.volume_up, color: kTuruncu),
              label: const Text(
                'dinle',
                style: TextStyle(color: kTuruncu, fontSize: 16),
              ),
            ),
            Text(
              aktif.seviye >= 3
                  ? '☀️ tekrar zamanı: hatırlıyor musun?'
                  : 'karta dokun ve çevir',
              style: const TextStyle(color: Color(0xFF7E766E), fontSize: 14),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget yuvarlakButon({
    required IconData ikon,
    required Color renk,
    required Color zemin,
    required String etiket,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        Material(
          color: zemin,
          elevation: 4,
          shape: CircleBorder(
            side: BorderSide(color: renk.withValues(alpha: 0.25), width: 2),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 76,
              height: 76,
              child: Icon(ikon, color: renk, size: 38),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(etiket, style: const TextStyle(color: kSoluk)),
      ],
    );
  }

  Widget kartEkrani() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          hedefSatiri(),
          const SizedBox(height: 24),
          kayisiKart(),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              yuvarlakButon(
                ikon: Icons.close,
                renk: const Color(0xFFE8674A),
                zemin: kKart,
                etiket: 'Bilmiyorum',
                onTap: () => kartCevapla(false),
              ),
              yuvarlakButon(
                ikon: Icons.check,
                renk: Colors.white,
                zemin: kTuruncu,
                etiket: 'Biliyorum',
                onTap: () => kartCevapla(true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Test sekmesi: duruma göre mod seçimi, soru ya da sonuç ekranı
  Widget testEkrani() {
    if (testDurumu == 'soru') return soruEkrani();
    if (testDurumu == 'sonuc') return sonucEkrani();
    return modSecimEkrani();
  }

  Widget modKarti(String mod, IconData ikon, String baslik, String aciklama) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: kKart,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => turBaslat(mod),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: kVurguZemin,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(ikon, color: kParlakTuruncu, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        baslik,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(aciklama, style: const TextStyle(color: kSoluk)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: kSoluk),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget modSecimEkrani() {
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Text(
            'Nasıl çalışmak istersin?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: kParlakTuruncu,
            ),
          ),
        ),
        modKarti('secmeli', Icons.touch_app, 'Çoktan seçmeli', '4 şıktan doğruyu seç'),
        modKarti('yazma', Icons.keyboard, 'Yazarak', 'Cevabı kendin yaz, en kalıcısı'),
        modKarti('dinle', Icons.hearing, 'Dinle ve seç', 'Kelimeyi sadece duy, anlamını bul'),
        kutu(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Yön',
                style: TextStyle(fontWeight: FontWeight.bold, color: kSoluk),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('İngilizce → Türkçe'),
                    selected: !tersYon,
                    onSelected: (_) => setState(() => tersYon = false),
                  ),
                  ChoiceChip(
                    label: const Text('Türkçe → İngilizce'),
                    selected: tersYon,
                    onSelected: (_) => setState(() => tersYon = true),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Dinle modunda kelime hep İngilizce okunur.',
                style: TextStyle(fontSize: 12, color: kSoluk),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Her tur $turUzunlugu soru. Açık seviyelerden sorulur.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: kSoluk),
          ),
        ),
      ],
    );
  }

  // Bir şık butonu: cevaptan sonra doğrusu yeşil, yanlış seçilen kırmızı olur
  Widget sikButonu(String sik) {
    Color zemin = kKart;
    Color yazi = kYazi;
    if (cevaplandi) {
      if (sik == dogruSik) {
        zemin = const Color(0xFF2E9E5B);
        yazi = Colors.white;
      } else if (sik == secilenSik) {
        zemin = const Color(0xFFC94A3A);
        yazi = Colors.white;
      } else {
        yazi = const Color(0xFF5C554F);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: zemin,
        borderRadius: BorderRadius.circular(18),
        elevation: cevaplandi ? 0 : 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: cevaplandi ? null : () => sikSec(sik),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
            child: Text(
              sik,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: yazi,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Sorunun gösterildiği beyaz kart
  Widget soruKarti() {
    final k = soru;
    final dinleModu = testModu == 'dinle';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: kKart,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        children: [
          Text(
            dinleModu
                ? 'Duyduğun kelimenin anlamı ne?'
                : (tersMi() ? 'İngilizcesi ne?' : 'Türkçesi ne?'),
            style: const TextStyle(color: kSoluk),
          ),
          const SizedBox(height: 14),
          if (dinleModu)
            Material(
              color: kTuruncu,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => oku(k.ing),
                child: const SizedBox(
                  width: 96,
                  height: 96,
                  child: Icon(Icons.volume_up, color: Colors.white, size: 48),
                ),
              ),
            ),
          if (!dinleModu || cevaplandi)
            Padding(
              padding: EdgeInsets.only(top: dinleModu ? 12 : 0),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  soruMetni(k),
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                    color: kParlakTuruncu,
                  ),
                ),
              ),
            ),
          // İngilizce kelime görünüyorsa dinlenebilir
          if (!dinleModu && (!tersMi() || cevaplandi))
            TextButton.icon(
              onPressed: () => oku(k.ing),
              icon: const Icon(Icons.volume_up, color: kTuruncu),
              label: const Text('dinle', style: TextStyle(color: kTuruncu)),
            ),
        ],
      ),
    );
  }

  // Doğru/yanlış kutusu ve sonraki butonu
  Widget geriBildirim() {
    final k = soru;
    final renk = sonCevapDogru ? const Color(0xFF4CC37A) : const Color(0xFFE8674A);
    final zemin = sonCevapDogru ? const Color(0xFF14231A) : const Color(0xFF2A1715);
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: zemin,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(
                sonCevapDogru ? Icons.check_circle : Icons.cancel,
                color: renk,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  sonCevapDogru ? 'Doğru! 🎉' : 'Doğrusu: ${k.ing} = ${k.anlam}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: renk,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: sonrakiSoru,
            child: Text(
              soruNo + 1 >= turSorulari.length ? 'Sonuçları gör' : 'Sonraki →',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget soruEkrani() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: kSoluk),
                onPressed: () => setState(() => testDurumu = 'secim'),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (soruNo + 1) / turSorulari.length,
                    minHeight: 10,
                    backgroundColor: kVurguZemin,
                    color: kTuruncu,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${soruNo + 1}/${turSorulari.length}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: kSoluk),
              ),
            ],
          ),
          const SizedBox(height: 16),
          soruKarti(),
          const SizedBox(height: 20),
          if (testModu == 'yazma') ...[
            TextField(
              controller: cevapKutusu,
              enabled: !cevaplandi,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20),
              decoration: InputDecoration(
                hintText: tersMi() ? 'İngilizcesini yaz' : 'Türkçesini yaz',
                filled: true,
                fillColor: kKart,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => yaziKontrol(),
            ),
            const SizedBox(height: 12),
            if (!cevaplandi)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => cevapla(false),
                      child: const Text('Bilmiyorum'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: yaziKontrol,
                      child: const Text('Kontrol et'),
                    ),
                  ),
                ],
              ),
          ] else ...[
            for (final sik in siklar) sikButonu(sik),
          ],
          if (cevaplandi) ...[
            const SizedBox(height: 8),
            geriBildirim(),
          ],
        ],
      ),
    );
  }

  Widget sonucEkrani() {
    final toplam = turSorulari.length;
    final oran = toplam == 0 ? 0.0 : turDogru / toplam;
    final mesaj = oran >= 0.9
        ? 'Harika! 🍑'
        : (oran >= 0.6 ? 'Güzel gidiyorsun!' : 'Tekrar etmeye devam!');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Center(
          child: SizedBox(
            width: 180,
            height: 200,
            child: CustomPaint(
              painter: KayisiCizim(renk: kTuruncu, doluluk: oran),
              child: Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Center(
                  child: Text(
                    '$turDogru/$toplam',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: oran >= 0.5 ? Colors.white : kParlakTuruncu,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          mesaj,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: kParlakTuruncu,
          ),
        ),
        const SizedBox(height: 20),
        if (turYanlislar.isNotEmpty)
          Material(
            color: kKart,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'Tekrar et',
                    style: TextStyle(fontWeight: FontWeight.bold, color: kSoluk),
                  ),
                ),
                for (final k in turYanlislar)
                  ListTile(
                    title: Text(
                      k.ing,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(k.anlam),
                    trailing: IconButton(
                      icon: const Icon(Icons.volume_up, color: kTuruncu),
                      onPressed: () => oku(k.ing),
                    ),
                  ),
              ],
            ),
          ),
          ),
        const SizedBox(height: 20),
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: () => turBaslat(testModu),
            child: const Text('Yeni tur', style: TextStyle(fontSize: 18)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: OutlinedButton(
            onPressed: () => setState(() => testDurumu = 'secim'),
            child: const Text('Mod değiştir'),
          ),
        ),
      ],
    );
  }

  // YENİ: Bir seviyenin kartı: ad, ilerleme çubuğu, aç/kapa düğmesi
  Widget paketKarti(String duzey, String ad) {
    final liste = kelimeler.where((k) => k.duzey == duzey).toList();
    final toplam = liste.length;
    final ogrenilen = liste.where((k) => k.seviye >= 3).length;
    return kutu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kTuruncu,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  duzey == 'Benim' ? '★' : duzey,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ad,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$ogrenilen / $toplam kelime öğrenildi',
                      style: const TextStyle(color: kSoluk),
                    ),
                  ],
                ),
              ),
              Switch(
                value: seciliDuzeyler.contains(duzey),
                onChanged: toplam == 0 ? null : (acik) => duzeyDegistir(duzey, acik),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: toplam == 0 ? 0 : ogrenilen / toplam,
              minHeight: 8,
              backgroundColor: kVurguZemin,
              color: kTuruncu,
            ),
          ),
        ],
      ),
    );
  }

  // ===== YENİ: Profil sekmesi (Paketler sekmesi de buraya taşındı) =====

  Widget profilEkrani() {
    final ogrenilen = kelimeler.where((k) => k.seviye >= 3).length;
    final saat =
        '${profil.saat.toString().padLeft(2, '0')}:${profil.dakika.toString().padLeft(2, '0')}';
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 28),
      children: [
        // Profil kartı: dokununca Hesabım sayfası açılır
        kutu(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: hesabiAc,
            leading: CircleAvatar(
              radius: 30,
              backgroundColor: kVurguZemin,
              child: Text(profil.avatar, style: const TextStyle(fontSize: 30)),
            ),
            title: Text(
              profil.ad.isEmpty ? 'Adını ekle' : profil.ad,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              '$ogrenilen kelime öğrendi · ${seriHesapla()} gün seri',
              style: const TextStyle(color: kSoluk, fontWeight: FontWeight.w600),
            ),
            trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF7E766E)),
          ),
        ),

        bolumBasligi('ÇALIŞMA'),
        kutu(
          child: Column(
            children: [
              ayarSatiri(
                ikon: Icons.flag_outlined,
                ad: 'Günlük hedef',
                deger: '${profil.hedef} kelime',
                onTap: hesabiAc,
              ),
              ayarSatiri(
                ikon: Icons.notifications_none_rounded,
                ad: 'Hatırlatma',
                deger: profil.bildirim ? saat : 'Kapalı',
                onTap: hesabiAc,
              ),
            ],
          ),
        ),

        bolumBasligi('SEVİYELER'),
        for (final d in duzeyBilgisi.entries) paketKarti(d.key, d.value),
        kutu(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.add_circle_outline, color: kTuruncu),
            title: const Text(
              'Kendi kelimeni ekle',
              style: TextStyle(fontWeight: FontWeight.bold, color: kSoluk),
            ),
            children: [
              TextField(
                controller: ingKutusu,
                decoration: const InputDecoration(
                  labelText: 'İngilizce kelime',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: trKutusu,
                decoration: const InputDecoration(
                  labelText: 'Türkçe anlamı',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => kelimeEkle(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: kelimeEkle,
                  child: const Text('Kaydet'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),

        bolumBasligi('DİĞER'),
        kutu(
          child: ayarSatiri(
            ikon: Icons.restart_alt_rounded,
            ad: 'İlerlemeyi sıfırla',
            renk: const Color(0xFFE8674A),
            onTap: sifirlaSor,
          ),
        ),
        const SizedBox(height: 18),
        const Center(
          child: Text(
            "ApriEnglish 1.0 · Malatya'dan sevgilerle",
            style: TextStyle(fontSize: 12, color: Color(0xFF5C554F)),
          ),
        ),
      ],
    );
  }

  // Gri, küçük, aralıklı harfli bölüm başlığı
  Widget bolumBasligi(String metin) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
        child: Text(
          metin,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: Color(0xFF7E766E),
          ),
        ),
      );

  // Ayar listesindeki bir satır: ikon, ad, sağda değer ve ok
  Widget ayarSatiri({
    required IconData ikon,
    required String ad,
    String? deger,
    Color renk = kYazi,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(ikon, color: renk == kYazi ? kSoluk : renk),
      title: Text(
        ad,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: renk),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (deger != null)
            Text(
              deger,
              style: const TextStyle(fontWeight: FontWeight.w700, color: kTuruncu),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF7E766E)),
        ],
      ),
    );
  }

  // YENİ: Her şeyi sıfırlamadan önce mutlaka sorar
  Future<void> sifirlaSor() async {
    final eminMi = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İlerleme sıfırlansın mı?'),
        content: const Text(
          'Bütün kelimeler hama döner; seri, takvim ve ders kayısıları silinir. '
          'Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE8674A)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sıfırla'),
          ),
        ],
      ),
    );
    if (eminMi != true || !mounted) return; // Vazgeç ya da dışarı dokunuldu
    setState(() {
      for (final k in kelimeler) {
        k.seviye = 0;
        k.yanlis = 0;
        k.tekrar = null;
      }
      gecmis.clear();
      dersPuanlari.clear();
      bugun = 0;
      aktif = kelimeSec();
      onYuz = true;
      kaydiriciyiKur();
    });
    final prefs = SharedPreferencesAsync();
    // Çok eski sürümden kalan bugün sayacı geri gelmesin
    await prefs.remove('tarih');
    await prefs.remove('bugun');
    await kelimeleriKaydet();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('İlerleme sıfırlandı.')),
    );
  }

  // Renkli küçük kayısı (aşamasına göre)
  Widget kucukKayisi(int seviye, double boyut) {
    return Container(
      width: boyut,
      height: boyut * 0.94,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.4),
          colors: durumRenkleri(seviye),
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(1, 2)),
        ],
      ),
    );
  }

  // Koyu gri yuvarlak köşeli kutu. Container yerine Material: içindeki ListTile'ların dokunma efekti görünsün
  Widget kutu({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: kKart,
        borderRadius: BorderRadius.circular(20),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }

  // 🔥 Seri ve bugün
  Widget seriKutusu() {
    final seri = seriHesapla();
    return kutu(
      child: Row(
        children: [
          const Text('🔥', style: TextStyle(fontSize: 36)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$seri gün seri',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: kParlakTuruncu,
                  ),
                ),
                Text(
                  'Bugün $bugun kelime bildin',
                  style: const TextStyle(color: kSoluk),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Takvim karesinin rengi: o gün ne kadar çok kelime bilindiyse o kadar koyu
  Color takvimRengi(int sayi) {
    if (sayi >= 10) return kParlakTuruncu;
    if (sayi >= 5) return const Color(0xFFC0662A);
    if (sayi >= 1) return const Color(0xFF6E3F1E);
    return kCizgi;
  }

  // 📅 Son 12 hafta: her sütun bir hafta, her satır bir gün (Pzt..Paz)
  Widget takvim() {
    final bugunTarih = DateTime.now();
    final buPazartesi = bugunTarih.subtract(Duration(days: bugunTarih.weekday - 1));
    final baslangic = buPazartesi.subtract(const Duration(days: 7 * 11));
    return kutu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Son 12 hafta',
            style: TextStyle(fontWeight: FontWeight.bold, color: kSoluk),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(12, (hafta) {
              return Column(
                children: List.generate(7, (gun) {
                  final tarih = baslangic.add(Duration(days: hafta * 7 + gun));
                  final gelecek = tarih.isAfter(bugunTarih);
                  final sayi = gecmis[tarihMetni(tarih)] ?? 0;
                  return Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: gelecek ? Colors.transparent : takvimRengi(sayi),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              );
            }),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('az ', style: TextStyle(color: kSoluk, fontSize: 12)),
              for (final s in [0, 1, 5, 10])
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: takvimRengi(s),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const Text(' çok', style: TextStyle(color: kSoluk, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  // ☀️ Kurutma özeti: dört aşamanın sayıları
  Widget kurutmaKutusu() {
    int say(int grup) =>
        kelimeler.where((k) => durumGrubu(k.seviye) == grup).length;
    final zamaniGelen =
        kelimeler.where((k) => k.seviye >= 3 && zamaniGeldi(k)).length;

    Widget asama(int seviye, int sayi, String ad) {
      return Expanded(
        child: Column(
          children: [
            kucukKayisi(seviye, 30),
            const SizedBox(height: 6),
            Text(
              '$sayi',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: kParlakTuruncu,
              ),
            ),
            Text(ad, style: const TextStyle(fontSize: 12, color: kSoluk)),
          ],
        ),
      );
    }

    return kutu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '☀️ Kurutma',
            style: TextStyle(fontWeight: FontWeight.bold, color: kSoluk),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              asama(0, say(0), 'ham'),
              asama(1, say(1), 'yarı'),
              asama(3, say(3), 'kurutmada'),
              asama(4, say(4), 'kuru'),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '3 kez bildiğin kelime kurutmaya alınır. 3 gün sonra yine bilirsen '
            'kuru kayısı olur: artık kalıcı!',
            style: TextStyle(fontSize: 13, color: kSoluk),
          ),
          if (zamaniGelen > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Bugün tekrar zamanı gelen: $zamaniGelen kelime',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: kParlakTuruncu,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Listede kelimenin altındaki açıklama
  String kelimeAciklamasi(Kelime k) {
    if (k.seviye >= 3 && k.tekrar != null && !zamaniGeldi(k)) {
      final kalan = DateTime.parse(k.tekrar!)
          .difference(DateTime.parse(bugununTarihi()))
          .inDays;
      return '${k.duzey} · ${k.anlam} · ${durumAdi(k.seviye)} · $kalan gün sonra tekrar';
    }
    return '${k.duzey} · ${k.anlam} · ${durumAdi(k.seviye)}';
  }

  // Hasat sekmesi: seri, takvim, kurutma, arama ve liste
  Widget hasatEkrani() {
    final filtreler = {-1: 'Hepsi', 0: 'Ham', 1: 'Yarı', 3: 'Kurutmada', 4: 'Kuru'};
    final gorunen = kelimeler.where((k) {
      final filtreUygun = filtre == -1 || durumGrubu(k.seviye) == filtre;
      final aramaUygun = arama.isEmpty ||
          k.ing.contains(arama) ||
          k.anlam.contains(arama);
      return filtreUygun && aramaUygun;
    }).toList();

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      children: [
        seriKutusu(),
        takvim(),
        kurutmaKutusu(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: aramaKutusu,
            decoration: InputDecoration(
              hintText: 'Kelime ara (${kelimeler.length} kelime)',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: kKart,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (metin) {
              setState(() {
                arama = turkceKucuk(metin.trim());
              });
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              for (final f in filtreler.entries)
                ChoiceChip(
                  label: Text(f.value),
                  selected: filtre == f.key,
                  onSelected: (_) {
                    setState(() {
                      filtre = f.key;
                    });
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (gorunen.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Burada kelime yok.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kSoluk),
            ),
          ),
        for (final k in gorunen)
          ListTile(
            leading: kucukKayisi(k.seviye, 26),
            title: Text(
              k.ing,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(kelimeAciklamasi(k)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.volume_up, color: kTuruncu),
                  onPressed: () => oku(k.ing),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => kelimeSil(k),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!yuklendi) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // YENİ: İlk açılışta önce tanıtım
    if (!tanitimTamam) {
      return TanitimSayfasi(profil: profil.kopya(), onBitti: tanitimBitti);
    }
    // Sekmeler: 0 ana sayfa, 1 kartlar, 2 test, 3 hasat, 4 profil
    final ekranlar = [
      anaSayfaEkrani(),
      kartEkrani(),
      testEkrani(),
      hasatEkrani(),
      profilEkrani(),
    ];
    const basliklar = ['', 'Kartlar', 'Test', 'Hasat', 'Profil'];
    return Scaffold(
      // Ana sayfanın kendi üst şeridi var; başlık çubuğu sadece diğer sekmelerde
      appBar: sekme == 0
          ? null
          : AppBar(title: Text(basliklar[sekme])),
      body: ekranlar[sekme],
      // YENİ: Sadece ikonlu alt menü (yazılar gizli, basılı tutunca görünür)
      bottomNavigationBar: NavigationBar(
        selectedIndex: sekme,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        height: 68,
        onDestinationSelected: (i) {
          setState(() {
            sekme = i;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined, color: kSoluk),
            selectedIcon: Icon(Icons.home_rounded, color: kTuruncu),
            label: 'Ana sayfa',
            tooltip: 'Ana sayfa',
          ),
          NavigationDestination(
            icon: Icon(Icons.style_outlined, color: kSoluk),
            selectedIcon: Icon(Icons.style, color: kTuruncu),
            label: 'Kartlar',
            tooltip: 'Kartlar',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_outlined, color: kSoluk),
            selectedIcon: Icon(Icons.edit, color: kTuruncu),
            label: 'Test',
            tooltip: 'Test',
          ),
          NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined, color: kSoluk),
            selectedIcon: Icon(Icons.wb_sunny, color: kTuruncu),
            label: 'Hasat',
            tooltip: 'Hasat',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded, color: kSoluk),
            selectedIcon: Icon(Icons.person_rounded, color: kTuruncu),
            label: 'Profil',
            tooltip: 'Profil',
          ),
        ],
      ),
    );
  }
}


// ======================= Hesabım =======================

// YENİ: Kullanıcının bilgileri ve ayarları
class Profil {
  String ad;
  String avatar;
  int hedef; // günlük kelime hedefi
  bool bildirim; // günlük hatırlatma açık mı
  int saat;
  int dakika;

  Profil({
    this.ad = '',
    this.avatar = '🧑',
    this.hedef = 10,
    this.bildirim = false,
    this.saat = 20,
    this.dakika = 0,
  });

  // Hesabım sayfası bir kopya üzerinde çalışır; Kaydet'e basılmazsa asıl profil değişmez
  Profil kopya() => Profil(
        ad: ad,
        avatar: avatar,
        hedef: hedef,
        bildirim: bildirim,
        saat: saat,
        dakika: dakika,
      );

  Map<String, dynamic> toJson() => {
        'ad': ad,
        'avatar': avatar,
        'hedef': hedef,
        'bildirim': bildirim,
        'saat': saat,
        'dakika': dakika,
      };

  factory Profil.fromJson(Map<String, dynamic> j) => Profil(
        ad: j['ad'] ?? '',
        avatar: j['avatar'] ?? '🧑',
        hedef: j['hedef'] ?? 10,
        bildirim: j['bildirim'] ?? false,
        saat: j['saat'] ?? 20,
        dakika: j['dakika'] ?? 0,
      );
}

// YENİ: Ayrı bir sayfa. Navigator.push ile açılır, Navigator.pop ile sonucu geri verir.
class HesapSayfasi extends StatefulWidget {
  final Profil profil;
  final int oneri;
  final String oneriAciklama;
  final Map<String, int> istatistikler;

  const HesapSayfasi({
    super.key,
    required this.profil,
    required this.oneri,
    required this.oneriAciklama,
    required this.istatistikler,
  });

  @override
  State<HesapSayfasi> createState() => _HesapSayfasiState();
}

class _HesapSayfasiState extends State<HesapSayfasi> {
  static const avatarlar = [
    '👩', '👨', '🧑', '👧', '👦', '👵', '👴', '🧕', '🧔',
    '👱‍♀️', '👱‍♂️', '👩🏻', '👨🏽', '🧑🏾', '👩🏿',
    '👩‍🎓', '👨‍🎓', '👩‍💻', '👨‍💻', '👩‍🏫', '👨‍🏫',
    '👩‍💼', '👨‍💼', '👩‍⚕️', '👨‍⚕️', '👩‍🍳', '👨‍🍳',
  ];

  late Profil p;
  late TextEditingController adKutusu;
  late TextEditingController hedefKutusu;

  @override
  void initState() {
    super.initState();
    p = widget.profil;
    adKutusu = TextEditingController(text: p.ad);
    hedefKutusu = TextEditingController(text: '${p.hedef}');
  }

  @override
  void dispose() {
    adKutusu.dispose();
    hedefKutusu.dispose();
    super.dispose();
  }

  String saatMetni() =>
      '${p.saat.toString().padLeft(2, '0')}:${p.dakika.toString().padLeft(2, '0')}';

  Future<void> saatSec() async {
    final secilen = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: p.saat, minute: p.dakika),
    );
    if (secilen == null) return;
    setState(() {
      p.saat = secilen.hour;
      p.dakika = secilen.minute;
    });
  }

  void kaydet() {
    final hedef = int.tryParse(hedefKutusu.text) ?? 0;
    if (hedef < 1 || hedef > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Günlük hedef 1 ile 100 arasında olmalı.')),
      );
      return;
    }
    p.ad = adKutusu.text.trim();
    p.hedef = hedef;
    Navigator.pop(context, p); // profili ana sayfaya geri gönder
  }

  // Beyaz kutu. Container yerine Material: içindeki ListTile'ların dokunma efekti görünsün
  Widget kutu({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: kKart,
        borderRadius: BorderRadius.circular(20),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }

  Widget baslik(String metin) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          metin,
          style: const TextStyle(fontWeight: FontWeight.bold, color: kSoluk),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hesabım')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Büyük avatar
          Center(
            child: CircleAvatar(
              radius: 52,
              backgroundColor: kVurguZemin,
              child: Text(p.avatar, style: const TextStyle(fontSize: 56)),
            ),
          ),
          const SizedBox(height: 16),

          // Avatar seçimi
          kutu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                baslik('Avatarını seç'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in avatarlar)
                      GestureDetector(
                        onTap: () => setState(() => p.avatar = a),
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: p.avatar == a ? kVurguZemin : kCizgi,
                            border: Border.all(
                              color: p.avatar == a ? kTuruncu : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: Text(a, style: const TextStyle(fontSize: 26)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Ad
          kutu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                baslik('Adın'),
                TextField(
                  controller: adKutusu,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Örneğin: Hamid',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),

          // Günlük hedef + öneri
          kutu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                baslik('Günlük hedef'),
                TextField(
                  controller: hedefKutusu,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    suffixText: 'kelime / gün',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kZemin,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline, color: kParlakTuruncu),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.oneriAciklama,
                          style: const TextStyle(fontSize: 13, color: kSoluk),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(
                          () => hedefKutusu.text = '${widget.oneri}',
                        ),
                        child: Text('${widget.oneri} uygula'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bildirim
          kutu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                baslik('Bildirim'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Günlük hatırlatma'),
                  subtitle: const Text('Her gün seçtiğin saatte hatırlatır'),
                  value: p.bildirim,
                  onChanged: (acik) => setState(() => p.bildirim = acik),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: p.bildirim,
                  leading: const Icon(Icons.alarm),
                  title: const Text('Saat'),
                  trailing: Text(
                    saatMetni(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: kParlakTuruncu,
                    ),
                  ),
                  onTap: p.bildirim ? saatSec : null,
                ),
                TextButton.icon(
                  onPressed: denemeBildirimi,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Deneme bildirimi gönder'),
                ),
              ],
            ),
          ),

          // İstatistikler
          kutu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                baslik('İstatistikler'),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.1,
                  children: [
                    for (final e in widget.istatistikler.entries)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${e.value}',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: kParlakTuruncu,
                            ),
                          ),
                          Text(
                            e.key,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, color: kSoluk),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: kaydet,
              child: const Text('Kaydet', style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}


// ======================= Tanıtım (ilk açılış) =======================

// YENİ: 5 sayfalık karşılama. Sağa kaydırarak ya da Devam ile ilerlenir.
class TanitimSayfasi extends StatefulWidget {
  final Profil profil;
  final void Function(Profil profil, Set<String> duzeyler) onBitti;

  const TanitimSayfasi({super.key, required this.profil, required this.onBitti});

  @override
  State<TanitimSayfasi> createState() => _TanitimSayfasiState();
}

class _TanitimSayfasiState extends State<TanitimSayfasi> {
  static const sayfaSayisi = 5;
  static const avatarlar = [
    '👩', '👨', '🧑', '👧', '👦', '🧕', '🧔', '👵', '👴',
    '👩‍🎓', '👨‍🎓', '👩‍💻', '👨‍💻', '👩‍🏫', '👨‍🏫',
  ];

  final PageController sayfaKontrol = PageController();
  int sayfa = 0;
  late Profil p;
  late TextEditingController adKutusu;
  String seviye = 'yeni'; // 'yeni', 'biraz', 'orta'

  @override
  void initState() {
    super.initState();
    p = widget.profil;
    p.bildirim = true; // hatırlatma varsayılan olarak açık, istersen kapatırsın
    adKutusu = TextEditingController(text: p.ad);
  }

  @override
  void dispose() {
    sayfaKontrol.dispose();
    adKutusu.dispose();
    super.dispose();
  }

  void ileri() {
    FocusScope.of(context).unfocus(); // klavye açıksa kapat
    if (sayfa < sayfaSayisi - 1) {
      sayfaKontrol.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      bitir();
    }
  }

  void geri() {
    sayfaKontrol.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void bitir() {
    p.ad = adKutusu.text.trim();
    // Seçilen seviyeye göre hangi paketler açık olsun
    final duzeyler = switch (seviye) {
      'biraz' => <String>{'A1', 'A2', 'Benim'},
      'orta' => <String>{'A2', 'B1', 'Benim'},
      _ => <String>{'A1', 'Benim'},
    };
    widget.onBitti(p, duzeyler);
  }

  // Her sayfanın ortak iskeleti: ortalanmış ve kaydırılabilir
  Widget iskelet(List<Widget> icerik) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: icerik),
      ),
    );
  }

  Widget baslik(String metin) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          metin,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: kParlakTuruncu,
          ),
        ),
      );

  Widget aciklama(String metin) => Text(
        metin,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16, color: kSoluk, height: 1.4),
      );

  // Seçilebilir kart (seviye ve hedef sayfalarında)
  Widget secenek({
    required bool secili,
    required String emoji,
    required String ad,
    required String detay,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: secili ? kVurguZemin : kKart,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: secili ? kTuruncu : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 30)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ad,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(detay, style: const TextStyle(color: kSoluk)),
                    ],
                  ),
                ),
                if (secili) const Icon(Icons.check_circle, color: kTuruncu),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Sayfa 1: Hoş geldin
  Widget hosgeldin() {
    return iskelet([
      SizedBox(
        width: 190,
        height: 210,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1400),
          curve: Curves.easeInOut,
          builder: (context, v, _) => CustomPaint(
            painter: KayisiCizim(renk: kTuruncu, doluluk: v),
          ),
        ),
      ),
      const SizedBox(height: 28),
      baslik("ApriEnglish'e\nhoş geldin!"),
      aciklama('İngilizce kelimeleri kayısı kartlarıyla, her gün biraz biraz öğren.'),
    ]);
  }

  // Sayfa 2: Nasıl çalışır
  Widget nasilCalisir() {
    Widget satir(IconData ikon, String ad, String detay) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: kVurguZemin,
              child: Icon(ikon, color: kParlakTuruncu, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ad,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(detay, style: const TextStyle(color: kSoluk, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return iskelet([
      baslik('Nasıl çalışır?'),
      const SizedBox(height: 8),
      satir(Icons.style, 'Kartları çevir',
          'Kelimeyi gör, karta dokun, anlamını öğren. Bildin mi, bilemedin mi söyle.'),
      satir(Icons.wb_sunny, 'Kayısını kurut',
          '3 kez bildiğin kelime kurutmaya alınır. Birkaç gün sonra yine bilirsen kalıcı olur.'),
      satir(Icons.edit, 'Kendini test et',
          'Çoktan seçmeli, yazarak ya da sadece dinleyerek.'),
    ]);
  }

  // Sayfa 3: Avatar ve ad
  Widget tanisalim() {
    return iskelet([
      baslik('Seni tanıyalım'),
      CircleAvatar(
        radius: 48,
        backgroundColor: kVurguZemin,
        child: Text(p.avatar, style: const TextStyle(fontSize: 52)),
      ),
      const SizedBox(height: 16),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final a in avatarlar)
            GestureDetector(
              onTap: () => setState(() => p.avatar = a),
              child: Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.avatar == a ? kVurguZemin : kKart,
                  border: Border.all(
                    color: p.avatar == a ? kTuruncu : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: Text(a, style: const TextStyle(fontSize: 24)),
              ),
            ),
        ],
      ),
      const SizedBox(height: 20),
      TextField(
        controller: adKutusu,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          hintText: 'Adın',
          filled: true,
          fillColor: kKart,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        onSubmitted: (_) => ileri(),
      ),
    ]);
  }

  // Sayfa 4: Seviye
  Widget seviyeSec() {
    return iskelet([
      baslik('İngilizcen ne durumda?'),
      aciklama('Sana uygun kelimelerle başlayalım.'),
      const SizedBox(height: 20),
      secenek(
        secili: seviye == 'yeni',
        emoji: '🌱',
        ad: 'Yeni başlıyorum',
        detay: 'A1 · en temel kelimeler',
        onTap: () => setState(() => seviye = 'yeni'),
      ),
      secenek(
        secili: seviye == 'biraz',
        emoji: '🌿',
        ad: 'Biraz biliyorum',
        detay: 'A1 + A2 · günlük hayat',
        onTap: () => setState(() => seviye = 'biraz'),
      ),
      secenek(
        secili: seviye == 'orta',
        emoji: '🌳',
        ad: 'Orta seviyeyim',
        detay: 'A2 + B1 · iş, eğitim, fikirler',
        onTap: () => setState(() => seviye = 'orta'),
      ),
    ]);
  }

  // Sayfa 5: Hedef ve hatırlatma
  Widget hedefSec() {
    Widget hedef(int sayi, String emoji, String ad) => secenek(
          secili: p.hedef == sayi,
          emoji: emoji,
          ad: '$sayi kelime / gün',
          detay: ad,
          onTap: () => setState(() => p.hedef = sayi),
        );
    return iskelet([
      baslik('Günlük hedefin'),
      aciklama('İstediğin zaman Hesabım\'dan değiştirebilirsin.'),
      const SizedBox(height: 20),
      hedef(5, '☕', 'Rahat · yaklaşık 5 dakika'),
      hedef(10, '🍑', 'Normal · yaklaşık 10 dakika'),
      hedef(20, '🔥', 'Ciddi · yaklaşık 20 dakika'),
      hedef(30, '🚀', 'Yoğun · yaklaşık 30 dakika'),
      const SizedBox(height: 6),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Her akşam hatırlat'),
        subtitle: Text(
          'Saat ${p.saat.toString().padLeft(2, '0')}:${p.dakika.toString().padLeft(2, '0')}'
          ' · saati Hesabım\'dan değiştirebilirsin',
        ),
        value: p.bildirim,
        onChanged: (acik) => setState(() => p.bildirim = acik),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final sonSayfa = sayfa == sayfaSayisi - 1;
    return Scaffold(
      backgroundColor: kZemin,
      body: SafeArea(
        child: Column(
          children: [
            // Sağ üstte "Geç": varsayılanlarla hemen başlar
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: sonSayfa ? null : bitir,
                child: Text(sonSayfa ? '' : 'Geç'),
              ),
            ),
            Expanded(
              child: PageView(
                controller: sayfaKontrol,
                onPageChanged: (i) => setState(() => sayfa = i),
                children: [
                  hosgeldin(),
                  nasilCalisir(),
                  tanisalim(),
                  seviyeSec(),
                  hedefSec(),
                ],
              ),
            ),
            // Sayfa noktaları: aktif olan uzun turuncu
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(sayfaSayisi, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == sayfa ? 26 : 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: i == sayfa ? kTuruncu : kCizgi,
                    borderRadius: BorderRadius.circular(5),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Row(
                children: [
                  if (sayfa > 0)
                    TextButton(onPressed: geri, child: const Text('Geri')),
                  const Spacer(),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: ileri,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          sonSayfa ? 'Başlayalım! 🍑' : 'Devam',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ======================= Ders sayfası =======================

// YENİ: Ders bitince ana sayfaya giden sonuç
class DersSonucu {
  final Map<Kelime, bool> dogrular; // her kelime: hatasız bilindi mi
  final int puan; // 1-3 kayısı

  DersSonucu(this.dogrular, this.puan);
}

// Dersin bir adımı: hangi ekran ve hangi kelime(ler)
class DersAdimi {
  final String tur; // 'tanit', 'secmeli' ya da 'eslestir'
  final List<Kelime> kelimeler;

  DersAdimi(this.tur, this.kelimeler);
}

class DersSayfasi extends StatefulWidget {
  final Ders ders;
  final List<Kelime> tumKelimeler; // yanlış şıkları buradan seçeriz
  final void Function(String) oku; // ana sayfadaki seslendirme

  const DersSayfasi({
    super.key,
    required this.ders,
    required this.tumKelimeler,
    required this.oku,
  });

  @override
  State<DersSayfasi> createState() => _DersSayfasiState();
}

class _DersSayfasiState extends State<DersSayfasi> {
  static const kYesil = Color(0xFF4CC37A);
  static const kKirmizi = Color(0xFFE8674A);

  final Random rastgele = Random();
  final Stopwatch kronometre = Stopwatch(); // dersin süresi
  List<DersAdimi> adimlar = [];
  int adimNo = 0;
  final Set<Kelime> yanlislar = {}; // derste en az bir kez yanlış yapılanlar
  bool bitti = false;

  // Çoktan seçmeli (tanıtımdaki 2 şık da secilen'i kullanır)
  List<String> siklar = [];
  List<String> ikiSik = []; // tanıtım: doğru anlam + 1 yanlış
  String? secilen;

  // Eşleştirme
  List<Kelime> sol = []; // İngilizce sütun
  List<Kelime> sag = []; // Türkçe sütun (ayrı karıştırılır)
  Kelime? seciliSol;
  Kelime? seciliSag;
  Set<Kelime> eslesenler = {};
  Kelime? hataSol; // yanlış eşleşme yarım saniye kırmızı yanar
  Kelime? hataSag;

  DersAdimi get adim => adimlar[adimNo];

  @override
  void initState() {
    super.initState();
    dersiKur();
  }

  // Ders planı: kelimeler 5'erli iki gruba ayrılır. Her grup için:
  // önce yeni kelimeler tanıtılır, sonra her biri sorulur, en son eşleştirme.
  void dersiKur() {
    final kelimeler = widget.ders.kelimeler;
    adimlar = [];
    for (int i = 0; i < kelimeler.length; i += 5) {
      final grup = kelimeler.sublist(i, min(i + 5, kelimeler.length));
      for (final k in grup) {
        if (k.seviye == 0) adimlar.add(DersAdimi('tanit', [k]));
      }
      final karisik = [...grup]..shuffle(rastgele);
      for (final k in karisik) {
        adimlar.add(DersAdimi('secmeli', [k]));
      }
      if (grup.length >= 3) adimlar.add(DersAdimi('eslestir', grup));
    }
    adimNo = 0;
    yanlislar.clear();
    bitti = false;
    kronometre
      ..reset()
      ..start();
    adimiHazirla();
  }

  // Yeni adıma geçerken o adımın ihtiyaçlarını hazırlar
  void adimiHazirla() {
    final a = adim;
    secilen = null;
    if (a.tur == 'tanit' || a.tur == 'secmeli') {
      widget.oku(a.kelimeler.first.ing);
    }
    if (a.tur == 'secmeli') {
      siklar = siklariUret(a.kelimeler.first);
    }
    if (a.tur == 'tanit') {
      // 4 şıklık listeden doğrusunu ve bir yanlışı alıp karıştır
      final k = a.kelimeler.first;
      final yanlis = siklariUret(k).firstWhere((s) => s != k.anlam);
      ikiSik = [k.anlam, yanlis]..shuffle(rastgele);
    }
    if (a.tur == 'eslestir') {
      sol = [...a.kelimeler]..shuffle(rastgele);
      sag = [...a.kelimeler]..shuffle(rastgele);
      seciliSol = null;
      seciliSag = null;
      eslesenler = {};
      hataSol = null;
      hataSag = null;
    }
  }

  // Doğru anlam + aynı seviyeden 3 yanlış anlam, karışık sırayla.
  // Anlamı ortak olan kelimeler (house "ev" / home "ev, yuva") şık olmaz.
  List<String> siklariUret(Kelime k) {
    final parcalar = k.anlam.split(', ').toSet();
    bool ortakMi(Kelime x) => x.anlam.split(', ').any(parcalar.contains);
    var adaylar = widget.tumKelimeler
        .where((x) => x.duzey == k.duzey && !ortakMi(x))
        .map((x) => x.anlam)
        .toSet()
        .toList();
    if (adaylar.length < 3) {
      adaylar = widget.tumKelimeler
          .where((x) => !ortakMi(x))
          .map((x) => x.anlam)
          .toSet()
          .toList();
    }
    adaylar.shuffle(rastgele);
    return [k.anlam, ...adaylar.take(3)]..shuffle(rastgele);
  }

  void ileri() {
    if (adimNo + 1 >= adimlar.length) {
      kronometre.stop();
      setState(() {
        bitti = true;
      });
      return;
    }
    setState(() {
      adimNo++;
      adimiHazirla();
    });
  }

  // Tanıtımda tahmin: yanlış tahmin puanı düşürmez, kelimeyi ilk kez görüyorsun
  void tahminEt(String sik) {
    if (secilen != null) return;
    setState(() {
      secilen = sik;
    });
  }

  void sikSec(String sik) {
    if (secilen != null) return; // ikinci kez seçilemez
    final k = adim.kelimeler.first;
    setState(() {
      secilen = sik;
      if (sik != k.anlam) yanlislar.add(k);
    });
  }

  void solSec(Kelime k) {
    if (eslesenler.contains(k)) return;
    widget.oku(k.ing);
    setState(() {
      seciliSol = k;
    });
    eslesmeyiDene();
  }

  void sagSec(Kelime k) {
    if (eslesenler.contains(k)) return;
    setState(() {
      seciliSag = k;
    });
    eslesmeyiDene();
  }

  // İki taraftan da seçim yapıldıysa karşılaştır
  void eslesmeyiDene() {
    final a = seciliSol;
    final b = seciliSag;
    if (a == null || b == null) return;
    if (a == b) {
      setState(() {
        eslesenler.add(a);
        seciliSol = null;
        seciliSag = null;
      });
      return;
    }
    yanlislar.add(a);
    setState(() {
      hataSol = a;
      hataSag = b;
      seciliSol = null;
      seciliSag = null;
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return; // sayfa kapandıysa dokunma
      setState(() {
        hataSol = null;
        hataSag = null;
      });
    });
  }

  // 10 kelimeden kaçı hatasız: %90+ = 3, %60+ = 2, gerisi 1 kayısı
  int puanHesapla() {
    final n = widget.ders.kelimeler.length;
    final dogru = widget.ders.kelimeler.where((k) => !yanlislar.contains(k)).length;
    final oran = dogru / n;
    if (oran >= 0.9) return 3;
    if (oran >= 0.6) return 2;
    return 1;
  }

  // ---------------- Görünüm ----------------

  @override
  Widget build(BuildContext context) {
    if (bitti) return sonucEkrani();
    final a = adim;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ustCubuk(),
              const SizedBox(height: 22),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: switch (a.tur) {
                    'tanit' => tanitEkrani(a.kelimeler.first),
                    'secmeli' => secmeliEkrani(a.kelimeler.first),
                    _ => eslestirEkrani(),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Çarpı, ilerleme çubuğu, adım sayısı
  Widget ustCubuk() {
    return Row(
      children: [
        IconButton(
          tooltip: 'Dersten çık',
          onPressed: () => Navigator.pop(context), // sonuç yollamadan çık
          icon: const Icon(Icons.close_rounded, color: kSoluk, size: 28),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: adimNo / adimlar.length),
              duration: const Duration(milliseconds: 300),
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 12,
                backgroundColor: kCizgi,
                color: kTuruncu,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '${adimNo + 1}/${adimlar.length}',
          style: const TextStyle(fontWeight: FontWeight.w800, color: kSoluk),
        ),
      ],
    );
  }

  Widget dinleButonu(Kelime k, {double boyut = 60, bool dolu = true}) {
    return Material(
      color: dolu ? kTuruncu : kVurguZemin,
      shape: dolu
          ? const CircleBorder()
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        customBorder: dolu
            ? const CircleBorder()
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: () => widget.oku(k.ing),
        child: SizedBox(
          width: boyut,
          height: boyut,
          child: Icon(
            Icons.volume_up_rounded,
            size: boyut * 0.47,
            color: dolu ? const Color(0xFF1A0E05) : kTuruncu,
          ),
        ),
      ),
    );
  }

  Widget genisButon(String metin, VoidCallback? onTap, {Color renk = kTuruncu}) {
    return SizedBox(
      height: 58,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: renk,
          foregroundColor: const Color(0xFF1A0E05),
          disabledBackgroundColor: kCizgi,
          disabledForegroundColor: const Color(0xFF7E766E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        child: Text(metin),
      ),
    );
  }

  // 1) Yeni kelime tanıtımı
  Widget tanitEkrani(Kelime k) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: kVurguZemin,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'YENİ KELİME',
              style: TextStyle(
                color: kTuruncu,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: kKart,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 64,
                  height: 72,
                  child: CustomPaint(painter: KayisiCizim(renk: kTuruncu)),
                ),
                const SizedBox(height: 18),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    k.ing,
                    style: const TextStyle(fontSize: 50, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 18),
                dinleButonu(k),
                const SizedBox(height: 26),
                const Divider(color: kCizgi, thickness: 1),
                const SizedBox(height: 18),
                Text(
                  secilen == null
                      ? 'Sence anlamı ne?'
                      : (secilen == k.anlam ? 'Doğru tahmin!' : 'Bu sefer olmadı, aklında tut:'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: secilen == null
                        ? kSoluk
                        : (secilen == k.anlam ? kYesil : kKirmizi),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: tahminButonu(ikiSik[0], k)),
                    const SizedBox(width: 12),
                    Expanded(child: tahminButonu(ikiSik[1], k)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        genisButon('Devam', secilen == null ? null : ileri), // seçmeden geçilmez
      ],
    );
  }

  // Tanıtımdaki iki şıktan biri
  Widget tahminButonu(String sik, Kelime k) {
    var cerceve = kCizgi;
    var zemin = Colors.transparent;
    var yazi = kYazi;
    if (secilen != null) {
      if (sik == k.anlam) {
        cerceve = kYesil;
        zemin = const Color(0xFF14231A);
        yazi = kYesil;
      } else if (sik == secilen) {
        cerceve = kKirmizi;
        zemin = const Color(0xFF2A1715);
        yazi = kKirmizi;
      } else {
        yazi = const Color(0xFF5C554F);
      }
    }
    final sekil = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: cerceve, width: 2),
    );
    return Material(
      color: zemin,
      shape: sekil,
      child: InkWell(
        customBorder: sekil,
        onTap: () => tahminEt(sik),
        child: Container(
          height: 64,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              sik,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: yazi,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 2) Çoktan seçmeli
  Widget secmeliEkrani(Kelime k) {
    const harfler = ['A', 'B', 'C', 'D'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Doğru anlamı seç',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kSoluk),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            dinleButonu(k, boyut: 52, dolu: false),
            const SizedBox(width: 14),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  k.ing,
                  style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        for (int i = 0; i < siklar.length; i++) sikButonu(harfler[i], siklar[i], k),
        const Spacer(),
        if (secilen != null) geriBildirim(k),
      ],
    );
  }

  Widget sikButonu(String harf, String sik, Kelime k) {
    var cerceve = kCizgi;
    var zemin = Colors.transparent;
    var yazi = kYazi;
    if (secilen != null) {
      if (sik == k.anlam) {
        cerceve = kYesil;
        zemin = const Color(0xFF14231A);
        yazi = kYesil;
      } else if (sik == secilen) {
        cerceve = kKirmizi;
        zemin = const Color(0xFF2A1715);
        yazi = kKirmizi;
      } else {
        yazi = const Color(0xFF5C554F);
      }
    }
    final sekil = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: cerceve, width: 2),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: zemin,
        shape: sekil,
        child: InkWell(
          customBorder: sekil,
          onTap: () => sikSec(sik),
          child: Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cerceve, width: 2),
                  ),
                  child: Text(
                    harf,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: secilen == null ? kSoluk : yazi,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    sik,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: yazi,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Cevaptan sonra alttaki yeşil/kırmızı panel
  Widget geriBildirim(Kelime k) {
    final dogru = secilen == k.anlam;
    final renk = dogru ? kYesil : kKirmizi;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dogru ? const Color(0xFF14231A) : const Color(0xFF2A1715),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: renk,
                child: Icon(
                  dogru ? Icons.check_rounded : Icons.close_rounded,
                  color: kZemin,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  dogru ? 'Harika!' : 'Doğrusu: ${k.anlam}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                    color: renk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          genisButon('Devam', ileri, renk: renk),
        ],
      ),
    );
  }

  // 3) Eşleştirme
  Widget eslestirEkrani() {
    final hepsiBitti = eslesenler.length == sol.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Çiftleri eşleştir',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'İngilizce kelimeyi Türkçesiyle birleştir',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kSoluk),
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  for (final k in sol)
                    eslesmeButonu(
                      k.ing,
                      secili: seciliSol == k,
                      bitti: eslesenler.contains(k),
                      hata: hataSol == k,
                      onTap: () => solSec(k),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  for (final k in sag)
                    eslesmeButonu(
                      k.anlam,
                      secili: seciliSag == k,
                      bitti: eslesenler.contains(k),
                      hata: hataSag == k,
                      onTap: () => sagSec(k),
                    ),
                ],
              ),
            ),
          ],
        ),
        const Spacer(),
        genisButon('Devam', hepsiBitti ? ileri : null), // hepsi bitmeden pasif
      ],
    );
  }

  Widget eslesmeButonu(
    String metin, {
    required bool secili,
    required bool bitti,
    required bool hata,
    required VoidCallback onTap,
  }) {
    var cerceve = kCizgi;
    var zemin = Colors.transparent;
    var yazi = kYazi;
    if (bitti) {
      cerceve = kKart;
      zemin = kKart;
      yazi = const Color(0xFF5C554F);
    } else if (hata) {
      cerceve = kKirmizi;
      zemin = const Color(0xFF2A1715);
      yazi = kKirmizi;
    } else if (secili) {
      cerceve = kTuruncu;
      zemin = kVurguZemin;
      yazi = kTuruncu;
    }
    final sekil = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: cerceve, width: 2),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: zemin,
        shape: sekil,
        child: InkWell(
          customBorder: sekil,
          onTap: bitti ? null : onTap,
          child: Container(
            height: 62,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                metin,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: yazi,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 4) Ders sonu
  Widget sonucEkrani() {
    final d = widget.ders;
    final puan = puanHesapla();
    final dogru = d.kelimeler.length - yanlislar.length;
    final sure = kronometre.elapsed;
    final sureMetni =
        '${sure.inMinutes}:${(sure.inSeconds % 60).toString().padLeft(2, '0')}';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Ortadaki kayısı büyük, yanlardakiler küçük
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(3, (i) {
                  final boy = i == 1 ? 86.0 : 64.0;
                  final dolu = i < puan;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: dolu ? 1 : 0),
                      duration: Duration(milliseconds: 500 + i * 300),
                      builder: (context, v, _) => SizedBox(
                        width: boy * 0.88,
                        height: boy,
                        child: CustomPaint(
                          painter: KayisiCizim(
                            renk: dolu ? kTuruncu : kCizgi,
                            doluluk: v,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 22),
              const Text(
                'Ders tamam!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                '${d.duzey} · Ders ${d.no} · ${d.baslik}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: kSoluk,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  istatistikKutusu('DOĞRU', '$dogru/${d.kelimeler.length}', kYesil),
                  const SizedBox(width: 12),
                  istatistikKutusu('SÜRE', sureMetni, const Color(0xFF7C9CFF)),
                  const SizedBox(width: 12),
                  istatistikKutusu('KAYISI', '$puan/3', kTuruncu),
                ],
              ),
              const SizedBox(height: 22),
              if (yanlislar.isNotEmpty)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: kKart,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tekrar edilecekler',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final k in yanlislar)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kCizgi,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${k.ing} · ${k.anlam}',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Bu kelimeler pratikte daha sık karşına çıkacak.',
                            style: TextStyle(fontSize: 13, color: Color(0xFF7E766E)),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                const Spacer(),
              const SizedBox(height: 16),
              genisButon('Devam et', () {
                final dogrular = {
                  for (final k in d.kelimeler) k: !yanlislar.contains(k),
                };
                Navigator.pop(context, DersSonucu(dogrular, puan));
              }),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () {
                  setState(() {
                    dersiKur(); // aynı dersi baştan
                  });
                },
                child: const Text(
                  'Dersi tekrarla',
                  style: TextStyle(
                    color: kSoluk,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget istatistikKutusu(String baslik, String deger, Color renk) {
    return Expanded(
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: renk, width: 2),
        ),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: renk,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                baslik,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: kZemin,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                deger,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: renk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
