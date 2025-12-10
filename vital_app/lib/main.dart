import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'screens/user_type_selection_screen.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Load environment variables
    await dotenv.load(fileName: ".env");

    // Initialize Gemini with API key from .env
    final apiKey = dotenv.env['API_KEY'];
    if (apiKey != null &&
        apiKey.isNotEmpty &&
        apiKey != 'your_gemini_api_key_here') {
      try {
        Gemini.init(apiKey: apiKey);
      } catch (e) {
        // Log error but don't crash the app
        debugPrint('Warning: Failed to initialize Gemini: $e');
        debugPrint(
          'Chat functionality may not work. Please check your API_KEY in .env file.',
        );
      }
    } else {
      debugPrint('Warning: API_KEY not found or invalid in .env file.');
      debugPrint(
        'Chat functionality will not work. Please set API_KEY=your_actual_api_key in .env file.',
      );
    }
  } catch (e) {
    // If .env file doesn't exist or can't be loaded, log warning
    debugPrint('Warning: Could not load .env file: $e');
    debugPrint(
      'Chat functionality will not work. Please create a .env file with API_KEY=your_actual_api_key',
    );
  }

  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vital App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        // Show loading indicator while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // If user is logged in, we need to check their type and show appropriate screen
        // For now, show user type selection - the login flow will handle navigation
        // Note: In a production app, you'd store the user type in shared preferences
        // or check it from Firestore to auto-navigate to the correct screen
        return const UserTypeSelectionScreen();
      },
    );
  }
}
