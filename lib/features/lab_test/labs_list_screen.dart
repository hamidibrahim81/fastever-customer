import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../notification/notificationscreen.dart';
import 'lab_test_booking_screen.dart';

class LabsListScreen extends StatefulWidget {
  const LabsListScreen({super.key});

  @override
  State<LabsListScreen> createState() => _LabsListScreenState();
}

class _LabsListScreenState extends State<LabsListScreen> {
  Position? _currentPosition;
  bool _isLoadingPosition = true;

  static const Color primaryColor = Color(0xFF111827);
  static const Color accentColor = Color(0xFFFF4D6D);
  static const Color themePurple = Color(0xFF7E22CE);
  static const Color backgroundColor = Color(0xFFF6F6F9);
  static const Color textDark = Color(0xFF1F2937);
  static const Color textLight = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _isLoadingPosition = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isLoadingPosition = false);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _isLoadingPosition = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching location: $e");
      if (mounted) setState(() => _isLoadingPosition = false);
    }
  }

  double _calculateDistance(dynamic latVal, dynamic lngVal) {
    if (_currentPosition == null) return 0.0;
    try {
      double labLat = double.tryParse(latVal.toString()) ?? 0.0;
      double labLng = double.tryParse(lngVal.toString()) ?? 0.0;
      if (labLat == 0.0 || labLng == 0.0) return 0.0;

      double distanceInMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        labLat,
        labLng,
      );
      return distanceInMeters / 1000;
    } catch (_) {
      return 0.0;
    }
  }

  void _navigateToBooking(BuildContext context, Map<String, dynamic> labData) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LabTestBookingScreen(selectedLab: labData),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 6,
        shadowColor: Colors.black.withOpacity(0.3),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Nearby Diagnostic Labs 🔬",
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: const [
          NotificationBellIconButton(),
          SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _isLoadingPosition
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: themePurple),
                    SizedBox(height: 12),
                    Text(
                      "Locating nearby labs...",
                      style: TextStyle(
                          color: textLight,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )
            : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('labs').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: themePurple));
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Text(
                        "No diagnostic labs available right now.",
                        style: TextStyle(
                            fontSize: 14,
                            color: textLight,
                            fontWeight: FontWeight.bold),
                      ),
                    );
                  }

                  final docs = snapshot.data!.docs;

                  List<Map<String, dynamic>> labsList = docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    double distance = _calculateDistance(
                        data['latitude'], data['longitude']);

                    return {
                      'centre_id': data['centre_id'] ?? doc.id,
                      'name': data['name'] ?? 'Diagnostic Lab',
                      'location': data['location'] ?? 'Available',
                      'latitude': data['latitude'] ?? '',
                      'longitude': data['longitude'] ?? '',
                      'image': data['image'] ?? '',
                      'services': List<String>.from(data['services'] ?? []),
                      'distance_km': distance,
                    };
                  }).toList();

                  if (_currentPosition != null) {
                    labsList.sort((a, b) => (a['distance_km'] as double)
                        .compareTo(b['distance_km'] as double));
                  }

                  return ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(20.0),
                    itemCount: labsList.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 18),
                    itemBuilder: (context, index) {
                      final lab = labsList[index];
                      final String name = lab['name'];
                      final String location = lab['location'];
                      final String imageUrl = lab['image'];
                      final double distanceKm = lab['distance_km'];
                      final List<String> services = lab['services'];

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(color: Colors.black.withOpacity(0.05)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: InkWell(
                            onTap: () => _navigateToBooking(context, lab),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Lab Cover Header Image
                                SizedBox(
                                  height: 160,
                                  width: double.infinity,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: imageUrl.isNotEmpty
                                            ? Image.network(
                                                imageUrl,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    Container(
                                                  color: themePurple.withOpacity(0.1),
                                                  child: const Icon(
                                                      Icons.science_rounded,
                                                      size: 50,
                                                      color: themePurple),
                                                ),
                                              )
                                            : Container(
                                                color: themePurple.withOpacity(0.1),
                                                child: const Icon(
                                                    Icons.science_rounded,
                                                    size: 50,
                                                    color: themePurple),
                                              ),
                                      ),

                                      // Distance Badge Overlay
                                      if (_currentPosition != null && distanceKm > 0)
                                        Positioned(
                                          top: 12,
                                          right: 12,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: primaryColor.withOpacity(0.9),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.near_me_rounded,
                                                    color: accentColor, size: 14),
                                                const SizedBox(width: 4),
                                                Text(
                                                  "${distanceKm.toStringAsFixed(1)} km away",
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),

                                // Lab Info Details
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  name,
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: primaryColor,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    const Icon(
                                                        Icons.location_on_rounded,
                                                        size: 15,
                                                        color: accentColor),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      location.toUpperCase(),
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: textDark,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),

                                                // Clean single-line count indicator instead of chips
                                                Row(
                                                  children: [
                                                    const Icon(
                                                        Icons.medical_services_outlined,
                                                        size: 14,
                                                        color: themePurple),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      services.isNotEmpty
                                                          ? "${services.length}+ tests available"
                                                          : "Tests available",
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: themePurple,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: primaryColor,
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 16, vertical: 10),
                                            ),
                                            onPressed: () =>
                                                _navigateToBooking(context, lab),
                                            child: const Text(
                                              "Book Test ➔",
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}