// Kişiye özel programın hesapları: tempo, hatırlatma saati, yol haritası.

import 'dart:math';

import '../modeller/ders.dart';
import '../yardimcilar/tarih.dart';

// Kişiye özel programın hesapları. Hepsi basit kurallar ve bölme işlemi.

// Bir ders yaklaşık 4-5 dakika sürüyor; tekrar için de pay bırakıyoruz
int gunlukDersSayisi(int dakika) => switch (dakika) {
      <= 5 => 1,
      <= 10 => 2,
      <= 15 => 3,
      _ => 5,
    };

// Programın tek kaynağı günlük hedef: 10 kelime = 1 ders (en az 1)
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
