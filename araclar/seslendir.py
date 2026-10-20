"""ApriEnglish seslendirme betiği (Chirp 3 HD sürümü).

lib/paket.dart içindeki bütün İngilizce kelimeleri Google Cloud Text-to-Speech
"Chirp 3: HD" modeliyle, "Puck" sesiyle (Amerikan İngilizcesi) seslendirir,
ffmpeg ile başındaki/sonundaki sessizliği kırpıp kısa MP3'lere çevirir ve
assets/telaffuz/ klasörüne kaydeder. Uygulama hangi kelimenin hangi dosyada
olduğunu assets/telaffuz/dizin.json dosyasından öğrenir.

Kullanım (proje klasöründe, yani kelime_kartlari içinde):
    python araclar/seslendir.py --deneme     -> sadece 5 kelime (önce bunu dene)
    python araclar/seslendir.py              -> bütün kelimeler

API anahtarı koda YAZILMAZ. Google Cloud'da oluşturduğun İLK anahtarı
(ApriEnglish ses betiği) ortam değişkeni olarak ver:
    $env:GOOGLE_TTS_KEY = "anahtarın"

Gerekli program: ffmpeg. Betik yarıda kesilirse tekrar çalıştır: kaldığı yerden devam eder.
"""

import base64
import json
import os
import re
import shutil
import subprocess
import sys
import time
import unicodedata
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

# ---- Ayarlar ----
SES = os.environ.get("TTS_SES", "en-US-Chirp3-HD-Puck")
DIL = "en-US"
AYNI_ANDA = 4  # aynı anda kaç istek
# -----------------

KOK = Path(__file__).resolve().parent.parent
PAKET = KOK / "lib" / "paket.dart"
HEDEF = KOK / "assets" / "telaffuz"
ADRES = "https://texttospeech.googleapis.com/v1/text:synthesize?key="


def kelimeleri_oku():
    metin = PAKET.read_text(encoding="utf-8").split("const dersPlani")[0]
    satirlar = re.findall(
        r"\[\s*'((?:[^'\\]|\\.)*)'\s*,\s*'(?:[^'\\]|\\.)*'\s*,\s*'(?:A1|A2|B1|B2)'\s*\]", metin
    )
    return list(dict.fromkeys(s.replace("\\'", "'") for s in satirlar))


def dosya_adi(kelime):
    # café -> cafe, o'clock -> o_clock, ice cream -> ice_cream
    sade = unicodedata.normalize("NFKD", kelime).encode("ascii", "ignore").decode()
    sade = re.sub(r"[^a-z0-9]+", "_", sade.lower()).strip("_")
    return (sade or "kelime") + ".mp3"


def seslendir(anahtar, kelime):
    """Google'dan WAV (24 kHz, 16 bit) olarak ses alır."""
    govde = {
        "input": {"text": kelime},
        "voice": {"languageCode": DIL, "name": SES},
        "audioConfig": {"audioEncoding": "LINEAR16", "sampleRateHertz": 24000},
    }
    istek = urllib.request.Request(
        ADRES + anahtar,
        data=json.dumps(govde).encode(),
        headers={"Content-Type": "application/json"},
    )
    bekleme = 5
    for deneme in range(8):
        try:
            with urllib.request.urlopen(istek, timeout=60) as yanit:
                veri = json.loads(yanit.read())
            return base64.b64decode(veri["audioContent"])
        except urllib.error.HTTPError as hata:
            ayrinti = hata.read().decode(errors="ignore")
            if hata.code in (429, 500, 502, 503, 504) and deneme < 7:
                time.sleep(bekleme)
                bekleme = min(bekleme * 2, 120)
                continue
            raise RuntimeError(f"HTTP {hata.code}: {ayrinti[:600]}") from None
        except (urllib.error.URLError, TimeoutError):
            if deneme < 7:
                time.sleep(bekleme)
                bekleme = min(bekleme * 2, 120)
                continue
            raise


