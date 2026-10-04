import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../notification/notificationscreen.dart';
import 'tourist_bus_booking_form_screen.dart';

class TouristBusesScreen extends StatelessWidget {
  const TouristBusesScreen({super.key});

  // Theme Color Tokens
  static const Color primaryColor = Color(0xFF111827);
  static const Color accentColor = Color(0xFFFF4D6D);
  static const Color backgroundColor = Color(0xFFF7F8FA);
  static const Color textDark = Color(0xFF1F2937);
  static const Color textLight = Color(0xFF6B7280);

  void _navigateToBooking(BuildContext context, Map<String, dynamic> busData) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TouristBusBookingFormScreen(
          selectedBus: busData,
        ),
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
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(24),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Tourist Buses 🚌",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        actions: const [
          NotificationBellIconButton(),
          SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          // Fetches live documents directly from the `tourist_bus` collection in Firestore
          stream: FirebaseFirestore.instance.collection('tourist_bus').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: accentColor),
              );
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(
                child: Text(
                  "No tourist buses available right now.",
                  style: TextStyle(
                    fontSize: 14,
                    color: textLight,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }

            final busDocs = snapshot.data!.docs;

            return ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(20.0),
              itemCount: busDocs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 20),
              itemBuilder: (context, index) {
                final doc = busDocs[index];
                final data = doc.data() as Map<String, dynamic>;

                final String busName = data['name'] ?? 'Tourist Bus';
                final String busLocation = data['location'] ?? 'Available';
                final String imageUrl = data['image'] ?? '';
                final String centreId = data['centre_id'] ?? doc.id;

                final Map<String, dynamic> formattedBusData = {
                  'id': centreId,
                  'title': busName,
                  'location': busLocation,
                  'image': imageUrl,
                };

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Prominent Bus Image Section at Top
                        SizedBox(
                          height: 180,
                          width: double.infinity,
                          child: imageUrl.isNotEmpty
                              ? Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Image.asset(
                                    'assets/instahub/torist.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: backgroundColor,
                                      child: const Icon(
                                        Icons.directions_bus_rounded,
                                        size: 60,
                                        color: primaryColor,
                                      ),
                                    ),
                                  ),
                                )
                              : Image.asset(
                                  'assets/instahub/torist.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: backgroundColor,
                                    child: const Icon(
                                      Icons.directions_bus_rounded,
                                      size: 60,
                                      color: primaryColor,
                                    ),
                                  ),
                                ),
                        ),

                        // 2. Bus Details & Booking Action Section under the image
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          busName,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: primaryColor,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.location_on_rounded,
                                              size: 16,
                                              color: accentColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              busLocation.toUpperCase(),
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: textDark,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  // Book Bus Button
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryColor,
                                      foregroundColor: Colors.white,
                                      elevation: 2,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 12,
                                      ),
                                    ),
                                    onPressed: () => _navigateToBooking(context, formattedBusData),
                                    child: const Text(
                                      "Book Bus ➔",
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
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
                );
              },
            );
          },
        ),
      ),
    );
  }
}