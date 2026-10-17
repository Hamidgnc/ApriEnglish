// Kodla çizilen resimler: kayısı, seri halkası, ders kartı manzarası.

import 'dart:math';

import 'package:flutter/material.dart';

import '../tema.dart';

// Kodla çizilen kayısı. doluluk: 0 = içi boş, 1 = içi tamamen turuncu
class KayisiCizim extends CustomPainter {
  final Color renk;
  final double doluluk;

  KayisiCizim({required this.renk, this.doluluk = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cizgi = Paint()
      ..color = renk
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round;

    final govde = Rect.fromLTWH(w * 0.05, h * 0.22, w * 0.90, h * 0.74);
    if (doluluk > 0) {
      canvas.drawOval(govde, Paint()..color = renk.withValues(alpha: doluluk));
    }
    canvas.drawOval(govde, cizgi);

    canvas.drawArc(
      Rect.fromLTWH(w * 0.25, h * 0.22, w * 0.32, h * 0.66),
      -pi / 2,
      0.95,
      false,
      cizgi,
    );

    canvas.drawLine(Offset(w * 0.49, h * 0.23), Offset(w * 0.53, h * 0.08), cizgi);

    canvas.save();
    canvas.translate(w * 0.53, h * 0.08);
    canvas.rotate(-0.45);
    canvas.drawOval(Rect.fromLTWH(0, -h * 0.06, w * 0.34, h * 0.12), cizgi);
    canvas.restore();
  }

  @override
  bool shouldRepaint(KayisiCizim old) =>
      old.renk != renk || old.doluluk != doluluk;
}

// Ana sayfadaki seri halkası. oran: 0 = boş, 1 = tam dolu
class HalkaCizim extends CustomPainter {
  final double oran;

  HalkaCizim(this.oran);

  @override
  void paint(Canvas canvas, Size size) {
    const kalinlik = 10.0;
    final merkez = Offset(size.width / 2, size.height / 2);
    final yaricap = size.width / 2 - kalinlik / 2;
    final kalem = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kalinlik
      ..strokeCap = StrokeCap.round;
    // Önce gri zemin halkası, sonra üstüne turuncu ilerleme yayı
    canvas.drawCircle(merkez, yaricap, kalem..color = kCizgi);
    if (oran > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: merkez, radius: yaricap),
        -pi / 2, // saat 12 yönünden başla
        2 * pi * oran,
        false,
        kalem..color = kTuruncu,
      );
    }
  }

  @override
  bool shouldRepaint(HalkaCizim old) => old.oran != oran;
}

// Ders kartındaki manzara: gökyüzü, güneş, tepeler ve kayısı ağaçları.
// Her seviyenin gökyüzü farklı: A1 gün batımı, A2 öğle, B1 gece, B2 şafak.
class ManzaraCizim extends CustomPainter {
  final String duzey;

  ManzaraCizim(this.duzey);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final (List<Color> gok, Color gunes, Color tepe1, Color tepe2) = switch (duzey) {
      'A2' => (
          const [Color(0xFF2F6FA8), Color(0xFF7FB6DA), Color(0xFFE6D3A3)],
          const Color(0xFFFFF1B8),
          const Color(0xFF4F6B3A),
          const Color(0xFF2E3F24),
        ),
      'B1' => (
          const [Color(0xFF0B1030), Color(0xFF1F2A5C), Color(0xFF3E3F7A)],
          const Color(0xFFE9E6D0),
          const Color(0xFF2A2848),
          const Color(0xFF17162B),
        ),
      'B2' => (
          const [Color(0xFF16323F), Color(0xFF3B7482), Color(0xFFF0BE96)],
          const Color(0xFFFFE6B8),
          const Color(0xFF35524F),
          const Color(0xFF1C2C2A),
        ),
      _ => (
          const [Color(0xFF2B2240), Color(0xFF8E4A58), Color(0xFFE9955A)],
          const Color(0xFFFFCF8A),
          const Color(0xFF5E3437),
          const Color(0xFF33231F),
        ),
    };

    // Gökyüzü: yukarıdan aşağı renk geçişi
    final gokBoya = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: gok,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, gokBoya);

    // Güneş (B1'de ay)
    canvas.drawCircle(Offset(w * 0.74, h * 0.56), w * 0.10, Paint()..color = gunes);

    // Arkadaki sivri dağlar
    final dag = Path()
      ..moveTo(0, h * 0.68)
      ..lineTo(w * 0.18, h * 0.50)
      ..lineTo(w * 0.35, h * 0.63)
      ..lineTo(w * 0.55, h * 0.43)
      ..lineTo(w * 0.77, h * 0.65)
      ..lineTo(w, h * 0.53)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(dag, Paint()..color = tepe1);

    // Öndeki yumuşak tepe
    final tepe = Path()
      ..moveTo(0, h * 0.79)
      ..quadraticBezierTo(w * 0.25, h * 0.69, w * 0.5, h * 0.77)
      ..quadraticBezierTo(w * 0.75, h * 0.84, w, h * 0.74)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(tepe, Paint()..color = tepe2);

    // İki kayısı ağacı
    agac(canvas, Offset(w * 0.18, h * 0.76), w * 0.068);
    agac(canvas, Offset(w * 0.82, h * 0.77), w * 0.058);
  }

  void agac(Canvas canvas, Offset kok, double r) {
    canvas.drawRect(
      Rect.fromLTWH(kok.dx - r * 0.15, kok.dy - r * 0.4, r * 0.3, r * 1.1),
      Paint()..color = const Color(0xFF21160F),
    );
    final tepe = Offset(kok.dx, kok.dy - r);
    canvas.drawCircle(tepe, r, Paint()..color = const Color(0xFF2E4A33));
    final meyve = Paint()..color = kTuruncu;
    canvas.drawCircle(tepe + Offset(-r * 0.4, -r * 0.25), r * 0.18, meyve);
    canvas.drawCircle(tepe + Offset(r * 0.35, r * 0.05), r * 0.18, meyve);
    canvas.drawCircle(tepe + Offset(-r * 0.05, r * 0.4), r * 0.18, meyve);
  }

  @override
  bool shouldRepaint(ManzaraCizim old) => old.duzey != duzey;
}
