import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class SalonColors {
  static const Color primary = Color(0xFF111827);
  static const Color accent = Color(0xFFFF4D6D);
}

class SalonBookingForm extends StatefulWidget {
  final String salonId;
  final String salonName;
  final List<String> availableServices;

  const SalonBookingForm({
    required this.salonId,
    required this.salonName,
    required this.availableServices,
    super.key,
  });

  @override
  State<SalonBookingForm> createState() => _SalonBookingFormState();
}

class _SalonBookingFormState extends State<SalonBookingForm> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();

  bool _isSubmitting = false;

  DateTime? _selectedDate;
  String? _selectedSlotString;
  int? _selectedStartMinutes;
  int? _selectedEndMinutes;

  final Map<String, bool> _servicesSelectionMap = {};

  // Track reserved slot configurations for the selected day
  List<Map<String, int>> _reservedSlotsOnSelectedDate = [];

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
    _dateController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  // Generates 30-minute intervals from 10:00 AM (600 mins) to 9:00 PM (1260 mins)
  List<Map<String, dynamic>> _generateTimeSlots() {
    List<Map<String, dynamic>> slots = [];
    int start = 10 * 60; // 10:00 AM
    int end = 21 * 60;   // 9:00 PM

    while (start < end) {
      int next = start + 30;
      
      String startLabel = _formatMinutes(start);
      String endLabel = _formatMinutes(next);
      
      slots.add({
        'label': "$startLabel to $endLabel",
        'start_minutes': start,
        'end_minutes': next,
      });
      start = next;
    }
    return slots;
  }

  String _formatMinutes(int minutes) {
    int hour = minutes ~/ 60;
    int min = minutes % 60;
    String ampm = hour >= 12 ? "PM" : "AM";
    int displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    String minStr = min.toString().padLeft(2, '0');
    return "$displayHour:$minStr $ampm";
  }

  // 🔍 Fetch active (non-cancelled) booked blocks from Firestore for the chosen date
  Future<void> _updateReservedSlots() async {
    if (_dateController.text.isEmpty) return;
    
    try {
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('salons')
          .doc(widget.salonId)
          .collection('centre_orders')
          .where('booking_date', isEqualTo: _dateController.text)
          .get();

      List<Map<String, int>> reserved = [];
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final String status = data['status'] ?? 'booked';

        // ONLY treat as reserved if status is NOT cancelled
        if (status != 'cancelled') {
          int start = data['slot_start_minutes'] ?? 0;
          int end = data['slot_end_minutes'] ?? 0;
          reserved.add({'start': start, 'end': end});
        }
      }

      setState(() {
        _reservedSlotsOnSelectedDate = reserved;
      });
    } catch (e) {
      debugPrint("Error loading reserved blocks: $e");
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
            colorScheme: const ColorScheme.light(primary: SalonColors.accent, onPrimary: Colors.white, onSurface: Color(0xFF222222)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
        _selectedSlotString = null;
        _selectedStartMinutes = null;
        _selectedEndMinutes = null;
      });
      await _updateReservedSlots();
    }
  }

  void _showSlotPicker() async {
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select an appointment date first.")),
      );
      return;
    }

    await _updateReservedSlots();

    if (!mounted) return;

    final List<Map<String, dynamic>> slots = _generateTimeSlots();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Select Available Time Slot",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: SalonColors.primary),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: slots.length,
                  itemBuilder: (context, index) {
                    final slot = slots[index];
                    final int startMins = slot['start_minutes'];
                    final int endMins = slot['end_minutes'];
                    final bool isSelected = _selectedSlotString == slot['label'];

                    bool isAlreadyBooked = false;
                    for (var reserved in _reservedSlotsOnSelectedDate) {
                      if ((startMins >= reserved['start']! && startMins < reserved['end']!) ||
                          (endMins > reserved['start']! && endMins <= reserved['end']!) ||
                          (startMins <= reserved['start']! && endMins >= reserved['end']!)) {
                        isAlreadyBooked = true;
                        break;
                      }
                    }

                    Color containerBg;
                    Color textColor;
                    Color borderColor;
                    Widget? trailingWidget;

                    if (isAlreadyBooked) {
                      containerBg = Colors.grey.shade100;
                      textColor = Colors.grey.shade400;
                      borderColor = Colors.grey.shade200;
                      trailingWidget = const Text(
                        "Booked", 
                        style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      );
                    } else if (isSelected) {
                      containerBg = SalonColors.accent;
                      textColor = Colors.white;
                      borderColor = SalonColors.accent;
                      trailingWidget = const Icon(Icons.check_circle, color: Colors.white);
                    } else {
                      containerBg = const Color(0xFFFAFAFC);
                      textColor = SalonColors.primary;
                      borderColor = Colors.grey.shade200;
                      trailingWidget = null;
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Container(
                        decoration: BoxDecoration(
                          color: containerBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor, width: 1),
                        ),
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          enabled: !isAlreadyBooked,
                          title: Text(
                            slot['label'],
                            style: TextStyle(
                              fontWeight: (isSelected || isAlreadyBooked) ? FontWeight.bold : FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                          trailing: trailingWidget,
                          onTap: isAlreadyBooked ? null : () {
                            setState(() {
                              _selectedSlotString = slot['label'];
                              _selectedStartMinutes = startMins;
                              _selectedEndMinutes = endMins;
                            });
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitBooking() async {
    List<String> chosenServices = [];
    _servicesSelectionMap.forEach((service, isSelected) {
      if (isSelected) chosenServices.add(service);
    });

    if (chosenServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please choose at least one grooming service option.")),
      );
      return;
    }

    final bool formValid = _formKey.currentState!.validate();

    if (!formValid || _selectedSlotString == null || _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all required inputs and select a time slot.")),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Authentication required.")));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;

      await _updateReservedSlots();
      
      bool isConflict = false;
      for (var reserved in _reservedSlotsOnSelectedDate) {
        if ((_selectedStartMinutes! >= reserved['start']! && _selectedStartMinutes! < reserved['end']!) ||
            (_selectedEndMinutes! > reserved['start']! && _selectedEndMinutes! <= reserved['end']!) ||
            (_selectedStartMinutes! <= reserved['start']! && _selectedEndMinutes! >= reserved['end']!)) {
          isConflict = true;
          break;
        }
      }

      if (isConflict) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "This specific time block is already reserved. Please select another slot!",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: Color(0xFFD32F2F), 
            duration: Duration(seconds: 2), 
          ),
        );
        setState(() => _isSubmitting = false);
        return;
      }

      final DocumentReference globalBookingRef = firestore.collection('booking_salon_service').doc();
      final String orderId = globalBookingRef.id;

      final DocumentReference salonSubcollectionRef = firestore
          .collection('salons')
          .doc(widget.salonId)
          .collection('centre_orders')
          .doc(orderId);

      final DocumentReference userSubcollectionRef = firestore
          .collection('users')
          .doc(user.uid)
          .collection('salon_booking')
          .doc(orderId);

      final Map<String, dynamic> bookingPayload = {
        'order_id': orderId,
        'salon_id': widget.salonId, 
        'salon_name': widget.salonName,
        'name': _nameController.text.trim(),
        'contact': _contactController.text.trim(),
        'booking_date': _dateController.text,
        'booking_time': _selectedSlotString,
        'slot_start_minutes': _selectedStartMinutes,
        'slot_end_minutes': _selectedEndMinutes,
        'selected_services': chosenServices,
        'comments': _commentController.text.trim(),
        'userId': user.uid,
        'status': 'booked',
        'timestamp': FieldValue.serverTimestamp(),
      };

      WriteBatch batch = firestore.batch();
      batch.set(globalBookingRef, bookingPayload);
      batch.set(salonSubcollectionRef, bookingPayload);
      batch.set(userSubcollectionRef, bookingPayload);
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
                  decoration: const BoxDecoration(color: Color(0xFFFEF2F2), shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle_rounded, color: SalonColors.accent, size: 55),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Booking Confirmed!",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Color(0xFF222222)),
                ),
                const SizedBox(height: 14),
                const Text(
                  "Your booking of time is successfully registered! Please arrive at your selected slot timing for a premium hassle-free experience.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF1F2937), fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1, height: 1.4),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "Need Support or Assistance?",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF111827)),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.phone_rounded, size: 14, color: SalonColors.accent),
                          SizedBox(width: 6),
                          Text("+918921752969", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.mail_outline_rounded, size: 14, color: SalonColors.accent),
                          SizedBox(width: 6),
                          Text("bloohostgroup.official@gmail.com", style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                        ],
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 24),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        centerTitle: true,
        title: Text(
          widget.salonName,
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
                          color: isChecked ? SalonColors.accent : const Color(0xFF222222),
                        ),
                      ),
                      value: isChecked,
                      activeColor: SalonColors.accent,
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
                    _buildField(_nameController, "Your Name *", Icons.person_outline_rounded, SalonColors.accent),
                    const SizedBox(height: 4),
                    _buildField(_contactController, "Contact Number *", Icons.phone_android_rounded, SalonColors.accent, keyboardType: TextInputType.phone),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _buildSectionHeader("Select Appointment Schedule"),
              _buildSectionContainer(
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _selectDate,
                        child: IgnorePointer(
                          child: _buildField(_dateController, "Appointment Date *", Icons.calendar_month_rounded, SalonColors.accent),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: _showSlotPicker,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAFAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200, width: 1),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.access_time_rounded, size: 22, color: Colors.grey.shade500),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _selectedSlotString ?? "Select Slot *",
                                  style: TextStyle(
                                    fontSize: 14, 
                                    color: _selectedSlotString != null ? const Color(0xFF111827) : Colors.grey,
                                    fontWeight: _selectedSlotString != null ? FontWeight.w600 : FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _buildSectionHeader("Additional Instructions"),
              _buildSectionContainer(
                child: _buildField(_commentController, "Add comments or preferences details (Optional)", Icons.chat_bubble_outline_rounded, SalonColors.accent, maxLines: 3),
              ),
              const SizedBox(height: 35),
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: SalonColors.accent.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 6))
                  ],
                ),
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: SalonColors.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: _isSubmitting ? null : _submitBooking,
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "CONFIRM SALON APPOINTMENT",
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