import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'track_order_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class ActiveOrderBottomBar extends StatelessWidget {
  const ActiveOrderBottomBar({super.key});

  // ✅ MATCHED: Dynamic time calculation from Track Screen
  String _calculateRemainingTime(Map<String, dynamic> data) {
    final String status = (data['status'] ?? 'pending').toLowerCase();
    if (status == 'delivered') return "Delivered";

    final created = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
    final elapsedMins = DateTime.now().difference(created).inMinutes;

    int baseMins = 40; // Default

    if (status == 'accepted') {
      baseMins = 35;
    } else if (status.contains('accepted') || status.contains('preparing') || status == 'ready') {
      baseMins = 25;
    } else if (status.contains('out_for_delivery') || status.contains('picked')) {
      int transit = int.tryParse(data['deliveryPartnerETA']?.toString() ?? "12") ?? 12;
      return transit <= 1 ? "1 min" : "$transit mins";
    }

    int remaining = baseMins - elapsedMins;
    return remaining <= 0 ? "Arriving shortly" : "$remaining mins";
  }

  // ✅ MATCHED: Pretty Status strings from Track Screen
  String _prettyStatus(String status) {
    final s = status.toLowerCase().trim();
    switch (s) {
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
    bool isOut = status.contains('out') || status.contains('picked');

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
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 15),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
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
                  _buildLiveIcon(isOut),
                  const SizedBox(width: 15),
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
                        ],
                      ],
                    ),
                  ),
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