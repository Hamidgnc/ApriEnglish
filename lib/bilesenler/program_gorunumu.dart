// Programı gösteren parça (tanıtımın sonu ve Profil > Programım).

import 'package:flutter/material.dart';

import '../servisler/program.dart';
import '../tema.dart';
import '../yardimcilar/tarih.dart';

// Programı gösteren parça. Hem tanıtımın sonunda hem de Profil > Programım'da kullanılır.
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
        // Başlangıç ve hedef bitiş, yıllarıyla
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
