// Ses efektleri ve titreşim.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

// Ses ve titreşim. Her ekrandan Efekt.dogru() gibi çağrılır;
// açık/kapalı ayarı profilden gelir (Profil > Ses efektleri / Titreşim).
class Efekt {
  static bool ses = true;
  static bool titresim = true;
  // Her ses için ayrı, önceden yüklenmiş bir oynatıcı: basınca beklemeden çalar
  static final Map<String, AudioPlayer> _oynaticilar = {};

  // Uygulama açılırken bir kez çağrılır (main içinde)
  static Future<void> hazirla() async {
    try {
      // Efekt sesi başka sesleri (ör. kelime okuma) kesmesin, onlarla karışsın
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
      );
    } catch (_) {}
    for (final ad in ['dogru', 'yanlis', 'tamam']) {
      try {
        final oynatici = AudioPlayer();
        // Düşük gecikme modu: kısa efektler için yapılmış hızlı oynatıcı (Android SoundPool)
        await oynatici.setPlayerMode(PlayerMode.lowLatency);
        await oynatici.setReleaseMode(ReleaseMode.stop); // bitince silinmesin, tekrar çalınsın
        await oynatici.setSource(AssetSource('sesler/$ad.wav')); // şimdiden belleğe yükle
        _oynaticilar[ad] = oynatici;
      } catch (_) {
        // Ses yüklenemezse uygulama çökmesin; o ses sessizce atlanır
      }
    }
  }

  static Future<void> _cal(String ad) async {
    if (!ses) return;
    final oynatici = _oynaticilar[ad];
    if (oynatici == null) return;
    try {
      await oynatici.stop(); // hâlâ çalıyorsa başa sar
      await oynatici.resume();
    } catch (_) {}
  }

  // Not: lightImpact/heavyImpact gibi ince türler bazı telefonlarda (ör. Samsung)
  // hiç hissedilmiyor. vibrate() her Android telefonda çalışıyor.
  static void titret() {
    if (titresim) HapticFeedback.vibrate();
  }

  static void dogru() {
    titret(); // tek kısa titreşim
    _cal('dogru');
  }

  static void yanlis() {
    titret();
    // Yanlışta iki kez: "bzz-bzz", doğrudan ayırt edilsin
    Future.delayed(const Duration(milliseconds: 120), titret);
    _cal('yanlis');
  }

  static void tamam() {
    titret();
    _cal('tamam');
  }
}
