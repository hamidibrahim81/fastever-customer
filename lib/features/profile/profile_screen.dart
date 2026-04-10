import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../home/home_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  bool _saving = false;
  bool _gettingLocation = false;

  @override
  void initState() {
    super.initState();
    _phoneController.text = FirebaseAuth.instance.currentUser?.phoneNumber ?? "";
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  // -------------------------
  // 📍 LOGIC: GET GPS LOCATION
  // -------------------------
  Future<void> _getLocation() async {
    setState(() => _gettingLocation = true);

    // 1. Check Service
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar("Location services are disabled.", isError: true);
      setState(() => _gettingLocation = false);
      return;
    }

    // 2. Check Permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar("Location permissions are denied.", isError: true);
        setState(() => _gettingLocation = false);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnackBar("Location permissions are permanently denied.", isError: true);
      setState(() => _gettingLocation = false);
      return;
    }

    // 3. Get Position & Format Link
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      setState(() {
        // ✅ FIX: Correct Google Maps Universal Link format
        _locationController.text = 
            "https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}";
      });
      
      _showSnackBar("Location fetched!", isError: false);
    } catch (e) {
      _showSnackBar("Failed to get location.");
    } finally {
      setState(() => _gettingLocation = false);
    }
  }

  // -------------------------
  // 💾 LOGIC: SAVE TO FIRESTORE
  // -------------------------
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Validation: Ensure location is fetched
    if (_locationController.text.isEmpty) {
      _showSnackBar("Please tap the GPS icon to get your location.");
      return;
    }

    setState(() => _saving = true);

    final uid = FirebaseAuth.instance.currentUser!.uid;
    
    try {
      // ✅ FIX: Use SetOptions(merge: true) to prevent wiping other data
      await FirebaseFirestore.instance.collection("users").doc(uid).set({
        "name": _nameController.text.trim(),
        "address": _addressController.text.trim(),
        "phone": _phoneController.text.trim(), // Keep phone in sync
        "location": _locationController.text.trim(),
        "updatedAt": FieldValue.serverTimestamp(),
        // Only set createdAt if it doesn't exist (handled by merge)
      }, SetOptions(merge: true)); 
      
      if (!mounted) return;

      // Success -> Go Home
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      _showSnackBar("Failed to save profile. Try again.");
    } finally {
      setState(() => _saving = false);
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // -------------------------
  // 🎨 UI DESIGN
  // -------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Complete Profile", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "Tell us about yourself",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "We need these details to deliver your orders.",
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
                const SizedBox(height: 30),

                // Name Input
                _buildTextFormField(
                  controller: _nameController,
                  labelText: "Full Name",
                  icon: Icons.person_outline,
                  validator: (val) => val!.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 16),

                // Address Input
                _buildTextFormField(
                  controller: _addressController,
                  labelText: "Home Address",
                  icon: Icons.home_outlined,
                  validator: (val) => val!.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 16),

                // Phone (Read Only)
                _buildTextFormField(
                  controller: _phoneController,
                  labelText: "Phone Number",
                  icon: Icons.phone_android,
                  readOnly: true,
                ),
                const SizedBox(height: 16),

                // Location Input (With Button)
                TextFormField(
                  controller: _locationController,
                  readOnly: true,
                  validator: (val) => val!.isEmpty ? "Location required" : null,
                  decoration: InputDecoration(
                    labelText: "Delivery Location",
                    prefixIcon: const Icon(Icons.map_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey[50],
                    suffixIcon: IconButton(
                      icon: _gettingLocation
                          ? const SizedBox(
                              width: 20, 
                              height: 20, 
                              child: CircularProgressIndicator(strokeWidth: 2)
                            )
                          : const Icon(Icons.my_location, color: Colors.blueAccent),
                      onPressed: _gettingLocation ? null : _getLocation,
                    ),
                  ),
                ),
                
                const SizedBox(height: 40),

                // Save Button
                SizedBox(
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black, // Premium Black
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            "Save & Continue", 
                            style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    String? Function(String?)? validator,
    bool readOnly = false,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      validator: validator,
      decoration: InputDecoration(
        labelText: labelText,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: readOnly ? Colors.grey[200] : Colors.grey[50],
      ),
    );
  }
}