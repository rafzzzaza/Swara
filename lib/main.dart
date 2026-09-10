import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'providers/download_provider.dart';
import 'providers/home_provider.dart';
import 'providers/player_provider.dart';
import 'providers/playlist_provider.dart';
import 'providers/search_provider.dart';
import 'screens/home_screen.dart';
import 'services/database_service.dart';
import 'services/download_service.dart';
import 'services/music_api_service.dart';
import 'services/youtube_audio_service.dart';

const kSwaraGold = Color(0xFFE5A93C);
const kSwaraBg = Color(0xFF0F0F0F);
const kSwaraSurface = Color(0xFF1E1E1E);
const kSwaraSurfaceHigh = Color(0xFF2A2A2A);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid) {
    await Permission.notification.request();
  }

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.rafapc.music_stream_app.channel.audio',
    androidNotificationChannelName: 'Putar Musik Swara',
    androidNotificationChannelDescription:
        'Menampilkan kontrol playback musik di notifikasi.',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
    notificationColor: kSwaraGold,
  );

  final api = MusicApiService();
  final database = DatabaseService();
  final youtube = YoutubeAudioService();

  runApp(SwaraApp(
    api: api,
    database: database,
    youtube: youtube,
  ));
}

class SwaraApp extends StatelessWidget {
  final MusicApiService api;
  final DatabaseService database;
  final YoutubeAudioService youtube;

  const SwaraApp({
    super.key,
    required this.api,
    required this.database,
    required this.youtube,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlayerProvider(api, youtube)),
        ChangeNotifierProvider(create: (_) => HomeProvider(api)),
        ChangeNotifierProvider(create: (_) => SearchProvider(api)),
        ChangeNotifierProvider(create: (_) => PlaylistProvider(database)),
        ChangeNotifierProvider(
            create: (_) => DownloadProvider(DownloadService(), database)),
      ],
      child: MaterialApp(
        title: 'Swara',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: const HomeScreen(),
      ),
    );
  }

  ThemeData _buildTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: kSwaraGold,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: kSwaraBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: kSwaraBg,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: kSwaraSurface,
        indicatorColor: kSwaraGold.withValues(alpha: 0.18),
        iconTheme: const WidgetStatePropertyAll(IconThemeData(size: 22)),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: Colors.white,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
        thumbColor: Colors.white,
        overlayColor: kSwaraGold.withValues(alpha: 0.2),
        trackHeight: 3,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: kSwaraSurface,
        modalBackgroundColor: kSwaraSurface,
        showDragHandle: true,
        dragHandleColor: Colors.white24,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? kSwaraGold : Colors.white24,
        ),
      ),
    );
  }
}