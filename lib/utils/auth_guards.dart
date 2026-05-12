import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fastevergo_v1/main.dart'; 
import 'package:fastevergo_v1/features/auth/login_screen.dart';
import 'package:google_fonts/google_fonts.dart';

bool requireLoginGlobal(String message) {
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) return true;

  final context = appNavigatorKey.currentContext;
  if (context == null) return false;

  // Use a BottomSheet instead of a SnackBar. 
  // It is immune to the "Deactivated Widget" error.
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1E43),
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_person_rounded, color: Colors.white, size: 50),
          const SizedBox(height: 16),
          Text(
            "Login Required",
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1A1E43),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(context); // Close sheet
                appNavigatorKey.currentState?.push(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              child: const Text("LOGIN NOW", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Maybe Later", style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    ),
  );

  return false;
}