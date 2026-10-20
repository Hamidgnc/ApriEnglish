// Kelimelerin sesli okunması.
//
// 1) Önce hazır kayıt: paketteki 3000 kelime Google'ın Chirp 3 HD "Puck" sesiyle
//    önceden seslendirildi (araclar/seslendir.py) ve assets/telaffuz/ içinde duruyor.
//    Hangi kelimenin hangi dosyada olduğu assets/telaffuz/dizin.json'da yazar.
// 2) Kaydı olmayan kelimeler (ör. eskiden kullanıcının eklediği kelimeler) için
//    telefonun ses motoru (TTS) yedek olarak kullanılır: varsa Google motoru,
//    İngilizce yüklü mü kontrolü ve o dildeki en kaliteli ses seçilir.

import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class Telaffuz {
  static final FlutterTts _tts = FlutterTts();
  static final AudioPlayer _oynatici = AudioPlayer();
  static Map<String, String> _dizin = {}; // kelime -> dosya adı
  static Future<void>? _hazirlik;

  // Profil'deki "Kelimeleri otomatik oku" anahtarı; kapalıysa sadece hoparlöre basınca okunur
  static bool otomatik = true;

  // Google'ın ses motorunun paket adı (telefonda "Google Konuşma Hizmetleri")
  static const _googleMotoru = 'com.google.android.tts';

  // Uygulama açılırken bir kez çağrılır; birden çok kez çağrılsa da bir kez çalışır
  static Future<void> hazirla() => _hazirlik ??= _kur();

  static Future<void> _kur() async {
    // Hazır kayıtların listesi
    try {
      final metin = await rootBundle.loadString('assets/telaffuz/dizin.json');
      _dizin = Map<String, String>.from(jsonDecode(metin));
      await _oynatici.setReleaseMode(ReleaseMode.stop);
      debugPrint('TELAFFUZ: dizin yüklendi, ${_dizin.length} kayıt');
    } catch (e) {
      debugPrint('TELAFFUZ: dizin YÜKLENEMEDİ -> $e');
      _dizin = {}; // dosya yoksa her şey TTS ile okunur
    }

    // Yedek: telefonun ses motoru
    try {
      if (Platform.isAndroid) {
        final motorlar = await _tts.getEngines;
        if (motorlar is List && motorlar.contains(_googleMotoru)) {
          await _tts.setEngine(_googleMotoru);
        }
      }

      // Önce Amerikan, yoksa İngiliz İngilizcesi. İkisi de yoksa yine en-US denenir.
      var dil = 'en-US';
      if (await _tts.isLanguageAvailable('en-US') != true &&
          await _tts.isLanguageAvailable('en-GB') == true) {
        dil = 'en-GB';
      }
      await _tts.setLanguage(dil);
      await _enIyiSesiSec(dil);

      await _tts.setSpeechRate(0.45); // Android'de 0.5 normal hız; biraz yavaş, net
      await _tts.setPitch(1.0);
    } catch (_) {
      // Ses motoru bir şeyi desteklemiyorsa varsayılanlarla devam edilir
    }
  }

  // O dildeki sesler arasından en kalitelisini seçer.
  // Android her sese 100 (çok düşük) ile 500 (çok yüksek) arası bir kalite puanı verir.
  // İnternet isteyen sesler biraz geri plana atılır: internet yokken susmasınlar.
  static Future<void> _enIyiSesiSec(String dil) async {
    final sesler = await _tts.getVoices;
    if (sesler is! List) return;

    Map? enIyi;
    var enIyiPuan = -1;
    for (final s in sesler) {
      if (s is! Map) continue;
      final yerel = '${s['locale']}'.replaceAll('_', '-').toLowerCase();
      if (yerel != dil.toLowerCase()) continue;

      var puan = int.tryParse('${s['quality']}') ?? 300;
      final internetli = '${s['network_required']}' == 'true' || '${s['network_required']}' == '1';
      if (internetli) puan -= 50;
      if (puan > enIyiPuan) {
        enIyiPuan = puan;
        enIyi = s;
      }
    }

    if (enIyi != null) {
      await _tts.setVoice({'name': '${enIyi['name']}', 'locale': '${enIyi['locale']}'});
    }
  }

  static Future<void> oku(String metin) async {
    await hazirla();
    await dur(); // önceki okuma bitmeden yenisine geçildiyse sustur

    final dosya = _dizin[metin] ?? _dizin[metin.toLowerCase()];
    debugPrint('TELAFFUZ: "$metin" -> ${dosya ?? "KAYIT YOK"}');
    if (dosya != null) {
      try {
        await _oynatici.play(AssetSource('telaffuz/$dosya'));
        return;
      } catch (e) {
        debugPrint('TELAFFUZ: çalınamadı -> $e');
        // Dosya çalınamazsa aşağıda TTS ile okunur
      }
    }
    await _tts.speak(metin);
  }

  static Future<void> dur() async {
    await _oynatici.stop();
    await _tts.stop();
  }
}
