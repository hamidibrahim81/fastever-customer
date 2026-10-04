import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'track_order_screen.dart';

class ActiveOrderBottomBar extends StatelessWidget {
  const ActiveOrderBottomBar({super.key});

  String _calculateRemainingTime(Map<String, dynamic> data) {
    final String status = (data['status'] ?? 'pending').toLowerCase().trim();
    if (status == 'delivered') return "Delivered";

    if (status == 'out_for_delivery' || status == 'on_the_way' || status == 'picked') {
      if (data['deliveryPartnerETA'] != null) {
        int transit = int.tryParse(data['deliveryPartnerETA'].toString()) ?? 12;
        return transit <= 1 ? "1 min" : "$transit mins";
      }
      return "12 mins";
    }

    final created = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
    final elapsedMins = DateTime.now().difference(created).inMinutes;

    int baseRemainingMins = 40;
    if (status == 'accepted') {
      baseRemainingMins = 35;
    } else if (status.contains('preparing')) {
      baseRemainingMins = 30;
    } else if (status == 'ready') {
      baseRemainingMins = 25;
    } else if (status == 'partner_accepted') {
      baseRemainingMins = 20;
    } else if (status == 'arrived_at_pickup') {
      baseRemainingMins = 15;
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

  Future<void> _makeCall(String phone) async {
    if (phone.trim().isEmpty) return;
    final Uri url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _sendEmail(String email, String orderId) async {
    if (email.trim().isEmpty) return;
    final Uri url = Uri.parse('mailto:$email?subject=Delayed Order Support: $orderId');
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

        final created = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
        final elapsedMins = DateTime.now().difference(created).inMinutes;

        // Vanish completely after 80 minutes (60 min normal/support start + 20 min active support window)
        if (elapsedMins >= 80) {
          return const SizedBox.shrink();
        }

        // Active support mode between 60 and 80 minutes
        final bool isDelayed = elapsedMins >= 60;
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
          child: _buildPremiumBar(
            context: context,
            orderId: doc.id,
            status: status,
            time: remainingTime,
            isDelayed: isDelayed,
          ),
        );
      },
    );
  }

  Widget _buildPremiumBar({
    required BuildContext context,
    required String orderId,
    required String status,
    required String time,
    required bool isDelayed,
  }) {
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
                    color: (isDelayed ? Colors.redAccent : Colors.orange).withOpacity(0.18),
                    blurRadius: 25,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(
                  color: isDelayed ? Colors.redAccent.withOpacity(0.3) : Colors.white.withOpacity(0.06),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _buildLiveIcon(isDelayed),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isDelayed ? "ORDER DELAYED" : _prettyStatus(status).toUpperCase(),
                              style: TextStyle(
                                color: isDelayed ? Colors.redAccent : Colors.orange,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isDelayed ? "Contact our support team" : "Estimated Delivery: $time",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (!isDelayed && partnerName.isNotEmpty) ...[
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
                      if (isDelayed)
                        _buildSupportActions(orderId)
                      else if (partnerPhone.isNotEmpty)
                        _buildActionButton(
                          label: "CALL",
                          icon: Icons.phone_in_talk_rounded,
                          color: const Color(0xFF2E7D32),
                          onTap: () => _makeCall(partnerPhone),
                        )
                      else
                        _buildActionButton(
                          label: "TRACK",
                          icon: Icons.pin_drop_rounded,
                          color: Colors.orange.shade800,
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
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
                              gradient: LinearGradient(
                                colors: isDelayed
                                    ? [Colors.redAccent, Colors.red]
                                    : [Colors.orangeAccent, Colors.orange],
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

  Widget _buildSupportActions(String orderId) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance.collection('customer_supprt').limit(1).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final supportData = snapshot.data!.docs.first.data() as Map<String, dynamic>;
        final callNumber = supportData['support_call']?.toString() ?? '';
        final mailAddress = supportData['support_mail']?.toString() ?? '';

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (callNumber.isNotEmpty)
              IconButton(
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  padding: const EdgeInsets.all(8),
                ),
                icon: const Icon(Icons.call, color: Colors.white, size: 16),
                onPressed: () => _makeCall(callNumber),
              ),
            if (mailAddress.isNotEmpty) ...[
              const SizedBox(width: 6),
              IconButton(
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.blueGrey.shade800,
                  padding: const EdgeInsets.all(8),
                ),
                icon: const Icon(Icons.email_rounded, color: Colors.white, size: 16),
                onPressed: () => _sendEmail(mailAddress, orderId),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 4),
            Icon(icon, color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveIcon(bool isDelayed) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: (isDelayed ? Colors.redAccent : Colors.orange).withOpacity(0.12),
        shape: BoxShape.circle,
        border: Border.all(
          color: (isDelayed ? Colors.redAccent : Colors.orange).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Icon(
        isDelayed ? Icons.support_agent_rounded : Icons.fastfood_rounded,
        color: isDelayed ? Colors.redAccent : Colors.orange,
        size: 22,
      ),
    );
  }
}