def mp3_yap(wav, hedef):
    """Baştaki/sondaki sessizliği kırpar, küçük bir MP3'e çevirir. Süreyi (sn) döndürür."""
    kirp = (
        "silenceremove=start_periods=1:start_threshold=-45dB,"
        "areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
        "adelay=60,apad=pad_dur=0.15"
    )
    sonuc = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-i", "pipe:0",
         "-af", kirp, "-ac", "1", "-codec:a", "libmp3lame", "-b:a", "48k", str(hedef)],
        input=wav, capture_output=True,
    )
    if sonuc.returncode != 0:
        raise RuntimeError("ffmpeg hatası: " + sonuc.stderr.decode(errors="ignore")[:300])
    return max(0, len(wav) - 44) / 48000  # 24000 örnek/sn x 2 bayt


def main():
    anahtar = os.environ.get("GOOGLE_TTS_KEY", "").strip()
    if not anahtar:
        sys.exit('API anahtarı yok. Önce şunu çalıştır:  $env:GOOGLE_TTS_KEY = "anahtarın"')
    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg bulunamadı. Kur: winget install Gyan.FFmpeg  (sonra VS Code'u kapatıp aç)")

    kelimeler = kelimeleri_oku()
    if "--deneme" in sys.argv:
        kelimeler = ["apricot", "chicken", "comfortable", "thought", "good morning"]
    HEDEF.mkdir(parents=True, exist_ok=True)

    dizin_yolu = HEDEF / "dizin.json"
    dizin = json.loads(dizin_yolu.read_text(encoding="utf-8")) if dizin_yolu.exists() else {}
    for k in kelimeler:
        if (HEDEF / dosya_adi(k)).exists():
            dizin[k] = dosya_adi(k)
    yapilacak = [k for k in kelimeler if not (HEDEF / dosya_adi(k)).exists()]
    print(f"Ses: {SES}")
    print(f"Toplam {len(kelimeler)} kelime, {len(yapilacak)} tanesi seslendirilecek.")

    def kaydet():
        dizin_yolu.write_text(json.dumps(dizin, ensure_ascii=False, indent=0), encoding="utf-8")

    sureler = {}
    hatalar = []
    biten = 0
    durdur = False
    with ThreadPoolExecutor(max_workers=AYNI_ANDA) as havuz:
        isler = {havuz.submit(seslendir, anahtar, k): k for k in yapilacak}
        for is_ in as_completed(isler):
            kelime = isler[is_]
            try:
                sureler[kelime] = mp3_yap(is_.result(), HEDEF / dosya_adi(kelime))
                dizin[kelime] = dosya_adi(kelime)
                biten += 1
                if biten % 50 == 0 or len(yapilacak) <= 10:
                    print(f"  {biten}/{len(yapilacak)}  ({kelime})")
                    kaydet()
            except Exception as hata:
                hatalar.append((kelime, str(hata)))
                print(f"  HATA '{kelime}': {hata}")
                if any(k in str(hata) for k in ("HTTP 400", "HTTP 401", "HTTP 402", "HTTP 403", "HTTP 404")):
                    print("Ayar/yetki hatası; betik durduruluyor. Hata mesajını Claude'a gönder.")
                    durdur = True
            if durdur:
                havuz.shutdown(cancel_futures=True)
                break
    kaydet()

    supheli = [k for k, s in sureler.items() if s > 2.5 + 0.6 * k.count(" ")]
    if supheli:
        rapor = KOK / "araclar" / "telaffuz_kontrol.txt"
        eski = rapor.read_text(encoding="utf-8").splitlines() if rapor.exists() else []
        rapor.write_text("\n".join(dict.fromkeys(eski + supheli)), encoding="utf-8")
        print(f"{len(supheli)} kelime şüpheli uzunlukta: araclar/telaffuz_kontrol.txt dosyasına bak.")

    print(f"Bitti. Başarılı: {biten}, hata: {len(hatalar)}, toplam dosya: {len(dizin)}")
    if hatalar and not durdur:
        print("Hatalı kelimeler için betiği tekrar çalıştırman yeterli.")


if __name__ == "__main__":
    main()
