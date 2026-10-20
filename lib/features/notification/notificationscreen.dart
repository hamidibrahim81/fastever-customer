import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FoodNotificationColors {
  static const Color primaryDark = Color(0xFF111827);
  static const Color accentOrange = Color(0xFFFF6B00);
  static const Color successGreen = Color(0xFF16A34A);
  static const Color pendingBlue = Color(0xFF2563EB);
  static const Color alertRed = Color(0xFFDC2626);
  static const Color background = Color(0xFFF8FAFC);
  static const Color cardBorder = Color(0xFFE2E8F0);
  static const Color textMuted = Color(0xFF64748B);
}

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _markNotificationsAsRead();
  }

  // 🕒 Persist timestamp to reset badge count upon viewing
  Future<void> _markNotificationsAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await prefs.setInt(
        'last_notification_read_${user.uid}',
        DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DateTime _parseDateTime(dynamic val) {
    if (val is Timestamp) return val.toDate();
    if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
    return DateTime.now();
  }

  String _formatDateTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) return "Just now";
    if (difference.inMinutes < 60) return "${difference.inMinutes}m ago";
    if (difference.inHours < 24) return "${difference.inHours}h ago";

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final period = date.hour >= 12 ? "PM" : "AM";
    final minute = date.minute.toString().padLeft(2, '0');

    return "$day/$month/$year • $hour:$minute $period";
  }

  Map<String, dynamic> _getStatusConfig(String status) {
    switch (status.toLowerCase().trim()) {
      case 'pending':
        return {
          'title': 'Order Placed',
          'message': 'Your order has been received and sent to the store.',
          'icon': Icons.receipt_long_rounded,
          'color': FoodNotificationColors.pendingBlue,
          'bgColor': const Color(0xFFEFF6FF),
        };
      case 'accepted':
        return {
          'title': 'Order Confirmed',
          'message': 'The store accepted your order and started preparation.',
          'icon': Icons.storefront_rounded,
          'color': FoodNotificationColors.accentOrange,
          'bgColor': const Color(0xFFFFF7ED),
        };
      case 'ready':
        return {
          'title': 'Prepared & Packed',
          'message': 'Your items are packed and waiting for delivery pickup.',
          'icon': Icons.check_circle_outline_rounded,
          'color': const Color(0xFFD97706),
          'bgColor': const Color(0xFFFEF3C7),
        };
      case 'partner_accepted':
      case 'arrived_at_pickup':
        return {
          'title': 'Delivery Partner Assigned',
          'message': 'A partner has reached the store to collect your package.',
          'icon': Icons.two_wheeler_rounded,
          'color': const Color(0xFF0284C7),
          'bgColor': const Color(0xFFF0F9FF),
        };
      case 'out_for_delivery':
      case 'on_the_way':
      case 'picked':
        return {
          'title': 'Out for Delivery',
          'message': 'Your package is on its way to your destination.',
          'icon': Icons.delivery_dining_rounded,
          'color': FoodNotificationColors.accentOrange,
          'bgColor': const Color(0xFFFFF7ED),
        };
      case 'delivered':
        return {
          'title': 'Order Delivered',
          'message': 'Package has been delivered to your location. Enjoy!',
          'icon': Icons.task_alt_rounded,
          'color': FoodNotificationColors.successGreen,
          'bgColor': const Color(0xFFF0FDF4),
        };
      case 'cancelled':
        return {
          'title': 'Order Cancelled',
          'message': 'This order was cancelled.',
          'icon': Icons.cancel_outlined,
          'color': FoodNotificationColors.alertRed,
          'bgColor': const Color(0xFFFEF2F2),
        };
      default:
        return {
          'title': status.toUpperCase().replaceAll('_', ' '),
          'message': 'Order status update received.',
          'icon': Icons.notifications_active_rounded,
          'color': FoodNotificationColors.primaryDark,
          'bgColor': const Color(0xFFF1F5F9),
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: FoodNotificationColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: FoodNotificationColors.primaryDark,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Food & Store Updates",
          style: TextStyle(
            color: FoodNotificationColors.primaryDark,
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: FoodNotificationColors.primaryDark,
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: FoodNotificationColors.textMuted,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(text: "Live Updates"),
                Tab(text: "Past Notifications"),
              ],
            ),
          ),
        ),
      ),
      body: user == null
          ? const Center(child: Text("Please sign in to view your notifications."))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('orders')
                  .where('userId', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: FoodNotificationColors.accentOrange,
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState("No notifications yet");
                }

                final List<Map<String, dynamic>> orders = snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  data['_id'] = doc.id;
                  return data;
                }).toList();

                orders.sort((a, b) {
                  DateTime dateA = _parseDateTime(a['createdAt'] ?? a['timestamp']);
                  DateTime dateB = _parseDateTime(b['createdAt'] ?? b['timestamp']);
                  return dateB.compareTo(dateA);
                });

                final liveOrders = orders.where((o) {
                  final s = (o['status'] ?? '').toString().toLowerCase().trim();
                  return s != 'delivered' && s != 'cancelled';
                }).toList();

                final pastOrders = orders.where((o) {
                  final s = (o['status'] ?? '').toString().toLowerCase().trim();
                  return s == 'delivered' || s == 'cancelled';
                }).toList();

                return TabBarView(
                  controller: _tabController,
                  children: [
                    _buildNotificationList(liveOrders, isLiveTab: true),
                    _buildNotificationList(pastOrders, isLiveTab: false),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 48,
              color: Color(0xFFCBD5E1),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: FoodNotificationColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationList(List<Map<String, dynamic>> orders, {required bool isLiveTab}) {
    if (orders.isEmpty) {
      return _buildEmptyState(isLiveTab ? "No active orders in progress" : "No past notifications");
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        final String status = (order['status'] ?? 'pending').toString();
        final statusCfg = _getStatusConfig(status);
        final date = _parseDateTime(order['createdAt'] ?? order['timestamp']);
        final items = (order['items'] as List?) ?? [];
        final total = double.tryParse(order['total'].toString()) ?? 0.0;
        final orderId = order['orderId'] ?? order['_id'] ?? 'N/A';
        final isInstaHub = order['restaurantId'] == 'instahub';

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: FoodNotificationColors.cardBorder.withOpacity(0.7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isInstaHub ? const Color(0xFFEDE9FE) : const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isInstaHub ? Icons.flash_on_rounded : Icons.restaurant_rounded,
                            size: 13,
                            color: isInstaHub ? const Color(0xFF7C3AED) : FoodNotificationColors.accentOrange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isInstaHub ? "INSTAHUB GROCERY" : "FOOD ORDER",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: isInstaHub ? const Color(0xFF7C3AED) : FoodNotificationColors.accentOrange,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _formatDateTime(date),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: FoodNotificationColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: statusCfg['bgColor'],
                        shape: BoxShape.circle,
                        border: Border.all(color: (statusCfg['color'] as Color).withOpacity(0.2)),
                      ),
                      child: Icon(statusCfg['icon'], size: 22, color: statusCfg['color']),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusCfg['title'],
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: FoodNotificationColors.primaryDark,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            statusCfg['message'],
                            style: const TextStyle(
                              fontSize: 13,
                              color: FoodNotificationColors.textMuted,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.receipt_rounded, size: 14, color: FoodNotificationColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          "ID: ${orderId.length > 8 ? orderId.substring(0, 8) : orderId}",
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            color: FoodNotificationColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "•  ${items.length} ${items.length == 1 ? 'item' : 'items'}",
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: FoodNotificationColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      "₹${total.toStringAsFixed(2)}",
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: FoodNotificationColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// 🔔 Clean Notification Bell Button (Enforced Pure White by Default)
class NotificationBellIconButton extends StatefulWidget {
  final Color color;

  const NotificationBellIconButton({
    super.key,
    this.color = Colors.white, // Defaults strictly to pure white
  });

  @override
  State<NotificationBellIconButton> createState() => _NotificationBellIconButtonState();
}

class _NotificationBellIconButtonState extends State<NotificationBellIconButton> {
  int _lastReadTimestamp = 0;

  @override
  void initState() {
    super.initState();
    _loadLastRead();
  }

  Future<void> _loadLastRead() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && mounted) {
      setState(() {
        _lastReadTimestamp = prefs.getInt('last_notification_read_${user.uid}') ?? 0;
      });
    }
  }

  void _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationScreen()),
    );
    // Refresh last read timestamp upon popping back so badge disappears immediately
    _loadLastRead();
  }

  DateTime _parseTime(dynamic val) {
    if (val is Timestamp) return val.toDate();
    if (val is String) return DateTime.tryParse(val) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return IconButton(
        icon: Icon(Icons.notifications_rounded, color: widget.color, size: 26),
        color: widget.color,
        splashColor: Colors.white24,
        onPressed: _openNotifications,
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        int unreadCount = 0;

        if (snapshot.hasData && snapshot.data != null) {
          unreadCount = snapshot.data!.docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final status = (data['status'] ?? '').toString().toLowerCase().trim();
            final isActive = status != 'delivered' && status != 'cancelled';

            if (!isActive) return false;

            final orderTime = _parseTime(data['createdAt'] ?? data['timestamp']);
            return orderTime.millisecondsSinceEpoch > _lastReadTimestamp;
          }).length;
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Icon(Icons.notifications_rounded, color: widget.color, size: 26),
              color: widget.color,
              splashColor: Colors.white24,
              onPressed: _openNotifications,
            ),
            if (unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(3.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B00),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}