import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../notification/notificationscreen.dart';

class TouristBusBookingFormScreen extends StatefulWidget {
  final Map<String, dynamic> selectedBus;

  const TouristBusBookingFormScreen({
    super.key,
    required this.selectedBus,
  });

  @override
  State<TouristBusBookingFormScreen> createState() => _TouristBusBookingFormScreenState();
}

class _TouristBusBookingFormScreenState extends State<TouristBusBookingFormScreen> {
  static const Color primaryColor = Color(0xFF111827);
  static const Color accentColor = Color(0xFFFF4D6D);
  static const Color backgroundColor = Color(0xFFF7F8FA);
  static const Color textDark = Color(0xFF1F2937);
  static const Color textLight = Color(0xFF6B7280);

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _whereToGoController = TextEditingController();
  final TextEditingController _commentsController = TextEditingController();
  final TextEditingController _pickupDateController = TextEditingController();

  DateTime? _selectedDate;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _prefillUserData();
  }

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
        debugPrint("Error prefilling profile data: $e");
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _whereToGoController.dispose();
    _commentsController.dispose();
    _pickupDateController.dispose();
    super.dispose();
  }

  Future<void> _selectPickupDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: primaryColor,
              onPrimary: Colors.white,
              onSurface: textDark,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _pickupDateController.text = DateFormat('dd MMM yyyy').format(picked);
      });
    }
  }

  Future<void> _makeCall(String phoneNumber) async {
    final uri = Uri.parse("tel:$phoneNumber");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll('+', '').replaceAll(' ', '');
    final uri = Uri.parse("https://wa.me/$cleanPhone?text=Hi,%20I%20have%20an%20inquiry%20regarding%20my%20bus%20booking.");
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
        'where_to_go': _whereToGoController.text.trim(),
        'comments': _commentsController.text.trim(),
        'pickup_date': _pickupDateController.text.trim(),
        'bus_id': widget.selectedBus['id'],
        'bus_name': widget.selectedBus['title'],
        'bus_location': widget.selectedBus['location'] ?? '',
        'status': 'booked',
        'created_at': FieldValue.serverTimestamp(),
      };

      // 1. Save to User Subcollection
      final docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tourist_bus_booking')
          .add(bookingPayload);

      // 2. Save to Master Collection
      await FirebaseFirestore.instance
          .collection('booking_tourist_bus_service')
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
                  "Your request for ${widget.selectedBus['title']} has been placed successfully.",
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
            content: Text("Error placing booking: $e"),
            backgroundColor: accentColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bus = widget.selectedBus;

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
          "Book ${bus['title']}",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
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
                // Vehicle Selected Banner
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
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.directions_bus_rounded,
                          color: primaryColor,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bus['title'] as String,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Location: ${(bus['location'] ?? 'Available').toString().toUpperCase()}",
                              style: const TextStyle(fontSize: 12, color: textLight),
                            ),
                          ],
                        ),
                      ),
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
                        "Passenger & Booking Details 📝",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Name Field
                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(fontSize: 14, color: textDark),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Please enter your name' : null,
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

                      // Phone Number Field
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(fontSize: 14, color: textDark),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter phone number';
                          if (v.trim().length < 10) return 'Enter a valid phone number';
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

                      // Where to Go Field
                      TextFormField(
                        controller: _whereToGoController,
                        style: const TextStyle(fontSize: 14, color: textDark),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Please enter destination' : null,
                        decoration: InputDecoration(
                          labelText: "Where to Go",
                          prefixIcon: const Icon(Icons.location_on_rounded, color: accentColor),
                          filled: true,
                          fillColor: backgroundColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Pickup Date Field
                      TextFormField(
                        controller: _pickupDateController,
                        readOnly: true,
                        onTap: _selectPickupDate,
                        style: const TextStyle(fontSize: 14, color: textDark),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Please select pickup date' : null,
                        decoration: InputDecoration(
                          labelText: "Pickup Date",
                          prefixIcon: const Icon(Icons.calendar_month_rounded, color: primaryColor),
                          suffixIcon: const Icon(Icons.arrow_drop_down_rounded, color: textLight),
                          filled: true,
                          fillColor: backgroundColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Comments Field
                      TextFormField(
                        controller: _commentsController,
                        maxLines: 3,
                        style: const TextStyle(fontSize: 14, color: textDark),
                        decoration: InputDecoration(
                          labelText: "Comments / Special Requirements",
                          hintText: "E.g., Number of passengers, luggage details, or time preferences",
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

                // Submit Button
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
                            "Confirm Bus Request ➔",
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