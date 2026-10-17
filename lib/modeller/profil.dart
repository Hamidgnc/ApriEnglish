// Kullanıcının profili ve ayarları (ad, avatar, hedef, program, ses...).

// Kullanıcının bilgileri ve ayarları
class Profil {
  String ad;
  String avatar;
  int hedef; // günlük kelime hedefi
  bool bildirim; // günlük hatırlatma açık mı
  int saat;
  int dakika;
  String amac; // neden öğreniyor (okul, is, seyahat, dizi, kendim)
  int sure; // günde kaç dakika ayırabilir (5, 10, 15, 30)
  String zaman; // ne zaman çalışmayı sever (sabah, ogle, aksam, gece)
  String programBaslangic; // programa başlanan gün (yyyy-aa-gg), boşsa henüz yok
  String planBitis; // plan yapıldığı gün hesaplanan bitiş; önde/geride kıyası için
  bool ses; // ses efektleri açık mı
  bool titresim; // titreşim açık mı

  Profil({
    this.ad = '',
    this.avatar = '🧑',
    this.hedef = 10,
    this.bildirim = false,
    this.saat = 20,
    this.dakika = 0,
    this.amac = '',
    this.sure = 10,
    this.zaman = 'aksam',
    this.programBaslangic = '',
    this.planBitis = '',
    this.ses = true,
    this.titresim = true,
  });

  // Hesabım sayfası bir kopya üzerinde çalışır; Kaydet'e basılmazsa asıl profil değişmez
  Profil kopya() => Profil(
        ad: ad,
        avatar: avatar,
        hedef: hedef,
        bildirim: bildirim,
        saat: saat,
        dakika: dakika,
        amac: amac,
        sure: sure,
        zaman: zaman,
        programBaslangic: programBaslangic,
        planBitis: planBitis,
        ses: ses,
        titresim: titresim,
      );

  Map<String, dynamic> toJson() => {
        'ad': ad,
        'avatar': avatar,
        'hedef': hedef,
        'bildirim': bildirim,
        'saat': saat,
        'dakika': dakika,
        'amac': amac,
        'sure': sure,
        'zaman': zaman,
        'programBaslangic': programBaslangic,
        'planBitis': planBitis,
        'ses': ses,
        'titresim': titresim,
      };

  // Eski kayıtlarda yeni alanlar yok: ?? ile varsayılan değer veriyoruz (migration)
  factory Profil.fromJson(Map<String, dynamic> j) => Profil(
        ad: j['ad'] ?? '',
        avatar: j['avatar'] ?? '🧑',
        hedef: j['hedef'] ?? 10,
        bildirim: j['bildirim'] ?? false,
        saat: j['saat'] ?? 20,
        dakika: j['dakika'] ?? 0,
        amac: j['amac'] ?? '',
        sure: j['sure'] ?? 10,
        zaman: j['zaman'] ?? 'aksam',
        programBaslangic: j['programBaslangic'] ?? '',
        planBitis: j['planBitis'] ?? '',
        ses: j['ses'] ?? true,
        titresim: j['titresim'] ?? true,
      );
}
