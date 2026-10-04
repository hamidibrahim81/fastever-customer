import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'cleaning_service_form.dart';

// ✅ GLOBAL AUTH GUARD IMPORT
import 'package:fastevergo_v1/utils/auth_guards.dart';

// ✅ IMPORT NOTIFICATION SCREEN FOR NAVIGATION
import 'package:fastevergo_v1/features/notification/NotificationScreen.dart';

class HomeServicesScreen extends StatelessWidget {
  const HomeServicesScreen({super.key});

  static const Color _primaryDark = Color(0xFF111827);
  static const Color _accentPink = Color(0xFFFF4D6D);
  static const Color _bgColor = Color(0xFFF8FAFC);

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> services = [
      {
        "key": "electrician",
        "title": "Electrician",
        "subtitle": "Wiring, repairs, switches & fan installations",
        "icon": Icons.electric_bolt_rounded,
        "color": const Color(0xFFFFB300),
        "tag": "Instant"
      },
      {
        "key": "plumber",
        "title": "Plumber",
        "subtitle": "Leakages, pipes, taps & bathroom fittings",
        "icon": Icons.water_drop_rounded,
        "color": const Color(0xFF2196F3),
        "tag": "Expert"
      },
      {
        "key": "house_cleaning",
        "title": "House Cleaning",
        "subtitle": "Deep home, office, kitchen & flat cleaning",
        "icon": Icons.cleaning_services_rounded,
        "color": _accentPink,
        "tag": "Popular"
      },
      {
        "key": "ac_service",
        "title": "AC Service",
        "subtitle": "Cooling repair, gas refill & servicing",
        "icon": Icons.ac_unit_rounded,
        "color": const Color(0xFF00BCD4),
        "tag": "Certified"
      },
      {
        "key": "appliance_repair",
        "title": "Appliance Repair",
        "subtitle": "Fridge, TV, washing machine & microwave fixes",
        "icon": Icons.home_repair_service_rounded,
        "color": const Color(0xFF4CAF50),
        "tag": "Quick Fix"
      },
      {
        "key": "home_shifting",
        "title": "Home Shifting",
        "subtitle": "Packers, movers & safe logistics help",
        "icon": Icons.local_shipping_rounded,
        "color": const Color(0xFF9C27B0),
        "tag": "Safe Transit"
      },
    ];

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _primaryDark,
        elevation: 6,
        shadowColor: Colors.black.withOpacity(0.3),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(24),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Home Services",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          // 🔔 Notification Bell Icon Integration
          IconButton(
            icon: const Icon(Icons.notifications_rounded, color: Colors.white, size: 24),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        // 🔄 Listening to the home_service_status document real-time
        stream: FirebaseFirestore.instance
            .collection('app_settings')
            .doc('home_service_status')
            .snapshots(),
        builder: (context, snapshot) {
          // Extract service status map safely
          Map<String, dynamic> serviceStatusMap = {};
          if (snapshot.hasData && snapshot.data!.exists) {
            serviceStatusMap = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          }

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // HERO BANNER
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_primaryDark, Color(0xFF1F2937)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: _primaryDark.withOpacity(0.2),
                        blurRadius: 15,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              "Doorstep Care 🏠",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              "Verified local professionals ready to help with your home maintenance.",
                              style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _accentPink.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.verified_user_rounded, color: _accentPink, size: 28),
                      ),
                    ],
                  ),
                ),
              ),

              // SECTION TITLE
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 16, 24, 12),
                  child: Text(
                    "Available Services ⚡",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _primaryDark,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),

              // SERVICES LIST (Fixed 'slivers' to 'sliver')
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = services[index];
                      final String serviceKey = item["key"];
                      
                      // Check status from Firestore. Default to true if missing.
                      final bool isEnabled = serviceStatusMap[serviceKey] ?? true;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14.0),
                        child: _buildServiceCard(
                          context: context,
                          title: item["title"],
                          subtitle: item["subtitle"],
                          icon: item["icon"],
                          iconColor: item["color"],
                          tag: item["tag"],
                          isEnabled: isEnabled,
                        ),
                      );
                    },
                    childCount: services.length,
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }

  // ✅ REUSABLE SERVICE CARD WIDGET WITH STATUS CONTROL
  Widget _buildServiceCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required String tag,
    required bool isEnabled,
  }) {
    return GestureDetector(
      onTap: () {
        if (!isEnabled) {
          // 🚫 Show message when service is turned off/under maintenance
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Currently we are unable to provide $title service. Under Maintenance."),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

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
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.55, // Dim out if disabled
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isEnabled 
                  ? const Color(0xFFE2E8F0).withOpacity(0.6) 
                  : Colors.redAccent.withOpacity(0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.025),
                blurRadius: 12,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Row(
            children: [
              // Styled Icon Container
              Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  color: (isEnabled ? iconColor : Colors.grey).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  color: isEnabled ? iconColor : Colors.grey,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              // Text Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _primaryDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isEnabled ? iconColor : Colors.grey).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isEnabled ? tag : "Maintenance",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isEnabled ? iconColor : Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isEnabled ? subtitle : "Temporarily unavailable. Please check back later.",
                      style: TextStyle(
                        fontSize: 12,
                        color: isEnabled ? const Color(0xFF64748B) : Colors.red.shade300,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _bgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isEnabled ? Icons.arrow_forward_ios_rounded : Icons.lock_outline_rounded,
                  size: 14,
                  color: isEnabled ? _primaryDark : Colors.redAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}