import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/profile_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyDNJvgzHTc310wf04SG7p5Fx7zUuan_Tns",
        authDomain: "pixsense-eca71.firebaseapp.com",
        projectId: "pixsense-eca71",
        storageBucket: "pixsense-eca71.appspot.com",
        messagingSenderId: "67705534223",
        appId: "1:67705534223:web:fb28110e6e0be94a6eb07a",
        measurementId: "G-5M3XWZFPQV",
      ),
    );

    // Configure Firestore settings
    FirebaseFirestore.instance.settings = Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      sslEnabled: true,
    );
  } catch (e) {
    print('Comprehensive Firebase Initialization Error: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<bool> isUserLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: isUserLoggedIn(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const MaterialApp(
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }

        final isLoggedIn = snapshot.data ?? false;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(primaryColor: Color(0xFF673AB7)),
          home: isLoggedIn ? const DashboardScreen() : const WelcomeScreen(),
        );
      },
    );
  }
}