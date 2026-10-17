// Uygulama içi öneri ve sorun bildirme formu (arka planda Google Form).

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../tema.dart';

// Kullanıcı uygulamanın içinden yazar; mesaj arka planda Google Formuna gider,
// cevaplar Google E-Tablosu'nda toplanır. Sunucu gerekmez.
class GeriBildirimSayfasi extends StatefulWidget {
  final String ad; // profildeki ad, formun "İsim" sorusuna yazılır

  const GeriBildirimSayfasi({super.key, required this.ad});

  @override
  State<GeriBildirimSayfasi> createState() => _GeriBildirimSayfasiState();
}

class _GeriBildirimSayfasiState extends State<GeriBildirimSayfasi> {
  // Formun adresi: linkteki "viewform" yerine "formResponse" = cevap gönderme kapısı
  static const formAdresi =
      'https://docs.google.com/forms/d/e/1FAIpQLScnV-00z6rlYMY45U1GNJtybDt4HsLb0_EnFuxiQ7pIP3ArSA/formResponse';
  // Her sorunun gizli kimliği (önceden doldurulmuş linkten aldık)
  static const konuKimligi = 'entry.185359346';
  static const mesajKimligi = 'entry.379842936';
  static const isimKimligi = 'entry.1645225265';

  final TextEditingController mesajKutusu = TextEditingController();
  String konu = 'Öneri'; // formdaki seçeneklerle birebir aynı yazılmalı
  bool gonderiliyor = false; // gönderirken buton dönen çembere dönüşür

  @override
  void dispose() {
    mesajKutusu.dispose();
    super.dispose();
  }

  Future<void> gonder() async {
    final mesaj = mesajKutusu.text.trim();
    if (mesaj.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Biraz daha yazar mısın? En az 5 harf.')),
      );
      return;
    }
    setState(() => gonderiliyor = true);
    bool basarili = false;
    try {
      // POST: formu doldurup "Gönder"e basmanın kod hâli
      final cevap = await http.post(
        Uri.parse(formAdresi),
        body: {
          konuKimligi: konu,
          mesajKimligi: mesaj,
          isimKimligi: widget.ad,
        },
      ).timeout(const Duration(seconds: 15)); // 15 sn'de cevap yoksa vazgeç
      basarili = cevap.statusCode == 200; // 200 = "tamam, aldım"
    } catch (_) {
      basarili = false; // internet yok ya da zaman aşımı
    }
    if (!mounted) return; // beklerken sayfa kapandıysa dokunma
    setState(() => gonderiliyor = false);
    if (basarili) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teşekkürler! Mesajın bize ulaştı.')),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gönderilemedi. İnternet bağlantını kontrol edip tekrar dene.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Öneri ve sorun bildir')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ApriEnglish\'i birlikte geliştirelim. Aklına gelen her şeyi yaz, '
                'hepsini tek tek okuyoruz.',
                style: TextStyle(fontSize: 15, color: kSoluk, height: 1.4),
              ),
              const SizedBox(height: 20),
              const Text(
                'KONU',
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
                  for (final k in ['Öneri', 'Sorun', 'Diğer'])
                    ChoiceChip(
                      label: Text(k),
                      selected: konu == k,
                      onSelected: (_) => setState(() => konu = k),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: TextField(
                  controller: mesajKutusu,
                  maxLines: null, // satır sınırı yok
                  expands: true, // kutu kalan alanı doldursun
                  maxLength: 1000,
                  textAlignVertical: TextAlignVertical.top,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: konu == 'Sorun'
                        ? 'Ne oldu? Hangi ekranda, ne yaparken?'
                        : 'Mesajını yaz...',
                    filled: true,
                    fillColor: kKart,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 58,
                child: FilledButton(
                  onPressed: gonderiliyor ? null : gonder, // gönderirken çift basılmasın
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
                  child: gonderiliyor
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 3, color: kTuruncu),
                        )
                      : const Text('Gönder'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
