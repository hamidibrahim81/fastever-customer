import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lottie/lottie.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as maps;

class TrackOrderScreen extends StatefulWidget {
  final String orderId;

  const TrackOrderScreen({super.key, required this.orderId});

  @override
  State<TrackOrderScreen> createState() => _TrackOrderScreenState();
}

class _TrackOrderScreenState extends State<TrackOrderScreen> {
  Timer? _timer;
  Timer? _animTimer;

  maps.GoogleMapController? _mapController;
  final Set<maps.Marker> _markers = {};
  final Set<maps.Polyline> _polylines = {};

  bool _isMapReady = false;

  GeoPoint? _lastDriverGeo;
  maps.LatLng? _animatedDriverLatLng;

  double _driverRotation = 0.0;

  @override
  void initState() {
    super.initState();
    _saveDeviceToken();

    // ✅ Smooth countdown (seconds)
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _saveDeviceToken() async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('order_status')
            .doc(widget.orderId)
            .set({'fcmToken': token}, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Error saving FCM token: $e");
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  double _bearing(maps.LatLng a, maps.LatLng b) {
    final lat1 = a.latitude * math.pi / 180;
    final lon1 = a.longitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final lon2 = b.longitude * math.pi / 180;
    final dLon = lon2 - lon1;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final brng = math.atan2(y, x);
    final deg = (brng * 180 / math.pi + 360) % 360;
    return deg;
  }

  // ✅ Smooth marker animation for 60-sec driver updates
  void _animateDriverTo(maps.LatLng next) {
    final prev = _animatedDriverLatLng ?? next;

    _animTimer?.cancel();

    // Animate for ~55 seconds (keeps marker moving even if updates are 60s)
    const totalSeconds = 55;
    const fps = 15; // smooth + light
    final totalSteps = totalSeconds * fps;
    final stepMs = (1000 / fps).round();

    final rot = _bearing(prev, next);
    _driverRotation = rot;

    int step = 0;
    _animTimer = Timer.periodic(Duration(milliseconds: stepMs), (t) {
      step++;
      final f = step / totalSteps;

      final lat = prev.latitude + (next.latitude - prev.latitude) * f;
      final lng = prev.longitude + (next.longitude - prev.longitude) * f;
      final cur = maps.LatLng(lat, lng);

      _animatedDriverLatLng = cur;
      _setMarkersAndPolyline(cur);

      if (mounted) setState(() {});

      if (step >= totalSteps) {
        t.cancel();
        _animatedDriverLatLng = next;
        _setMarkersAndPolyline(next);
        if (mounted) setState(() {});
      }
    });
  }

  void _setMarkersAndPolyline(maps.LatLng driverLatLng) {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'driver');
      _markers.add(
        maps.Marker(
          markerId: const maps.MarkerId('driver'),
          position: driverLatLng,
          flat: true,
          rotation: _driverRotation,
          anchor: const Offset(0.5, 0.5),
          icon: maps.BitmapDescriptor.defaultMarkerWithHue(
            maps.BitmapDescriptor.hueOrange,
          ),
          infoWindow: const maps.InfoWindow(title: "Delivery Partner"),
        ),
      );

      // Draw straight line polyline (simple route preview)
      _polylines.clear();
      if (_destLatLng != null) {
        _polylines.add(
          maps.Polyline(
            polylineId: const maps.PolylineId("route"),
            points: [driverLatLng, _destLatLng!],
            width: 5,
          ),
        );
      }
    });
  }

  maps.LatLng? _destLatLng;

  void _updateMapCameraWithLatLng(maps.LatLng driverLatLng) {
    if (_mapController == null) return;
    _mapController!.animateCamera(
      maps.CameraUpdate.newLatLngZoom(driverLatLng, 15),
    );
  }

  // ===========================
  // ADVANCED ETA LOGIC
  // ===========================
  int _remainingSeconds(Map<String, dynamic> data) {
    String rawStatus =
        (data['status'] ?? 'confirmed').toString().toLowerCase().trim();

    String status = rawStatus.replaceAll(' ', '_').replaceAll('-', '_');

    if (status == 'delivered') return 0;
    if (status == 'arrived') return 0;

    final DateTime createdAt =
        (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

    final DateTime stageStart =
        (data['lastUpdated'] as Timestamp?)?.toDate() ?? createdAt;

    final int elapsedTotalMins =
        DateTime.now().difference(createdAt).inMinutes;

    final int elapsedStageMins =
        DateTime.now().difference(stageStart).inMinutes;

    final double distanceKm = (data['distanceKm'] is num)
        ? (data['distanceKm'] as num).toDouble()
        : 0.0;

    final int travelMins = (distanceKm * 5).round();

    const int restaurantBase = 5;
    const int cookingBase = 15;
    const int partnerBase = 5;
    const int loopAdd = 5;
    const int loopEvery = 5;

    int baseTotal = restaurantBase + cookingBase + partnerBase + travelMins;

    int addLoopAfterBase({required int elapsed, required int base}) {
      if (elapsed <= base) return 0;
      final extra = elapsed - base;
      final blocks = (extra + loopEvery - 1) ~/ loopEvery;
      return blocks * loopAdd;
    }

    int addLoopFromStart({required int elapsed}) {
      final blocks = elapsed ~/ loopEvery;
      return blocks * loopAdd;
    }

    int extraAdded = 0;

    if (status == 'confirmed') {
      extraAdded = addLoopFromStart(elapsed: elapsedStageMins);
    } else if (status == 'restaurant_accepted' || status == 'preparing_food') {
      extraAdded =
          addLoopAfterBase(elapsed: elapsedStageMins, base: cookingBase);
    } else if (status == 'ready') {
      extraAdded = addLoopFromStart(elapsed: elapsedStageMins);
    } else if (status == 'partner_picked') {
      extraAdded = addLoopAfterBase(elapsed: elapsedStageMins, base: travelMins);
    }

    final int remainingMins = (baseTotal + extraAdded) - elapsedTotalMins;

    // Convert to seconds smoothly
    final int elapsedTotalSecs = DateTime.now().difference(createdAt).inSeconds;
    final int targetTotalSecs = (baseTotal + extraAdded) * 60;
    return targetTotalSecs - elapsedTotalSecs;
  }

  String _formatTime(int seconds, String status) {
    if (status == 'delivered') return "Delivered";
    if (status == 'arrived') return "Arrived";

    if (seconds <= 0) return "Arriving shortly";
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return "${mins}m ${secs.toString().padLeft(2, '0')}s";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: const Text(
          "Track Your Order",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('order_status')
            .doc(widget.orderId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.orange),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return _buildCompletedUI();
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          String rawStatus = (data['status'] ?? 'confirmed').toString();
          String status = rawStatus.toLowerCase().replaceAll(' ', '_');

          if (status == 'delivered') {
            return _buildCompletedUI();
          }

          final int remainingSecs = _remainingSeconds(data);
          final String arrivalTime = _formatTime(remainingSecs, status);

          GeoPoint? driverLoc = data['driverLocation'];
          final GeoPoint? destLoc = data['destinationLocation'];
          final String instructions = data['deliveryInstructions'] ?? "";

          if (destLoc != null) {
            _destLatLng = maps.LatLng(destLoc.latitude, destLoc.longitude);
            _markers.removeWhere((m) => m.markerId.value == 'destination');
            _markers.add(
              maps.Marker(
                markerId: const maps.MarkerId('destination'),
                position: _destLatLng!,
                icon: maps.BitmapDescriptor.defaultMarkerWithHue(
                  maps.BitmapDescriptor.hueRed,
                ),
                infoWindow: const maps.InfoWindow(title: "Delivery Point"),
              ),
            );
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('drivers')
                .where('currentOrderId', isEqualTo: widget.orderId)
                .limit(1)
                .snapshots(),
            builder: (context, driverSnapshot) {
              if (driverSnapshot.hasData &&
                  driverSnapshot.data!.docs.isNotEmpty) {
                final driverData = driverSnapshot.data!.docs.first.data()
                    as Map<String, dynamic>;

                if (driverData['currentLocation'] != null) {
                  driverLoc = driverData['currentLocation'];
                }
              }

              if (driverLoc != null && _isMapReady) {
                // detect driver location change
                final changed = _lastDriverGeo == null ||
                    _lastDriverGeo!.latitude != driverLoc!.latitude ||
                    _lastDriverGeo!.longitude != driverLoc!.longitude;

                if (changed) {
                  _lastDriverGeo = driverLoc;

                  final next = maps.LatLng(driverLoc!.latitude, driverLoc!.longitude);

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _animateDriverTo(next);
                    _updateMapCameraWithLatLng(next);
                  });
                } else {
                  // keep markers updated using current animated pos
                  final cur = _animatedDriverLatLng ??
                      maps.LatLng(driverLoc!.latitude, driverLoc!.longitude);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _setMarkersAndPolyline(cur);
                  });
                }
              }

              return SingleChildScrollView(
                child: Column(
                  children: [
                    _buildModernHeader(
                      arrivalTime,
                      (data['statusMessage'] ?? rawStatus).toString(),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _buildMapOrStatusGraphic(status, driverLoc, destLoc),
                          const SizedBox(height: 20),
                          if (data['driverName'] != null)
                            _buildModernDriverCard(
                              data['driverName'],
                              data['driverPhone'],
                            ),
                          if (instructions.isNotEmpty)
                            _buildModernInstructionCard(instructions),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMapOrStatusGraphic(
      String status, GeoPoint? driverLoc, GeoPoint? destLoc) {
    if (driverLoc != null) {
      final initial = maps.LatLng(driverLoc.latitude, driverLoc.longitude);

      return SizedBox(
        height: 250,
        child: maps.GoogleMap(
          initialCameraPosition: maps.CameraPosition(target: initial, zoom: 15),
          onMapCreated: (c) {
            _mapController = c;
            _isMapReady = true;

            // initial markers
            _animatedDriverLatLng = initial;
            _setMarkersAndPolyline(initial);
            _updateMapCameraWithLatLng(initial);
          },
          markers: _markers,
          polylines: _polylines,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
        ),
      );
    }

    // if no driver yet, you can show Lottie (kept minimal)
    return Container(
      height: 250,
      alignment: Alignment.center,
      child: Lottie.asset(
        'assets/animations/waiting.json',
        height: 140,
        errorBuilder: (c, e, s) => const Icon(Icons.hourglass_bottom, size: 60),
      ),
    );
  }

  Widget _buildModernHeader(String time, String status) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 25),
      child: Column(
        children: [
          const Text("ESTIMATED ARRIVAL"),
          const SizedBox(height: 8),
          Text(
            time,
            style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            status.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernDriverCard(String name, String? phone) {
    return Row(
      children: [
        Expanded(child: Text(name)),
        IconButton(
          onPressed: () => launchUrl(Uri.parse('tel:$phone')),
          icon: const Icon(Icons.call),
        ),
      ],
    );
  }

  Widget _buildModernInstructionCard(String note) {
    return Text(note);
  }

  Widget _buildCompletedUI() {
    return const Center(
      child: Text("Order Delivered"),
    );
  }
}