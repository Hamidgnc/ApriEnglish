// Ders ekranı: tanıtım, çoktan seçmeli, eşleştirme ve ders sonu.

import 'dart:math';

import 'package:flutter/material.dart';

import '../bilesenler/cizimler.dart';
import '../modeller/ders.dart';
import '../modeller/kelime.dart';
import '../servisler/efekt.dart';
import '../tema.dart';

// Ders bitince ana sayfaya giden sonuç
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
  final List<Kelime> tumKelimeler; // ders yetmezse yanlış şıklar buradan tamamlanır
  final List<Kelime> Function(Kelime) konuArkadaslari; // kelimenin dersindeki diğerleri
  final void Function(String) oku; // ana sayfadaki seslendirme

  const DersSayfasi({
    super.key,
    required this.ders,
    required this.tumKelimeler,
    required this.konuArkadaslari,
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

  // Doğru anlam + 3 yanlış anlam; yanlışlar önce aynı dersten (aynı konu)
  List<String> siklariUret(Kelime k) => sikUret(
        kelime: k,
        ayniDers: widget.konuArkadaslari(k),
        tumKelimeler: widget.tumKelimeler,
        metin: (x) => x.anlam,
        rastgele: rastgele,
      );

  void ileri() {
    if (adimNo + 1 >= adimlar.length) {
      kronometre.stop();
      setState(() {
        bitti = true;
      });
      Efekt.tamam(); // ders bitti
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
    if (sik == adim.kelimeler.first.anlam) {
      Efekt.dogru();
    } else {
      Efekt.yanlis();
    }
  }

  void sikSec(String sik) {
    if (secilen != null) return; // ikinci kez seçilemez
    final k = adim.kelimeler.first;
    setState(() {
      secilen = sik;
      if (sik != k.anlam) yanlislar.add(k);
    });
    if (sik == k.anlam) {
      Efekt.dogru();
    } else {
      Efekt.yanlis();
    }
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
      Efekt.dogru();
      return;
    }
    Efekt.yanlis();
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
