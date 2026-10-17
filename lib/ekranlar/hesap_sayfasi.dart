// Hesabım sayfası: avatar, ad, günlük hedef, hatırlatma, istatistikler.

import 'package:flutter/material.dart';

import '../modeller/profil.dart';
import '../servisler/bildirim.dart';
import '../tema.dart';

// Ayrı bir sayfa. Navigator.push ile açılır, Navigator.pop ile sonucu geri verir.
class HesapSayfasi extends StatefulWidget {
  final Profil profil;
  final int oneri;
  final String oneriAciklama;
  final Map<String, int> istatistikler;

  const HesapSayfasi({
    super.key,
    required this.profil,
    required this.oneri,
    required this.oneriAciklama,
    required this.istatistikler,
  });

  @override
  State<HesapSayfasi> createState() => _HesapSayfasiState();
}

class _HesapSayfasiState extends State<HesapSayfasi> {
  static const avatarlar = [
    '👩', '👨', '🧑', '👧', '👦', '👵', '👴', '🧕', '🧔',
    '👱‍♀️', '👱‍♂️', '👩🏻', '👨🏽', '🧑🏾', '👩🏿',
    '👩‍🎓', '👨‍🎓', '👩‍💻', '👨‍💻', '👩‍🏫', '👨‍🏫',
    '👩‍💼', '👨‍💼', '👩‍⚕️', '👨‍⚕️', '👩‍🍳', '👨‍🍳',
  ];

  late Profil p;
  late TextEditingController adKutusu;

  @override
  void initState() {
    super.initState();
    p = widget.profil;
    adKutusu = TextEditingController(text: p.ad);
  }

  @override
  void dispose() {
    adKutusu.dispose();
    super.dispose();
  }

  String saatMetni() =>
      '${p.saat.toString().padLeft(2, '0')}:${p.dakika.toString().padLeft(2, '0')}';

  Future<void> saatSec() async {
    final secilen = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: p.saat, minute: p.dakika),
    );
    if (secilen == null) return;
    setState(() {
      p.saat = secilen.hour;
      p.dakika = secilen.minute;
    });
  }

  // Hedef artık yazılmıyor, − / + ile değişiyor; 5'er 5'er, 5 ile 100 arası
  void hedefDegistir(int fark) {
    setState(() {
      p.hedef = (p.hedef + fark).clamp(5, 100).toInt();
    });
  }

  void kaydet() {
    p.ad = adKutusu.text.trim();
    Navigator.pop(context, p); // profili ana sayfaya geri gönder
  }

  // Gri, küçük, aralıklı harfli bölüm başlığı
  Widget baslik(String metin) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
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

  // Koyu gri kutu. Material: içindeki dokunma efektleri görünsün
  Widget kutu({required Widget child}) {
    return Material(
      color: kKart,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  // − ve + için yuvarlak buton
  Widget artiEksi(IconData ikon, VoidCallback onTap) {
    return Material(
      color: kCizgi,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(ikon, color: kYazi),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hesabım')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // Büyük avatar ve altında ad
          Center(
            child: CircleAvatar(
              radius: 52,
              backgroundColor: kVurguZemin,
              child: Text(p.avatar, style: const TextStyle(fontSize: 56)),
            ),
          ),
          const SizedBox(height: 16),
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
          ),

          baslik('AVATAR'),
          kutu(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final a in avatarlar)
                  GestureDetector(
                    onTap: () => setState(() => p.avatar = a),
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.avatar == a ? kVurguZemin : kCizgi,
                        border: Border.all(
                          color: p.avatar == a ? kTuruncu : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: Text(a, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
              ],
            ),
          ),

          baslik('GÜNLÜK HEDEF'),
          kutu(
            child: Column(
              children: [
                Row(
                  children: [
                    artiEksi(Icons.remove_rounded, () => hedefDegistir(-5)),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '${p.hedef}',
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              color: kTuruncu,
                              height: 1.1,
                            ),
                          ),
                          const Text(
                            'kelime / gün',
                            style: TextStyle(color: kSoluk, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    artiEksi(Icons.add_rounded, () => hedefDegistir(5)),
                  ],
                ),
                const SizedBox(height: 14),
                // Uygulamanın önerisi: son 7 güne göre
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  decoration: BoxDecoration(
                    color: kZemin,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline_rounded, color: kTuruncu, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.oneriAciklama,
                          style: const TextStyle(fontSize: 13, color: kSoluk),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => p.hedef = widget.oneri),
                        child: Text(
                          '${widget.oneri} yap',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          baslik('HATIRLATMA'),
          kutu(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Günlük hatırlatma',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Her gün seçtiğin saatte hatırlatır',
                    style: TextStyle(color: kSoluk),
                  ),
                  value: p.bildirim,
                  onChanged: (acik) => setState(() => p.bildirim = acik),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: p.bildirim,
                  leading: const Icon(Icons.schedule_rounded),
                  title: const Text('Saat', style: TextStyle(fontWeight: FontWeight.w700)),
                  trailing: Text(
                    saatMetni(),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: p.bildirim ? kTuruncu : const Color(0xFF5C554F),
                    ),
                  ),
                  onTap: p.bildirim ? saatSec : null,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: denemeBildirimi,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Deneme bildirimi gönder'),
                  ),
                ),
              ],
            ),
          ),

          baslik('İSTATİSTİKLER'),
          // 3 sütunlu kutucuklar
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            children: [
              for (final e in widget.istatistikler.entries)
                Container(
                  decoration: BoxDecoration(
                    color: kKart,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${e.value}',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: kTuruncu,
                        ),
                      ),
                      Text(
                        e.key,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: kSoluk),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      // Kaydet butonu altta sabit: liste ne kadar uzun olursa olsun görünür
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 58,
            child: FilledButton(
              onPressed: kaydet,
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
              child: const Text('Kaydet'),
            ),
          ),
        ),
      ),
    );
  }
}
