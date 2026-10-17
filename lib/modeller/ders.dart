// Ders modeli, seviye listesi, ders başlıkları ve şık üretici.

import 'dart:math';

import '../paket.dart';
import 'kelime.dart';

// Paketteki seviyeler, kolaydan zora. Seviye eklenirse sadece burası değişir.
const seviyeler = ['A1', 'A2', 'B1', 'B2'];

// Bir seviyenin ders başlıkları (ders planından)
List<String> dersBasliklari(String duzey) =>
    [for (final d in dersPlani) if (d.$1 == duzey) d.$2];

// Bir ders = aynı seviyeden sıradaki 10 kelime
class Ders {
  final String duzey; // A1, A2, B1
  final int no; // 1, 2, 3...
  final String baslik; // "Yiyecek ve içecek" gibi
  final List<Kelime> kelimeler;

  Ders(this.duzey, this.no, this.baslik, this.kelimeler);

  // Kayıtta dersi bu adla tutarız, ör. "A1-3"
  String get kimlik => '$duzey-$no';
}

// Çoktan seçmeli şıklar: doğru cevap + yanlış şıklar, karışık sırayla.
// Yanlış şıklar ÖNCE AYNI DERSTEN (aynı konu) seçilir: "apple" sorulunca şıklar
// "elma, muz, üzüm, kiraz" olur; konuya bakıp tahminle bilinemez.
// Ders yetmezse aynı seviyeden, o da yetmezse bütün kelimelerden tamamlanır.
// Anlamı ortak olanlar (house "ev" / home "ev, yuva") şık olmaz: ikisi de doğru sayılırdı.
// metin: şıkta kelimenin hangi yüzü görünecek (Türkçe anlam ya da İngilizcesi).
List<String> sikUret({
  required Kelime kelime,
  required List<Kelime> ayniDers,
  required List<Kelime> tumKelimeler,
  required String Function(Kelime) metin,
  required Random rastgele,
  int adet = 3,
}) {
  final parcalar = kelime.anlam.split(', ').toSet();
  bool uygun(Kelime x) =>
      x.ing != kelime.ing && !x.anlam.split(', ').any(parcalar.contains);
  final dogru = metin(kelime);
  final yanlislar = <String>[];
  final havuzlar = [
    ayniDers,
    tumKelimeler.where((x) => x.duzey == kelime.duzey).toList(),
    tumKelimeler,
  ];
  for (final havuz in havuzlar) {
    final karisik = havuz.where(uygun).toList()..shuffle(rastgele);
    for (final x in karisik) {
      final m = metin(x);
      if (m != dogru && !yanlislar.contains(m)) yanlislar.add(m);
      if (yanlislar.length == adet) break;
    }
    if (yanlislar.length == adet) break;
  }
  return [dogru, ...yanlislar]..shuffle(rastgele);
}
