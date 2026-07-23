import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Import decoupled form screens & notification screen
import 'booktimeformscreen.dart';
import 'turftimeformscreen.dart';
import 'petbooktimeformscreen.dart';
import '../notification/notificationscreen.dart';

class LocalColors {
  static const Color primary = Color(0xFF111827);
  static const Color accent = Color(0xFFFF4D6D);
  static const Color background = Color(0xFFF7F8FA);
  static const Color textDark = Color(0xFF1F2937);
  static const Color textLight = Color(0xFF6B7280);
}

// ======================================================================
// 1. MASTER GATEWAY: BOOK YOUR TIME CATEGORIES SCREEN
// ======================================================================
class BookTimeHubScreen extends StatelessWidget {
  const BookTimeHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> categories = [
      {'title': 'Salon & Grooming', 'image': 'assets/instahub/salon.png', 'active': true},
      {'title': 'Pet Care', 'image': 'assets/instahub/petcare.png', 'active': true},
      {'title': 'Turf Booking', 'image': 'assets/instahub/turf.png', 'active': true},
    ];

    return Scaffold(
      backgroundColor: LocalColors.background,
      appBar: AppBar(
        backgroundColor: LocalColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Book Your Time ⏰",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: const [
          NotificationBellIconButton(),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: const Text(
              "Select Service Field",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: LocalColors.primary),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: categories.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.9,
              ),
              itemBuilder: (context, index) {
                final cat = categories[index];
                return GestureDetector(
                  onTap: () {
                    if (cat['active'] == true) {
                      if (cat['title'] == 'Salon & Grooming') {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SalonDirectoryScreen()));
                      } else if (cat['title'] == 'Pet Care') {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const PetCareDirectoryScreen()));
                      } else if (cat['title'] == 'Turf Booking') {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const TurfDirectoryScreen()));
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("${cat['title']} subsystem coming online soon!")),
                      );
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.black.withOpacity(0.03)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 8, offset: const Offset(0, 2))
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: SizedBox(
                              width: double.infinity,
                              height: double.infinity,
                              child: Image.asset(
                                cat['image'],
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: LocalColors.primary.withOpacity(0.05),
                                  child: const Icon(Icons.storefront_rounded, size: 40, color: LocalColors.textLight),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    cat['title'],
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: LocalColors.primary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (cat['active'] != true)
                                    const Text(
                                      "Coming Soon",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: LocalColors.textLight,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// 2. LIVE DIRECTORY LIST: SALONS SCREEN
// ======================================================================
class SalonDirectoryScreen extends StatelessWidget {
  const SalonDirectoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LocalColors.background,
      appBar: AppBar(
        backgroundColor: LocalColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Premium Salons ✂️",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: const [
          NotificationBellIconButton(),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('salons').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: LocalColors.accent));
          }
          
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  "Connection error: ${snapshot.error}\nVerify database rule mappings!",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text("No salons available right now.", style: TextStyle(color: Colors.grey)),
            );
          }

          final salons = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: salons.length,
            itemBuilder: (context, index) {
              final salonData = salons[index].data() as Map<String, dynamic>;
              final String docId = salons[index].id; 

              final List<dynamic> rawServices = salonData['services'] is List ? salonData['services'] as List : [];
              final List<String> verifiedServices = rawServices.map((e) => e.toString()).toList();

              return Container(
                margin: const EdgeInsets.only(bottom: 16), 
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
                  ],
                  border: Border.all(color: Colors.black.withOpacity(0.02)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CachedNetworkImage(
                        imageUrl: salonData['image'] ?? '',
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: Colors.grey.shade100),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.storefront_rounded, size: 40, color: Colors.grey),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    salonData['name'] ?? 'Premium Salon',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: LocalColors.primary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (salonData['latitude'] != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: const Color(0xFF16A34A).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                    child: const Text(
                                      "Available",
                                      style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.location_on_rounded, size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    salonData['location'] ?? 'Location not set', 
                                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24, thickness: 0.5),
                            SizedBox(
                              width: double.infinity,
                              height: 45,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: LocalColors.primary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text("BOOK SALON NOW", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SalonBookingForm(
                                        salonId: docId, 
                                        salonName: salonData['name'] ?? 'Premium Salon', 
                                        availableServices: verifiedServices,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            )
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ======================================================================
// 3. LIVE DIRECTORY LIST: PET CARE SCREEN
// ======================================================================
class PetCareDirectoryScreen extends StatelessWidget {
  const PetCareDirectoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LocalColors.background,
      appBar: AppBar(
        backgroundColor: LocalColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Pet Care Centers 🐾", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        actions: const [
          NotificationBellIconButton(),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        // 🎯 Collection stream configured to 'pet_care'
        stream: FirebaseFirestore.instance.collection('pet_care').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: LocalColors.accent));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No pet care centers available right now.", style: TextStyle(color: Colors.grey)));
          }

          final pets = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: pets.length,
            itemBuilder: (context, index) {
              final petData = pets[index].data() as Map<String, dynamic>;
              final String docId = pets[index].id;
              final List<dynamic> rawServices = petData['services'] is List ? petData['services'] as List : [];
              final List<String> verifiedServices = rawServices.map((e) => e.toString()).toList();
              final String imageUrl = ((petData['image'] ?? petData['image '])?.toString() ?? '').trim();

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                  border: Border.all(color: Colors.black.withOpacity(0.02)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CachedNetworkImage(
                        imageUrl: imageUrl,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: Colors.grey.shade100),
                        errorWidget: (context, url, error) => Container(color: Colors.grey.shade200, child: const Icon(Icons.pets_rounded, size: 40, color: Colors.grey)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text(petData['name'] ?? 'Pet Care Center', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: LocalColors.primary), overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.location_on_rounded, size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Expanded(child: Text(petData['location'] ?? 'Location not set', style: const TextStyle(color: Colors.grey, fontSize: 13), overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                            const Divider(height: 24, thickness: 0.5),
                            SizedBox(
                              width: double.infinity,
                              height: 45,
                              child: FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: LocalColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                child: const Text("BOOK PET CARE SLOT", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => PetBookingFormScreen(petId: docId, petName: petData['name'] ?? 'Pet Care Center', availableServices: verifiedServices)),
                                  );
                                },
                              ),
                            )
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ======================================================================
// 4. LIVE DIRECTORY LIST: TURF BOOKING SCREEN
// ======================================================================
class TurfDirectoryScreen extends StatelessWidget {
  const TurfDirectoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LocalColors.background,
      appBar: AppBar(
        backgroundColor: LocalColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Turf Arena Booking ⚽",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: const [
          NotificationBellIconButton(),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('turf').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: LocalColors.accent));
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  "Connection error: ${snapshot.error}\nVerify database rules for 'turf' collection!",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text("No turfs available for booking right now.", style: TextStyle(color: Colors.grey)),
            );
          }

          final turfs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: turfs.length,
            itemBuilder: (context, index) {
              final turfData = turfs[index].data() as Map<String, dynamic>;
              final String docId = turfs[index].id;

              final List<dynamic> rawSports = turfData['sports'] is List ? turfData['sports'] as List : [];
              final List<String> verifiedSports = rawSports.map((e) => e.toString()).toList();
              
              final priceVal = turfData['price_per_hour'];
              final String pricePerHour = priceVal != null 
                  ? "₹$priceVal/hr" 
                  : "Rate on request";

              final String rawImageUrl = (turfData['image'] ?? turfData['image '])?.toString() ?? '';
              final String imageUrl = rawImageUrl.trim();

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
                  ],
                  border: Border.all(color: Colors.black.withOpacity(0.02)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CachedNetworkImage(
                        imageUrl: imageUrl,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: Colors.grey.shade100),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.sports_soccer_rounded, size: 40, color: Colors.grey),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    turfData['name'] ?? 'Premium Arena',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: LocalColors.primary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: LocalColors.accent.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    pricePerHour,
                                    style: const TextStyle(color: LocalColors.accent, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.location_on_rounded, size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    turfData['location'] ?? 'Location not set',
                                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (verifiedSports.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: verifiedSports.map((sport) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: LocalColors.background,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.black.withOpacity(0.05)),
                                    ),
                                    child: Text(
                                      sport,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: LocalColors.textDark),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                            const Divider(height: 24, thickness: 0.5),
                            SizedBox(
                              width: double.infinity,
                              height: 45,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: LocalColors.primary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text("BOOK TURF SLOT", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TurfBookingFormScreen(
                                        turfId: docId,
                                        turfName: turfData['name'] ?? 'Premium Arena',
                                        availableSports: verifiedSports,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            )
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}