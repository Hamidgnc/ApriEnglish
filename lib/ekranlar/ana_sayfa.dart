// Ana ekran: alt menü ve dört sekme (Ana sayfa, Pratik, Hasat, Profil).
// Uygulamanın verileri (kelimeler, geçmiş, profil) burada tutulur.

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bilesenler/cizimler.dart';
import '../bilesenler/program_gorunumu.dart';
import '../modeller/ders.dart';
import '../modeller/kelime.dart';
import '../modeller/profil.dart';
import '../paket.dart';
import '../servisler/bildirim.dart';
import '../servisler/efekt.dart';
import '../servisler/program.dart';
import '../tema.dart';
import '../yardimcilar/tarih.dart';
import 'ders_sayfasi.dart';
import 'geri_bildirim_sayfasi.dart';
import 'hesap_sayfasi.dart';
import 'tanitim_sayfasi.dart';

class AnaSayfa extends StatefulWidget {
  const AnaSayfa({super.key});

  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> {
  static const anahtar = 'kelimeler';

  // Seviye adları (Paketler ekranında sırayla gösterilir)
  static const duzeyBilgisi = {
    'A1': 'Başlangıç',
    'A2': 'Temel',
    'B1': 'Orta',
    'B2': 'Orta üstü',
    'Benim': 'Benim kelimelerim',
  };

  List<Kelime> kelimeler = []; // ilk açılışta hazır paketle dolar
  Set<String> seciliDuzeyler = {'A1', 'Benim'}; // çalışılan seviyeler
  String aktifDuzey = 'A1'; // ana sayfada derslerini gördüğün seviye
  final Random rastgele = Random();
  final FlutterTts ses = FlutterTts();
  bool yuklendi = false;
  int sekme = 0;
  int bugun = 0; // bugün bilinen kelime sayısı
  Profil profil = Profil(); // ad, avatar, hedef, bildirim ayarları
  bool tanitimTamam = true; // ilk açılış tanıtımı görüldü mü
  bool tanitimTekrar = false; // tanıtım Profil'den tekrar mı izleniyor (çıkılabilir)
  Map<String, int> gecmis = {}; // her gün kaç kelime bilindi (takvim için)
  int sepet = 0; // kayısı sepeti sayısı (0-2); kaçırılan günde seriyi korur
  Set<String> korunanGunler = {}; // sepetle korunan günler (seri bozulmaz)
  String? sonSepet; // en son sepet kazanılan gün
  List<Ders> dersler = []; // paketten oluşturulan dersler
  Map<String, Ders> kelimeninDersi = {}; // "apple" -> Yiyecek dersi (şıklar için)
  Map<String, int> dersPuanlari = {}; // "A1-3" -> kazanılan kayısı (0-3)
  PageController? dersKaydirici; // ana sayfadaki ders kartlarını kaydırır

  // Hasat ekranı
  final TextEditingController aramaKutusu = TextEditingController();
  String arama = '';
  int filtre = -1; // -1 hepsi, 0 ham, 1 yarı, 3 kurutmada, 4 kuru
  // Hasat takviminde gösterilen ay (ayın 1'i)
  DateTime takvimAyi = DateTime(DateTime.now().year, DateTime.now().month);

  // Kartlar ekranı
  late Kelime aktif;
  bool onYuz = true;

  // Test ekranı
  // Test turu
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
      Efekt.ses = profil.ses;
      Efekt.titresim = profil.titresim;
    }
    final duzeyMetni = await prefs.getString('duzeyler');
    if (duzeyMetni != null) {
      seciliDuzeyler = Set<String>.from(jsonDecode(duzeyMetni));
    }
    // Hazır paket daha önce eklenmediyse ekle
    // Paket sürümü: yeni kelimeler eklendikçe artar (1: 582 kelime, 2: ~3000 kelime + B2).
    // Telefondaki sürüm eskiyse eksik kelimeler eklenir, var olanların ilerlemesi korunur.
    const guncelPaket = 2;
    final paketSurumu = await prefs.getInt('paket') ?? 0;
    final paketEklendi = paketSurumu < guncelPaket;
    if (paketEklendi) {
      paketiEkle();
      await prefs.setInt('paket', guncelPaket);
    }
    // Ders puanlarını yükle, dersleri kur, kaydırıcıyı sıradaki derste aç
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
    // Sepet bilgileri ve en son ne zaman girildiği
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

