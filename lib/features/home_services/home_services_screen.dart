import 'package:flutter/material.dart';
import 'cleaning_service_form.dart'; // Adjust if you change the form name

// ✅ GLOBAL AUTH GUARD IMPORT
import 'package:fastevergo_v1/utils/auth_guards.dart';

class HomeServicesScreen extends StatelessWidget {
  const HomeServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF333333),
        elevation: 0,
        title: const Text(
          "Home Services",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: const Color(0xfff5f5f5),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "Available Services 🏠",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF333333),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Find the best help for your home needs.",
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 25),

          // ⚡ Electrician
          _buildServiceCard(
            context: context,
            title: "Electrician",
            subtitle: "Wiring, repairs, switches & fan installations",
            icon: Icons.electric_bolt_rounded,
            iconColor: const Color(0xFFFFB300), // Amber/Yellow
          ),
          const SizedBox(height: 16),

          // 🚰 Plumber
          _buildServiceCard(
            context: context,
            title: "Plumber",
            subtitle: "Leakages, pipes, taps & bathroom fittings",
            icon: Icons.water_drop_rounded,
            iconColor: const Color(0xFF2196F3), // Blue
          ),
          const SizedBox(height: 16),

          // 🧹 House Cleaning
          _buildServiceCard(
            context: context,
            title: "House Cleaning",
            subtitle: "Deep home, office, kitchen & flat cleaning",
            icon: Icons.cleaning_services_rounded,
            iconColor: const Color(0xFFFD3C68), // Pink/Red
          ),
          const SizedBox(height: 16),

          // ❄️ AC Service
          _buildServiceCard(
            context: context,
            title: "AC Service",
            subtitle: "Cooling repair, gas refill & servicing",
            icon: Icons.ac_unit_rounded,
            iconColor: const Color(0xFF00BCD4), // Cyan
          ),
          const SizedBox(height: 16),

          // 🧰 Appliance Repair
          _buildServiceCard(
            context: context,
            title: "Appliance Repair",
            subtitle: "Fridge, TV, washing machine & microwave fixes",
            icon: Icons.home_repair_service_rounded,
            iconColor: const Color(0xFF4CAF50), // Green
          ),
          const SizedBox(height: 16),

          // 🚚 Home Shifting
          _buildServiceCard(
            context: context,
            title: "Home Shifting",
            subtitle: "Packers, movers & safe logistics help",
            icon: Icons.local_shipping_rounded,
            iconColor: const Color(0xFF9C27B0), // Purple
          ),
        ],
      ),
    );
  }

  // ✅ REUSABLE SERVICE CARD WIDGET
  Widget _buildServiceCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    return GestureDetector(
      onTap: () {
        // Auth Guard check
        if (!requireLoginGlobal("Please login to book a $title service")) return;

        // Navigates and explicitly passes the chosen service type string
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CleaningServiceForm(serviceType: title),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            // Styled Icon Container
            Container(
              height: 60,
              width: 60,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 15),
            // Text Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}