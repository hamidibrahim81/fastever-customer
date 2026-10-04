import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// Address selector import matching your project structure
import '../food/cart/ManageAddressScreen.dart';

class LabTestBookingScreen extends StatefulWidget {
  final Map<String, dynamic> selectedLab;

  const LabTestBookingScreen({
    super.key,
    required this.selectedLab,
  });

  @override
  State<LabTestBookingScreen> createState() => _LabTestBookingScreenState();
}

class _LabTestBookingScreenState extends State<LabTestBookingScreen> {
  final _formKey = GlobalKey<FormState>();

  // Input Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _landmarkController = TextEditingController();
  final TextEditingController _commentsController = TextEditingController();

  // Location configuration states
  String? _selectedAddress;
  double? _latitude;
  double? _longitude;
  bool _addressTouchedAndEmpty = false;
  bool _isSubmitting = false;

  // View more toggle for tests
  bool _showAllTests = false;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  final Map<String, bool> _testsSelectionMap = {};

  // Theme Colors
  static const Color primaryColor = Color(0xFF111827);
  static const Color accentColor = Color(0xFFFF4D6D);
  static const Color themePurple = Color(0xFF7E22CE);
  static const Color backgroundColor = Color(0xFFF6F6F9);

  @override
  void initState() {
    super.initState();
    // Populate services checkboxes from selected lab's `services` array
    final List<String> labServices =
        List<String>.from(widget.selectedLab['services'] ?? []);
    for (var service in labServices) {
      _testsSelectionMap[service] = false;
    }
    _prefillUserData();
  }

