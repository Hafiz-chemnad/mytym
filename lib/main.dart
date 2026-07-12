import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// --- Modular Screen / Service Imports ---
import 'package:whatsapp_erp/features/auth/screens/login_screen.dart';
import 'package:whatsapp_erp/features/auth/services/auth_db_service.dart';
import 'package:whatsapp_erp/features/dashboard/screens/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  MediaKit.ensureInitialized();

  // 🎥 Redirects video_player (used by VideoBubble) to media_kit on desktop
  VideoPlayerMediaKit.ensureInitialized(
    windows: true,
    linux: true,
  );

  // 🎵 Redirects just_audio (used by AudioBubble) to media_kit on desktop
  JustAudioMediaKit.ensureInitialized(
    windows: true,
    linux: true,
  );

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        useMaterial3: true,
        fontFamily: 'Roboto',
        fontFamilyFallback: const [
          'Apple Color Emoji',
          'Segoe UI Emoji',
          'Segoe UI Symbol',
          'Noto Color Emoji',
        ],
      ),
      home: FutureBuilder<String?>(
        // 🚀 Use the new Modular Auth DB Service instead of DatabaseHelper
        future: AuthDbService.instance.getSessionRestaurantId(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final savedId = snapshot.data;
          return (savedId != null)
              ? DashboardScreen(restaurantId: savedId)
              : const LoginScreen();
        },
      ),
    );
  }
}

