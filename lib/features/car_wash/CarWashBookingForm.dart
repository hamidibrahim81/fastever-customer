import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// Ensure this path matches your project structure for address retrieval
import '../food/cart/ManageAddressScreen.dart';

class CarWashBookingForm extends StatefulWidget {
  final String centreId;
  final String centreName;
  final List<String> availableServices;

  const CarWashBookingForm({
    required this.centreId,
    required this.centreName,
    required this.availableServices,
    super.key,
  });

  @override
  State<CarWashBookingForm> createState() => _CarWashBookingFormState();
}

class _CarWashBookingFormState extends State<CarWashBookingForm> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _landmarkController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();

  // Location configuration states
  String? _selectedAddress;
  double? _latitude;
  double? _longitude;
  bool _isSubmitting = false;
  bool _addressTouchedAndEmpty = false;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  // Track checked laundry services map checklist matrix
  final Map<String, bool> _servicesSelectionMap = {};

  @override
  void initState() {
    super.initState();
    for (var service in widget.availableServices) {
      _servicesSelectionMap[service] = false;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _landmarkController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Color _getThemeColor() {
    return const Color(0xFFFF4D6D); 
  }

  Future<void> _pickAddress() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ManageAddressScreen()),
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _selectedAddress = result['full_display_address'] as String?;
        _latitude = result['lat'] as double?;
        _longitude = result['lng'] as double?;
        _addressTouchedAndEmpty = false;
      });
    } else if (result != null && result is String) {
      setState(() {
        _selectedAddress = result;
        _latitude = 0.0;
        _longitude = 0.0;
        _addressTouchedAndEmpty = false;
      });
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 14)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: _getThemeColor(), onPrimary: Colors.white, onSurface: const Color(0xFF222222)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: _getThemeColor(), onPrimary: Colors.white, onSurface: const Color(0xFF222222)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
        _timeController.text = picked.format(context);
      });
    }
  }

  Future<void> _submitBooking() async {
    List<String> chosenServices = [];
    _servicesSelectionMap.forEach((service, isSelected) {
      if (isSelected) chosenServices.add(service);
    });

    if (chosenServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please choose at least one washing service option.")),
      );
      return;
    }

    final bool formValid = _formKey.currentState!.validate();

    if (_selectedAddress == null || _selectedAddress!.isEmpty) {
      setState(() => _addressTouchedAndEmpty = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select your address profile location.")),
      );
      return;
    }

    if (!formValid) return;

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final FirebaseFirestore firestore = FirebaseFirestore.instance;

      // 1. Generate a common reference to share the exact same generated document ID
      final DocumentReference globalBookingRef = firestore.collection('booking_washing_service').doc();
      final String orderId = globalBookingRef.id;

      // 2. Setup reference for the new subcollection under the specific washing centre
      final DocumentReference centreSubcollectionRef = firestore
          .collection('washing_centre')
          .doc(widget.centreId)
          .collection('centre_orders')
          .doc(orderId);

      // 3. Prepare dataset map layout containing payment status modifications
      final Map<String, dynamic> bookingPayload = {
        'order_id': orderId,
        'washing_centre_id': widget.centreId, 
        'washing_centre_name': widget.centreName,
        'name': _nameController.text.trim(),
        'contact': _contactController.text.trim(),
        'address': _selectedAddress,
        'latitude': _latitude ?? 0.0,
        'longitude': _longitude ?? 0.0,
        'landmark': _landmarkController.text.trim(),
        'pickup_date': _dateController.text,
        'pickup_time': _timeController.text,
        'selected_services': chosenServices,
        'comments': _commentController.text.trim(),
        'userId': user?.uid ?? 'anonymous',
        'status': 'Pending',
        'payment_of_centre': 'pending',
        'payment_of_customer': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      };

      // 4. Commit atomic dual-write deployment sequence
      WriteBatch batch = firestore.batch();
      batch.set(globalBookingRef, bookingPayload);
      batch.set(centreSubcollectionRef, bookingPayload);
      await batch.commit();

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                  child: Icon(Icons.check_circle_rounded, color: _getThemeColor(), size: 55),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Booking Confirmed!",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Color(0xFF222222)),
                ),
                const SizedBox(height: 14),
                Text(
                  "Our pickup partner will call you shortly and arrive at your preferred time for a smooth and hassle-free pickup.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade800, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2),
                ),
                const SizedBox(height: 8),
                Text(
                  "സൗകര്യപ്രദമായ പിക്കപ്പിനായി, ഞങ്ങളുടെ പിക്കപ്പ് പങ്കാളി ഉടൻ നിങ്ങളെ വിളിച്ച് നിങ്ങൾ തിരഞ്ഞെടുത്ത സമയത്ത് എത്തിച്ചേരുന്നതാണ്.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF111827),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(context); 
                      Navigator.pop(context); 
                    },
                    child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Booking failed: $e")));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = _getThemeColor();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        centerTitle: true,
        title: Text(
          widget.centreName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader("Select Services Needed"),
              _buildSectionContainer(
                child: Column(
                  children: widget.availableServices.map<Widget>((service) {
                    bool isChecked = _servicesSelectionMap[service] ?? false;
                    return CheckboxListTile(
                      title: Text(
                        service,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isChecked ? FontWeight.bold : FontWeight.w500,
                          color: isChecked ? themeColor : const Color(0xFF222222),
                        ),
                      ),
                      value: isChecked,
                      activeColor: themeColor,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (bool? val) {
                        setState(() => _servicesSelectionMap[service] = val ?? false);
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 22),
              _buildSectionHeader("Customer Details"),
              _buildSectionContainer(
                child: Column(
                  children: [
                    _buildField(_nameController, "Your Name *", Icons.person_outline_rounded, themeColor),
                    const SizedBox(height: 4),
                    _buildField(_contactController, "Contact Number *", Icons.phone_android_rounded, themeColor, keyboardType: TextInputType.phone),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _buildSectionHeader("Select Pickup Schedule"),
              _buildSectionContainer(
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _selectDate,
                        child: IgnorePointer(
                          child: _buildField(_dateController, "Pickup Date *", Icons.calendar_month_rounded, themeColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: _selectTime,
                        child: IgnorePointer(
                          child: _buildField(_timeController, "Pickup Time *", Icons.access_time_rounded, themeColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _buildSectionHeader("Pickup Location"),
              _buildSectionContainer(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: _pickAddress,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: _addressTouchedAndEmpty ? Colors.red.withOpacity(0.1) : themeColor.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Icon(
                                Icons.location_on_rounded,
                                color: _addressTouchedAndEmpty ? Colors.red.shade700 : themeColor,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedAddress != null ? "Selected Pickup Address" : "Select saved address *",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _addressTouchedAndEmpty ? Colors.red.shade700 : (_selectedAddress != null ? themeColor : Colors.grey.shade800),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selectedAddress ?? "Tap to import your address details",
                                    style: TextStyle(fontSize: 13, color: _selectedAddress != null ? Colors.black87 : Colors.grey.shade500, height: 1.3),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                    if (_addressTouchedAndEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(left: 16, bottom: 14),
                        child: Text("Pickup address is mandatory *", style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSectionContainer(
                child: _buildField(_landmarkController, "Landmark / Flat / Building Floor (Optional)", Icons.domain_rounded, themeColor),
              ),
              const SizedBox(height: 22),
              _buildSectionHeader("Additional Instructions"),
              _buildSectionContainer(
                child: _buildField(_commentController, "Add comments or vehicle details (Optional)", Icons.chat_bubble_outline_rounded, themeColor, maxLines: 3),
              ),
              const SizedBox(height: 35),
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: themeColor.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 6))
                  ],
                ),
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: themeColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: _isSubmitting ? null : _submitBooking,
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "CONFIRM VEHICLE WASH BOOKING",
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white, letterSpacing: 0.5),
                        ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF111827), letterSpacing: 0.3)),
    );
  }

  Widget _buildSectionContainer({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: child,
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, Color focusColor, {int maxLines = 1, TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 15, color: Color(0xFF111827)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
          prefixIcon: Icon(icon, size: 22, color: Colors.grey.shade500),
          filled: true,
          fillColor: const Color(0xFFFAFAFC),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: focusColor, width: 1.8)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200, width: 1)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.shade400, width: 1)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red, width: 1.8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        validator: (val) {
          if (label.contains("Optional")) return null;
          return (val == null || val.isEmpty) ? "Field cannot be empty" : null;
        },
      ),
    );
  }
}