  Future<void> _prefillUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      if (user.displayName != null && user.displayName!.isNotEmpty) {
        _nameController.text = user.displayName!;
      }
      if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
        _contactController.text = user.phoneNumber!;
      }

      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          final data = doc.data();
          if (data != null) {
            if (_nameController.text.isEmpty && data['name'] != null) {
              _nameController.text = data['name'];
            }
            if (_contactController.text.isEmpty && data['phone'] != null) {
              _contactController.text = data['phone'];
            }
          }
        }
      } catch (e) {
        debugPrint("Error prefilling profile: $e");
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _landmarkController.dispose();
    _commentsController.dispose();
    super.dispose();
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
            colorScheme: const ColorScheme.light(
              primary: themePurple,
              onPrimary: Colors.white,
              onSurface: primaryColor,
            ),
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
      initialTime: _selectedTime ?? const TimeOfDay(hour: 7, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: themePurple,
              onPrimary: Colors.white,
              onSurface: primaryColor,
            ),
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

  Future<void> _submitLabTestBooking() async {
    List<String> chosenTests = [];
    _testsSelectionMap.forEach((test, isSelected) {
      if (isSelected) chosenTests.add(test);
    });

    if (chosenTests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please select at least one required test option.")),
      );
      return;
    }

    final bool formValid = _formKey.currentState!.validate();

    if (_selectedAddress == null || _selectedAddress!.isEmpty) {
      setState(() => _addressTouchedAndEmpty = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please select your sample collection address.")),
      );
      return;
    }

    if (!formValid) return;

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? 'guest';
      final FirebaseFirestore firestore = FirebaseFirestore.instance;

      final DocumentReference globalRef =
          firestore.collection('booking_lab_service').doc();
      final String orderId = globalRef.id;

      final String centreId = widget.selectedLab['centre_id'] ?? '';
      final String centreName =
          widget.selectedLab['name'] ?? 'Diagnostic Lab';

      final Map<String, dynamic> bookingPayload = {
        'order_id': orderId,
        'user_id': uid,
        'centre_id': centreId,
        'centre_name': centreName,
        'patient_name': _nameController.text.trim(),
        'contact_number': _contactController.text.trim(),
        'collection_address': _selectedAddress,
        'latitude': _latitude ?? 0.0,
        'longitude': _longitude ?? 0.0,
        'landmark': _landmarkController.text.trim(),
        'collection_date': _dateController.text.trim(),
        'collection_time': _timeController.text.trim(),
        'selected_tests': chosenTests,
        'comments': _commentsController.text.trim(),
        'status': 'booked',
        'results_sent': 'pending',
        'created_at': FieldValue.serverTimestamp(),
      };

      final DocumentReference userSubcollectionRef = firestore
          .collection('users')
          .doc(uid)
          .collection('lab_booking')
          .doc(orderId);

      DocumentReference? centreSubcollectionRef;
      if (centreId.isNotEmpty) {
        centreSubcollectionRef = firestore
            .collection('labs')
            .doc(centreId)
            .collection('centre_orders')
            .doc(orderId);
      }

      WriteBatch batch = firestore.batch();
      batch.set(globalRef, bookingPayload);
      batch.set(userSubcollectionRef, bookingPayload);
      if (centreSubcollectionRef != null) {
        batch.set(centreSubcollectionRef, bookingPayload);
      }

      await batch.commit();

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF3E8FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded,
                      color: themePurple, size: 55),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Lab Booking Confirmed!",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: primaryColor),
                ),
                const SizedBox(height: 12),
                Text(
                  "A certified sample collection partner from $centreName will reach your address at the selected date and time.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.grey.shade800, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pop(context);
                    },
                    child: const Text("OK",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Booking failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> labServices =
        List<String>.from(widget.selectedLab['services'] ?? []);

    // Slice to 5 items if not expanded
    final List<String> displayedServices = _showAllTests
        ? labServices
        : labServices.take(5).toList();

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 6,
        shadowColor: Colors.black.withOpacity(0.3),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.selectedLab['name'] ?? "Book Lab Test",
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🧪 Select Tests Available at this Lab (Max 5 with View More)
              if (labServices.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSectionHeader("Select Tests Needed *"),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10, right: 4),
                      child: Text(
                        "${_testsSelectionMap.values.where((v) => v).length} selected",
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: themePurple,
                        ),
                      ),
                    ),
                  ],
                ),
                _buildSectionContainer(
                  child: Column(
                    children: [
                      ...displayedServices.map((service) {
                        bool isChecked = _testsSelectionMap[service] ?? false;
                        return CheckboxListTile(
                          title: Text(
                            service,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isChecked
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isChecked ? themePurple : primaryColor,
                            ),
                          ),
                          value: isChecked,
                          activeColor: themePurple,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (bool? val) {
                            setState(() =>
                                _testsSelectionMap[service] = val ?? false);
                          },
                        );
                      }),

                      // View More / View Less Toggle Button
                      if (labServices.length > 5) ...[
                        const Divider(height: 16),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _showAllTests = !_showAllTests;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _showAllTests
                                      ? "View Less"
                                      : "View More Tests (+${labServices.length - 5})",
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: themePurple,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  _showAllTests
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: themePurple,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 22),
              ],

              // 👤 Patient Details
              _buildSectionHeader("Patient Details"),
              _buildSectionContainer(
                child: Column(
                  children: [
                    _buildField(_nameController, "Patient Full Name *",
                        Icons.person_outline_rounded),
                    const SizedBox(height: 6),
                    _buildField(
                        _contactController,
                        "Contact Number *",
                        Icons.phone_android_rounded,
                        keyboardType: TextInputType.phone),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // 📅 Sample Collection Schedule
              _buildSectionHeader("Select Pickup Schedule"),
              _buildSectionContainer(
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _selectDate,
                        child: IgnorePointer(
                          child: _buildField(_dateController, "Date *",
                              Icons.calendar_month_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: _selectTime,
                        child: IgnorePointer(
                          child: _buildField(_timeController, "Time *",
                              Icons.access_time_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // 📍 Home Address Section
              _buildSectionHeader("Sample Collection Address"),
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
                                color: _addressTouchedAndEmpty
                                    ? Colors.red.withOpacity(0.1)
                                    : themePurple.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Icon(
                                Icons.location_on_rounded,
                                color: _addressTouchedAndEmpty
                                    ? Colors.red.shade700
                                    : themePurple,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedAddress != null
                                        ? "Selected Pickup Address"
                                        : "Select saved address *",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _addressTouchedAndEmpty
                                          ? Colors.red.shade700
                                          : (_selectedAddress != null
                                              ? themePurple
                                              : Colors.grey.shade800),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selectedAddress ??
                                        "Tap to import address details",
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _selectedAddress != null
                                          ? Colors.black87
                                          : Colors.grey.shade500,
                                      height: 1.3,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded,
                                size: 14, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                    if (_addressTouchedAndEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(left: 16, bottom: 14),
                        child: Text(
                          "Collection address is mandatory *",
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 14),

              _buildSectionContainer(
                child: _buildField(
                    _landmarkController,
                    "Landmark / Flat / House No (Optional)",
                    Icons.domain_rounded),
              ),

              const SizedBox(height: 22),

              // 📝 Notes / Special Instructions
              _buildSectionHeader("Additional Instructions"),
              _buildSectionContainer(
                child: _buildField(
                    _commentsController,
                    "Add comments or special test requests (Optional)",
                    Icons.chat_bubble_outline_rounded,
                    maxLines: 3),
              ),

              const SizedBox(height: 35),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isSubmitting ? null : _submitLabTestBooking,
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "CONFIRM LAB BOOKING ➔",
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              letterSpacing: 0.5),
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
      child: Text(
        title,
        style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: primaryColor,
            letterSpacing: 0.3),
      ),
    );
  }

  Widget _buildSectionContainer(
      {required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }

  Widget _buildField(
      TextEditingController controller, String label, IconData icon,
      {int maxLines = 1,
      TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 15, color: primaryColor),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
              color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
          prefixIcon: Icon(icon, size: 22, color: Colors.grey.shade500),
          filled: true,
          fillColor: const Color(0xFFFAFAFC),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: themePurple, width: 1.8)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200, width: 1)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red.shade400, width: 1)),
          focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 1.8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        validator: (val) {
          if (label.contains("Optional")) return null;
          return (val == null || val.trim().isEmpty)
              ? "Field cannot be empty"
              : null;
        },
      ),
    );
  }
}