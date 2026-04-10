import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'track_order_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class ActiveOrderBottomBar extends StatelessWidget {
  const ActiveOrderBottomBar({super.key});

  // ✅ PRESERVED: Your original calculation logic
  String _calculateRemainingTime(Map<String, dynamic> data) {
    if (data['status'] == 'delivered') return "Delivered";

    DateTime createdAt =
        (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
    DateTime now = DateTime.now();
    int minutesPassed = now.difference(createdAt).inMinutes;
    int transitTime =
        int.tryParse(data['deliveryPartnerETA']?.toString() ?? "10") ?? 10;

    if (data['status'] == 'out_for_delivery') {
      return transitTime <= 1 ? "1 min" : "$transitTime mins";
    }

    int basePrepTime = 15;
    int calculatedPrepTime = basePrepTime;

    if (minutesPassed >= basePrepTime) {
      int extraLags = ((minutesPassed - basePrepTime) / 5).floor() + 1;
      calculatedPrepTime += (extraLags * 5);
    }

    int remaining = (calculatedPrepTime + transitTime) - minutesPassed;
    return remaining <= 0 ? "Arriving shortly" : "$remaining mins";
  }

  String _prettyStatus(String status) {
    final s = status.toLowerCase().trim();
    switch (s) {
      case 'confirmed':
        return "Confirmed";
      case 'restaurant_accepted':
        return "Restaurant Accepted";
      case 'preparing_food':
      case 'preparing':
        return "Preparing Food";
      case 'ready':
      case 'ready_for_delivery':
        return "Ready for Pickup";
      case 'partner_taked_food':
      case 'partner_picked':
      case 'picked':
        return "Partner Picked Food";
      case 'out_for_delivery':
        return "On the Way";
      case 'arrived':
        return "Arrived";
      case 'delivered':
        return "Delivered";
      default:
        return status.replaceAll('_', ' ').toUpperCase();
    }
  }

  Future<void> _callPartner(String phone) async {
    if (phone.trim().isEmpty) return;
    final Uri url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('order_status')
          .where('userId', isEqualTo: user.uid)
          .where('status', isNotEqualTo: 'delivered')
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        // ✅ UI LOGIC: Animated appear/disappear to prevent "flicker" lag
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final doc = snapshot.data!.docs.first;
        final data = doc.data() as Map<String, dynamic>;
        final String status = data['status'] ?? 'pending';
        final String remainingTime = _calculateRemainingTime(data);

        return TweenAnimationBuilder(
          duration: const Duration(milliseconds: 500),
          tween: Tween<double>(begin: 1.0, end: 0.0), // Slide up from bottom
          builder: (context, double value, child) {
            return Transform.translate(
              offset: Offset(0, value * 100),
              child: child,
            );
          },
          child: _buildPremiumBar(context, doc.id, status, remainingTime),
        );
      },
    );
  }

  // ✅ NEW: Professional UI Widget for the Bottom Bar
  Widget _buildPremiumBar(
      BuildContext context, String orderId, String status, String time) {
    bool isOut = status == 'out_for_delivery';

    return SafeArea(
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('order_status')
            .doc(orderId)
            .snapshots(),
        builder: (context, snap) {
          final live = (snap.data?.data() as Map<String, dynamic>?) ?? {};
          final String partnerName =
              (live['deliveryPartnerName'] ?? live['driverName'] ?? "")
                  .toString();
          final String partnerPhone =
              (live['deliveryPartnerPhone'] ?? live['driverPhone'] ?? "")
                  .toString();

          return GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 15),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                // Premium Dark Theme matching the Logo vibe
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A1A), Color(0xFF2D2D2D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Row(
                children: [
                  // Pulse Animation Icon Section
                  _buildLiveIcon(isOut),
                  const SizedBox(width: 15),

                  // Information Column
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _prettyStatus(status),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isOut ? "Reaching you in $time" : "Estimated arrival: $time",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (partnerName.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            partnerName,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (partnerPhone.isNotEmpty)
                            Text(
                              partnerPhone,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.55),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),

                  // Call Button (shows only if phone exists)
                  if (partnerPhone.isNotEmpty)
                    GestureDetector(
                      onTap: () => _callPartner(partnerPhone),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.call, color: Colors.white, size: 14),
                            SizedBox(width: 6),
                            Text(
                              "CALL",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Text(
                            "TRACK",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.radar, color: Colors.white, size: 14),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLiveIcon(bool isOut) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Pulsing background effect
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
        ),
        Icon(
          isOut ? Icons.motorcycle_rounded : Icons.restaurant_rounded,
          color: Colors.orange,
          size: 24,
        ),
      ],
    );
  }
}