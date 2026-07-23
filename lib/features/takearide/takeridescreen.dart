import 'package:flutter/material.dart';
import '../notification/notificationscreen.dart';
import 'ride_booking_form_screen.dart';

class TakeRideScreen extends StatefulWidget {
  const TakeRideScreen({super.key});

  @override
  State<TakeRideScreen> createState() => _TakeRideScreenState();
}

class _TakeRideScreenState extends State<TakeRideScreen> {
  // Theme Color Tokens matching FASTever Core
  static const Color primaryColor = Color(0xFF111827);
  static const Color accentColor = Color(0xFFFF4D6D);
  static const Color backgroundColor = Color(0xFFF7F8FA);
  static const Color textDark = Color(0xFF1F2937);
  static const Color textLight = Color(0xFF6B7280);

  // Selected vehicle state
  String _selectedVehicleId = 'taxi';

  final List<Map<String, dynamic>> _rideTypes = [
    {
      'id': 'taxi',
      'title': 'Taxi',
      'subtitle': '4-seater sedan / hatch',
      'capacity': '4 Passengers',
      'icon': Icons.local_taxi_rounded,
      'badge': 'Fastest',
      'color': const Color(0xFFFFB703),
    },
    {
      'id': 'pickup',
      'title': 'Pickup',
      'subtitle': 'Utility pickup truck',
      'capacity': 'Up to 1.5 Tons',
      'icon': Icons.agriculture_rounded,
      'badge': 'Goods',
      'color': const Color(0xFF2A9D8F),
    },
    {
      'id': 'mini_truck',
      'title': 'Mini Truck',
      'subtitle': 'Small commercial truck',
      'capacity': 'Up to 3.5 Tons',
      'icon': Icons.local_shipping_rounded,
      'badge': 'Heavy Freight',
      'color': const Color(0xFFE76F51),
    },
    {
      'id': 'tourist_bus',
      'title': 'Tourist Buses',
      'subtitle': 'Luxury AC / Non-AC bus',
      'capacity': '12 - 50 Seats',
      'icon': Icons.directions_bus_rounded,
      'badge': 'Group Travel',
      'color': const Color(0xFF457B9D),
    },
  ];

  void _onBookRidePressed() {
    final selectedRide = _rideTypes.firstWhere((r) => r['id'] == _selectedVehicleId);

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
        child: SingleChildScrollView(
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

              // Grid of Ride Categories
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _rideTypes.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 0.95,
                ),
                itemBuilder: (context, index) {
                  final ride = _rideTypes[index];
                  final isSelected = ride['id'] == _selectedVehicleId;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedVehicleId = ride['id'];
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? accentColor : Colors.black.withOpacity(0.04),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: (ride['color'] as Color).withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  ride['icon'] as IconData,
                                  color: ride['color'] as Color,
                                  size: 24,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? accentColor.withOpacity(0.1)
                                      : backgroundColor,
                                  borderRadius: BorderRadius.circular(8),
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
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.info_outline_rounded, size: 12, color: textLight),
                                  const SizedBox(width: 4),
                                  Text(
                                    ride['capacity'] as String,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 28),

              // Confirm Ride Button
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
                  onPressed: _onBookRidePressed,
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
        ),
      ),
    );
  }
}