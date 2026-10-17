// Kelime modeli ve kelimenin olgunlaşma aşamalarıyla ilgili yardımcılar.

import 'package:flutter/material.dart';

class Kelime {
  String ing;
  String anlam;
  int yanlis;
  int seviye; // 0 = ham, 1-2 = yarı olgun, 3 = kurutmada, 4 = kuru kayısı
  String? tekrar; // bir sonraki tekrar günü (yyyy-aa-gg), yoksa null
  String duzey; // A1, A2, B1 ya da Benim (kendi eklediklerin)

  Kelime({
    required this.ing,
    required this.anlam,
    this.yanlis = 0,
    this.seviye = 0,
    this.tekrar,
    this.duzey = 'Benim',
  });

  Map<String, dynamic> toJson() {
    return {
      'ing': ing,
      'anlam': anlam,
      'yanlis': yanlis,
      'seviye': seviye,
      'tekrar': tekrar,
      'duzey': duzey,
    };
  }

  factory Kelime.fromJson(Map<String, dynamic> json) {
    return Kelime(
      ing: json['ing'],
      anlam: json['anlam'],
      yanlis: json['yanlis'],
      seviye: json['seviye'] ?? 0, // eski kayıtlarda seviye yok -> 0
      tekrar: json['tekrar'], // eski kayıtlarda yok -> null
      duzey: json['duzey'] ?? 'Benim', // eski kayıtlarda yok -> Benim
    );
  }
}

// Aşamaya göre kayısı renkleri: [iç (parlak), dış (koyu)]
List<Color> durumRenkleri(int seviye) {
  if (seviye >= 4) return const [Color(0xFFC98A4B), Color(0xFF8A4F22)]; // kuru
  if (seviye == 3) return const [Color(0xFFFFC45C), Color(0xFFEC7020)]; // kurutmada
  if (seviye >= 1) return const [Color(0xFFFFEB8C), Color(0xFFE1BE3C)]; // yarı
  return const [Color(0xFFC8E68C), Color(0xFF82B450)]; // ham
}

String durumAdi(int seviye) {
  if (seviye >= 4) return 'kuru kayısı';
  if (seviye == 3) return 'kurutmada';
  if (seviye >= 1) return 'yarı olgun';
  return 'ham';
}

// Filtre için grup: 0 ham, 1 yarı, 3 kurutmada, 4 kuru
int durumGrubu(int seviye) {
  if (seviye >= 4) return 4;
  if (seviye == 3) return 3;
  if (seviye >= 1) return 1;
  return 0;
}
