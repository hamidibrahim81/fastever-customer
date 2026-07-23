import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class TurfColors {
  static const Color primary = Color(0xFF111827);
  static const Color accent = Color(0xFFFF4D6D);
}

class TurfBookingFormScreen extends StatefulWidget {
  final String turfId;
  final String turfName;
  final List<String> availableSports;

  const TurfBookingFormScreen({
    required this.turfId,
    required this.turfName,
    required this.availableSports,
    super.key,
  });

  @override
  State<TurfBookingFormScreen> createState() => _TurfBookingFormScreenState();
}

class _TurfBookingFormScreenState extends State<TurfBookingFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();

  bool _isSubmitting = false;

  DateTime? _selectedDate;

  // Selected multi-slot tracking list for adding multiple hours
  final List<Map<String, dynamic>> _selectedSlots = [];

  final Map<String, bool> _sportsSelectionMap = {};

  // Track reserved slot configurations for the selected day from Firestore
  List<Map<String, int>> _reservedSlotsOnSelectedDate = [];

  @override
  void initState() {
    super.initState();
    for (var sport in widget.availableSports) {
      _sportsSelectionMap[sport] = false;
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

  // ⚽ Generates 1-HOUR intervals from 6:00 AM (360 mins) to 12:00 AM Midnight (1440 mins)
  List<Map<String, dynamic>> _generate1HourTimeSlots() {
    List<Map<String, dynamic>> slots = [];
    int start = 6 * 60; // 6:00 AM
    int end = 24 * 60; // 12:00 AM Midnight

    while (start < end) {
      int next = start + 60; // 1 Hour (60 mins)

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
    int hour = (minutes ~/ 60) % 24;
    int min = minutes % 60;
    String ampm = (minutes ~/ 60) >= 12 && (minutes ~/ 60) < 24 ? "PM" : "AM";
    int displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    String minStr = min.toString().padLeft(2, '0');
    return "$displayHour:$minStr $ampm";
  }

  // 🔍 Fetch active (non-cancelled) reserved slots from Firestore
  Future<void> _updateReservedSlots() async {
    if (_dateController.text.isEmpty) return;

    try {
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('turf')
          .doc(widget.turfId)
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
      debugPrint("Error loading reserved turf blocks: $e");
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: TurfColors.accent,
              onPrimary: Colors.white,
              onSurface: Color(0xFF222222),
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
        _selectedSlots.clear();
      });
      await _updateReservedSlots();
    }
  }

  void _showSlotPicker() async {
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a date first.")),
      );
      return;
    }

    await _updateReservedSlots();

    if (!mounted) return;

    final List<Map<String, dynamic>> slots = _generate1HourTimeSlots();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setBottomSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Select Turf Hours (1-Hr Slots)",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: TurfColors.primary,
                        ),
                      ),
                      Text(
                        "${_selectedSlots.length} Hr(s) Selected",
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: TurfColors.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: slots.length,
                      itemBuilder: (context, index) {
                        final slot = slots[index];
                        final int startMins = slot['start_minutes'];
                        final int endMins = slot['end_minutes'];

                        final bool isSelected = _selectedSlots.any((element) =>
                            element['start_minutes'] == startMins &&
                            element['end_minutes'] == endMins);

                        // Check non-cancelled reserved overlaps
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
                            "Reserved",
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        } else if (isSelected) {
                          containerBg = TurfColors.accent;
                          textColor = Colors.white;
                          borderColor = TurfColors.accent;
                          trailingWidget = const Icon(Icons.check_circle, color: Colors.white);
                        } else {
                          containerBg = const Color(0xFFFAFAFC);
                          textColor = TurfColors.primary;
                          borderColor = Colors.grey.shade200;
                          trailingWidget = const Icon(Icons.add_circle_outline, color: Colors.grey);
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
                              onTap: isAlreadyBooked
                                  ? null
                                  : () {
                                      setBottomSheetState(() {
                                        if (isSelected) {
                                          _selectedSlots.removeWhere((element) =>
                                              element['start_minutes'] == startMins);
                                        } else {
                                          _selectedSlots.add(slot);
                                          _selectedSlots.sort((a, b) => (a['start_minutes'] as int)
                                              .compareTo(b['start_minutes'] as int));
                                        }
                                      });
                                      setState(() {});
                                    },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: TurfColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text("CONFIRM SELECTED HOURS", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _getSlotsSummaryText() {
    if (_selectedSlots.isEmpty) return "Select Turf Hours *";
    if (_selectedSlots.length == 1) return _selectedSlots.first['label'];

    int startMins = _selectedSlots.first['start_minutes'];
    int endMins = _selectedSlots.last['end_minutes'];

    return "${_formatMinutes(startMins)} to ${_formatMinutes(endMins)} (${_selectedSlots.length} hrs)";
  }

  Future<void> _submitBooking() async {
    List<String> chosenSports = [];
    _sportsSelectionMap.forEach((sport, isSelected) {
      if (isSelected) chosenSports.add(sport);
    });

    if (chosenSports.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select at least one sport preference.")),
      );
      return;
    }

    final bool formValid = _formKey.currentState!.validate();

    if (!formValid || _selectedSlots.isEmpty || _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please complete required fields and select at least one hour slot.")),
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

      int minStart = _selectedSlots.first['start_minutes'];
      int maxEnd = _selectedSlots.last['end_minutes'];

      bool isConflict = false;
      for (var slot in _selectedSlots) {
        int sMins = slot['start_minutes'];
        int eMins = slot['end_minutes'];

        for (var reserved in _reservedSlotsOnSelectedDate) {
          if ((sMins >= reserved['start']! && sMins < reserved['end']!) ||
              (eMins > reserved['start']! && eMins <= reserved['end']!) ||
              (sMins <= reserved['start']! && eMins >= reserved['end']!)) {
            isConflict = true;
            break;
          }
        }
        if (isConflict) break;
      }

      if (isConflict) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "One or more selected slots were just booked. Please pick another time!",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: Color(0xFFD32F2F),
            duration: Duration(seconds: 2),
          ),
        );
        setState(() => _isSubmitting = false);
        return;
      }

      final DocumentReference globalBookingRef = firestore.collection('booking_turf_service').doc();
      final String orderId = globalBookingRef.id;

      final DocumentReference turfSubcollectionRef = firestore
          .collection('turf')
          .doc(widget.turfId)
          .collection('centre_orders')
          .doc(orderId);

      final DocumentReference userSubcollectionRef = firestore
          .collection('users')
          .doc(user.uid)
          .collection('turf_booking')
          .doc(orderId);

      final Map<String, dynamic> bookingPayload = {
        'order_id': orderId,
        'turf_id': widget.turfId,
        'turf_name': widget.turfName,
        'name': _nameController.text.trim(),
        'contact': _contactController.text.trim(),
        'booking_date': _dateController.text,
        'booking_time': _getSlotsSummaryText(),
        'slot_start_minutes': minStart,
        'slot_end_minutes': maxEnd,
        'selected_sports': chosenSports,
        'comments': _commentController.text.trim(),
        'userId': user.uid,
        'status': 'booked',
        'timestamp': FieldValue.serverTimestamp(),
      };

      WriteBatch batch = firestore.batch();
      batch.set(globalBookingRef, bookingPayload);
      batch.set(turfSubcollectionRef, bookingPayload);
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
                  child: const Icon(Icons.sports_soccer_rounded, color: TurfColors.accent, size: 55),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Turf Reserved!",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Color(0xFF222222)),
                ),
                const SizedBox(height: 14),
                const Text(
                  "Your turf slot has been successfully booked! Please arrive on time with your team for a smooth session.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF1F2937), fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
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
                        "Need Assistance?",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF111827)),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.phone_rounded, size: 14, color: TurfColors.accent),
                          SizedBox(width: 6),
                          Text("+918921752969", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
                        ],
                      ),
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
          widget.turfName,
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
              _buildSectionHeader("Select Sports Category"),
              _buildSectionContainer(
                child: Column(
                  children: widget.availableSports.map<Widget>((sport) {
                    bool isChecked = _sportsSelectionMap[sport] ?? false;
                    return CheckboxListTile(
                      title: Text(
                        sport,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isChecked ? FontWeight.bold : FontWeight.w500,
                          color: isChecked ? TurfColors.accent : const Color(0xFF222222),
                        ),
                      ),
                      value: isChecked,
                      activeColor: TurfColors.accent,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (bool? val) {
                        setState(() => _sportsSelectionMap[sport] = val ?? false);
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 22),
              _buildSectionHeader("Player Details"),
              _buildSectionContainer(
                child: Column(
                  children: [
                    _buildField(_nameController, "Your Name *", Icons.person_outline_rounded, TurfColors.accent),
                    const SizedBox(height: 4),
                    _buildField(_contactController, "Contact Number *", Icons.phone_android_rounded, TurfColors.accent, keyboardType: TextInputType.phone),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _buildSectionHeader("Booking Date & Hours"),
              _buildSectionContainer(
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _selectDate,
                        child: IgnorePointer(
                          child: _buildField(_dateController, "Select Date *", Icons.calendar_month_rounded, TurfColors.accent),
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
                                  _getSlotsSummaryText(),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _selectedSlots.isNotEmpty ? const Color(0xFF111827) : Colors.grey,
                                    fontWeight: _selectedSlots.isNotEmpty ? FontWeight.w600 : FontWeight.w500,
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
                child: _buildField(_commentController, "Add comments or special requests (Optional)", Icons.chat_bubble_outline_rounded, TurfColors.accent, maxLines: 3),
              ),
              const SizedBox(height: 35),
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: TurfColors.accent.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 6))
                  ],
                ),
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: TurfColors.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: _isSubmitting ? null : _submitBooking,
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "CONFIRM TURF BOOKING",
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