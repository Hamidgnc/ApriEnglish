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

// Uygulamanın renkleri
const kTuruncu = Color(0xFFF5842C);
const kKoyuTuruncu = Color(0xFFCD5C16);
const kKrem = Color(0xFFFFF6E8);
const kAcikTuruncu = Color(0xFFFFE4C8);
const kKahve = Color(0xFF96643C);

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

class KelimeUygulamasi extends StatelessWidget {
  const KelimeUygulamasi({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ApriEnglish',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: kTuruncu,
          primary: kKoyuTuruncu,
        ),
        scaffoldBackgroundColor: kKrem,
        appBarTheme: const AppBarTheme(
          backgroundColor: kKrem,
          foregroundColor: kKoyuTuruncu,
          titleTextStyle: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: kKoyuTuruncu,
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: kAcikTuruncu,
        ),
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
  final Random rastgele = Random();
  final FlutterTts ses = FlutterTts();
  bool yuklendi = false;
  int sekme = 0;
  int bugun = 0; // bugün bilinen kelime sayısı
  Profil profil = Profil(); // YENİ: ad, avatar, hedef, bildirim ayarları
  Map<String, int> gecmis = {}; // her gün kaç kelime bilindi (takvim için)

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
    setState(() {
      bugun = gecmis[bugununTarihi()] ?? 0;
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
      } else if (seciliDuzeyler.length > 1) {
        seciliDuzeyler.remove(duzey);
      }
      aktif = kelimeSec();
      onYuz = true;
    });
    kelimeleriKaydet();
  }

  void kelimeSil(Kelime k) {
    if (kelimeler.length <= 1) return;
    setState(() {
      kelimeler.remove(k);
      aktif = kelimeSec();
    });
    kelimeleriKaydet();
  }

  // ---------------- Ekranlar ----------------

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
                color: kKoyuTuruncu,
              ),
            ),
          ),
        Text(
          bugun >= hedef
              ? 'Bugünkü hedef tamam! 🎉 ($bugun / $hedef)'
              : 'Bugünkü hedef: $bugun / $hedef',
          style: const TextStyle(color: kKahve, fontSize: 15),
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
              backgroundColor: kAcikTuruncu,
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
          color: Colors.white,
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
              style: const TextStyle(color: Color(0xFFBE966E), fontSize: 14),
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
        Text(etiket, style: const TextStyle(color: kKahve)),
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
                renk: const Color(0xFFD2463C),
                zemin: Colors.white,
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
        color: Colors.white,
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
                    color: kAcikTuruncu,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(ikon, color: kKoyuTuruncu, size: 30),
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
                      Text(aciklama, style: const TextStyle(color: kKahve)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: kKahve),
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
              color: kKoyuTuruncu,
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
                style: TextStyle(fontWeight: FontWeight.bold, color: kKahve),
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
                style: TextStyle(fontSize: 12, color: kKahve),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Her tur $turUzunlugu soru. Açık seviyelerden sorulur.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: kKahve),
          ),
        ),
      ],
    );
  }

  // Bir şık butonu: cevaptan sonra doğrusu yeşil, yanlış seçilen kırmızı olur
  Widget sikButonu(String sik) {
    Color zemin = Colors.white;
    Color yazi = const Color(0xFF3C2D23);
    if (cevaplandi) {
      if (sik == dogruSik) {
        zemin = const Color(0xFF4CAF50);
        yazi = Colors.white;
      } else if (sik == secilenSik) {
        zemin = const Color(0xFFE5534B);
        yazi = Colors.white;
      } else {
        yazi = const Color(0xFFB4A596);
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
        color: Colors.white,
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
            style: const TextStyle(color: kKahve),
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
                    color: kKoyuTuruncu,
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
    final renk = sonCevapDogru ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final zemin = sonCevapDogru ? const Color(0xFFE6F4E7) : const Color(0xFFFDE7E6);
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
                icon: const Icon(Icons.close, color: kKahve),
                onPressed: () => setState(() => testDurumu = 'secim'),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (soruNo + 1) / turSorulari.length,
                    minHeight: 10,
                    backgroundColor: kAcikTuruncu,
                    color: kTuruncu,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${soruNo + 1}/${turSorulari.length}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: kKahve),
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
                fillColor: Colors.white,
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
                      color: oran >= 0.5 ? Colors.white : kKoyuTuruncu,
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
            color: kKoyuTuruncu,
          ),
        ),
        const SizedBox(height: 20),
        if (turYanlislar.isNotEmpty)
          Material(
            color: Colors.white,
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
                    style: TextStyle(fontWeight: FontWeight.bold, color: kKahve),
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
                      style: const TextStyle(color: kKahve),
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
              backgroundColor: kAcikTuruncu,
              color: kTuruncu,
            ),
          ),
        ],
      ),
    );
  }

  // YENİ: Paketler sekmesi (eski Ekle sekmesinin yerine)
  Widget paketlerEkrani() {
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Text(
            'Çalışmak istediğin seviyeleri aç',
            style: TextStyle(color: kKahve, fontSize: 15),
          ),
        ),
        for (final d in duzeyBilgisi.entries) paketKarti(d.key, d.value),
        kutu(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.add_circle_outline, color: kTuruncu),
            title: const Text(
              'Kendi kelimeni ekle',
              style: TextStyle(fontWeight: FontWeight.bold, color: kKahve),
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
      ],
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

  // Beyaz yuvarlak köşeli kutu
  // Beyaz kutu. Container yerine Material: içindeki ListTile'ların dokunma efekti görünsün
  Widget kutu({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.white,
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
                    color: kKoyuTuruncu,
                  ),
                ),
                Text(
                  'Bugün $bugun kelime bildin',
                  style: const TextStyle(color: kKahve),
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
    if (sayi >= 10) return kKoyuTuruncu;
    if (sayi >= 5) return const Color(0xFFF5A15C);
    if (sayi >= 1) return const Color(0xFFFFD3A8);
    return const Color(0xFFF1E4D3);
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
            style: TextStyle(fontWeight: FontWeight.bold, color: kKahve),
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
              const Text('az ', style: TextStyle(color: kKahve, fontSize: 12)),
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
              const Text(' çok', style: TextStyle(color: kKahve, fontSize: 12)),
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
                color: kKoyuTuruncu,
              ),
            ),
            Text(ad, style: const TextStyle(fontSize: 12, color: kKahve)),
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
            style: TextStyle(fontWeight: FontWeight.bold, color: kKahve),
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
            style: TextStyle(fontSize: 13, color: kKahve),
          ),
          if (zamaniGelen > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Bugün tekrar zamanı gelen: $zamaniGelen kelime',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: kKoyuTuruncu,
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
              fillColor: Colors.white,
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
              style: TextStyle(color: kKahve),
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
    final ekranlar = [kartEkrani(), testEkrani(), paketlerEkrani(), hasatEkrani()];
    return Scaffold(
      appBar: AppBar(
        title: const Text('ApriEnglish'),
        actions: [
          // YENİ: Sağ üstte avatar, dokununca Hesabım açılır
          IconButton(
            tooltip: 'Hesabım',
            onPressed: hesabiAc,
            icon: Text(profil.avatar, style: const TextStyle(fontSize: 28)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ekranlar[sekme],
      bottomNavigationBar: NavigationBar(
        selectedIndex: sekme,
        onDestinationSelected: (i) {
          setState(() {
            sekme = i;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.style), label: 'Kartlar'),
          NavigationDestination(icon: Icon(Icons.edit), label: 'Test'),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Paketler'),
          NavigationDestination(icon: Icon(Icons.wb_sunny), label: 'Hasat'),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }

  Widget baslik(String metin) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          metin,
          style: const TextStyle(fontWeight: FontWeight.bold, color: kKahve),
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
              backgroundColor: kAcikTuruncu,
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
                            color: p.avatar == a ? kAcikTuruncu : const Color(0xFFF7F1EA),
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
                    color: kKrem,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline, color: kKoyuTuruncu),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.oneriAciklama,
                          style: const TextStyle(fontSize: 13, color: kKahve),
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
                      color: kKoyuTuruncu,
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
                              color: kKoyuTuruncu,
                            ),
                          ),
                          Text(
                            e.key,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, color: kKahve),
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
