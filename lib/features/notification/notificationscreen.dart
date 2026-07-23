import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationColors {
  static const Color primary = Color(0xFF111827);
  static const Color accent = Color(0xFFFF4D6D);
  static const Color background = Color(0xFFF7F8FA);
  static const Color textDark = Color(0xFF1F2937);
  static const Color textLight = Color(0xFF6B7280);
}

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ⏰ Helper method: Check 2-hour cutoff rule
  bool _isCancellationAllowed(String bookingDate, int slotStartMinutes) {
    try {
      final now = DateTime.now();
      final parsedDate = DateTime.parse(bookingDate);
      final bookingStartDateTime = parsedDate.add(Duration(minutes: slotStartMinutes));
      final differenceInMinutes = bookingStartDateTime.difference(now).inMinutes;
      return differenceInMinutes >= 120; // 2 hours
    } catch (_) {
      return true;
    }
  }

  // 📝 Helper method: Perform cancellation batch update across collections
  Future<void> _cancelBooking(
    String userId, 
    String subcollectionName, 
    String docId, 
    Map<String, dynamic> bookingData
  ) async {
    final String bDate = bookingData['booking_date'] ?? '';
    final int slotStartMinutes = bookingData['slot_start_minutes'] ?? 0;

    // ⛔ Check 2-Hour Rule
    if (!_isCancellationAllowed(bDate, slotStartMinutes)) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.orange, size: 28),
                SizedBox(width: 8),
                Text("Notice", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: NotificationColors.primary)),
              ],
            ),
            content: const Text(
              "Bookings cannot be cancelled within 2 hours of the scheduled start time.",
              style: TextStyle(fontSize: 14, color: NotificationColors.textDark, height: 1.4),
            ),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: NotificationColors.primary),
                onPressed: () => Navigator.pop(context),
                child: const Text("OK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Cancel Booking?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: NotificationColors.primary)),
        content: const Text("Are you sure you want to cancel this booking? This will free the slot for other users.", style: TextStyle(fontSize: 14, color: NotificationColors.textDark)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), 
            child: const Text("Keep Booking", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NotificationColors.accent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Yes, Cancel", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final firestore = FirebaseFirestore.instance;
      WriteBatch batch = firestore.batch();

      final Map<String, dynamic> updatePayload = {
        'status': 'cancelled',
        'cancelled_at': FieldValue.serverTimestamp(),
      };

      // 1. User Subcollection
      batch.update(firestore.collection('users').doc(userId).collection(subcollectionName).doc(docId), updatePayload);

      // 2. Venue Subcollection
      String centerCollection = 'salons';
      String centerId = bookingData['salon_id'] ?? '';

      if (subcollectionName == 'turf_booking') {
        centerCollection = 'turf';
        centerId = bookingData['turf_id'] ?? '';
      } else if (subcollectionName == 'pet_booking') {
        centerCollection = 'pet_care';
        centerId = bookingData['pet_id'] ?? '';
      }

      if (centerId.isNotEmpty) {
        batch.update(firestore.collection(centerCollection).doc(centerId).collection('centre_orders').doc(docId), updatePayload);
      }

      // 3. Global Master Collection
      String globalCollection = 'booking_salon_service';
      if (subcollectionName == 'turf_booking') {
        globalCollection = 'booking_turf_service';
      } else if (subcollectionName == 'pet_booking') {
        globalCollection = 'booking_pet_service';
      }

      batch.update(firestore.collection(globalCollection).doc(docId), updatePayload);

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Booking cancelled and slot liberated.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error cancelling booking: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: NotificationColors.background,
      appBar: AppBar(
        backgroundColor: NotificationColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("My Bookings 🔔", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: NotificationColors.accent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey.shade400,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(text: "Active Bookings"),
            Tab(text: "Booking History"),
          ],
        ),
      ),
      body: user == null
          ? const Center(child: Text("Please sign in to view your bookings."))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('salon_booking').snapshots(),
              builder: (context, salonSnapshot) {
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('turf_booking').snapshots(),
                  builder: (context, turfSnapshot) {
                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('pet_booking').snapshots(),
                      builder: (context, petSnapshot) {
                        List<Map<String, dynamic>> allBookings = [];

                        if (salonSnapshot.hasData) {
                          for (var doc in salonSnapshot.data!.docs) {
                            final data = doc.data() as Map<String, dynamic>;
                            data['_doc_id'] = doc.id;
                            data['_subcollection'] = 'salon_booking';
                            allBookings.add(data);
                          }
                        }

                        if (turfSnapshot.hasData) {
                          for (var doc in turfSnapshot.data!.docs) {
                            final data = doc.data() as Map<String, dynamic>;
                            data['_doc_id'] = doc.id;
                            data['_subcollection'] = 'turf_booking';
                            allBookings.add(data);
                          }
                        }

                        if (petSnapshot.hasData) {
                          for (var doc in petSnapshot.data!.docs) {
                            final data = doc.data() as Map<String, dynamic>;
                            data['_doc_id'] = doc.id;
                            data['_subcollection'] = 'pet_booking';
                            allBookings.add(data);
                          }
                        }

                        // Sort newest first
                        allBookings.sort((a, b) {
                          Timestamp tA = a['timestamp'] ?? Timestamp.now();
                          Timestamp tB = b['timestamp'] ?? Timestamp.now();
                          return tB.compareTo(tA);
                        });

                        final activeList = allBookings.where((b) => (b['status'] ?? 'booked') != 'cancelled').toList();
                        final historyList = allBookings.where((b) => (b['status'] ?? 'booked') == 'cancelled').toList();

                        return TabBarView(
                          controller: _tabController,
                          children: [
                            _buildBookingList(activeList, user.uid, isActiveTab: true),
                            _buildBookingList(historyList, user.uid, isActiveTab: false),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildBookingList(List<Map<String, dynamic>> bookings, String userId, {required bool isActiveTab}) {
    if (bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActiveTab ? Icons.event_available_rounded : Icons.history_rounded,
              size: 60,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              isActiveTab ? "No active bookings found" : "No booking history",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: bookings.length,
      itemBuilder: (context, index) {
        final booking = bookings[index];
        final String docId = booking['_doc_id'];
        final String subcollection = booking['_subcollection'];
        
        String typeTitle = "SALON APPOINTMENT";
        IconData typeIcon = Icons.content_cut_rounded;
        Color badgeBg = const Color(0xFFF3E8FF);
        Color badgeFg = const Color(0xFF7E22CE);

        if (subcollection == 'turf_booking') {
          typeTitle = "TURF BOOKING";
          typeIcon = Icons.sports_soccer_rounded;
          badgeBg = const Color(0xFFDCFCE7);
          badgeFg = const Color(0xFF15803D);
        } else if (subcollection == 'pet_booking') {
          typeTitle = "PET CARE BOOKING";
          typeIcon = Icons.pets_rounded;
          badgeBg = const Color(0xFFFEF3C7);
          badgeFg = const Color(0xFFB45309);
        }

        final String venueName = booking['salon_name'] ?? booking['turf_name'] ?? booking['pet_name'] ?? 'Care Center';
        final String date = booking['booking_date'] ?? 'N/A';
        final String time = booking['booking_time'] ?? 'N/A';
        final String status = booking['status'] ?? 'booked';
        final List<dynamic> services = booking['selected_sports'] ?? booking['selected_services'] ?? [];

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black.withOpacity(0.04)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: badgeBg,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(typeIcon, size: 18, color: badgeFg),
                          const SizedBox(width: 8),
                          Text(
                            typeTitle,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: badgeFg),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: status == 'cancelled' ? Colors.red.shade100 : Colors.green.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: status == 'cancelled' ? Colors.red.shade800 : Colors.green.shade800,
                          ),
                        ),
                      )
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(venueName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: NotificationColors.primary)),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: NotificationColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_month_rounded, size: 16, color: NotificationColors.accent),
                                  const SizedBox(width: 6),
                                  Text(date, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: NotificationColors.textDark)),
                                ],
                              ),
                            ),
                            Container(width: 1, height: 16, color: Colors.grey.shade300),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.access_time_filled_rounded, size: 16, color: NotificationColors.accent),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: NotificationColors.textDark), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (services.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: services.map<Widget>((s) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Text(s.toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: NotificationColors.textDark)),
                            );
                          }).toList(),
                        ),
                      ],
                      if (isActiveTab && status != 'cancelled') ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1, thickness: 0.5),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: NotificationColors.accent,
                              side: const BorderSide(color: NotificationColors.accent, width: 1),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            ),
                            icon: const Icon(Icons.cancel_rounded, size: 16),
                            label: const Text("Cancel Booking", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: () => _cancelBooking(userId, subcollection, docId, booking),
                          ),
                        )
                      ]
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// 🔔 Reusable Bell Icon Badge Widget for AppBars
class NotificationBellIconButton extends StatelessWidget {
  const NotificationBellIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return IconButton(
        icon: const Icon(Icons.notifications_rounded, color: Colors.white),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationScreen())),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('salon_booking').where('status', isEqualTo: 'booked').snapshots(),
      builder: (context, salonSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('turf_booking').where('status', isEqualTo: 'booked').snapshots(),
          builder: (context, turfSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('pet_booking').where('status', isEqualTo: 'booked').snapshots(),
              builder: (context, petSnap) {
                int activeCount = 0;
                if (salonSnap.hasData) activeCount += salonSnap.data!.docs.length;
                if (turfSnap.hasData) activeCount += turfSnap.data!.docs.length;
                if (petSnap.hasData) activeCount += petSnap.data!.docs.length;

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_rounded, color: Colors.white),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationScreen())),
                    ),
                    if (activeCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            '$activeCount',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}