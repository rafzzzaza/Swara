import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/auth_provider.dart';
import 'providers/download_provider.dart';
import 'providers/history_provider.dart';
import 'providers/home_provider.dart';
import 'providers/player_provider.dart';
import 'providers/playlist_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/search_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/cloud_service.dart';
import 'services/database_service.dart';
import 'services/audio_resolver.dart';
import 'services/download_service.dart';
import 'services/history_service.dart';
import 'services/music_api_service.dart';
import 'services/recommendation_service.dart';
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

  // Login online Supabase (no-op bila kredensial tidak diberikan).
  await AuthService.initialize();

  final api = MusicApiService();
  final database = DatabaseService();
  final youtube = YoutubeAudioService();
  final resolver = AudioResolver(youtube: youtube);
  final prefs = await SharedPreferences.getInstance();
  final rec = RecommendationService(prefs);
  final cloud = CloudService();
  final auth = AuthProvider(AuthService());
  final deviceId = _ensureDeviceId(prefs);
  final historyService = HistoryService(database, cloud, deviceId);

  runApp(SwaraApp(
    api: api,
    database: database,
    resolver: resolver,
    rec: rec,
    cloud: cloud,
    prefs: prefs,
    deviceId: deviceId,
    historyService: historyService,
    authProvider: auth,
  ));
}

String _ensureDeviceId(SharedPreferences prefs) {
  const key = 'swara_device_id';
  final existing = prefs.getString(key);
  if (existing != null && existing.isNotEmpty) return existing;
  final id =
      'user_${DateTime.now().millisecondsSinceEpoch}_${1000 + math.Random().nextInt(9000)}';
  prefs.setString(key, id);
  return id;
}

class SwaraApp extends StatelessWidget {
  final MusicApiService api;
  final DatabaseService database;
  final AudioResolver resolver;
  final RecommendationService rec;
  final CloudService cloud;
  final SharedPreferences prefs;
  final String deviceId;
  final HistoryService historyService;
  final AuthProvider authProvider;

  const SwaraApp({
    super.key,
    required this.api,
    required this.database,
    required this.resolver,
    required this.rec,
    required this.cloud,
    required this.prefs,
    required this.deviceId,
    required this.historyService,
    required this.authProvider,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider(
            create: (_) => PlayerProvider(api, resolver, rec, historyService)),
        ChangeNotifierProvider(create: (_) => HomeProvider(api, rec)),
        ChangeNotifierProvider(create: (_) => SearchProvider(api, rec)),
        ChangeNotifierProvider(create: (_) => PlaylistProvider(database)),
        ChangeNotifierProvider(
            create: (_) => DownloadProvider(DownloadService(resolver), database)),
        ChangeNotifierProvider(create: (_) => HistoryProvider(historyService)),
        ChangeNotifierProvider(
            create: (_) =>
                ProfileProvider(prefs, cloud, deviceId: deviceId)..load()),
        Provider<RecommendationService>.value(value: rec),
        Provider<CloudService>.value(value: cloud),
      ],
      child: MaterialApp(
        title: 'Swara',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: const SwaraRoot(),
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

/// Gerbang masuk aplikasi: layar login online bila diperlukan,
/// sebaliknya langsung ke Beranda (mode tamu / sudah login).
class SwaraRoot extends StatefulWidget {
  const SwaraRoot({super.key});

  @override
  State<SwaraRoot> createState() => _SwaraRootState();
}

class _SwaraRootState extends State<SwaraRoot> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.initialized) {
      return const Scaffold(
        backgroundColor: kSwaraBg,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (auth.onlineEnabled && !auth.isGuest && auth.user == null) {
      return const AuthScreen();
    }
    return const HomeScreen();
  }
}