// Ders modeli, seviye listesi ve ders başlıkları.

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
