import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../notification/notificationscreen.dart';
import 'ride_booking_form_screen.dart';
import 'tourist_buses_screen.dart';

class TakeRideScreen extends StatefulWidget {
  const TakeRideScreen({super.key});

  @override
  State<TakeRideScreen> createState() => _TakeRideScreenState();
}

class _TakeRideScreenState extends State<TakeRideScreen> {
  // Theme Color Tokens
  static const Color primaryColor = Color(0xFF111827);
  static const Color accentColor = Color(0xFFFF4D6D);
  static const Color backgroundColor = Color(0xFFF7F8FA);
  static const Color textDark = Color(0xFF1F2937);
  static const Color textLight = Color(0xFF6B7280);

  String _selectedVehicleId = 'taxi';

  // Regular Vehicles Grid Items
  final List<Map<String, dynamic>> _gridRideTypes = [
    {
      'id': 'taxi',
      'title': 'Taxi',
      'subtitle': '4-seater sedan / hatch',
      'capacity': '4 Passengers',
      'icon': Icons.local_taxi_rounded,
      'badge': 'Fastest',
      'color': const Color(0xFFFFB703),
      'image': 'assets/instahub/taxi.png',
    },
    {
      'id': 'pickup',
      'title': 'Pickup',
      'subtitle': 'Utility pickup truck',
      'capacity': 'Up to 1.5 Tons',
      'icon': Icons.agriculture_rounded,
      'badge': 'Goods',
      'color': const Color(0xFF2A9D8F),
      'image': 'assets/instahub/pickup.png',
    },
    {
      'id': 'mini_truck',
      'title': 'Mini Truck',
      'subtitle': 'Small commercial truck',
      'capacity': 'Up to 3.5 Tons',
      'icon': Icons.local_shipping_rounded,
      'badge': 'Heavy Freight',
      'color': const Color(0xFFE76F51),
      'image': 'assets/instahub/truck.png',
    },
  ];

  void _onBookRidePressed(Map<String, Map<String, dynamic>> pricingData) {
    if (_selectedVehicleId == 'tourist_bus') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TouristBusesScreen()),
      );
      return;
    }

    final selectedRide = Map<String, dynamic>.from(
      _gridRideTypes.firstWhere((r) => r['id'] == _selectedVehicleId),
    );

    // Attach pricing fields from Firestore
    selectedRide['min_charge'] = pricingData[_selectedVehicleId]?['min_charge'] ?? 0;
    selectedRide['per_km_charge'] = pricingData[_selectedVehicleId]?['per_km_charge'] ?? 0;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RideBookingFormScreen(
          selectedVehicle: selectedRide,
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
          "Take a Ride 🚖",
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
          stream: FirebaseFirestore.instance.collection('ride_pricing').snapshots(),
          builder: (context, snapshot) {
            Map<String, Map<String, dynamic>> pricingMap = {};
            if (snapshot.hasData) {
              for (var doc in snapshot.data!.docs) {
                pricingMap[doc.id] = doc.data() as Map<String, dynamic>;
              }
            }

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section Title
                  const Text(
                    "Select Vehicle Type 🚗",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Choose the right transportation option for your journey or cargo",
                    style: TextStyle(fontSize: 13, color: textLight),
                  ),

                  const SizedBox(height: 20),

                  // 1. Grid for Taxi, Pickup, Mini Truck
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _gridRideTypes.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.88,
                    ),
                    itemBuilder: (context, index) {
                      final ride = _gridRideTypes[index];
                      final String vehicleId = ride['id'];
                      final isSelected = vehicleId == _selectedVehicleId;

                      final priceInfo = pricingMap[vehicleId];
                      final num minCharge = priceInfo?['min_charge'] ?? 0;
                      final num perKmCharge = priceInfo?['per_km_charge'] ?? 0;

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedVehicleId = vehicleId;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? accentColor : Colors.black.withOpacity(0.06),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isSelected
                                    ? accentColor.withOpacity(0.12)
                                    : Colors.black.withOpacity(0.02),
                                blurRadius: isSelected ? 12 : 6,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Stack(
                              children: [
                                // Soft opacity background image (removes harsh mirror look)
                                Positioned.fill(
                                  child: Opacity(
                                    opacity: 0.12,
                                    child: Image.asset(
                                      ride['image'] as String,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                    ),
                                  ),
                                ),

                                // Clean solid inner padding layer
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: (ride['color'] as Color).withOpacity(0.15),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              ride['icon'] as IconData,
                                              color: ride['color'] as Color,
                                              size: 22,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? accentColor.withOpacity(0.15)
                                                  : backgroundColor,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              ride['badge'] as String,
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: isSelected ? accentColor : textLight,
                                              ),
                                            ),
                                          )
                                        ],
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            ride['title'] as String,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: primaryColor,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            ride['subtitle'] as String,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: textLight,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 6),

                                          // Pricing Box
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              color: backgroundColor,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.black.withOpacity(0.03)),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  "Min Charge: ₹$minCharge",
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: primaryColor,
                                                  ),
                                                ),
                                                const SizedBox(height: 1),
                                                Text(
                                                  "Rate: ₹$perKmCharge / KM",
                                                  style: const TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w600,
                                                    color: accentColor,
                                                  ),
                                                ),
                                              ],
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
                  ),

                  const SizedBox(height: 18),

                  // 2. Separate Dedicated Tourist Buses Section Banner
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TouristBusesScreen()),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF457B9D).withOpacity(0.3),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          children: [
                            // Soft opacity background image for bus
                            Positioned.fill(
                              child: Opacity(
                                opacity: 0.12,
                                child: Image.asset(
                                  'assets/instahub/torist.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF457B9D).withOpacity(0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.directions_bus_rounded,
                                      color: Color(0xFF457B9D),
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              "Tourist Buses 🚌",
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: primaryColor,
                                              ),
                                            ),
                                            SizedBox(width: 6),
                                            Text(
                                              "• Group Travel",
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: accentColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          "Luxury AC / Non-AC buses available for long tours & trips",
                                          style: TextStyle(fontSize: 11, color: textLight),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 16,
                                    color: primaryColor,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: primaryColor.withOpacity(0.3),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: () => _onBookRidePressed(pricingMap),
                      child: const Text(
                        "Proceed to Booking ➔",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}