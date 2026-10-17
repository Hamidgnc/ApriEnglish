// Tarih yardımcıları: "yyyy-aa-gg" metinleri, Türkçe ay adları.

String tarihMetni(DateTime d) => d.toIso8601String().substring(0, 10);

String bugununTarihi() => tarihMetni(DateTime.now());

String gunSonra(int gun) => tarihMetni(DateTime.now().add(Duration(days: gun)));

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
