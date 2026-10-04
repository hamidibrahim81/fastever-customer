import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../notification/notificationscreen.dart';

class RideBookingFormScreen extends StatefulWidget {
  final Map<String, dynamic> selectedVehicle;
  final String? initialPickup;
  final String? initialDestination;

  const RideBookingFormScreen({
    super.key,
    required this.selectedVehicle,
    this.initialPickup,
    this.initialDestination,
  });

  @override
  State<RideBookingFormScreen> createState() => _RideBookingFormScreenState();
}

class _RideBookingFormScreenState extends State<RideBookingFormScreen> {
  // Theme Color Tokens matching FASTever Core
  static const Color primaryColor = Color(0xFF111827);
  static const Color accentColor = Color(0xFFFF4D6D);
  static const Color backgroundColor = Color(0xFFF7F8FA);
  static const Color textDark = Color(0xFF1F2937);
  static const Color textLight = Color(0xFF6B7280);

  final _formKey = GlobalKey<FormState>();

  // Input Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();
  final TextEditingController _commentsController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialPickup != null) {
      _pickupController.text = widget.initialPickup!;
    }
    if (widget.initialDestination != null) {
      _dropController.text = widget.initialDestination!;
    }
    _prefillUserData();
  }

  // Pre-fill user details if available
  Future<void> _prefillUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      if (user.displayName != null && user.displayName!.isNotEmpty) {
        _nameController.text = user.displayName!;
      }
      if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
        _phoneController.text = user.phoneNumber!;
      }

      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data();
          if (data != null) {
            if (_nameController.text.isEmpty && data['name'] != null) {
              _nameController.text = data['name'];
            }
            if (_phoneController.text.isEmpty && data['phone'] != null) {
              _phoneController.text = data['phone'];
            }
          }
        }
      } catch (e) {
        debugPrint("Error fetching user profile details: $e");
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _pickupController.dispose();
    _dropController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  Future<void> _makeCall(String phoneNumber) async {
    final uri = Uri.parse("tel:$phoneNumber");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll('+', '').replaceAll(' ', '');
    final uri = Uri.parse("https://wa.me/$cleanPhone?text=Hi,%20I%20have%20an%20inquiry%20regarding%20my%20ride%20booking.");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<String> _fetchSupportPhone() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('customer_supprt').get();
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        return data['support_call']?.toString() ?? "+918921752969";
      }
    } catch (_) {}
    return "+918921752969";
  }

  Future<void> _submitBooking() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final String uid = user?.uid ?? 'guest';

      final bookingPayload = {
        'user_id': uid,
        'user_name': _nameController.text.trim(),
        'user_phone': _phoneController.text.trim(),
        'pickup_location': _pickupController.text.trim(),
        'drop_location': _dropController.text.trim(),
        'comments': _commentsController.text.trim(),
        'vehicle_id': widget.selectedVehicle['id'],
        'vehicle_type': widget.selectedVehicle['title'],
        'min_charge': widget.selectedVehicle['min_charge'] ?? 0,
        'per_km_charge': widget.selectedVehicle['per_km_charge'] ?? 0,
        'status': 'booked',
        'created_at': FieldValue.serverTimestamp(),
      };

      // 1. Save to User Subcollection
      final docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('ride_booking')
          .add(bookingPayload);

      // 2. Save to Master Collection
      await FirebaseFirestore.instance
          .collection('booking_ride_service')
          .doc(docRef.id)
          .set(bookingPayload);

      final supportPhone = await _fetchSupportPhone();

      if (mounted) {
        setState(() => _isSubmitting = false);

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Column(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.green, size: 54),
                SizedBox(height: 10),
                Text(
                  "Booking Confirmed!",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Your request for a ${widget.selectedVehicle['title']} has been placed successfully.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: textDark, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.access_time_filled_rounded, color: Color(0xFF2563EB), size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Our team will contact you within 1 hr for assistance.",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E40AF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Need instant help? Reach support below:",
                  style: TextStyle(fontSize: 11, color: textLight),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: const Icon(Icons.phone_rounded, size: 16),
                        label: const Text("Call Us", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () => _makeCall(supportPhone),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: const Icon(Icons.chat_rounded, size: 16),
                        label: const Text("WhatsApp", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () => _openWhatsApp(supportPhone),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                  child: const Text("Done", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error placing ride booking: $e"),
            backgroundColor: accentColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.selectedVehicle;
    final num minCharge = vehicle['min_charge'] ?? 0;
    final num perKmCharge = vehicle['per_km_charge'] ?? 0;

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
        title: Text(
          "Book ${vehicle['title']} 🚖",
          style: const TextStyle(
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
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Vehicle Summary Banner with Rates
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.black.withOpacity(0.04)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: (vehicle['color'] as Color).withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              vehicle['icon'] as IconData,
                              color: vehicle['color'] as Color,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vehicle['title'] as String,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "${vehicle['subtitle']} • ${vehicle['capacity']}",
                                  style: const TextStyle(fontSize: 12, color: textLight),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 10),

                      // Fare Summary Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Minimum Charge", style: TextStyle(fontSize: 11, color: textLight)),
                              Text("₹$minCharge", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryColor)),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text("Rate Per KM", style: TextStyle(fontSize: 11, color: textLight)),
                              Text("₹$perKmCharge / KM", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: accentColor)),
                            ],
                          ),
                        ],
                      )
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Form Fields
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(color: Colors.black.withOpacity(0.03)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Passenger & Route Details 📝",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 18),

                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(fontSize: 14, color: textDark),
                        validator: (value) => value == null || value.trim().isEmpty ? 'Please enter your name' : null,
                        decoration: InputDecoration(
                          labelText: "Full Name",
                          prefixIcon: const Icon(Icons.person_outline_rounded, color: primaryColor),
                          filled: true,
                          fillColor: backgroundColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),

                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(fontSize: 14, color: textDark),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Please enter phone number';
                          if (value.trim().length < 10) return 'Enter a valid phone number';
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: "Phone Number",
                          prefixIcon: const Icon(Icons.phone_outlined, color: primaryColor),
                          filled: true,
                          fillColor: backgroundColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),

                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _pickupController,
                        style: const TextStyle(fontSize: 14, color: textDark),
                        validator: (value) => value == null || value.trim().isEmpty ? 'Please enter pickup location' : null,
                        decoration: InputDecoration(
                          labelText: "Pickup Location",
                          prefixIcon: const Icon(Icons.my_location_rounded, color: accentColor),
                          filled: true,
                          fillColor: backgroundColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),

                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _dropController,
                        style: const TextStyle(fontSize: 14, color: textDark),
                        validator: (value) => value == null || value.trim().isEmpty ? 'Please enter drop location' : null,
                        decoration: InputDecoration(
                          labelText: "Drop Location",
                          prefixIcon: const Icon(Icons.location_on_rounded, color: primaryColor),
                          filled: true,
                          fillColor: backgroundColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),

                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _commentsController,
                        maxLines: 3,
                        style: const TextStyle(fontSize: 14, color: textDark),
                        decoration: InputDecoration(
                          labelText: "Comments / Special Instructions",
                          hintText: "E.g., Fragile items, extra luggage, or pickup timing preference",
                          hintStyle: const TextStyle(fontSize: 12, color: textLight),
                          alignLabelWithHint: true,
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(bottom: 40),
                            child: Icon(Icons.chat_bubble_outline_rounded, color: primaryColor),
                          ),
                          filled: true,
                          fillColor: backgroundColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: primaryColor.withOpacity(0.3),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: _isSubmitting ? null : _submitBooking,
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            "Confirm Ride Request ➔",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}