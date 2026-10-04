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

  // 🛡️ Safe DateTime parser for sorting regardless of whether it's stored as Timestamp, String, or null
  DateTime _parseDateTime(dynamic val) {
    if (val is Timestamp) {
      return val.toDate();
    } else if (val is String) {
      return DateTime.tryParse(val) ?? DateTime.now();
    }
    return DateTime.now();
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
    final String bDate = bookingData['booking_date'] ?? bookingData['pickup_date'] ?? bookingData['scheduled_date'] ?? '';
    final int slotStartMinutes = bookingData['slot_start_minutes'] ?? 0;

    // ⛔ Check 2-Hour Rule (for time-slotted bookings)
    if (bDate.isNotEmpty && slotStartMinutes > 0 && !_isCancellationAllowed(bDate, slotStartMinutes)) {
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
        content: const Text("Are you sure you want to cancel this booking? This action cannot be undone.", style: TextStyle(fontSize: 14, color: NotificationColors.textDark)),
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

      if (subcollectionName == 'food_orders') {
        batch.update(firestore.collection('orders').doc(docId), updatePayload);
      } else if (subcollectionName == 'home_service') {
        batch.update(firestore.collection('home_service').doc(docId), updatePayload);
      } else if (subcollectionName == 'laundry') {
        batch.update(firestore.collection('laundry').doc(docId), updatePayload);
      } else if (subcollectionName == 'pharmacy_orders') {
        batch.update(firestore.collection('users').doc(userId).collection('pharmacy_orders').doc(docId), updatePayload);
        batch.update(firestore.collection('pharmacy_orders').doc(docId), updatePayload);
      } else {
        batch.update(firestore.collection('users').doc(userId).collection(subcollectionName).doc(docId), updatePayload);
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Booking cancelled successfully.")),
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
        title: const Text("My Bookings & Orders 🔔", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
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
          ? const Center(child: Text("Please sign in to view your orders."))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('salon_booking').snapshots(),
              builder: (context, salonSnapshot) {
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('turf_booking').snapshots(),
                  builder: (context, turfSnapshot) {
                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('pet_booking').snapshots(),
                      builder: (context, petSnapshot) {
                        return StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('ride_booking').snapshots(),
                          builder: (context, rideSnapshot) {
                            return StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('tourist_bus_booking').snapshots(),
                              builder: (context, busSnapshot) {
                                return StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance.collection('orders').where('userId', isEqualTo: user.uid).snapshots(),
                                  builder: (context, foodSnapshot) {
                                    return StreamBuilder<QuerySnapshot>(
                                      stream: FirebaseFirestore.instance.collection('home_service').where('userId', isEqualTo: user.uid).snapshots(),
                                      builder: (context, homeServiceSnapshot) {
                                        return StreamBuilder<QuerySnapshot>(
                                          stream: FirebaseFirestore.instance.collection('laundry').where('userId', isEqualTo: user.uid).snapshots(),
                                          builder: (context, laundrySnapshot) {
                                            return StreamBuilder<QuerySnapshot>(
                                              stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('pharmacy_orders').snapshots(),
                                              builder: (context, pharmacySnapshot) {
                                                List<Map<String, dynamic>> allBookings = [];

                                                void addDocs(AsyncSnapshot<QuerySnapshot> snapshot, String subName) {
                                                  if (snapshot.hasData && snapshot.data != null) {
                                                    for (var doc in snapshot.data!.docs) {
                                                      final data = doc.data() as Map<String, dynamic>;
                                                      data['_doc_id'] = doc.id;
                                                      data['_subcollection'] = subName;
                                                      allBookings.add(data);
                                                    }
                                                  }
                                                }

                                                addDocs(salonSnapshot, 'salon_booking');
                                                addDocs(turfSnapshot, 'turf_booking');
                                                addDocs(petSnapshot, 'pet_booking');
                                                addDocs(rideSnapshot, 'ride_booking');
                                                addDocs(busSnapshot, 'tourist_bus_booking');
                                                addDocs(foodSnapshot, 'food_orders');
                                                addDocs(homeServiceSnapshot, 'home_service');
                                                addDocs(laundrySnapshot, 'laundry');
                                                addDocs(pharmacySnapshot, 'pharmacy_orders');

                                                // Safe sorting using _parseDateTime to prevent type casting crashes
                                                allBookings.sort((a, b) {
                                                  DateTime dateA = _parseDateTime(a['createdAt'] ?? a['timestamp'] ?? a['created_at']);
                                                  DateTime dateB = _parseDateTime(b['createdAt'] ?? b['timestamp'] ?? b['created_at']);
                                                  return dateB.compareTo(dateA);
                                                });

                                                final activeList = allBookings.where((b) => (b['status'] ?? 'booked').toString().toLowerCase() != 'cancelled').toList();
                                                final historyList = allBookings.where((b) => (b['status'] ?? 'booked').toString().toLowerCase() == 'cancelled').toList();

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
                                    );
                                  },
                                );
                              },
                            );
                          },
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
        } else if (subcollection == 'ride_booking') {
          typeTitle = "RIDE SERVICE";
          typeIcon = Icons.local_taxi_rounded;
          badgeBg = const Color(0xFFFEF08A);
          badgeFg = const Color(0xFFA16207);
        } else if (subcollection == 'tourist_bus_booking') {
          typeTitle = "TOURIST BUS BOOKING";
          typeIcon = Icons.directions_bus_rounded;
          badgeBg = const Color(0xFFE0F2FE);
          badgeFg = const Color(0xFF0369A1);
        } else if (subcollection == 'food_orders') {
          typeTitle = "FOOD & INSTAHUB ORDER";
          typeIcon = Icons.fastfood_rounded;
          badgeBg = const Color(0xFFFFEDD5);
          badgeFg = const Color(0xFFC2410C);
        } else if (subcollection == 'home_service') {
          typeTitle = "HOME SERVICE (${(booking['service_category'] ?? 'General').toString().toUpperCase()})";
          typeIcon = Icons.home_repair_service_rounded;
          badgeBg = const Color(0xFFE0E7FF);
          badgeFg = const Color(0xFF3730A3);
        } else if (subcollection == 'laundry') {
          typeTitle = "LAUNDRY SERVICE";
          typeIcon = Icons.local_laundry_service_rounded;
          badgeBg = const Color(0xFFE0F2FE);
          badgeFg = const Color(0xFF0284C7);
        } else if (subcollection == 'pharmacy_orders') {
          typeTitle = "PHARMACY PRESCRIPTION";
          typeIcon = Icons.medical_services_rounded;
          badgeBg = const Color(0xFFCCFBF1);
          badgeFg = const Color(0xFF0D9488);
        }

        final String venueName = booking['salon_name'] ?? 
            booking['turf_name'] ?? 
            booking['pet_name'] ?? 
            booking['vehicle_type'] ?? 
            booking['bus_name'] ?? 
            booking['service_category'] ??
            booking['washing_centre_name'] ??
            (subcollection == 'food_orders' ? "Food Delivery Order" : null) ??
            (subcollection == 'pharmacy_orders' ? "Medicine Request" : null) ??
            'Booking Details';

        final String date = booking['booking_date'] ?? booking['pickup_date'] ?? booking['scheduled_date'] ?? 'N/A';
        final String time = booking['booking_time'] ?? booking['pickup_time'] ?? booking['scheduled_time'] ?? booking['drop_location'] ?? booking['where_to_go'] ?? 'N/A';
        final String status = booking['status'] ?? 'booked';
        final List<dynamic> services = booking['selected_sports'] ?? booking['selected_services'] ?? booking['service_categories'] ?? [];

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
                                  Icon(
                                    subcollection == 'ride_booking' || subcollection == 'tourist_bus_booking' 
                                        ? Icons.location_on_rounded 
                                        : Icons.access_time_filled_rounded, 
                                    size: 16, 
                                    color: NotificationColors.accent
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      time, 
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: NotificationColors.textDark), 
                                      overflow: TextOverflow.ellipsis
                                    ),
                                  ),
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
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('ride_booking').where('status', isEqualTo: 'booked').snapshots(),
                  builder: (context, rideSnap) {
                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('tourist_bus_booking').where('status', isEqualTo: 'booked').snapshots(),
                      builder: (context, busSnap) {
                        return StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('orders').where('userId', isEqualTo: user.uid).where('status', isEqualTo: 'pending').snapshots(),
                          builder: (context, foodSnap) {
                            return StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance.collection('home_service').where('userId', isEqualTo: user.uid).where('status', isEqualTo: 'Pending').snapshots(),
                              builder: (context, homeSnap) {
                                return StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance.collection('laundry').where('userId', isEqualTo: user.uid).where('status', isEqualTo: 'Pending').snapshots(),
                                  builder: (context, laundrySnap) {
                                    return StreamBuilder<QuerySnapshot>(
                                      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('pharmacy_orders').where('status', isEqualTo: 'Pending Approval').snapshots(),
                                      builder: (context, pharmacySnap) {
                                        int activeCount = 0;
                                        if (salonSnap.hasData) activeCount += salonSnap.data!.docs.length;
                                        if (turfSnap.hasData) activeCount += turfSnap.data!.docs.length;
                                        if (petSnap.hasData) activeCount += petSnap.data!.docs.length;
                                        if (rideSnap.hasData) activeCount += rideSnap.data!.docs.length;
                                        if (busSnap.hasData) activeCount += busSnap.data!.docs.length;
                                        if (foodSnap.hasData) activeCount += foodSnap.data!.docs.length;
                                        if (homeSnap.hasData) activeCount += homeSnap.data!.docs.length;
                                        if (laundrySnap.hasData) activeCount += laundrySnap.data!.docs.length;
                                        if (pharmacySnap.hasData) activeCount += pharmacySnap.data!.docs.length;

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
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}