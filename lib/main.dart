import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http; // YENİ: internete mesaj göndermek için
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

// Paketteki seviyeler, kolaydan zora. Seviye eklenirse sadece burası değişir.
const seviyeler = ['A1', 'A2', 'B1', 'B2'];

// Bir seviyenin ders başlıkları (ders planından)
List<String> dersBasliklari(String duzey) =>
    [for (final d in dersPlani) if (d.$1 == duzey) d.$2];

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

// YENİ: Sadece bildirim iznini ister (tanıtımda, hatırlatma seçilince)
Future<void> bildirimIzniIste() async {
  final android = bildirimler.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.requestNotificationsPermission();
}

// YENİ: Hemen bir deneme bildirimi gösterir
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
// Her seviyenin gökyüzü farklı: A1 gün batımı, A2 öğle, B1 gece, B2 şafak.
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
      'B2' => (
          const [Color(0xFF16323F), Color(0xFF3B7482), Color(0xFFF0BE96)],
          const Color(0xFFFFE6B8),
          const Color(0xFF35524F),
          const Color(0xFF1C2C2A),
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
    'B2': 'Orta üstü',
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
  bool tanitimTekrar = false; // YENİ: tanıtım Profil'den tekrar mı izleniyor (çıkılabilir)
  Map<String, int> gecmis = {}; // her gün kaç kelime bilindi (takvim için)
  int sepet = 0; // YENİ: kayısı sepeti sayısı (0-2); kaçırılan günde seriyi korur
  Set<String> korunanGunler = {}; // YENİ: sepetle korunan günler (seri bozulmaz)
  String? sonSepet; // YENİ: en son sepet kazanılan gün
  List<Ders> dersler = []; // YENİ: paketten oluşturulan dersler
  Map<String, int> dersPuanlari = {}; // YENİ: "A1-3" -> kazanılan kayısı (0-3)
  PageController? dersKaydirici; // YENİ: ana sayfadaki ders kartlarını kaydırır

  // Hasat ekranı
  final TextEditingController aramaKutusu = TextEditingController();
  String arama = '';
  int filtre = -1; // -1 hepsi, 0 ham, 1 yarı, 3 kurutmada, 4 kuru
  // YENİ: Hasat takviminde gösterilen ay (ayın 1'i)
  DateTime takvimAyi = DateTime(DateTime.now().year, DateTime.now().month);

  // Kartlar ekranı
  late Kelime aktif;
  bool onYuz = true;

  // Test ekranı
  // YENİ: Test turu
  static const turUzunlugu = 10;
  String testDurumu = 'secim'; // 'secim' -> 'soru' -> 'sonuc', ya da 'kartlar'
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
    // Paket sürümü: yeni kelimeler eklendikçe artar (1: 582 kelime, 2: ~3000 kelime + B2).
    // Telefondaki sürüm eskiyse eksik kelimeler eklenir, var olanların ilerlemesi korunur.
    const guncelPaket = 2;
    final paketSurumu = await prefs.getInt('paket') ?? 0;
    final paketEklendi = paketSurumu < guncelPaket;
    if (paketEklendi) {
      paketiEkle();
      await prefs.setInt('paket', guncelPaket);
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
        seviyeler.firstWhere(seciliDuzeyler.contains, orElse: () => 'A1');
    kaydiriciyiKur();
    // YENİ: Sepet bilgileri ve en son ne zaman girildiği
    sepet = await prefs.getInt('sepet') ?? 0;
    korunanGunler = Set<String>.from(await prefs.getStringList('korunanGunler') ?? []);
    sonSepet = await prefs.getString('sonSepet');
    final sonGiris = await prefs.getString('sonGiris');
    final yokGun = sonGiris == null
        ? 0
        : DateTime.parse(bugununTarihi()).difference(DateTime.parse(sonGiris)).inDays;
    final kullanilan = sepetleKoru(); // dün gelmediysen sepet devreye girer
    await prefs.setString('sonGiris', bugununTarihi());
    setState(() {
      bugun = gecmis[bugununTarihi()] ?? 0;
      tanitimTamam = tanitimGoruldu;
      aktif = kelimeSec();
      yuklendi = true;
    });
    if (paketEklendi || kullanilan > 0) kelimeleriKaydet();
    // Ekran çizildikten sonra gerekiyorsa "tekrar hoş geldin" ya da sepet mesajı
    if (tanitimGoruldu) {
      WidgetsBinding.instance.addPostFrameCallback((_) => donusMesaji(yokGun, kullanilan));
    }
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
    await prefs.setInt('sepet', sepet);
    await prefs.setStringList('korunanGunler', korunanGunler.toList());
    if (sonSepet != null) await prefs.setString('sonSepet', sonSepet!);
  }

  // ---------------- Dersler ----------------

  // Dersleri paket.dart'taki ders planından kurar. Ders numarası seviye içindeki
  // sırasıdır ve hiç değişmez; böylece kayıtlı kayısılar (ör. "A1-3") doğru derse ait kalır.
  void dersleriOlustur() {
    final harita = {for (final k in kelimeler) k.ing: k};
    final sayac = <String, int>{}; // her seviyede kaçıncı ders
    dersler = [];
    for (final (duzey, baslik, liste) in dersPlani) {
      final no = (sayac[duzey] ?? 0) + 1;
      sayac[duzey] = no;
      // Silinmiş kelimeler atlanır; ders tamamen boşaldıysa gösterilmez
      final dersKelimeleri = [
        for (final ing in liste)
          if (harita[ing] != null) harita[ing]!,
      ];
      if (dersKelimeleri.isEmpty) continue;
      dersler.add(Ders(duzey, no, baslik, dersKelimeleri));
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
            for (final d in seviyeler)
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

  // YENİ: Günlük tekrar: önce kurutma zamanı gelenler, sonra derste/kartta
  // yanlış yapılıp henüz olgunlaşmayanlar. En fazla 10 kelime.
  List<Kelime> tekrarKelimeleri() {
    final zamaniGelen =
        kelimeler.where((k) => k.seviye >= 3 && k.tekrar != null && zamaniGeldi(k));
    final zayif = kelimeler.where((k) => k.seviye < 3 && k.yanlis > 0);
    return [...zamaniGelen, ...zayif].take(10).toList();
  }

  // Tekrar kartı varsa ana sayfada en başta durur, dersler bir sağa kayar
  int get tekrarKaymasi => tekrarKelimeleri().isEmpty ? 0 : 1;

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
      // Tekrar bekleyen kelime varsa önce tekrar kartı görünsün
      initialPage: tekrarKaymasi == 1 ? 0 : siradakiDers(),
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
      // Tekrar oynanırsa en iyi puan kalır (günlük tekrarın puanı tutulmaz)
      if (d.no > 0) {
        dersPuanlari[d.kimlik] = max(dersPuanlari[d.kimlik] ?? 0, sonuc.puan);
      }
      aktif = kelimeSec();
    });
    await kelimeleriKaydet();
    // Kartları sıradaki derse kaydır
    final kaydirici = dersKaydirici;
    if (kaydirici != null && kaydirici.hasClients) {
      kaydirici.animateToPage(
        siradakiDers() + tekrarKaymasi,
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
    // Bugünkü hedef tam şimdi dolduysa 7 günlük sepet kuralına bak
    if (bugun == profil.hedef) sepetKazanmaKontrol();
  }

  // ---------------- Kayısı sepeti ----------------

  // Bir gün "aktif" mi: ya çalışılmış ya da sepetle korunmuş
  bool aktifGun(DateTime gun) {
    final t = tarihMetni(gun);
    return (gecmis[t] ?? 0) > 0 || korunanGunler.contains(t);
  }

  // YENİ: Son 7 günün hepsinde hedef tamamsa 1 sepet (en fazla 2)
  void sepetKazanmaKontrol() {
    if (sepet >= 2) return;
    final simdi = DateTime.now();
    for (int i = 0; i < 7; i++) {
      final gun = tarihMetni(simdi.subtract(Duration(days: i)));
      if ((gecmis[gun] ?? 0) < profil.hedef) return; // bir gün bile eksikse yok
    }
    // Aynı 7 günlük dilim için ikinci kez verilmesin
    final yediGunOnce = tarihMetni(simdi.subtract(const Duration(days: 6)));
    if (sonSepet != null && sonSepet!.compareTo(yediGunOnce) >= 0) return;
    sepet++;
    sonSepet = bugununTarihi();
    // bildi() bir setState içinde çağrılıyor; mesajı ekran çizildikten sonra göster
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('7 gün üst üste hedef! Bir kayısı sepeti kazandın.'),
        ),
      );
    });
  }

  // YENİ: Dünden geriye kaçırılan günleri sepetle kapatır, kaç sepet kullanıldığını döndürür.
  // Sepet yetmiyorsa hiç harcanmaz (seri zaten bozulacak, boşa gitmesin).
  int sepetleKoru() {
    if (sepet == 0) return 0;
    final kacirilan = <String>[];
    var gun = DateTime.now().subtract(const Duration(days: 1)); // dünden başla
    while (!aktifGun(gun) && kacirilan.length <= sepet) {
      kacirilan.add(tarihMetni(gun));
      gun = gun.subtract(const Duration(days: 1));
    }
    // Kaçırılan yoksa, sepet yetmiyorsa ya da öncesinde korunacak bir seri yoksa kullanma
    if (kacirilan.isEmpty || kacirilan.length > sepet || !aktifGun(gun)) return 0;
    korunanGunler.addAll(kacirilan);
    sepet -= kacirilan.length;
    return kacirilan.length;
  }

  // YENİ: Uzun aradan dönene nazik karşılama; sepet kullanıldıysa haber ver
  Future<void> donusMesaji(int yokGun, int kullanilan) async {
    if (!mounted) return;
    if (yokGun >= 3) {
      final dusur = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Tekrar hoş geldin!'),
          content: Text(
            '$yokGun gündür yoktun. Önemli olan geri dönmek, kaldığın yerden devam ediyoruz.'
            '${kullanilan > 0 ? ' Kayısı sepetin serini korudu.' : ''}'
            '${profil.sure > 5 ? '\n\nBiraz yavaşlayıp günde 5 dakikayla başlamak ister misin?' : ''}',
          ),
          actions: profil.sure > 5
              ? [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Böyle kalsın'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('5 dakikaya düşür'),
                  ),
                ]
              : [
                  FilledButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Hadi başlayalım'),
                  ),
                ],
        ),
      );
      if (dusur == true && mounted) {
        setState(() {
          profil.sure = 5;
          profil.hedef = gunlukDersSayisi(5) * 10;
          planiYenile();
        });
        profiliKaydet();
      }
    } else if (kullanilan > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kullanilan == 1
                ? 'Dün gelmedin ama kayısı sepetin serini korudu! Kalan sepet: $sepet'
                : '$kullanilan gün gelmedin ama sepetlerin serini korudu! Kalan sepet: $sepet',
          ),
        ),
      );
    }
  }

  // Bilinmeyen kelime ham hâline döner
  void bilemedi(Kelime k) {
    k.yanlis++;
    k.seviye = 0;
    k.tekrar = null;
  }

  // YENİ: Şimdiye kadarki en uzun seri
  int enUzunSeri() {
    // Çalışılan günler + sepetle korunan günler
    final gunler = {
      ...gecmis.entries.where((e) => e.value > 0).map((e) => e.key),
      ...korunanGunler,
    }.map(DateTime.parse).toList()
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

  // Tanıtım bitince seçimleri uygular, kaydeder; istenirse ilk dersi hemen açar
  Future<void> tanitimBitti(
    Profil yeni,
    Set<String> duzeyler,
    String baslangic,
    bool dersAc,
  ) async {
    setState(() {
      profil = yeni;
      seciliDuzeyler = duzeyler;
      tanitimTamam = true;
      tanitimTekrar = false;
      sekme = 0; // tanıtımdan sonra hep ana sayfaya dön
      aktifDuzey = baslangic;
      aktif = kelimeSec();
      onYuz = true;
      kaydiriciyiKur();
    });
    // Ana sayfa ekrana çizildikten SONRA dersi aç (önce sayfa oluşmalı)
    if (dersAc) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final liste = gorunenDersler;
        if (mounted && liste.isNotEmpty) dersiBaslat(liste[siradakiDers()]);
      });
    }
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
    final hedefDegisti = sonuc.hedef != profil.hedef;
    setState(() {
      profil = sonuc;
      // Hedef = tempo. Değiştiyse plan yeniden hesaplanır, önde/geride kıyası buradan başlar
      if (hedefDegisti) planiYenile();
    });
    final prefs = SharedPreferencesAsync();
    await prefs.setString('profil', jsonEncode(profil.toJson()));
    await bildirimiAyarla(profil.bildirim, profil.saat, profil.dakika);
  }

  // Kaç gündür aralıksız çalışılıyor?
  int seriHesapla() {
    var gun = DateTime.now();
    // Bugün henüz çalışmadıysan seri dünden sayılır, bozulmaz
    if (!aktifGun(gun)) {
      gun = gun.subtract(const Duration(days: 1));
    }
    int seri = 0;
    while (aktifGun(gun)) { // sepetle korunan günler de seriye dahil
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
          aktifDuzey = seviyeler.firstWhere(
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

  // Kelimeyi siler, alttaki mesajdan "Geri al" ile eski yerine döner
  void kelimeSil(Kelime k) {
    if (kelimeler.length <= 1) return;
    final sira = kelimeler.indexOf(k); // geri alınca aynı yere koymak için
    setState(() {
      kelimeler.remove(k);
      aktif = kelimeSec();
      dersleriOlustur(); // silinen kelime dersten de çıksın
    });
    kelimeleriKaydet();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar() // önceki mesaj varsa kapat
      ..showSnackBar(
        SnackBar(
          content: Text("'${k.ing}' silindi"),
          action: SnackBarAction(
            label: 'Geri al',
            onPressed: () {
              setState(() {
                kelimeler.insert(min(sira, kelimeler.length), k);
                dersleriOlustur();
              });
              kelimeleriKaydet();
            },
          ),
        ),
      );
  }

  // ---------------- Ekranlar ----------------

  // ===== YENİ: Ana sayfa =====

  Widget anaSayfaEkrani() {
    final liste = gorunenDersler;
    final tekrar = tekrarKelimeleri();
    final kayma = tekrar.isEmpty ? 0 : 1;
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
              itemCount: liste.length + kayma,
              itemBuilder: (context, i) {
                if (kayma == 1 && i == 0) return tekrarKarti(tekrar);
                return dersKarti(liste[i - kayma]);
              },
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
            const SizedBox(height: 6),
            // YENİ: Kaç kayısı sepetin var
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shopping_basket_outlined,
                  size: 16,
                  color: sepet > 0 ? kTuruncu : const Color(0xFF5C554F),
                ),
                const SizedBox(width: 4),
                Text(
                  '$sepet',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: sepet > 0 ? kTuruncu : const Color(0xFF5C554F),
                  ),
                ),
              ],
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
        final korundu = !calisti && korunanGunler.contains(tarihMetni(gun));
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
                    color: calisti || korundu ? kTuruncu : (bugunMu ? kYazi : kCizgi),
                    width: 2,
                  ),
                ),
                child: calisti
                    ? const Icon(Icons.check_rounded, size: 18, color: kZemin)
                    : (korundu
                        ? const Icon(Icons.shopping_basket_outlined, size: 15, color: kTuruncu)
                        : null),
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

  // YENİ: Günlük tekrar kartı (ders kartıyla aynı boyda, manzarasız)
  Widget tekrarKarti(List<Kelime> tekrar) {
    return LayoutBuilder(
      builder: (context, alan) {
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
                      color: kKart,
                      border: Border.all(color: kTuruncu, width: 3),
                    ),
                    child: Column(
                      children: [
                        SizedBox(height: cap * 0.15),
                        const Icon(Icons.wb_sunny_outlined, color: kTuruncu, size: 46),
                        const SizedBox(height: 10),
                        const Text(
                          'Günlük tekrar',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${tekrar.length} kelime seni bekliyor',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: kSoluk,
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: cap * 0.56,
                          height: 52,
                          child: FilledButton(
                            onPressed: () =>
                                dersiBaslat(Ders('Tekrar', 0, 'Günlük tekrar', tekrar)),
                            style: FilledButton.styleFrom(
                              backgroundColor: kTuruncu,
                              foregroundColor: const Color(0xFF1A0E05),
                              textStyle: const TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            child: const Text('Başla'),
                          ),
                        ),
                        SizedBox(height: cap * 0.11),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: kTuruncu,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'TEKRAR ZAMANI',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
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

  // Kartlar sekmesindeki çevrilebilir kayısı kartı. Boyu ekrana göre esner.
  Widget kayisiKart() {
    final renkler = durumRenkleri(aktif.seviye);
    return GestureDetector(
      onTap: () {
        setState(() {
          onYuz = !onYuz;
        });
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: kKart,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Column(
          children: [
            const SizedBox(height: 18),
            // Kelimenin aşaması: ham, yarı olgun, kurutmada, kuru kayısı
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: kCizgi,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: renkler[1],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    aktif.seviye >= 3 && zamaniGeldi(aktif)
                        ? 'TEKRAR ZAMANI'
                        : durumAdi(aktif.seviye).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: kSoluk,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                // Kayısı, eldeki alana sığacak kadar büyük çizilir.
                // Center olmazsa AspectRatio sıkı ölçüye uymak zorunda kalır, oran bozulur.
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 240 / 270,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: onYuz ? 0 : 1),
                      duration: const Duration(milliseconds: 350),
                      builder: (context, v, _) {
                        return CustomPaint(
                          painter: KayisiCizim(renk: kTuruncu, doluluk: v),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(30, 80, 30, 16),
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  onYuz ? aktif.ing : aktif.anlam,
                                  style: TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.w900,
                                    color: Color.lerp(kTuruncu, const Color(0xFF1A0E05), v),
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
            ),
            TextButton.icon(
              onPressed: () => oku(aktif.ing),
              icon: const Icon(Icons.volume_up_rounded, color: kTuruncu),
              label: const Text(
                'dinle',
                style: TextStyle(color: kTuruncu, fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            const Text(
              'karta dokun ve çevir',
              style: TextStyle(color: Color(0xFF7E766E), fontSize: 14),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // Ders ekranındakiyle aynı tarz geniş buton
  Widget kartButonu(String metin, {required bool dolu, required VoidCallback onTap}) {
    return SizedBox(
      height: 58,
      child: dolu
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: kTuruncu,
                foregroundColor: const Color(0xFF1A0E05),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                textStyle: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              child: Text(metin),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: kYazi,
                side: const BorderSide(color: kCizgi, width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                textStyle: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Text(metin),
            ),
    );
  }

  // Kartlar sekmesi: kart ekranın kalanını doldurur, butonlar hep görünür
  Widget kartEkrani() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        children: [
          Expanded(child: kayisiKart()),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: kartButonu(
                  'Bilmiyorum',
                  dolu: false,
                  onTap: () => kartCevapla(false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: kartButonu(
                  'Biliyorum',
                  dolu: true,
                  onTap: () => kartCevapla(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Test sekmesi: duruma göre mod seçimi, soru ya da sonuç ekranı
  // Pratik sekmesi: liste, kartlar, soru ya da sonuç ekranı
  Widget testEkrani() {
    if (testDurumu == 'kartlar') return kartEkrani();
    if (testDurumu == 'soru') return soruEkrani();
    if (testDurumu == 'sonuc') return sonucEkrani();
    return modSecimEkrani();
  }

  // Pratik listesindeki büyük satır: yuvarlak ikon, kalın başlık, açıklama
  Widget modKarti(IconData ikon, String baslik, String aciklama, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Material(
        color: kKart,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    color: kVurguZemin,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(ikon, color: kTuruncu, size: 34),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        baslik,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        aciklama,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: kSoluk,
                        ),
                      ),
                    ],
                  ),
                ),
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
        modKarti(
          Icons.style_rounded,
          'KARTLAR',
          'Kartı çevir, bildiğini işaretle',
          () => setState(() => testDurumu = 'kartlar'),
        ),
        modKarti(
          Icons.checklist_rounded,
          'ÇOKTAN SEÇMELİ',
          '4 şıktan doğruyu seç',
          () => turBaslat('secmeli'),
        ),
        modKarti(
          Icons.keyboard_rounded,
          'YAZ',
          'Cevabı kendin yaz, en kalıcısı',
          () => turBaslat('yazma'),
        ),
        modKarti(
          Icons.headphones_rounded,
          'DİNLE',
          'Sadece duy, anlamını bul',
          () => turBaslat('dinle'),
        ),
        bolumBasligi('SORU YÖNÜ'),
        kutu(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 8),
              Text(
                'Her tur $turUzunlugu soru, açık seviyelerinden sorulur. '
                'Dinle modunda kelime hep İngilizce okunur.',
                style: const TextStyle(fontSize: 13, color: kSoluk),
              ),
            ],
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
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
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
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
      decoration: BoxDecoration(
        color: kKart,
        borderRadius: BorderRadius.circular(28),
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
                  width: 80,
                  height: 80,
                  child: Icon(Icons.volume_up_rounded, color: Color(0xFF1A0E05), size: 40),
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

  // Doğru/yanlış paneli: ekranın altına sabit, içinde devam butonu
  Widget geriBildirim() {
    final k = soru;
    final renk = sonCevapDogru ? const Color(0xFF4CC37A) : const Color(0xFFE8674A);
    final zemin = sonCevapDogru ? const Color(0xFF14231A) : const Color(0xFF2A1715);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: zemin,
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
                  sonCevapDogru ? Icons.check_rounded : Icons.close_rounded,
                  color: kZemin,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  sonCevapDogru ? 'Harika!' : 'Doğrusu: ${k.ing} = ${k.anlam}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: renk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: sonrakiSoru,
              style: FilledButton.styleFrom(
                backgroundColor: renk,
                foregroundColor: kZemin,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                textStyle: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              child: Text(
                soruNo + 1 >= turSorulari.length ? 'Sonuçları gör' : 'Devam',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Soru ekranı: üstte ilerleme, ortada soru ve şıklar, altta sabit panel
  Widget soruEkrani() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Turdan çık',
                  icon: const Icon(Icons.close_rounded, color: kSoluk, size: 28),
                  onPressed: () => setState(() => testDurumu = 'secim'),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (soruNo + 1) / turSorulari.length,
                      minHeight: 12,
                      backgroundColor: kCizgi,
                      color: kTuruncu,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${soruNo + 1}/${turSorulari.length}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: kSoluk),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Ortadaki kısım: sığmazsa (ör. klavye açıkken) sadece burası kayar
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  children: [
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
                  ],
                ),
              ),
            ),
            // Cevap verilince panel en altta, kaydırmadan görünür
            if (cevaplandi)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 8),
                child: geriBildirim(),
              ),
          ],
        ),
      ),
    );
  }

  // YENİ: Pratik turu sonu: ders sonu ekranıyla aynı dil
  Widget sonucEkrani() {
    final toplam = turSorulari.length;
    final oran = toplam == 0 ? 0.0 : turDogru / toplam;
    // Kayısı sayısı derslerle aynı kural: %90+ = 3, %60+ = 2, gerisi 1
    final puan = oran >= 0.9 ? 3 : (oran >= 0.6 ? 2 : 1);
    final mesaj = switch (puan) {
      3 => 'Harika!',
      2 => 'Güzel gidiyorsun!',
      _ => 'Tekrar etmeye devam!',
    };
    final modAdi = switch (testModu) {
      'yazma' => 'Yaz',
      'dinle' => 'Dinle',
      _ => 'Çoktan seçmeli',
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 36, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ortadaki kayısı büyük, yanlardakiler küçük; sırayla dolar
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
            Text(
              mesaj,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'Pratik · $modAdi',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: kSoluk,
              ),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                ozetKutusu('DOĞRU', '$turDogru/$toplam', const Color(0xFF4CC37A)),
                const SizedBox(width: 10),
                ozetKutusu('YANLIŞ', '${turYanlislar.length}', const Color(0xFFE8674A)),
                const SizedBox(width: 10),
                ozetKutusu('BUGÜN', '$bugun kelime', kTuruncu),
              ],
            ),
            const SizedBox(height: 20),
            // Yanlışlar: sığmazsa sadece bu kutu kayar
            if (turYanlislar.isNotEmpty)
              Expanded(
                // Material: içindeki ListTile'lar için (Container uyarı verir)
                child: Material(
                  color: kKart,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          'Tekrar edilecekler',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                      for (final k in turYanlislar)
                        ListTile(
                          title: Text(
                            k.ing,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(k.anlam, style: const TextStyle(color: kSoluk)),
                          trailing: IconButton(
                            tooltip: 'Dinle',
                            icon: const Icon(Icons.volume_up_rounded, color: kTuruncu),
                            onPressed: () => oku(k.ing),
                          ),
                        ),
                    ],
                  ),
                ),
              )
            else
              const Spacer(),
            const SizedBox(height: 16),
            SizedBox(
              height: 58,
              child: FilledButton(
                onPressed: () => turBaslat(testModu),
                style: FilledButton.styleFrom(
                  backgroundColor: kTuruncu,
                  foregroundColor: const Color(0xFF1A0E05),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  textStyle: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                child: const Text('Yeni tur'),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => setState(() => testDurumu = 'secim'),
              child: const Text(
                'Pratik listesine dön',
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
    );
  }

  // YENİ: Bir seviyenin kartı: ad, ilerleme çubuğu, aç/kapa düğmesi
  Widget paketKarti(String duzey, String ad, [VoidCallback? yenile]) {
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
                onChanged: toplam == 0
                    ? null
                    : (acik) {
                        duzeyDegistir(duzey, acik);
                        yenile?.call(); // ayrı sayfadaysak onu da yenile
                      },
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

  // ===== YENİ: Profil sekmesi: düz liste, satırlar ince çizgiyle ayrılır =====

  Widget profilEkrani() {
    final ogrenilen = kelimeler.where((k) => k.seviye >= 3).length;
    final saat =
        '${profil.saat.toString().padLeft(2, '0')}:${profil.dakika.toString().padLeft(2, '0')}';
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        // Üstte büyük avatar ve ad: dokununca Hesabım açılır
        InkWell(
          onTap: hesabiAc,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: kVurguZemin,
                  child: Text(profil.avatar, style: const TextStyle(fontSize: 34)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profil.ad.isEmpty ? 'Adını ekle' : profil.ad,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$ogrenilen kelime öğrendi · ${seriHesapla()} gün seri',
                        style: const TextStyle(color: kSoluk, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF7E766E)),
              ],
            ),
          ),
        ),

        satirGrubu([
          duzSatir(
            ikon: Icons.route_outlined,
            ad: 'Programım',
            deger: '${hedeftenDers(profil.hedef)} ders / gün',
            onTap: programiAc,
          ),
          duzSatir(
            ikon: Icons.school_outlined,
            ad: 'Seviyeler',
            deger: seviyeOzeti(),
            onTap: seviyeleriAc,
          ),
          duzSatir(
            ikon: Icons.flag_outlined,
            ad: 'Günlük hedef',
            deger: '${profil.hedef} kelime',
            onTap: hesabiAc,
          ),
          duzSatir(
            ikon: Icons.notifications_none_rounded,
            ad: 'Bildirimler',
            deger: profil.bildirim ? saat : 'Kapalı',
            onTap: hesabiAc,
          ),
        ]),
        const SizedBox(height: 18),
        satirGrubu([
          duzSatir(
            ikon: Icons.chat_bubble_outline_rounded,
            ad: 'Öneri ve sorun bildir',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => GeriBildirimSayfasi(ad: profil.ad)),
            ),
          ),
          duzSatir(
            ikon: Icons.replay_rounded,
            ad: 'Tanıtımı tekrar izle',
            // İlerleme silinmez; sadece seviye, süre ve hatırlatma yeniden seçilir
            onTap: () => setState(() {
              tanitimTamam = false;
              tanitimTekrar = true;
            }),
          ),
          duzSatir(
            ikon: Icons.info_outline_rounded,
            ad: 'Uygulama hakkında',
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'ApriEnglish',
              applicationVersion: '1.0',
              applicationLegalese: "Malatya'dan sevgilerle",
            ),
          ),
        ]),
        const SizedBox(height: 18),
        satirGrubu([
          duzSatir(
            ikon: Icons.restart_alt_rounded,
            ad: 'İlerlemeyi sıfırla',
            renk: const Color(0xFF7E766E), // soluk: kolay basılmasın diye göze batmaz
            okGoster: false,
            onTap: sifirlaSor,
          ),
        ]),
      ],
    );
  }

  // Açık seviyeler kısa yazılır: "A1 · A2 · ★"
  String seviyeOzeti() {
    final sira = [...seviyeler, 'Benim'];
    return sira
        .where(seciliDuzeyler.contains)
        .map((d) => d == 'Benim' ? '★' : d)
        .join(' · ');
  }

  // Satırları kenardan kenara bir blokta toplar, aralarına ince çizgi koyar
  Widget satirGrubu(List<Widget> satirlar) {
    // Container değil Material: içindeki ListTile'ların dokunma efekti görünsün
    return Material(
      color: kKart,
      child: Column(
        children: [
          for (int i = 0; i < satirlar.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, indent: 64, color: kCizgi),
            satirlar[i],
          ],
        ],
      ),
    );
  }

  // Düz liste satırı: ikon, ad, sağda değer ve ok
  Widget duzSatir({
    required IconData ikon,
    required String ad,
    String? deger,
    Color renk = kYazi,
    bool okGoster = true,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      minTileHeight: 64,
      contentPadding: const EdgeInsets.only(left: 20, right: 12),
      leading: Icon(ikon, color: renk == kYazi ? kSoluk : renk, size: 26),
      title: Text(
        ad,
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: renk),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (deger != null)
            Text(
              deger,
              style: const TextStyle(fontWeight: FontWeight.w700, color: kTuruncu),
            ),
          if (okGoster) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF7E766E)),
          ],
        ],
      ),
    );
  }

  // Tempo değişince yeni planın bitişini "ilk plan" olarak kaydeder
  void planiYenile() {
    final yeni = planHesapla(kalanDersler(), hedeftenDers(profil.hedef));
    if (yeni.isNotEmpty) profil.planBitis = tarihMetni(yeni.last.bitis);
    if (profil.programBaslangic.isEmpty) profil.programBaslangic = bugununTarihi();
  }

  // Aktif seviyeden itibaren, henüz bitmemiş (kayısısı 0) dersleri sayar
  Map<String, int> kalanDersler() => {
        for (final d in seviyeler)
          if (seviyeler.indexOf(d) >= seviyeler.indexOf(aktifDuzey))
            d: dersler
                .where((x) => x.duzey == d && (dersPuanlari[x.kimlik] ?? 0) == 0)
                .length,
      };

  // YENİ: Programım sayfası: güncel ilerlemeye göre yol haritası, süre değiştirilebilir
  void programiAc() {
    // Tanıtımı eski sürümde geçenlerin programı yok: bugünü başlangıç kabul et
    if (profil.programBaslangic.isEmpty) {
      final plan = planHesapla(kalanDersler(), hedeftenDers(profil.hedef));
      profil.programBaslangic = bugununTarihi();
      if (plan.isNotEmpty) profil.planBitis = tarihMetni(plan.last.bitis);
      profiliKaydet();
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (context, yenile) {
            final plan = planHesapla(kalanDersler(), hedeftenDers(profil.hedef));
            final liste = gorunenDersler;
            final siradaki = liste.isEmpty ? null : liste[siradakiDers()];
            final saat = '${profil.saat.toString().padLeft(2, '0')}:'
                '${profil.dakika.toString().padLeft(2, '0')}';
            return Scaffold(
              appBar: AppBar(title: const Text('Programım')),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  const Text(
                    'GÜNDE NE KADAR VAKİT?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      color: Color(0xFF7E766E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final dk in [5, 10, 15, 30])
                        ChoiceChip(
                          label: Text('$dk dk'),
                          // Seçili: hedef bu sürenin ders sayısına denk geliyorsa
                          selected: profil.hedef == gunlukDersSayisi(dk) * 10,
                          onSelected: (_) {
                            // Süre değişince günlük hedef de programa göre değişir
                            setState(() {
                              profil.sure = dk;
                              profil.hedef = gunlukDersSayisi(dk) * 10;
                              planiYenile(); // tempo değişti: kıyas buradan başlar
                            });
                            yenile(() {});
                            profiliKaydet();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ProgramGorunumu(
                    dakika: profil.sure,
                    hedef: profil.hedef,
                    plan: plan,
                    programBaslangic: profil.programBaslangic.isEmpty
                        ? null
                        : DateTime.parse(profil.programBaslangic),
                    ilkBitis:
                        profil.planBitis.isEmpty ? null : DateTime.parse(profil.planBitis),
                    baslangic: siradaki == null
                        ? 'Bütün dersler bitti!'
                        : 'Sıradaki: ${siradaki.duzey} · Ders ${siradaki.no} · ${siradaki.baslik}',
                    hatirlatma:
                        profil.bildirim ? '${zamanAdi(profil.zaman)} $saat' : null,
                    amac: profil.amac,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  // Profili telefona kaydeder
  Future<void> profiliKaydet() async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString('profil', jsonEncode(profil.toJson()));
  }

  // YENİ: Seviyeler ayrı sayfada. Sayfa ana durumun (State) dışında olduğu için
  // StatefulBuilder kullanıyoruz: "yenile" çağrılınca sadece bu sayfa yeniden çizilir.
  void seviyeleriAc() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (context, yenile) => Scaffold(
            appBar: AppBar(title: const Text('Seviyeler')),
            body: ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 28),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Pratik ve testler açık seviyelerden sorulur. '
                    'Ana sayfadaki dersler için sol üstteki rozete dokun.',
                    style: TextStyle(color: kSoluk, fontSize: 14),
                  ),
                ),
                for (final d in duzeyBilgisi.entries)
                  paketKarti(d.key, d.value, () => yenile(() {})),
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
                        onSubmitted: (_) {
                          kelimeEkle();
                          yenile(() {}); // Benim kelimelerim sayısı güncellensin
                        },
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            kelimeEkle();
                            yenile(() {});
                          },
                          child: const Text('Kaydet'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {}); // dönünce Profil'deki özet güncellensin
    });
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
      sepet = 0;
      korunanGunler.clear();
      sonSepet = null;
      aktif = kelimeSec();
      onYuz = true;
      kaydiriciyiKur();
    });
    final prefs = SharedPreferencesAsync();
    // Çok eski sürümden kalan bugün sayacı geri gelmesin
    await prefs.remove('tarih');
    await prefs.remove('bugun');
    await prefs.remove('sonSepet');
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

  // YENİ: Üstte üç kutu: seri, en uzun seri, bugün
  Widget seriKutusu() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          ozetKutusu('SERİ', '${seriHesapla()} gün', kTuruncu),
          const SizedBox(width: 10),
          ozetKutusu('EN UZUN', '${enUzunSeri()} gün', const Color(0xFF7C9CFF)),
          const SizedBox(width: 10),
          ozetKutusu('BUGÜN', '$bugun kelime', const Color(0xFF4CC37A)),
        ],
      ),
    );
  }

  // YENİ: Kayısı sepeti açıklaması ve sayısı
  Widget sepetKutusu() {
    return kutu(
      child: Row(
        children: [
          // İki sepet yeri: dolu olanlar turuncu
          for (int i = 0; i < 2; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                Icons.shopping_basket_rounded,
                size: 30,
                color: i < sepet ? kTuruncu : kCizgi,
              ),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kayısı sepeti: $sepet / 2',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 2),
                const Text(
                  '7 gün üst üste hedefini tamamla, 1 sepet kazan. '
                  'Bir günü kaçırırsan sepet serini korur.',
                  style: TextStyle(fontSize: 13, color: kSoluk, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Renkli başlıklı küçük kutu (ders sonu ekranındakiyle aynı tarz)
  Widget ozetKutusu(String baslik, String deger, Color renk) {
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
              padding: const EdgeInsets.symmetric(vertical: 5),
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
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  deger,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: renk,
                  ),
                ),
              ),
            ),
          ],
        ),
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

  // YENİ: Aylık takvim: telefondaki takvim gibi; çalışılan günler turuncu daire
  Widget takvim() {
    final bugunTarih = sadeceGun(DateTime.now());
    final ay = takvimAyi;
    final gunSayisi = DateTime(ay.year, ay.month + 1, 0).day; // sonraki ayın 0. günü = bu ayın son günü
    final bosluk = ay.weekday - 1; // ayın 1'i hangi güne denk geliyor (Pzt = 0 boşluk)
    final buAyMi = ay.year == bugunTarih.year && ay.month == bugunTarih.month;

    // En eski kayıtlı aya kadar geri gidilebilir
    final ilkKayit = gecmis.keys.isEmpty
        ? bugunTarih
        : DateTime.parse((gecmis.keys.toList()..sort()).first);
    final geriGidebilir = ay.isAfter(DateTime(ilkKayit.year, ilkKayit.month));

    // Bu ayın özeti
    var calisilanGun = 0;
    var toplamKelime = 0;
    for (int g = 1; g <= gunSayisi; g++) {
      final sayi = gecmis[tarihMetni(DateTime(ay.year, ay.month, g))] ?? 0;
      if (sayi > 0) calisilanGun++;
      toplamKelime += sayi;
    }

    // Takvim hücreleri: önce boşluklar, sonra günler; 7'şerli satırlara bölünür
    final hucreler = <Widget>[
      for (int i = 0; i < bosluk; i++) const SizedBox(),
      for (int g = 1; g <= gunSayisi; g++) gunHucresi(DateTime(ay.year, ay.month, g), bugunTarih),
    ];
    while (hucreler.length % 7 != 0) {
      hucreler.add(const SizedBox());
    }

    return kutu(
      child: Column(
        children: [
          // Ay başlığı ve oklar
          Row(
            children: [
              IconButton(
                tooltip: 'Önceki ay',
                onPressed: geriGidebilir
                    ? () => setState(() => takvimAyi = DateTime(ay.year, ay.month - 1))
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  '${aylar[ay.month - 1]} ${ay.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Sonraki ay',
                onPressed: buAyMi
                    ? null // geleceğe gidilmez
                    : () => setState(() => takvimAyi = DateTime(ay.year, ay.month + 1)),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          Text(
            calisilanGun == 0
                ? 'Bu ay henüz çalışılmadı'
                : '$calisilanGun gün çalıştın · $toplamKelime kelime',
            style: const TextStyle(color: kSoluk, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          // Gün başlıkları
          Row(
            children: [
              for (final h in ['P', 'S', 'Ç', 'P', 'C', 'C', 'P'])
                Expanded(
                  child: Center(
                    child: Text(
                      h,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF7E766E),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (int satir = 0; satir < hucreler.length ~/ 7; satir++)
            Row(
              children: [
                for (int i = 0; i < 7; i++)
                  Expanded(child: hucreler[satir * 7 + i]),
              ],
            ),
          const SizedBox(height: 10),
          // Renklerin anlamı
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('az ', style: TextStyle(color: kSoluk, fontSize: 12)),
              for (final s in [1, 5, 10])
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: takvimRengi(s),
                    shape: BoxShape.circle,
                  ),
                ),
              const Text(' çok', style: TextStyle(color: kSoluk, fontSize: 12)),
              const SizedBox(width: 16),
              const Icon(Icons.shopping_basket_outlined, size: 14, color: kTuruncu),
              const Text(' sepetle korundu', style: TextStyle(color: kSoluk, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  // Takvimde bir gün: numara; çalışıldıysa renkli daire, bugünse çerçeve
  Widget gunHucresi(DateTime gun, DateTime bugunTarih) {
    final sayi = gecmis[tarihMetni(gun)] ?? 0;
    final korundu = sayi == 0 && korunanGunler.contains(tarihMetni(gun));
    final gelecek = gun.isAfter(bugunTarih);
    final bugunMu = gun == bugunTarih;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: AspectRatio(
        aspectRatio: 1, // kare hücre, içinde daire
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: sayi > 0 ? takvimRengi(sayi) : Colors.transparent,
            border: bugunMu
                ? Border.all(color: kYazi, width: 2)
                : (korundu ? Border.all(color: kTuruncu, width: 1.5) : null),
          ),
          child: Center(
            child: korundu
                ? const Icon(Icons.shopping_basket_outlined, size: 16, color: kTuruncu)
                : Text(
                    '${gun.day}',
                    style: TextStyle(
                      fontWeight: sayi > 0 || bugunMu ? FontWeight.w900 : FontWeight.w600,
                      fontSize: 14,
                      color: gelecek
                          ? const Color(0xFF4A4440) // gelecek günler soluk
                          : (sayi >= 10 ? const Color(0xFF1A0E05) : kYazi),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // YENİ: Olgunlaşma özeti: dört aşama tek bir renkli çubukta
  Widget kurutmaKutusu() {
    int say(int grup) =>
        kelimeler.where((k) => durumGrubu(k.seviye) == grup).length;
    final zamaniGelen =
        kelimeler.where((k) => k.seviye >= 3 && k.tekrar != null && zamaniGeldi(k)).length;
    // (aşama, sayı, ad) üçlüleri: record kullanıyoruz
    final asamalar = [
      (0, say(0), 'ham'),
      (1, say(1), 'yarı olgun'),
      (3, say(3), 'kurutmada'),
      (4, say(4), 'kuru'),
    ];

    return kutu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.wb_sunny_outlined, color: kTuruncu, size: 20),
              SizedBox(width: 8),
              Text(
                'Olgunlaşma',
                style: TextStyle(fontWeight: FontWeight.w800, color: kSoluk),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Çubuk: her renk, o aşamadaki kelime sayısı kadar yer kaplar (flex)
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (final (seviye, sayi, _) in asamalar)
                    if (sayi > 0)
                      Expanded(
                        flex: sayi,
                        child: Container(color: durumRenkleri(seviye)[1]),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final (seviye, sayi, ad) in asamalar)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: durumRenkleri(seviye)[1],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$sayi',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      Text(ad, style: const TextStyle(fontSize: 12, color: kSoluk)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '3 kez bildiğin kelime kurutmaya alınır. 3 gün sonra yine bilirsen '
            'kuru kayısı olur: artık kalıcı!',
            style: TextStyle(fontSize: 13, color: Color(0xFF7E766E)),
          ),
          if (zamaniGelen > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Bugün tekrar zamanı gelen: $zamaniGelen kelime',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
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
        sepetKutusu(),
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
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 2),
          child: Text(
            'Silmek için kelimeyi sola kaydır',
            style: TextStyle(fontSize: 12, color: Color(0xFF7E766E)),
          ),
        ),
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
          // YENİ: Dismissible = kaydırınca kaybolan satır
          Dismissible(
            key: ValueKey(k), // her satırı kendi kelimesiyle tanır
            direction: DismissDirection.endToStart, // sadece sola
            confirmDismiss: (_) async => kelimeler.length > 1, // son kelime silinmez
            onDismissed: (_) => kelimeSil(k),
            background: Container(
              color: const Color(0xFFC94A3A),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
            ),
            child: ListTile(
              leading: kucukKayisi(k.seviye, 26),
              title: Text(
                k.ing,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                kelimeAciklamasi(k),
                style: const TextStyle(color: kSoluk),
              ),
              trailing: IconButton(
                tooltip: 'Dinle',
                icon: const Icon(Icons.volume_up_rounded, color: kTuruncu),
                onPressed: () => oku(k.ing),
              ),
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
      return TanitimSayfasi(
        profil: profil.kopya(),
        onBitti: tanitimBitti,
        // Tekrar izleniyorsa ✕ ile hiçbir şey değiştirmeden Profil'e dön
        onKapat: tanitimTekrar
            ? () => setState(() {
                  tanitimTamam = true;
                  tanitimTekrar = false;
                })
            : null,
      );
    }
    // Sekmeler: 0 ana sayfa, 1 pratik, 2 hasat, 3 profil
    final ekranlar = [
      anaSayfaEkrani(),
      testEkrani(),
      hasatEkrani(),
      profilEkrani(),
    ];
    // Pratik'te kartlar açıksa başlıkta "Kartlar" yazsın ve geri oku çıksın
    final kartlarAcik = sekme == 1 && testDurumu == 'kartlar';
    // Soru çözerken ve sonuçta başlık ile alt menü gizlenir, ekran tamamen ona kalır
    final odak = sekme == 1 && (testDurumu == 'soru' || testDurumu == 'sonuc');
    final baslik = kartlarAcik ? 'Kartlar' : ['', 'Pratik', 'Hasat', 'Profil'][sekme];
    final sayfa = Scaffold(
      // Ana sayfanın kendi üst şeridi var; başlık çubuğu sadece diğer sekmelerde
      appBar: sekme == 0 || odak
          ? null
          : AppBar(
              title: Text(baslik),
              leading: kartlarAcik
                  ? IconButton(
                      tooltip: 'Pratik listesine dön',
                      onPressed: () => setState(() => testDurumu = 'secim'),
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  : null,
            ),
      body: ekranlar[sekme],
      // YENİ: Sadece ikonlu alt menü (yazılar gizli, basılı tutunca görünür)
      bottomNavigationBar: odak
          ? null
          : NavigationBar(
            selectedIndex: sekme,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            height: 68,
            onDestinationSelected: (i) {
              setState(() {
                // Kartlardayken Pratik ikonuna tekrar basınca listeye dön
                if (i == 1 && sekme == 1) testDurumu = 'secim';
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
                icon: Icon(Icons.bolt_outlined, color: kSoluk),
                selectedIcon: Icon(Icons.bolt_rounded, color: kTuruncu),
                label: 'Pratik',
                tooltip: 'Pratik',
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
    // Telefonun geri tuşu: kartlar ya da soru açıksa uygulamadan çıkma, listeye dön
    return PopScope(
      canPop: !kartlarAcik && !odak,
      onPopInvokedWithResult: (cikildi, _) {
        if (!cikildi) setState(() => testDurumu = 'secim');
      },
      child: sayfa,
    );
  }
}


// ======================= Hesabım =======================

// Kullanıcının bilgileri ve ayarları
class Profil {
  String ad;
  String avatar;
  int hedef; // günlük kelime hedefi
  bool bildirim; // günlük hatırlatma açık mı
  int saat;
  int dakika;
  String amac; // YENİ: neden öğreniyor (okul, is, seyahat, dizi, kendim)
  int sure; // YENİ: günde kaç dakika ayırabilir (5, 10, 15, 30)
  String zaman; // YENİ: ne zaman çalışmayı sever (sabah, ogle, aksam, gece)
  String programBaslangic; // YENİ: programa başlanan gün (yyyy-aa-gg), boşsa henüz yok
  String planBitis; // YENİ: plan yapıldığı gün hesaplanan bitiş; önde/geride kıyası için

  Profil({
    this.ad = '',
    this.avatar = '🧑',
    this.hedef = 10,
    this.bildirim = false,
    this.saat = 20,
    this.dakika = 0,
    this.amac = '',
    this.sure = 10,
    this.zaman = 'aksam',
    this.programBaslangic = '',
    this.planBitis = '',
  });

  // Hesabım sayfası bir kopya üzerinde çalışır; Kaydet'e basılmazsa asıl profil değişmez
  Profil kopya() => Profil(
        ad: ad,
        avatar: avatar,
        hedef: hedef,
        bildirim: bildirim,
        saat: saat,
        dakika: dakika,
        amac: amac,
        sure: sure,
        zaman: zaman,
        programBaslangic: programBaslangic,
        planBitis: planBitis,
      );

  Map<String, dynamic> toJson() => {
        'ad': ad,
        'avatar': avatar,
        'hedef': hedef,
        'bildirim': bildirim,
        'saat': saat,
        'dakika': dakika,
        'amac': amac,
        'sure': sure,
        'zaman': zaman,
        'programBaslangic': programBaslangic,
        'planBitis': planBitis,
      };

  // Eski kayıtlarda yeni alanlar yok: ?? ile varsayılan değer veriyoruz (migration)
  factory Profil.fromJson(Map<String, dynamic> j) => Profil(
        ad: j['ad'] ?? '',
        avatar: j['avatar'] ?? '🧑',
        hedef: j['hedef'] ?? 10,
        bildirim: j['bildirim'] ?? false,
        saat: j['saat'] ?? 20,
        dakika: j['dakika'] ?? 0,
        amac: j['amac'] ?? '',
        sure: j['sure'] ?? 10,
        zaman: j['zaman'] ?? 'aksam',
        programBaslangic: j['programBaslangic'] ?? '',
        planBitis: j['planBitis'] ?? '',
      );
}


// ======================= Program =======================
// YENİ: Kişiye özel programın hesapları. Hepsi basit kurallar ve bölme işlemi.

// Bir ders yaklaşık 4-5 dakika sürüyor; tekrar için de pay bırakıyoruz
int gunlukDersSayisi(int dakika) => switch (dakika) {
      <= 5 => 1,
      <= 10 => 2,
      <= 15 => 3,
      _ => 5,
    };

// YENİ: Programın tek kaynağı günlük hedef: 10 kelime = 1 ders (en az 1)
int hedeftenDers(int hedef) => max(1, (hedef / 10).ceil());

// Sevilen zamana göre hatırlatma saati: (saat, dakika)
(int, int) hatirlatmaSaati(String zaman) => switch (zaman) {
      'sabah' => (8, 30),
      'ogle' => (12, 30),
      'gece' => (22, 30),
      _ => (20, 0),
    };

String zamanAdi(String zaman) => switch (zaman) {
      'sabah' => 'Her sabah',
      'ogle' => 'Her öğle',
      'gece' => 'Her gece',
      _ => 'Her akşam',
    };

// Amaca göre programın altındaki cümle
String amacMesaji(String amac) => switch (amac) {
      'okul' => 'Sınavlarda en çok çıkan temel kelimelerle başlıyoruz.',
      'is' => 'İş hayatında işine yarayacak kelimeler B1\'de seni bekliyor.',
      'seyahat' => 'Seyahatte lazım olacaklar A2 · Seyahat dersinde seni bekliyor.',
      'dizi' => 'Dizilerde ve filmlerde en sık duyacağın kelimelerle başlıyoruz.',
      _ => 'Her gün biraz, ama her gün. Gerisi kendiliğinden gelecek.',
    };

const aylar = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];
// "8 Aralık"; yıl bu yıldan farklıysa ya da istenirse "8 Aralık 2027"
String tarihYazisi(DateTime d, {bool yilli = false}) {
  final yil = yilli || d.year != DateTime.now().year ? ' ${d.year}' : '';
  return '${d.day} ${aylar[d.month - 1]}$yil';
}

// Saatleri atıp sadece günü bırakır (gün farkı hesaplarken saat karışmasın)
DateTime sadeceGun(DateTime d) => DateTime(d.year, d.month, d.day);

// Yol haritasının bir adımı. İsimli alanlı record: a.duzey, a.bitis diye okunur.
typedef PlanAdimi = ({
  String duzey,
  int ders,
  int gun,
  DateTime baslangic,
  DateTime bitis,
});

// Yol haritası: her seviye için başlangıç ve bitiş tarihi.
// gün = kalan ders ÷ günlük ders (yukarı yuvarlanır); seviyeler art arda gelir.
List<PlanAdimi> planHesapla(Map<String, int> kalanDers, int gunlukDers) {
  var tarih = sadeceGun(DateTime.now()); // sıradaki seviyenin ilk günü
  final plan = <PlanAdimi>[];
  for (final duzey in seviyeler) {
    final ders = kalanDers[duzey] ?? 0;
    if (ders == 0) continue;
    final gun = (ders / gunlukDers).ceil();
    // Başladığı gün de sayılır, o yüzden bitiş = başlangıç + gün - 1
    final bitis = tarih.add(Duration(days: gun - 1));
    plan.add((duzey: duzey, ders: ders, gun: gun, baslangic: tarih, bitis: bitis));
    tarih = bitis.add(const Duration(days: 1)); // sonraki seviye ertesi gün başlar
  }
  return plan;
}

// YENİ: Programı gösteren parça. Hem tanıtımın sonunda hem de Profil > Programım'da kullanılır.
class ProgramGorunumu extends StatelessWidget {
  final int dakika;
  final int hedef;
  final List<PlanAdimi> plan;
  final DateTime? programBaslangic; // programa başlanan gün (yoksa bugün)
  final DateTime? ilkBitis; // ilk planlanan bitiş; varsa önde/geride gösterilir
  final String baslangic; // "A1 · Ders 1 · Yiyecek ve içecek"
  final String? hatirlatma; // "Her akşam 20:00" ya da null (kapalı)
  final String amac;

  const ProgramGorunumu({
    super.key,
    required this.dakika,
    required this.hedef,
    required this.plan,
    this.programBaslangic,
    this.ilkBitis,
    required this.baslangic,
    required this.hatirlatma,
    required this.amac,
  });

  static const seviyeAdlari = {
    'A1': 'Başlangıç',
    'A2': 'Temel',
    'B1': 'Orta',
    'B2': 'Orta üstü',
  };

  static const baslikStili = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.4,
    color: Color(0xFF7E766E),
  );

  Widget bilgiSatiri(IconData ikon, String baslik, String metin) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, color: kTuruncu, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  baslik,
                  style: const TextStyle(fontSize: 13, color: kSoluk, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  metin,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Başlangıç / bitiş kutusu
  Widget tarihKutusu(String baslik, DateTime tarih, IconData ikon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kKart,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ikon, size: 16, color: kSoluk),
                const SizedBox(width: 6),
                Text(baslik, style: baslikStili.copyWith(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              tarihYazisi(tarih, yilli: true),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  // İlk plana göre önde mi geride mi? (gün farkı: eksi = önde, artı = geride)
  Widget durumSatiri(int fark) {
    final (Color renk, IconData ikon, String metin) = fark < 0
        ? (const Color(0xFF4CC37A), Icons.trending_up_rounded, 'Planından ${-fark} gün öndesin!')
        : fark > 0
            ? (const Color(0xFFE8674A), Icons.schedule_rounded,
                'Planından $fark gün geridesin. Sorun değil, devam!')
            : (kTuruncu, Icons.check_circle_outline_rounded, 'Tam planındasın!');
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: renk.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(ikon, color: renk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              metin,
              style: TextStyle(color: renk, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dersSayisi = hedeftenDers(hedef);
    // Seçilen süre bu ders sayısına uyuyorsa onu göster, uymuyorsa ders başı ~5 dk say
    final sure = gunlukDersSayisi(dakika) == dersSayisi ? dakika : dersSayisi * 5;
    final bugun = sadeceGun(DateTime.now());
    final bas = programBaslangic ?? bugun;
    final bit = plan.isEmpty ? null : plan.last.bitis;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Günlük plan kartı
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: kVurguZemin,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: kTuruncu, width: 2),
          ),
          child: Row(
            children: [
              Column(
                children: [
                  Text(
                    '$sure',
                    style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w900,
                      color: kTuruncu,
                      height: 1,
                    ),
                  ),
                  const Text(
                    'dk / gün',
                    style: TextStyle(fontWeight: FontWeight.w800, color: kTuruncu),
                  ),
                ],
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$dersSayisi ders + günlük tekrar',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Günlük hedefin $hedef kelime',
                      style: const TextStyle(color: kSoluk, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // YENİ: Başlangıç ve hedef bitiş, yıllarıyla
        if (bit != null)
          Row(
            children: [
              tarihKutusu('BAŞLANGIÇ', bas, Icons.play_arrow_rounded),
              const SizedBox(width: 10),
              tarihKutusu('HEDEF BİTİŞ', bit, Icons.flag_rounded),
            ],
          ),
        if (bit != null && ilkBitis != null)
          durumSatiri(sadeceGun(bit).difference(sadeceGun(ilkBitis!)).inDays),
        const SizedBox(height: 22),
        const Text('YOL HARİTAN', style: baslikStili),
        const SizedBox(height: 10),
        if (plan.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 18),
            child: Text(
              'Bütün dersleri bitirdin, tebrikler!',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        // Zaman çizelgesi: solda nokta ve çizgi, ortada tarih aralığı, sağda gün sayısı
        for (int i = 0; i < plan.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 28,
                  child: Column(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == 0 ? kTuruncu : Colors.transparent,
                          border: Border.all(color: kTuruncu, width: 2.5),
                        ),
                      ),
                      if (i < plan.length - 1)
                        Expanded(child: Container(width: 2.5, color: kCizgi)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${plan[i].duzey} · ${seviyeAdlari[plan[i].duzey]}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${tarihYazisi(plan[i].baslangic)} → ${tarihYazisi(plan[i].bitis)}',
                          style: const TextStyle(
                            color: kTuruncu,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${plan[i].ders} ders',
                          style: const TextStyle(color: kSoluk, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  '${plan[i].gun} gün',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: kSoluk,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
          decoration: BoxDecoration(
            color: kKart,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              bilgiSatiri(Icons.flag_outlined, 'Başlangıç noktan', baslangic),
              bilgiSatiri(
                Icons.notifications_none_rounded,
                'Hatırlatma',
                hatirlatma ?? 'Kapalı · Profil\'den açabilirsin',
              ),
              bilgiSatiri(Icons.lightbulb_outline_rounded, 'Senin için', amacMesaji(amac)),
            ],
          ),
        ),
      ],
    );
  }
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

  @override
  void initState() {
    super.initState();
    p = widget.profil;
    adKutusu = TextEditingController(text: p.ad);
  }

  @override
  void dispose() {
    adKutusu.dispose();
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

  // YENİ: Hedef artık yazılmıyor, − / + ile değişiyor; 5'er 5'er, 5 ile 100 arası
  void hedefDegistir(int fark) {
    setState(() {
      p.hedef = (p.hedef + fark).clamp(5, 100).toInt();
    });
  }

  void kaydet() {
    p.ad = adKutusu.text.trim();
    Navigator.pop(context, p); // profili ana sayfaya geri gönder
  }

  // Gri, küçük, aralıklı harfli bölüm başlığı
  Widget baslik(String metin) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
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

  // Koyu gri kutu. Material: içindeki dokunma efektleri görünsün
  Widget kutu({required Widget child}) {
    return Material(
      color: kKart,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  // − ve + için yuvarlak buton
  Widget artiEksi(IconData ikon, VoidCallback onTap) {
    return Material(
      color: kCizgi,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(ikon, color: kYazi),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hesabım')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // Büyük avatar ve altında ad
          Center(
            child: CircleAvatar(
              radius: 52,
              backgroundColor: kVurguZemin,
              child: Text(p.avatar, style: const TextStyle(fontSize: 56)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: adKutusu,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              hintText: 'Adın',
              filled: true,
              fillColor: kKart,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),

          baslik('AVATAR'),
          kutu(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
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
          ),

          baslik('GÜNLÜK HEDEF'),
          kutu(
            child: Column(
              children: [
                Row(
                  children: [
                    artiEksi(Icons.remove_rounded, () => hedefDegistir(-5)),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '${p.hedef}',
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              color: kTuruncu,
                              height: 1.1,
                            ),
                          ),
                          const Text(
                            'kelime / gün',
                            style: TextStyle(color: kSoluk, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    artiEksi(Icons.add_rounded, () => hedefDegistir(5)),
                  ],
                ),
                const SizedBox(height: 14),
                // Uygulamanın önerisi: son 7 güne göre
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  decoration: BoxDecoration(
                    color: kZemin,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline_rounded, color: kTuruncu, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.oneriAciklama,
                          style: const TextStyle(fontSize: 13, color: kSoluk),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => p.hedef = widget.oneri),
                        child: Text(
                          '${widget.oneri} yap',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          baslik('HATIRLATMA'),
          kutu(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Günlük hatırlatma',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Her gün seçtiğin saatte hatırlatır',
                    style: TextStyle(color: kSoluk),
                  ),
                  value: p.bildirim,
                  onChanged: (acik) => setState(() => p.bildirim = acik),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: p.bildirim,
                  leading: const Icon(Icons.schedule_rounded),
                  title: const Text('Saat', style: TextStyle(fontWeight: FontWeight.w700)),
                  trailing: Text(
                    saatMetni(),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: p.bildirim ? kTuruncu : const Color(0xFF5C554F),
                    ),
                  ),
                  onTap: p.bildirim ? saatSec : null,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: denemeBildirimi,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Deneme bildirimi gönder'),
                  ),
                ),
              ],
            ),
          ),

          baslik('İSTATİSTİKLER'),
          // 3 sütunlu kutucuklar
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            children: [
              for (final e in widget.istatistikler.entries)
                Container(
                  decoration: BoxDecoration(
                    color: kKart,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${e.value}',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: kTuruncu,
                        ),
                      ),
                      Text(
                        e.key,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: kSoluk),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      // Kaydet butonu altta sabit: liste ne kadar uzun olursa olsun görünür
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 58,
            child: FilledButton(
              onPressed: kaydet,
              style: FilledButton.styleFrom(
                backgroundColor: kTuruncu,
                foregroundColor: const Color(0xFF1A0E05),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                textStyle: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              child: const Text('Kaydet'),
            ),
          ),
        ),
      ),
    );
  }
}


// ======================= Tanıtım (ilk açılış) =======================

// Karşılama ve kişiye özel program: her sayfada bir soru, Devam ile ilerlenir.
class TanitimSayfasi extends StatefulWidget {
  final Profil profil;
  // Bitince: profil, açık seviyeler, ana sayfada başlanacak seviye, ilk ders hemen açılsın mı
  final void Function(Profil profil, Set<String> duzeyler, String baslangic, bool dersAc)
      onBitti;
  // YENİ: Tanıtım tekrar izleniyorsa çıkış; ilk açılışta null (çıkış yok, sorular cevaplanmalı)
  final VoidCallback? onKapat;

  const TanitimSayfasi({
    super.key,
    required this.profil,
    required this.onBitti,
    this.onKapat,
  });

  @override
  State<TanitimSayfasi> createState() => _TanitimSayfasiState();
}

class _TanitimSayfasiState extends State<TanitimSayfasi> {
  // Sayfalar: 0 hoş geldin, 1 amaç, 2 seviye, 3 süre, 4 zaman, 5 tanışalım, 6 program
  static const sayfaSayisi = 7;
  static const avatarlar = [
    '👩', '👨', '🧑', '👧', '👦', '🧕', '🧔', '👵', '👴',
    '👩‍🎓', '👨‍🎓', '👩‍💻', '👨‍💻', '👩‍🏫', '👨‍🏫',
  ];

  final PageController sayfaKontrol = PageController();
  int sayfa = 0;
  late Profil p;
  late TextEditingController adKutusu;

  // Cevaplar: null = henüz seçilmedi (Devam butonu pasif kalır)
  String? amac;
  String? seviye; // 'yeni', 'biraz', 'orta'
  int? sure; // dakika
  String? zaman; // 'sabah', 'ogle', 'aksam', 'gece', 'yok'

  @override
  void initState() {
    super.initState();
    p = widget.profil;
    adKutusu = TextEditingController(text: p.ad);
  }

  @override
  void dispose() {
    sayfaKontrol.dispose();
    adKutusu.dispose();
    super.dispose();
  }

  // Seviyeye göre: (açık seviyeler, başlangıç seviyesi)
  (Set<String>, String) seviyeAyari() => switch (seviye) {
        'biraz' => (<String>{'A1', 'A2', 'Benim'}, 'A2'),
        'orta' => (<String>{'A2', 'B1', 'Benim'}, 'B1'),
        'ileri' => (<String>{'B1', 'B2', 'Benim'}, 'B2'),
        _ => (<String>{'A1', 'Benim'}, 'A1'),
      };

  // Bu sayfada Devam'a basılabilir mi?
  bool get devamOlur => switch (sayfa) {
        1 => amac != null,
        2 => seviye != null,
        3 => sure != null,
        4 => zaman != null,
        _ => true,
      };

  Future<void> ileri() async {
    FocusScope.of(context).unfocus(); // klavye açıksa kapat
    // Hatırlatma seçildiyse izni tam şimdi iste: kullanıcı nedenini biliyor
    if (sayfa == 4 && zaman != 'yok') await bildirimIzniIste();
    if (!mounted) return;
    if (sayfa == 5) p.ad = adKutusu.text.trim(); // program sayfasında adıyla seslenelim
    sayfaKontrol.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void geri() {
    FocusScope.of(context).unfocus();
    sayfaKontrol.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void bitir(bool dersAc) {
    p.ad = adKutusu.text.trim();
    p.amac = amac ?? '';
    p.sure = sure ?? 10;
    p.hedef = gunlukDersSayisi(p.sure) * 10; // her ders 10 kelime
    p.zaman = zaman == null || zaman == 'yok' ? 'aksam' : zaman!;
    p.bildirim = zaman != 'yok';
    final (saat, dakika) = hatirlatmaSaati(p.zaman);
    p.saat = saat;
    p.dakika = dakika;
    // Program bugün başlıyor; ilk planlanan bitiş önde/geride kıyası için saklanır
    final hesap = plan();
    p.programBaslangic = bugununTarihi();
    p.planBitis = hesap.isEmpty ? '' : tarihMetni(hesap.last.bitis);
    final (duzeyler, baslangic) = seviyeAyari();
    widget.onBitti(p, duzeyler, baslangic, dersAc);
  }

  // ---------------- Parçalar ----------------

  // Soru sayfalarının iskeleti: büyük başlık, açıklama, seçenekler
  Widget soruSayfasi(String baslik, String? aciklama, List<Widget> icerik) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            baslik,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, height: 1.2),
          ),
          if (aciklama != null) ...[
            const SizedBox(height: 6),
            Text(aciklama, style: const TextStyle(fontSize: 15, color: kSoluk)),
          ],
          const SizedBox(height: 22),
          ...icerik,
        ],
      ),
    );
  }

  // Büyük seçenek satırı: solda ikon/rozet, ortada ad ve detay, seçiliyse turuncu çerçeve
  Widget secenek({
    required Widget sol,
    required String ad,
    String? detay,
    required bool secili,
    required VoidCallback onTap,
  }) {
    final sekil = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: secili ? kTuruncu : Colors.transparent, width: 2),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: secili ? kVurguZemin : kKart,
        shape: sekil,
        child: InkWell(
          customBorder: sekil,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                SizedBox(width: 48, height: 48, child: Center(child: sol)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ad,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      if (detay != null)
                        Text(detay, style: const TextStyle(color: kSoluk, fontSize: 14)),
                    ],
                  ),
                ),
                Icon(
                  secili ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: secili ? kTuruncu : kCizgi,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget ikon(IconData i) => Icon(i, color: kTuruncu, size: 30);

  // Seviye için 4 sinyal çubuğu: dolu çubuk sayısı = seviye
  Widget sinyal(int dolu) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        return Container(
          width: 7,
          height: 8.0 + i * 7,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: i < dolu ? kTuruncu : kCizgi,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  // Süre için yuvarlak sayı rozeti
  Widget sayiRozeti(int n) {
    return Text(
      '$n',
      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: kTuruncu),
    );
  }

  // ---------------- Sayfalar ----------------

  // 0) Hoş geldin
  Widget hosgeldin() {
    return LayoutBuilder(
      builder: (context, alan) {
        final cap = min(alan.maxWidth - 80, alan.maxHeight * 0.55);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: cap,
              height: cap,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: kKart, width: 6),
              ),
              child: ClipOval(child: CustomPaint(painter: ManzaraCizim('A1'))),
            ),
            const SizedBox(height: 30),
            const Text(
              'ApriEnglish',
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 36),
              child: Text(
                'İngilizce kelimeleri her gün biraz biraz öğren, '
                'kayısı gibi olgunlaştır.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: kSoluk, height: 1.4),
              ),
            ),
          ],
        );
      },
    );
  }

  // 1) Amaç
  Widget amacSayfasi() {
    Widget s(String kod, IconData i, String ad) => secenek(
          sol: ikon(i),
          ad: ad,
          secili: amac == kod,
          onTap: () => setState(() => amac = kod),
        );
    return soruSayfasi('Neden İngilizce öğreniyorsun?', 'Programını buna göre hazırlayacağız.', [
      s('okul', Icons.school_outlined, 'Okul ve sınavlar'),
      s('is', Icons.work_outline_rounded, 'İş ve kariyer'),
      s('seyahat', Icons.flight_takeoff_rounded, 'Seyahat'),
      s('dizi', Icons.movie_outlined, 'Film, dizi ve müzik'),
      s('kendim', Icons.self_improvement_rounded, 'Kendimi geliştirmek'),
    ]);
  }

  // 2) Seviye
  Widget seviyeSayfasi() {
    Widget s(String kod, int cubuk, String ad, String detay) => secenek(
          sol: sinyal(cubuk),
          ad: ad,
          detay: detay,
          secili: seviye == kod,
          onTap: () => setState(() => seviye = kod),
        );
    return soruSayfasi('İngilizcen ne durumda?', 'Sana uygun yerden başlayalım.', [
      s('yeni', 1, 'Yeni başlıyorum', 'A1 · en temel kelimeler'),
      s('biraz', 2, 'Biraz biliyorum', 'A2 · günlük hayat'),
      s('orta', 3, 'Orta seviyeyim', 'B1 · iş, eğitim, fikirler'),
      s('ileri', 4, 'İyi anlıyorum', 'B2 · haberler, tartışmalar, iş dünyası'),
    ]);
  }

  // 3) Süre
  Widget sureSayfasi() {
    Widget s(int dk, String ad) {
      final ders = gunlukDersSayisi(dk);
      return secenek(
        sol: sayiRozeti(dk),
        ad: '$dk dakika',
        detay: '$ad · günde $ders ders',
        secili: sure == dk,
        onTap: () => setState(() => sure = dk),
      );
    }

    return soruSayfasi('Günde ne kadar vakit ayırabilirsin?', 'Az ama her gün, çoktan iyidir.', [
      s(5, 'Rahat'),
      s(10, 'Normal'),
      s(15, 'Ciddi'),
      s(30, 'Yoğun'),
    ]);
  }

  // 4) Zaman
  Widget zamanSayfasi() {
    Widget s(String kod, IconData i, String ad) {
      final (saat, dk) = hatirlatmaSaati(kod);
      return secenek(
        sol: ikon(i),
        ad: ad,
        detay: 'Hatırlatma ${saat.toString().padLeft(2, '0')}:${dk.toString().padLeft(2, '0')}',
        secili: zaman == kod,
        onTap: () => setState(() => zaman = kod),
      );
    }

    return soruSayfasi('Ne zaman çalışmayı seversin?', 'O saatte seni nazikçe hatırlatalım.', [
      s('sabah', Icons.wb_twilight_rounded, 'Sabah'),
      s('ogle', Icons.wb_sunny_outlined, 'Öğle'),
      s('aksam', Icons.nightlight_outlined, 'Akşam'),
      s('gece', Icons.bedtime_outlined, 'Gece'),
      secenek(
        sol: const Icon(Icons.notifications_off_outlined, color: kSoluk, size: 28),
        ad: 'Hatırlatma istemiyorum',
        secili: zaman == 'yok',
        onTap: () => setState(() => zaman = 'yok'),
      ),
    ]);
  }

  // 5) Tanışalım
  Widget tanisalim() {
    return soruSayfasi('Seni tanıyalım', 'Bir avatar seç ve adını yaz.', [
      Center(
        child: CircleAvatar(
          radius: 48,
          backgroundColor: kVurguZemin,
          child: Text(p.avatar, style: const TextStyle(fontSize: 52)),
        ),
      ),
      const SizedBox(height: 18),
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
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
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

  // Seçimlere göre plan. Yeni kullanıcı: başlangıç seviyesinden itibaren bütün dersler.
  // Başlangıçtan önceki seviyeler plana girmez (ör. A2'den başlayana A1 gösterilmez).
  List<PlanAdimi> plan() {
    final (_, baslangic) = seviyeAyari();
    final kalan = {
      for (final d in seviyeler)
        if (seviyeler.indexOf(d) >= seviyeler.indexOf(baslangic))
          d: dersBasliklari(d).length,
    };
    return planHesapla(kalan, gunlukDersSayisi(sure ?? 10));
  }

  // 6) Sana özel program
  Widget programSayfasi() {
    final dk = sure ?? 10;
    final (_, baslangic) = seviyeAyari();
    final plan = this.plan();
    final (saat, dakika) = hatirlatmaSaati(zaman ?? 'aksam');
    final basliklar = dersBasliklari(baslangic);
    final ilkBaslik = basliklar.isEmpty ? '' : basliklar.first;
    final ad = adKutusu.text.trim();
    return soruSayfasi(
      ad.isEmpty ? 'Sana özel programın hazır!' : 'Programın hazır, $ad!',
      'Seçimlerine göre hesapladık. İstediğin zaman Profil\'den değiştirebilirsin.',
      [
        ProgramGorunumu(
          dakika: dk,
          hedef: gunlukDersSayisi(dk) * 10,
          plan: plan,
          baslangic: '$baslangic · Ders 1 · $ilkBaslik',
          hatirlatma: zaman == 'yok'
              ? null
              : '${zamanAdi(zaman ?? 'aksam')} ${saat.toString().padLeft(2, '0')}:'
                  '${dakika.toString().padLeft(2, '0')}',
          amac: amac ?? '',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sonSayfa = sayfa == sayfaSayisi - 1;
    // Telefonun geri tuşu: önceki soruya dön; ilk sayfadaysa (tekrar izlerken) çık
    return PopScope(
      // İlk açılışta hoş geldin sayfasındaysa geri tuşu uygulamadan normal çıksın
      canPop: sayfa == 0 && widget.onKapat == null,
      onPopInvokedWithResult: (cikildi, _) {
        if (cikildi) return;
        if (sayfa > 0) {
          geri();
        } else {
          widget.onKapat?.call();
        }
      },
      child: tanitimEkrani(sonSayfa),
    );
  }

  Widget tanitimEkrani(bool sonSayfa) {
    return Scaffold(
      backgroundColor: kZemin,
      body: SafeArea(
        child: Column(
          children: [
            // Üst çubuk: geri oku ve ilerleme. Hoş geldin sayfasında sadece
            // tekrar izlerken çıkış (✕) butonu var.
            SizedBox(
              height: 56,
              child: sayfa == 0
                  ? (widget.onKapat == null
                      ? null
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            tooltip: 'Tanıtımdan çık',
                            onPressed: widget.onKapat,
                            icon: const Icon(Icons.close_rounded, color: kSoluk, size: 28),
                          ),
                        ))
                  : Row(
                      children: [
                        IconButton(
                          tooltip: 'Geri',
                          onPressed: geri,
                          icon: const Icon(Icons.arrow_back_rounded, color: kSoluk),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(end: sayfa / (sayfaSayisi - 1)),
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
                        const SizedBox(width: 20),
                      ],
                    ),
            ),
            Expanded(
              child: PageView(
                controller: sayfaKontrol,
                // Parmakla kaydırılamaz: her soruya cevap verip butonla geçilir
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => sayfa = i),
                children: [
                  hosgeldin(),
                  amacSayfasi(),
                  seviyeSayfasi(),
                  sureSayfasi(),
                  zamanSayfasi(),
                  tanisalim(),
                  programSayfasi(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 58,
                    child: FilledButton(
                      onPressed: !devamOlur
                          ? null
                          : () {
                              if (sonSayfa) {
                                bitir(true);
                              } else {
                                ileri();
                              }
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: kTuruncu,
                        foregroundColor: const Color(0xFF1A0E05),
                        disabledBackgroundColor: kCizgi,
                        disabledForegroundColor: const Color(0xFF7E766E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      child: Text(
                        switch (sayfa) {
                          0 => 'Başlayalım',
                          6 => 'İlk dersime başla',
                          _ => 'Devam',
                        },
                      ),
                    ),
                  ),
                  if (sonSayfa)
                    TextButton(
                      onPressed: () => bitir(false),
                      child: const Text(
                        'Önce uygulamayı gezeyim',
                        style: TextStyle(color: kSoluk, fontWeight: FontWeight.w800),
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
                d.no == 0 ? d.baslik : '${d.duzey} · Ders ${d.no} · ${d.baslik}',
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


// ======================= Geri bildirim =======================

// YENİ: Kullanıcı uygulamanın içinden yazar; mesaj arka planda Google Formuna gider,
// cevaplar Google E-Tablosu'nda toplanır. Sunucu gerekmez.
class GeriBildirimSayfasi extends StatefulWidget {
  final String ad; // profildeki ad, formun "İsim" sorusuna yazılır

  const GeriBildirimSayfasi({super.key, required this.ad});

  @override
  State<GeriBildirimSayfasi> createState() => _GeriBildirimSayfasiState();
}

class _GeriBildirimSayfasiState extends State<GeriBildirimSayfasi> {
  // Formun adresi: linkteki "viewform" yerine "formResponse" = cevap gönderme kapısı
  static const formAdresi =
      'https://docs.google.com/forms/d/e/1FAIpQLScnV-00z6rlYMY45U1GNJtybDt4HsLb0_EnFuxiQ7pIP3ArSA/formResponse';
  // Her sorunun gizli kimliği (önceden doldurulmuş linkten aldık)
  static const konuKimligi = 'entry.185359346';
  static const mesajKimligi = 'entry.379842936';
  static const isimKimligi = 'entry.1645225265';

  final TextEditingController mesajKutusu = TextEditingController();
  String konu = 'Öneri'; // formdaki seçeneklerle birebir aynı yazılmalı
  bool gonderiliyor = false; // gönderirken buton dönen çembere dönüşür

  @override
  void dispose() {
    mesajKutusu.dispose();
    super.dispose();
  }

  Future<void> gonder() async {
    final mesaj = mesajKutusu.text.trim();
    if (mesaj.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Biraz daha yazar mısın? En az 5 harf.')),
      );
      return;
    }
    setState(() => gonderiliyor = true);
    bool basarili = false;
    try {
      // POST: formu doldurup "Gönder"e basmanın kod hâli
      final cevap = await http.post(
        Uri.parse(formAdresi),
        body: {
          konuKimligi: konu,
          mesajKimligi: mesaj,
          isimKimligi: widget.ad,
        },
      ).timeout(const Duration(seconds: 15)); // 15 sn'de cevap yoksa vazgeç
      basarili = cevap.statusCode == 200; // 200 = "tamam, aldım"
    } catch (_) {
      basarili = false; // internet yok ya da zaman aşımı
    }
    if (!mounted) return; // beklerken sayfa kapandıysa dokunma
    setState(() => gonderiliyor = false);
    if (basarili) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teşekkürler! Mesajın bize ulaştı.')),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gönderilemedi. İnternet bağlantını kontrol edip tekrar dene.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Öneri ve sorun bildir')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ApriEnglish\'i birlikte geliştirelim. Aklına gelen her şeyi yaz, '
                'hepsini tek tek okuyoruz.',
                style: TextStyle(fontSize: 15, color: kSoluk, height: 1.4),
              ),
              const SizedBox(height: 20),
              const Text(
                'KONU',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: Color(0xFF7E766E),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final k in ['Öneri', 'Sorun', 'Diğer'])
                    ChoiceChip(
                      label: Text(k),
                      selected: konu == k,
                      onSelected: (_) => setState(() => konu = k),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: TextField(
                  controller: mesajKutusu,
                  maxLines: null, // satır sınırı yok
                  expands: true, // kutu kalan alanı doldursun
                  maxLength: 1000,
                  textAlignVertical: TextAlignVertical.top,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: konu == 'Sorun'
                        ? 'Ne oldu? Hangi ekranda, ne yaparken?'
                        : 'Mesajını yaz...',
                    filled: true,
                    fillColor: kKart,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 58,
                child: FilledButton(
                  onPressed: gonderiliyor ? null : gonder, // gönderirken çift basılmasın
                  style: FilledButton.styleFrom(
                    backgroundColor: kTuruncu,
                    foregroundColor: const Color(0xFF1A0E05),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    textStyle: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  child: gonderiliyor
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 3, color: kTuruncu),
                        )
                      : const Text('Gönder'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
