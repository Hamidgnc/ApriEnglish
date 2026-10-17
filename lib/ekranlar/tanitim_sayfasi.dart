// İlk açılış tanıtımı ve kişiye özel program soruları.

import 'dart:math';

import 'package:flutter/material.dart';

import '../bilesenler/cizimler.dart';
import '../bilesenler/program_gorunumu.dart';
import '../modeller/ders.dart';
import '../modeller/profil.dart';
import '../servisler/bildirim.dart';
import '../servisler/program.dart';
import '../tema.dart';
import '../yardimcilar/tarih.dart';

// Karşılama ve kişiye özel program: her sayfada bir soru, Devam ile ilerlenir.
class TanitimSayfasi extends StatefulWidget {
  final Profil profil;
  // Bitince: profil, açık seviyeler, ana sayfada başlanacak seviye, ilk ders hemen açılsın mı
  final void Function(Profil profil, Set<String> duzeyler, String baslangic, bool dersAc)
      onBitti;
  // Tanıtım tekrar izleniyorsa çıkış; ilk açılışta null (çıkış yok, sorular cevaplanmalı)
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
