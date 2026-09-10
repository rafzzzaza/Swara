# Swara

Aplikasi streaming musik Android berbasis Flutter dengan tema gelap-keemasan ala Spotify. Swara menarik data musik **nyata** dari API publik **Deezer**, memutar **audio full-length** lewat pencarian YouTube, dan menampilkan antarmuka kaya carousel (Top Charts, Rilis Terbaru, Rekomendasi, Artis Populer) dengan mini-player melayang dan full-screen player bergradien dinamis dari warna sampul album.

## Fitur

- **Data Real dari Deezer API** — lagu trending, chart global, rilis terbaru, artis populer, genre/mood, dan pencarian ditampilkan tanpa data hardcode.
- **Full Audio via YouTube** — preview Deezer hanya 30 detik, jadi Swara mencari stream audio lengkap di YouTube berdasarkan judul + artis (`youtube_explode_dart`) dan memutar versi penuh. Jika resolusi gagal, otomatis kembali ke preview Deezer.
- **Player lengkap (just_audio)** — kontrol play/pause/next/prev, seek bar real-time dengan durasi sebenarnya, volume, repeat, shuffle, mode "Otomatis" (auto-queue rekomendasi), serta tombol Berikutnya di mini-player.
- **Full-screen player dinamis** — latar gradien diambil dari palet warna sampul album (`palette_generator`), artwork besar, panel "Now Playing" animasi (bar equalizer), indikator sumber audio (Full audio / Preview).
- **Home feed rich** — header sapaan, pill filter mood (Pop, Rock, Chill, dst.), grid akses cepat, carousel horizontal (Top Charts, Rilis Terbaru, Rekomendasi per genre, Artis Populer), skeleton shimmer saat loading, dan error state dengan tombol coba lagi.
- **Mini-player melayang** — artwork, judul dengan efek marquee, progres emas 2px, tombol antrian dan play/pause.
- **Antrian & Rekomendasi** — bottom-sheet antrian dengan rekomendasi dari artis lagu yang sedang diputar.
- **Playlist & Offline** — playlist lokal (SQLite) dan unduhan lagu untuk mode offline.
- **Notifikasi & Background** — kontrol playback di area notifikasi via `audio_service` + `just_audio_background`.

## Teknologi

| Aspek | Pilihan |
| --- | --- |
| Framework | Flutter 3.47 (Dart SDK ^3.13) |
| State management | Provider / ChangeNotifier |
| API musik | Deezer Public API (`api.deezer.com`) via `http` |
| Audio | `just_audio`, `just_audio_background`, `audio_service` |
| Audio full-length | `youtube_explode_dart` (stream audio-only) |
| Penyimpanan lokal | `sqflite` (playlist, riwayat), `path_provider` |
| Unduhan | `dio` |
| Gambar | `cached_network_image`, `palette_generator` |

## Struktur Direktori

```
lib/
├── main.dart                     # Inisialisasi, tema gelap-keemasan, wiring provider
├── models/                       # song, album, artist, genre, playlist
├── services/
│   ├── music_api_service.dart    # Klien Deezer (chart, search, genre, album, artis)
│   ├── youtube_audio_service.dart# Resolver stream audio full dari YouTube
│   ├── download_service.dart     # Unduh MP3 preview untuk offline
│   └── database_service.dart     # SQLite: playlist & riwayat
├── providers/
│   ├── player_provider.dart      # Logika pemutaran, antrian, rekomendasi
│   ├── home_provider.dart        # Data & state feed Beranda
│   ├── search_provider.dart      # Pencarian & saran kategori
│   ├── playlist_provider.dart    # Playlist lokal
│   └── download_provider.dart    # Unduhan & offline
├── screens/
│   ├── home_screen.dart          # Shell 4 tab + feed Beranda (IndexedStack)
│   ├── search_screen.dart        # Pencarian dengan grid kategori
│   ├── player_screen.dart        # Full-screen player bergradien dinamis
│   └── playlist_screen.dart      # Daftar playlist
└── widgets/
    ├── mini_player.dart          # Mini-player melayang
    ├── queue_sheet.dart          # Bottom-sheet antrian
    ├── shimmer.dart              # Skeleton shimmer
    └── marquee_text.dart         # Teks berjalan untuk judul panjang
```

## Menjalankan

### Prasyarat

- Flutter SDK + Android SDK + JDK pada mesin Anda.
- Device Android (atau emulator) untuk menjalankan.

Variabel lingkungan yang digunakan saat build di repository ini:

```powershell
$env:ANDROID_HOME = "C:\src\android-sdk"
$env:JAVA_HOME     = "C:\src\jbr"
$env:Path          = "C:\src\flutter\bin;" + $env:Path
```

### Analisis & Build

```powershell
flutter pub get
flutter analyze
flutter build apk --debug
```

APK hasil build tersedia di:

```
build\app\outputs\flutter-apk\app-debug.apk
```

### Instal ke device

```powershell
adb install -r build\app\outputs\flutter-apk\app-debug.apk
adb shell am start -n com.rafapc.music_stream_app/.MainActivity
```

> Catatan khusus repo ini: `android/app/build.gradle.kts` memakai `compileSdk = 37`
> (salinan platform `android-37` di `C:\src\android-sdk\platforms`) dan
> `MainActivity.kt` mewarisi `AudioServiceActivity` untuk playback di background.

## Cara Kerja Data & Audio

1. **Metadata & katalog**: `MusicApiService` mengambil track/album/artis/genre dari Deezer.
2. **Rekomendasi**: carousel rekomendasi dibangun dari pencarian artis lagu aktif (mis. `"Taylor Swift top"`).
3. **Pemutaran full-length**: `YoutubeAudioService` mencari `"<judul> <artis> official audio"` di YouTube, memilih stream `audio only` (bitrate <= 160 kbps), lalu memainkannya langsung via `just_audio`; hasil di-cache dalam memori. Kalau gagal, jatuh kembali ke preview 30 detik Deezer.
4. **Background playback**: notifikasi media berjalan via `audio_service`; paket aplikasi `com.rafapc.music_stream_app`.

## Peta Pengembangan

Fitur berikut sedang/telah direncanakan:

- [ ] Sistem rekomendasi lokal (riwayat pencarian & pemutaran) + seksi "Top Hits Indonesia" dan "Top Global Hits" di Beranda.
- [ ] Halaman Profil Pengguna & Riwayat Pemutaran (Recent Played).
- [ ] Sinkronisasi cloud ke **Supabase** (Postgres + Auth): tabel `users` dan `play_history`; aktif dengan kredensial `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`. Tanpa kredensial, aplikasi berjalan local-first.

## Lisensi

Dikembangkan untuk keperluan belajar/portofolio. Seluruh data musik hak cipta masing-masing pemiliknya (Deezer / YouTube).