  // Paketteki kelimeleri listeye ekler. Zaten olanlara dokunmaz,
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
    kelimeninDersi = {};
    for (final (duzey, baslik, liste) in dersPlani) {
      final no = (sayac[duzey] ?? 0) + 1;
      sayac[duzey] = no;
      // Silinmiş kelimeler atlanır; ders tamamen boşaldıysa gösterilmez
      final dersKelimeleri = [
        for (final ing in liste)
          if (harita[ing] != null) harita[ing]!,
      ];
      if (dersKelimeleri.isEmpty) continue;
      final ders = Ders(duzey, no, baslik, dersKelimeleri);
      dersler.add(ders);
      for (final k in dersKelimeleri) {
        kelimeninDersi[k.ing] = ders;
      }
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

  // Rozete dokununca alttan açılan seviye seçici
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

  // Günlük tekrar: önce kurutma zamanı gelenler, sonra derste/kartta
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

  // Ders sayfasını açar. Ders bitince sayfa sonucu geri yollar,
  // biz de kelimelerin aşamalarını ve dersin kayısı puanını güncelleriz.
  Future<void> dersiBaslat(Ders d) async {
    final sonuc = await Navigator.push<DersSonucu>(
      context,
      MaterialPageRoute(
        builder: (_) => DersSayfasi(
          ders: d,
          tumKelimeler: kelimeler,
          // Tekrar dersinde kelimeler karışık konulardan: her kelimenin kendi dersi
          konuArkadaslari: (k) => kelimeninDersi[k.ing]?.kelimeler ?? d.kelimeler,
          oku: oku,
        ),
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

  // Son 7 günün hepsinde hedef tamamsa 1 sepet (en fazla 2)
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

  // Dünden geriye kaçırılan günleri sepetle kapatır, kaç sepet kullanıldığını döndürür.
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

  // Uzun aradan dönene nazik karşılama; sepet kullanıldıysa haber ver
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

  // Şimdiye kadarki en uzun seri
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

  // Son 7 günün çalışmasına göre hedef önerisi (sayı, açıklama)
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
      Efekt.ses = profil.ses;
      Efekt.titresim = profil.titresim;
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

  // Hesabım sayfasını açar, Kaydet'e basılırsa yeni profili uygular
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
  // Şıklar: yanlışlar önce kelimenin kendi dersinden (aynı konu)
  List<String> siklariUret(Kelime k) => sikUret(
        kelime: k,
        ayniDers: kelimeninDersi[k.ing]?.kelimeler ?? [],
        tumKelimeler: kelimeler,
        metin: cevapMetni, // yöne göre Türkçe ya da İngilizce şıklar
        rastgele: rastgele,
      );

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
    if (dogru) {
      Efekt.dogru();
    } else {
      Efekt.yanlis();
    }
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
      Efekt.tamam(); // tur bitti
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

  // Bir seviyeyi açar ya da kapatır (en az bir seviye açık kalır)
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

  // ===== Ana sayfa =====

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
            // Kaç kayısı sepetin var
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

  // Günlük tekrar kartı (ders kartıyla aynı boyda, manzarasız)
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

  // Pratik turu sonu: ders sonu ekranıyla aynı dil
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

  // Bir seviyenin kartı: ad, ilerleme çubuğu, aç/kapa düğmesi
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

  // ===== Profil sekmesi: düz liste, satırlar ince çizgiyle ayrılır =====

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
        // Ses ve titreşim ayrı ayrı açılıp kapanır
        satirGrubu([
          anahtarSatiri(
            ikon: Icons.volume_up_outlined,
            ad: 'Ses efektleri',
            deger: profil.ses,
            onChanged: (acik) {
              setState(() => profil.ses = Efekt.ses = acik);
              profiliKaydet();
              if (acik) Efekt.dogru(); // açınca nasıl olduğunu duyur
            },
          ),
          anahtarSatiri(
            ikon: Icons.vibration_rounded,
            ad: 'Titreşim',
            deger: profil.titresim,
            onChanged: (acik) {
              setState(() => profil.titresim = Efekt.titresim = acik);
              profiliKaydet();
              if (acik) Efekt.titret(); // açınca bir kez titret
            },
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

  // Aç/kapa anahtarlı satır (ses, titreşim)
  Widget anahtarSatiri({
    required IconData ikon,
    required String ad,
    required bool deger,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      value: deger,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.only(left: 20, right: 12),
      secondary: Icon(ikon, color: kSoluk, size: 26),
      title: Text(
        ad,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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

  // Programım sayfası: güncel ilerlemeye göre yol haritası, süre değiştirilebilir
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

  // Seviyeler ayrı sayfada. Sayfa ana durumun (State) dışında olduğu için
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

  // Her şeyi sıfırlamadan önce mutlaka sorar
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

  // Üstte üç kutu: seri, en uzun seri, bugün
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

  // Kayısı sepeti açıklaması ve sayısı
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

  // Aylık takvim: telefondaki takvim gibi; çalışılan günler turuncu daire
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

  // Olgunlaşma özeti: dört aşama tek bir renkli çubukta
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
          // Dismissible = kaydırınca kaybolan satır
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
    // İlk açılışta önce tanıtım
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
      // Sadece ikonlu alt menü (yazılar gizli, basılı tutunca görünür)
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
