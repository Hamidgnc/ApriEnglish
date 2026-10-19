// "Uygulama hakkında" sayfası: sürüm, gizlilik, veri silme, iletişim ve lisanslar.

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bilesenler/cizimler.dart';
import '../tema.dart';

// Play Console'a girdiğimiz adreslerle birebir aynı olmalı
const gizlilikAdresi = 'https://sites.google.com/view/aprienglish-gizlilik';
const veriSilmeAdresi = 'https://sites.google.com/view/aprienglish-gizlilik/veri-silme';
const iletisimEpostasi = 'hello.aprienglish@gmail.com';

// Bir web sayfasını ya da e-posta uygulamasını telefonun kendi uygulamasında açar.
// Açılamazsa (örneğin e-posta uygulaması yoksa) kullanıcıya kısa bir uyarı gösterir.
Future<void> baglantiAc(BuildContext context, Uri adres) async {
  bool acildi = false;
  try {
    acildi = await launchUrl(adres, mode: LaunchMode.externalApplication);
  } catch (_) {
    acildi = false;
  }
  if (!acildi && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Açılamadı: ${adres.scheme == 'mailto' ? adres.path : adres}')),
    );
  }
}

class HakkindaSayfasi extends StatelessWidget {
  const HakkindaSayfasi({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Uygulama hakkında')),
      body: FutureBuilder<PackageInfo>(
        // Sürüm numarası pubspec.yaml'daki "version" satırından otomatik gelir
        future: PackageInfo.fromPlatform(),
        builder: (context, durum) {
          final surum = durum.data?.version ?? '';
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            children: [
              Center(
                child: SizedBox(
                  width: 92,
                  height: 92,
                  child: CustomPaint(painter: KayisiCizim(renk: kTuruncu, doluluk: 1)),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'ApriEnglish',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kYazi),
              ),
              const SizedBox(height: 4),
              Text(
                surum.isEmpty ? '' : 'Sürüm $surum',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: kSoluk),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  "A1'den B2'ye 3000 İngilizce kelime. Sana özel programla her gün biraz öğren.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, height: 1.4, color: kSoluk),
                ),
              ),
              const SizedBox(height: 28),
              Material(
                color: kKart,
                child: Column(
                  children: [
                    _satir(
                      ikon: Icons.lock_outline_rounded,
                      ad: 'Gizlilik politikası',
                      onTap: () => baglantiAc(context, Uri.parse(gizlilikAdresi)),
                    ),
                    _cizgi(),
                    _satir(
                      ikon: Icons.delete_outline_rounded,
                      ad: 'Verilerimin silinmesi',
                      onTap: () => baglantiAc(context, Uri.parse(veriSilmeAdresi)),
                    ),
                    _cizgi(),
                    _satir(
                      ikon: Icons.mail_outline_rounded,
                      ad: 'Bize yazın',
                      onTap: () => baglantiAc(
                        context,
                        Uri(scheme: 'mailto', path: iletisimEpostasi),
                      ),
                    ),
                    _cizgi(),
                    _satir(
                      ikon: Icons.description_outlined,
                      ad: 'Açık kaynak lisansları',
                      // Flutter'ın hazır sayfası: kullandığımız paketlerin lisanslarını listeler
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'ApriEnglish',
                        applicationVersion: surum,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                "Malatya'dan sevgilerle",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF7E766E)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _cizgi() => const Divider(height: 1, thickness: 1, indent: 64, color: kCizgi);

  Widget _satir({required IconData ikon, required String ad, required VoidCallback onTap}) {
    return ListTile(
      onTap: onTap,
      minTileHeight: 64,
      contentPadding: const EdgeInsets.only(left: 20, right: 12),
      leading: Icon(ikon, color: kSoluk, size: 26),
      title: Text(
        ad,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: kYazi),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF7E766E)),
    );
  }
}
