import 'dart:async';
import 'dart:math' show cos, sqrt, asin;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'home_screen.dart';

class ServiceCheckScreen extends StatefulWidget {
  const ServiceCheckScreen({super.key});

  @override
  State<ServiceCheckScreen> createState() => _ServiceCheckScreenState();
}

class _ServiceCheckScreenState extends State<ServiceCheckScreen> {
  bool _isLoading = true;
  bool _isInServiceArea = false;
  String _message = "Checking your location...";
  Position? _currentPosition;
  Map<String, dynamic>? _matchedArea;

  @override
  void initState() {
    super.initState();
    _checkLocationService();
  }

  Future<void> _checkLocationService() async {
    try {
      // 1. Check if Location Services (GPS) are enabled on the device
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isLoading = false;
          _message = "GPS is turned off. Please enable location services.";
        });
        return;
      }

      // 2. Handle Permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isLoading = false;
            _message = "Location permission denied. KEEVO needs this to find services near you.";
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isLoading = false;
          _message = "Location permissions are permanently denied. Please enable them in your phone settings.";
        });
        return;
      }

      // 3. Get Current Position
      _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      // 4. Fetch and Verify Service Areas
      final serviceAreas =
          await FirebaseFirestore.instance.collection('service_areas').get();

      bool insideArea = false;
      for (var doc in serviceAreas.docs) {
        final data = doc.data();
        double lat = (data['latitude'] as num).toDouble();
        double lon = (data['longitude'] as num).toDouble();
        double radiusKm = (data['radiusKm'] ?? 5).toDouble();

        double distance = _calculateDistance(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          lat,
          lon,
        );

        if (distance <= radiusKm) {
          insideArea = true;
          _matchedArea = data;
          break;
        }
      }

      if (insideArea) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      } else {
        setState(() {
          _isLoading = false;
          _isInServiceArea = false;
          _message = "KEEVO isn't available in your location yet. We're expanding fast!";
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _message = "Something went wrong. Please try again.";
      });
      debugPrint("ServiceCheck Error: $e");
    }
  }

  double _calculateDistance(lat1, lon1, lat2, lon2) {
    const p = 0.017453292519943295; // PI / 180
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) *
            cos(lat2 * p) *
            (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // Distance in km
  }

  Future<void> _changeLocationManually() async {
    setState(() {
      _isInServiceArea = true;
      _message = "Location changed to service area!";
    });

    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff5f5f5),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(color: Color(0xFFFD3C68))
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isInServiceArea ? Icons.check_circle : Icons.location_off,
                    size: 80,
                    color: _isInServiceArea
                        ? Colors.green
                        : const Color(0xFFFD3C68),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      _message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 30),
                  if (!_isInServiceArea)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.map_outlined),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFD3C68),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _changeLocationManually,
                      label: const Text("Change Location Manually"),
                    ),
                  if (!_isInServiceArea)
                    TextButton(
                      onPressed: () => _checkLocationService(),
                      child: const Text("Retry Location Check", style: TextStyle(color: Color(0xFFFD3C68))),
                    ),
                ],
              ),
      ),
    );
  }
}