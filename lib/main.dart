import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const KelimeUygulamasi());
}

class Kelime {
  String ing;
  String anlam;
  int yanlis;

  Kelime({required this.ing, required this.anlam, this.yanlis = 0});

  Map<String, dynamic> toJson() {
    return {'ing': ing, 'anlam': anlam, 'yanlis': yanlis};
  }

  factory Kelime.fromJson(Map<String, dynamic> json) {
    return Kelime(
      ing: json['ing'],
      anlam: json['anlam'],
      yanlis: json['yanlis'],
    );
  }
}

class KelimeUygulamasi extends StatelessWidget {
  const KelimeUygulamasi({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ApriEnglish',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
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
  List<Kelime> kelimeler = [
    Kelime(ing: 'apple', anlam: 'elma'),
    Kelime(ing: 'book', anlam: 'kitap'),
    Kelime(ing: 'water', anlam: 'su'),
    Kelime(ing: 'house', anlam: 'ev'),
    Kelime(ing: 'car', anlam: 'araba'),
  ];
  final Random rastgele = Random();
  bool yuklendi = false;
  int sekme = 0;

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
    kelimeleriYukle();
  }

  @override
  void dispose() {
    cevapKutusu.dispose();
    ingKutusu.dispose();
    trKutusu.dispose();
    super.dispose();
  }

  Future<void> kelimeleriYukle() async {
    final prefs = SharedPreferencesAsync();
    final metin = await prefs.getString(anahtar);
    if (metin != null) {
      final List<dynamic> liste = jsonDecode(metin);
      kelimeler = liste.map((e) => Kelime.fromJson(e)).toList();
    }
    setState(() {
      aktif = kelimeSec();
      testKelimesi = kelimeSec();
      yuklendi = true;
    });
  }

  Future<void> kelimeleriKaydet() async {
    final prefs = SharedPreferencesAsync();
    final metin = jsonEncode(kelimeler.map((k) => k.toJson()).toList());
    await prefs.setString(anahtar, metin);
  }

  Kelime kelimeSec() {
    final List<Kelime> torba = [];
    for (final k in kelimeler) {
      final agirlik = 1 + k.yanlis;
      torba.addAll(List.filled(agirlik, k));
    }
    return torba[rastgele.nextInt(torba.length)];
  }

  void kartCevapla(bool biliyordum) {
    setState(() {
      if (biliyordum) {
        if (aktif.yanlis > 0) aktif.yanlis--;
      } else {
        aktif.yanlis++;
      }
      aktif = kelimeSec();
      onYuz = true;
    });
    kelimeleriKaydet();
  }

  void kontrolEt() {
    final cevap = cevapKutusu.text.trim().toLowerCase();
    if (cevap.isEmpty) return;
    setState(() {
      if (cevap == testKelimesi.anlam) {
        dogruSayisi++;
        mesaj = 'Doğru!';
        if (testKelimesi.yanlis > 0) testKelimesi.yanlis--;
      } else {
        yanlisSayisi++;
        mesaj = 'Yanlış! ${testKelimesi.ing} = ${testKelimesi.anlam}';
        testKelimesi.yanlis++;
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
      testKelimesi.yanlis++;
      testKelimesi = kelimeSec();
      cevapKutusu.clear();
    });
    kelimeleriKaydet();
  }

  void kelimeEkle() {
    final ing = ingKutusu.text.trim().toLowerCase();
    final tr = trKutusu.text.trim().toLowerCase();
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

  Widget kartEkrani() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  onYuz = !onYuz;
                });
              },
              child: Card(
                color: onYuz ? null : Colors.blue.shade200,
                child: SizedBox(
                  width: double.infinity,
                  height: 220,
                  child: Center(
                    child: Text(
                      onYuz ? aktif.ing : aktif.anlam,
                      style: const TextStyle(fontSize: 36),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Çevirmek için karta dokun'),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => kartCevapla(false),
                    child: const Text('Bilmiyordum'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: () => kartCevapla(true),
                    child: const Text('Biliyordum'),
                  ),
                ),
              ],
            ),
          ],
        ),
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
            Text(
              '${testKelimesi.ing} = ?',
              style: const TextStyle(fontSize: 32),
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

  Widget listeEkrani() {
    return ListView.builder(
      itemCount: kelimeler.length,
      itemBuilder: (context, i) {
        final k = kelimeler[i];
        return ListTile(
          title: Text(k.ing),
          subtitle: Text(k.anlam),
          trailing: Text('yanlış: ${k.yanlis}'),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!yuklendi) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final ekranlar = [kartEkrani(), testEkrani(), ekleEkrani(), listeEkrani()];
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
          NavigationDestination(icon: Icon(Icons.list), label: 'Liste'),
        ],
      ),
    );
  }
}