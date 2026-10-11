import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Uygulamanın renkleri
const kTuruncu = Color(0xFFF5842C);
const kKoyuTuruncu = Color(0xFFCD5C16);
const kKrem = Color(0xFFFFF6E8);
const kAcikTuruncu = Color(0xFFFFE4C8);
const kKahve = Color(0xFF96643C);

void main() {
  runApp(const KelimeUygulamasi());
}

class Kelime {
  String ing;
  String anlam;
  int yanlis;
  int seviye; // 0 = ham, 1-2 = yarı olgun, 3 = kurutmada, 4 = kuru kayısı
  String? tekrar; // bir sonraki tekrar günü (yyyy-aa-gg), yoksa null

  Kelime({
    required this.ing,
    required this.anlam,
    this.yanlis = 0,
    this.seviye = 0,
    this.tekrar,
  });

  Map<String, dynamic> toJson() {
    return {
      'ing': ing,
      'anlam': anlam,
      'yanlis': yanlis,
      'seviye': seviye,
      'tekrar': tekrar,
    };
  }

  factory Kelime.fromJson(Map<String, dynamic> json) {
    return Kelime(
      ing: json['ing'],
      anlam: json['anlam'],
      yanlis: json['yanlis'],
      seviye: json['seviye'] ?? 0, // eski kayıtlarda seviye yok -> 0
      tekrar: json['tekrar'], // eski kayıtlarda yok -> null
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
  static const gunlukHedef = 10;

  List<Kelime> kelimeler = [
    Kelime(ing: 'apple', anlam: 'elma'),
    Kelime(ing: 'book', anlam: 'kitap'),
    Kelime(ing: 'water', anlam: 'su'),
    Kelime(ing: 'house', anlam: 'ev'),
    Kelime(ing: 'car', anlam: 'araba'),
  ];
  final Random rastgele = Random();
  final FlutterTts ses = FlutterTts();
  bool yuklendi = false;
  int sekme = 0;
  int bugun = 0; // bugün bilinen kelime sayısı
  Map<String, int> gecmis = {}; // her gün kaç kelime bilindi (takvim için)

  // Hasat ekranı
  final TextEditingController aramaKutusu = TextEditingController();
  String arama = '';
  int filtre = -1; // -1 hepsi, 0 ham, 1 yarı, 3 kurutmada, 4 kuru

  // Kartlar ekranı
  late Kelime aktif;
  bool onYuz = true;

  // Test ekranı
  late Kelime testKelimesi;
  final TextEditingController cevapKutusu = TextEditingController();
  String mesaj = '';
  int dogruSayisi = 0;
  int yanlisSayisi = 0;

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
    setState(() {
      bugun = gecmis[bugununTarihi()] ?? 0;
      aktif = kelimeSec();
      testKelimesi = kelimeSec();
      yuklendi = true;
    });
  }

  Future<void> kelimeleriKaydet() async {
    final prefs = SharedPreferencesAsync();
    final metin = jsonEncode(kelimeler.map((k) => k.toJson()).toList());
    await prefs.setString(anahtar, metin);
    await prefs.setString('gecmis', jsonEncode(gecmis));
  }

  // Tekrar zamanı geldi mi? (tarihi yoksa ya da bugün/geçmişteyse evet)
  bool zamaniGeldi(Kelime k) =>
      k.tekrar == null || k.tekrar!.compareTo(bugununTarihi()) <= 0;

  // Kurutmada/kuruda bekleyen kelimeler, zamanı gelene kadar sorulmaz
  bool bekliyor(Kelime k) => k.seviye >= 3 && !zamaniGeldi(k);

  Kelime kelimeSec() {
    final hazir = kelimeler.where((k) => !bekliyor(k)).toList();
    final havuz = hazir.isEmpty ? kelimeler : hazir; // hepsi bekliyorsa yine de sor
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

  void kontrolEt() {
    final cevap = turkceKucuk(cevapKutusu.text.trim());
    if (cevap.isEmpty) return;
    setState(() {
      if (cevap == testKelimesi.anlam) {
        dogruSayisi++;
        mesaj = 'Doğru!';
        bildi(testKelimesi);
      } else {
        yanlisSayisi++;
        mesaj = 'Yanlış! ${testKelimesi.ing} = ${testKelimesi.anlam}';
        bilemedi(testKelimesi);
      }
      testKelimesi = kelimeSec();
      cevapKutusu.clear();
    });
    kelimeleriKaydet();
  }

  void gec() {
    setState(() {
      yanlisSayisi++;
      mesaj = 'Geçildi: ${testKelimesi.ing} = ${testKelimesi.anlam}';
      bilemedi(testKelimesi);
      testKelimesi = kelimeSec();
      cevapKutusu.clear();
    });
    kelimeleriKaydet();
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
      kelimeler.add(Kelime(ing: ing, anlam: tr));
      ingKutusu.clear();
      trKutusu.clear();
    });
    kelimeleriKaydet();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("'$ing' eklendi!")),
    );
  }

  void kelimeSil(Kelime k) {
    if (kelimeler.length <= 1) return;
    setState(() {
      kelimeler.remove(k);
      aktif = kelimeSec();
      testKelimesi = kelimeSec();
    });
    kelimeleriKaydet();
  }

  // ---------------- Ekranlar ----------------

  Widget hedefSatiri() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          bugun >= gunlukHedef
              ? 'Bugünkü hedef tamam! 🎉'
              : 'Bugünkü hedef: $bugun / $gunlukHedef',
          style: const TextStyle(color: kKahve, fontSize: 15),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(gunlukHedef, (i) {
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

  Widget testEkrani() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Doğru: $dogruSayisi   Yanlış: $yanlisSayisi'),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${testKelimesi.ing} = ?',
                  style: const TextStyle(fontSize: 32),
                ),
                IconButton(
                  onPressed: () => oku(testKelimesi.ing),
                  icon: const Icon(Icons.volume_up, color: kTuruncu),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: cevapKutusu,
              decoration: const InputDecoration(
                labelText: 'Türkçe anlamı',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => kontrolEt(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: kontrolEt,
              child: const Text('Kontrol et'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: gec,
              child: const Text('Geç'),
            ),
            const SizedBox(height: 16),
            Text(mesaj, style: const TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }

  Widget ekleEkrani() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ingKutusu,
              decoration: const InputDecoration(
                labelText: 'İngilizce kelime',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: trKutusu,
              decoration: const InputDecoration(
                labelText: 'Türkçe anlamı',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => kelimeEkle(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: kelimeEkle,
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
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
  Widget kutu({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
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
      return '${k.anlam} · ${durumAdi(k.seviye)} · $kalan gün sonra tekrar';
    }
    return '${k.anlam} · ${durumAdi(k.seviye)}';
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
    final ekranlar = [kartEkrani(), testEkrani(), ekleEkrani(), hasatEkrani()];
    return Scaffold(
      appBar: AppBar(title: const Text('ApriEnglish')),
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
          NavigationDestination(icon: Icon(Icons.add), label: 'Ekle'),
          NavigationDestination(icon: Icon(Icons.wb_sunny), label: 'Hasat'),
        ],
      ),
    );
  }
}
