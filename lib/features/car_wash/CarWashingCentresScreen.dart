import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'CarWashBookingForm.dart'; 

class CarWashingCentresScreen extends StatelessWidget {
  const CarWashingCentresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Washing Centres 🚗",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('washing_centre').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFF4D6D)));
          }
          
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  "Connection error: ${snapshot.error}\nMake sure your security rules are published!",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text("No washing centres available right now.", style: TextStyle(color: Colors.grey)),
            );
          }

          final centres = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: centres.length,
            itemBuilder: (context, index) {
              final centreData = centres[index].data() as Map<String, dynamic>;
              final String docId = centres[index].id; 

              // Safe list extraction to prevent runtime dynamic crash patterns
              final List<dynamic> rawServices = centreData['services'] is List ? centreData['services'] as List : [];
              final List<String> verifiedServices = rawServices.map((e) => e.toString()).toList();

              return Container(
                margin: const EdgeInsets.only(bottom: 16), 
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
                  ],
                  border: Border.all(color: Colors.black.withOpacity(0.02))
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CachedNetworkImage(
                        imageUrl: centreData['image'] ?? '',
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: Colors.grey.shade100),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.local_car_wash_rounded, size: 40, color: Colors.grey),
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
                                    centreData['name'] ?? 'Washing Centre',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF111827)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: const Color(0xFF16A34A).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                  child: Text(
                                    "From ₹${centreData['minimum_amount'] ?? '0'}",
                                    style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 13),
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
                                    centreData['location'] ?? 'Location not set', 
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
                                  backgroundColor: const Color(0xFF111827),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CarWashBookingForm(
                                        centreId: docId, 
                                        centreName: centreData['name'] ?? 'Washing Centre', 
                                        availableServices: verifiedServices,
                                      ),
                                    ),
                                  );
                                },
                                child: const Text("BOOK WASH NOW", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
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