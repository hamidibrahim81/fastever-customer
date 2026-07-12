import 'package:flutter/material.dart';
import '../home_services/home_services_screen.dart'; // Adjust path if needed
import '../home/home_screen.dart'; // To navigate back or to standard pages

class OtherServicesScreen extends StatelessWidget {
  const OtherServicesScreen({super.key});

  // Premium Color Palette Tokens to match your style guide
  static const Color primary = Color(0xFF111827);
  static const Color accent = Color(0xFFFF4D6D);
  static const Color background = Color(0xFFF7F8FA);
  static const Color textDark = Color(0xFF1F2937);
  static const Color textLight = Color(0xFF6B7280);

  List<Map<String, dynamic>> get allServices => [
        // Updated the image path to homee.png below
        {'title': 'Home Service', 'image': 'assets/instahub/homee.png', 'screen': const HomeServicesScreen()},
        {'title': 'Laundry', 'image': 'assets/instahub/laundryy.png', 'screen': null},
        {'title': 'Car Wash', 'image': 'assets/instahub/carwashh.png', 'screen': null}, 
        {'title': 'Book Your Time', 'image': 'assets/instahub/bookyy.png', 'screen': null}, // Replace with destination when ready
        {'title': 'Events', 'image': 'assets/instahub/eventyy.png', 'screen': null},
        {'title': 'Take Ride', 'image': 'assets/instahub/ridey.png', 'screen': null},
        {'title': 'Pharmacy', 'image': 'assets/instahub/pharmacyy.png', 'screen': null},
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "All Services 🌟",
          style: TextStyle(color: primary, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: GridView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: allServices.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.88, // Matches your Quick Services grid design language
            ),
            itemBuilder: (context, index) {
              final item = allServices[index];
              return GestureDetector(
                onTap: () {
                  if (item['screen'] != null) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => item['screen']));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("${item['title']} system module coming online soon!")),
                    );
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 12, offset: const Offset(0, 4))
                    ],
                    border: Border.all(color: Colors.black.withOpacity(0.03)),
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
                              item['image'],
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  item['title'],
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  "Tap to book",
                                  style: TextStyle(fontSize: 10, color: textLight, fontWeight: FontWeight.w500),
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
      ),
    );
  }
}