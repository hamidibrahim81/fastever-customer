import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'track_order_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class ActiveOrderBottomBar extends StatelessWidget {
  const ActiveOrderBottomBar({super.key});

  // ✅ FIXED: Time decreases logically on milestones instead of rising
  String _calculateRemainingTime(Map<String, dynamic> data) {
    final String status = (data['status'] ?? 'pending').toLowerCase().trim();
    if (status == 'delivered') return "Delivered";

    // 1. Live Transit Modes
    if (status == 'out_for_delivery' || status == 'on_the_way' || status == 'picked') {
      if (data['deliveryPartnerETA'] != null) {
        int transit = int.tryParse(data['deliveryPartnerETA'].toString()) ?? 12;
        return transit <= 1 ? "1 min" : "$transit mins";
      }
      return "12 mins"; // Fallback delivery start estimate
    }

    // 2. Preparation/Milestone Countdown Calculations
    final created = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
    final elapsedMins = DateTime.now().difference(created).inMinutes;

    int baseRemainingMins = 40; // Initial default when order is 'pending'

    if (status == 'accepted') {
      baseRemainingMins = 35; // Drops immediately upon restaurant acceptance
    } else if (status.contains('preparing')) {
      baseRemainingMins = 30; // Drops during food creation phase
    } else if (status == 'ready') {
      baseRemainingMins = 25; // Drops further when food is packed and waiting
    } else if (status == 'partner_accepted') {
      baseRemainingMins = 20; // Drops when driver accepts gig
    } else if (status == 'arrived_at_pickup') {
      baseRemainingMins = 15; // Drops when driver stops at storefront
    }

    int finalRemaining = baseRemainingMins - elapsedMins;
    if (finalRemaining <= 0) {
      return "Arriving shortly";
    }
    return "$finalRemaining mins";
  }

  double _getProgress(String status) {
    final s = status.toLowerCase().trim();
    if (s == 'pending') return 0.15;
    if (s == 'accepted') return 0.35;
    if (s.contains('preparing')) return 0.50;
    if (s == 'ready') return 0.65;
    if (s == 'partner_accepted' || s == 'arrived_at_pickup') return 0.80;
    if (s == 'out_for_delivery' || s == 'on_the_way' || s == 'picked') return 0.92;
    if (s == 'delivered') return 1.0;
    return 0.2;
  }

  String _prettyStatus(String status) {
    final s = status.toLowerCase().trim();
    switch (s) {
      case 'pending':
        return "Order Placed";
      case 'accepted':
        return "Order Accepted";
      case 'ready':
        return "Your Food is Ready";
      case 'partner_accepted':
        return "Partner Assigned";
      case 'arrived_at_pickup':
        return "Partner at Restaurant";
      case 'out_for_delivery':
      case 'on_the_way':
      case 'picked':
        return "On the Way";
      case 'delivered':
        return "Delivered";
      default:
        return status.toUpperCase().replaceAll('_', ' ');
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
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final doc = snapshot.data!.docs.first;
        final data = doc.data() as Map<String, dynamic>;
        final String status = data['status'] ?? 'pending';
        final String remainingTime = _calculateRemainingTime(data);

        return TweenAnimationBuilder(
          duration: const Duration(milliseconds: 500),
          tween: Tween<double>(begin: 1.0, end: 0.0),
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

  Widget _buildPremiumBar(
      BuildContext context, String orderId, String status, String time) {
    bool isOut = status.contains('out') || status.contains('picked') || status.contains('way');

    return SafeArea(
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('order_status')
            .doc(orderId)
            .snapshots(),
        builder: (context, snap) {
          final live = (snap.data?.data() as Map<String, dynamic>?) ?? {};
          final String partnerName =
              (live['deliveryPartnerName'] ?? live['driverName'] ?? "").toString();
          final String partnerPhone =
              (live['deliveryPartnerPhone'] ?? live['driverPhone'] ?? "").toString();
          
          double progressWidth = _getProgress(status);

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TrackOrderScreen(orderId: orderId),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF141414), Color(0xFF242424)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.18),
                    blurRadius: 25,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _buildLiveIcon(isOut),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _prettyStatus(status).toUpperCase(),
                              style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isOut ? "Arriving in $time" : "Estimated Delivery: $time",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (partnerName.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.directions_bike, size: 12, color: Colors.white.withOpacity(0.5)),
                                  const SizedBox(width: 4),
                                  Text(
                                    partnerName,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (partnerPhone.isNotEmpty)
                        GestureDetector(
                          onTap: () => _callPartner(partnerPhone),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E7D32),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 14),
                                SizedBox(width: 6),
                                Text(
                                  "CALL",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade800,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            children: [
                              Text(
                                "TRACK",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.pin_drop_rounded, color: Colors.white, size: 14),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Premium Micro progress line bar
                  Container(
                    height: 4,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: (progressWidth * 100).round(),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Colors.orangeAccent, Colors.orange],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: ((1.0 - progressWidth) * 100).round(),
                          child: const SizedBox.shrink(),
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLiveIcon(bool isOut) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.orange.withOpacity(0.2), width: 1),
      ),
      child: Icon(
        isOut ? Icons.delivery_dining_rounded : Icons.fastfood_rounded,
        color: Colors.orange,
        size: 22,
      ),
    );
  }
}