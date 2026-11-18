import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ============================================================
// FASTEVER - ADDRESS LOCATION SCREEN
// ============================================================

class AddressScreen extends StatefulWidget {
  const AddressScreen({Key? key}) : super(key: key);

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen>
    with TickerProviderStateMixin {
  GoogleMapController? _mapController;

  final TextEditingController _searchController = TextEditingController();

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  static const String _googleApiKey = "AIzaSyB01Cnq_GNgcPXFHFPTWFmK-sS5WahXDNE";

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(9.2268, 76.8496),
    zoom: 14,
  );

  String _selectedAddress = "";

  LatLng? _selectedLatLng;
  CameraPosition? _cameraPosition;

  bool _isServiceable = false;
  bool _isMapMoving = false;
  bool _showLocationGuide = true;
  bool _showFingerAnimation = true;
  bool _isGettingLocation = false;
  bool _isCheckingLocation = false;
  bool _mapReady = false;

  int _addressRequestId = 0;
  int _searchSelectionId = 0;

  bool _placeDetailReceived = false;

  LatLng? _pendingCameraTarget;
  double _pendingCameraZoom = 17;

  List<Map<String, dynamic>> _availableServiceAreas = [];

  late AnimationController _pinAnimationController;
  late AnimationController _fingerAnimationController;

  Timer? _guideAutoCloseTimer;

  Offset? _mapTouchStart;

  @override
  void initState() {
    super.initState();

    _pinAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _fingerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6200),
    )..repeat();

    // Automatically close guidance after 5 seconds.
    _startGuideAutoCloseTimer();

    _loadServiceData();
  }

  @override
  void dispose() {
    _guideAutoCloseTimer?.cancel();

    _addressRequestId++;
    _searchSelectionId++;

    _pinAnimationController.dispose();
    _fingerAnimationController.dispose();

    _searchController.dispose();
    _mapController?.dispose();

    super.dispose();
  }

  // ============================================================
  // AUTOMATIC GUIDANCE TIMER
  // ============================================================

  void _startGuideAutoCloseTimer() {
    _guideAutoCloseTimer?.cancel();

    _guideAutoCloseTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;

      _closeGuide();
    });
  }

  void _closeGuide() {
    _guideAutoCloseTimer?.cancel();

    _fingerAnimationController.stop();

    if (!mounted) return;

    setState(() {
      _showLocationGuide = false;
      _showFingerAnimation = false;
    });
  }

  void _openGuide() {
    if (!mounted) return;

    setState(() {
      _showLocationGuide = true;
      _showFingerAnimation = true;
    });

    _fingerAnimationController
      ..reset()
      ..repeat();

    _startGuideAutoCloseTimer();
  }

  // ============================================================
  // STOP FINGER ANIMATION WHEN CUSTOMER DRAGS MAP
  // ============================================================

  void _stopFingerAnimation() {
    if (!_showFingerAnimation) return;

    _fingerAnimationController.stop();

    if (!mounted) return;

    setState(() {
      _showFingerAnimation = false;
    });
  }

  void _onMapPointerDown(PointerDownEvent event) {
    _mapTouchStart = event.position;
  }

  void _onMapPointerMove(PointerMoveEvent event) {
    final start = _mapTouchStart;

    if (start == null) return;

    final distance = (event.position - start).distance;

    if (distance > 8) {
      _stopFingerAnimation();
      _mapTouchStart = null;
    }
  }

  void _onMapPointerUp(PointerUpEvent event) {
    _mapTouchStart = null;
  }

  void _onMapPointerCancel(PointerCancelEvent event) {
    _mapTouchStart = null;
  }

  // ============================================================
  // INITIAL DATA
  // ============================================================

  Future<void> _loadServiceData() async {
    try {
      await _fetchServiceAreas();

      if (!mounted) return;

      await _getCurrentLocation();
    } catch (e) {
      debugPrint("Address initialization error: $e");
    }
  }

  Future<void> _fetchServiceAreas() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('service_areas')
          .get();

      if (!mounted) return;

      setState(() {
        _availableServiceAreas = snapshot.docs
            .map((doc) => doc.data())
            .toList();
      });

      if (_selectedLatLng != null) {
        await _updateAddress(_selectedLatLng!);
      }
    } catch (e) {
      debugPrint("Service area loading error: $e");

      if (!mounted) return;

      _showMessage(
        "Unable to load delivery areas. Check your internet.",
        isError: true,
      );
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        backgroundColor: isError ? Colors.red : Colors.black87,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ============================================================
  // CURRENT GPS LOCATION
  // ============================================================

  Future<void> _getCurrentLocation() async {
    if (_isGettingLocation) return;

    setState(() {
      _isGettingLocation = true;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        _showMessage(
          "Please enable location services on your phone.",
          isError: true,
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _showMessage("Please allow location permission.", isError: true);
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        _showMessage(
          "Enable location permission in your phone settings.",
          isError: true,
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;

      final currentLatLng = LatLng(position.latitude, position.longitude);

      FocusScope.of(context).unfocus();

      await _moveToLocation(currentLatLng, zoom: 17);
    } catch (e) {
      debugPrint("Current location error: $e");

      _showMessage(
        "Unable to find your location. Please try again.",
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGettingLocation = false;
        });
      }
    }
  }

  // ============================================================
  // MOVE CAMERA TO SELECTED LOCATION
  // ============================================================

  Future<void> _moveToLocation(LatLng target, {double zoom = 17}) async {
    if (!mounted) return;

    _pendingCameraTarget = target;
    _pendingCameraZoom = zoom;

    _cameraPosition = CameraPosition(target: target, zoom: zoom);

    final controller = _mapController;

    if (controller != null && _mapReady) {
      try {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(target, zoom),
        );

        if (!mounted) return;

        _pendingCameraTarget = null;
      } catch (e) {
        debugPrint("Camera movement error: $e");
      }
    }

    if (!mounted) return;

    await _updateAddress(target);
  }

  // ============================================================
  // SERVICE AREA VALIDATION
  // ============================================================

  double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value);
    }

    return null;
  }

  bool _isPointInPolygon(LatLng point, List<dynamic> polygonPoints) {
    if (polygonPoints.length < 3) return false;

    bool inside = false;
    int j = polygonPoints.length - 1;

    for (int i = 0; i < polygonPoints.length; i++) {
      final p1 = polygonPoints[i];
      final p2 = polygonPoints[j];

      if (p1 is! Map || p2 is! Map) {
        j = i;
        continue;
      }

      final lat1 = _toDouble(p1['lat']);
      final lng1 = _toDouble(p1['lng']);
      final lat2 = _toDouble(p2['lat']);
      final lng2 = _toDouble(p2['lng']);

      if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) {
        j = i;
        continue;
      }

      final intersects =
          ((lat1 > point.latitude) != (lat2 > point.latitude)) &&
          (point.longitude <
              (lng2 - lng1) * (point.latitude - lat1) / (lat2 - lat1) + lng1);

      if (intersects) {
        inside = !inside;
      }

      j = i;
    }

    return inside;
  }

  double _calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371.0;

    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final safeA = a.clamp(0.0, 1.0);

    return earthRadius * 2 * atan2(sqrt(safeA), sqrt(1 - safeA));
  }

  bool _checkServiceability(LatLng latLng) {
    for (final area in _availableServiceAreas) {
      if (area['enabled'] == false || area['isActive'] == false) {
        continue;
      }

      final polygon = area['polygon'];

      if (polygon is List && polygon.length >= 3) {
        if (_isPointInPolygon(latLng, polygon)) {
          return true;
        }

        continue;
      }

      final latitude = _toDouble(area['latitude']);
      final longitude = _toDouble(area['longitude']);

      final radius = _toDouble(area['radiusKm']) ?? 8;

      if (latitude == null || longitude == null) {
        continue;
      }

      final distance = _calculateDistanceKm(
        latitude,
        longitude,
        latLng.latitude,
        latLng.longitude,
      );

      if (distance <= radius) {
        return true;
      }
    }

    return false;
  }

  // ============================================================
  // ADDRESS LOOKUP
  // ============================================================

  Future<void> _updateAddress(LatLng latLng) async {
    final requestId = ++_addressRequestId;

    if (!mounted) return;

    setState(() {
      _selectedLatLng = latLng;
      _selectedAddress = "";
      _isServiceable = false;
      _isCheckingLocation = true;
    });

    final foundService = _checkServiceability(latLng);

    String resolvedAddress = "";

    try {
      final placemarks = await placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;

        final components = <String>[
          place.name ?? "",
          place.street ?? "",
          place.subLocality ?? "",
          place.locality ?? "",
          place.administrativeArea ?? "",
          place.postalCode ?? "",
        ];

        final uniqueComponents = <String>[];

        for (final component in components) {
          final value = component.trim();

          if (value.isNotEmpty &&
              !uniqueComponents.any(
                (existing) => existing.toLowerCase() == value.toLowerCase(),
              )) {
            uniqueComponents.add(value);
          }
        }

        resolvedAddress = uniqueComponents.join(", ");
      }
    } catch (e) {
      debugPrint("Reverse geocoding error: $e");
    }

    if (!mounted || requestId != _addressRequestId) {
      return;
    }

    if (resolvedAddress.trim().isEmpty) {
      resolvedAddress =
          "${latLng.latitude.toStringAsFixed(6)}, "
          "${latLng.longitude.toStringAsFixed(6)}";
    }

    setState(() {
      _selectedLatLng = latLng;
      _selectedAddress = resolvedAddress;
      _isServiceable = foundService;
      _isCheckingLocation = false;
    });
  }

  Future<void> _onCameraIdle() async {
    if (!mounted) return;

    setState(() {
      _isMapMoving = false;
    });

    _pinAnimationController.reverse();

    final position = _cameraPosition;

    if (position == null) return;

    await _updateAddress(position.target);
  }

  Future<void> _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;

    _mapReady = true;

    final target = _pendingCameraTarget;

    if (target != null) {
      try {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(target, _pendingCameraZoom),
        );

        _pendingCameraTarget = null;
      } catch (e) {
        debugPrint("Initial camera error: $e");
      }
    }
  }

  // ============================================================
  // SEARCH LOCATION SELECTION
  // ============================================================

  Future<void> _selectSearchLocation(LatLng target) async {
    if (!mounted) return;

    FocusScope.of(context).unfocus();

    _searchController.clear();

    setState(() {
      _isCheckingLocation = true;
      _selectedLatLng = null;
      _isServiceable = false;
    });

    await _moveToLocation(target, zoom: 17);
  }

  // ============================================================
  // SEARCH RESULT FALLBACK
  // ============================================================

  Future<void> _searchFallback(String description, int selectionId) async {
    await Future<void>.delayed(const Duration(milliseconds: 1000));

    if (!mounted || selectionId != _searchSelectionId || _placeDetailReceived) {
      return;
    }

    try {
      final locations = await locationFromAddress(description);

      if (!mounted ||
          selectionId != _searchSelectionId ||
          _placeDetailReceived ||
          locations.isEmpty) {
        return;
      }

      final target = LatLng(
        locations.first.latitude,
        locations.first.longitude,
      );

      _placeDetailReceived = true;

      await _selectSearchLocation(target);
    } catch (e) {
      debugPrint("Search fallback error: $e");

      if (mounted &&
          selectionId == _searchSelectionId &&
          !_placeDetailReceived) {
        _showMessage(
          "Unable to locate this place. Try another result.",
          isError: true,
        );
      }
    }
  }

  // ============================================================
  // ANIMATED LOCATION PIN
  // ============================================================

  Widget _buildAnimatedLocationPin() {
    return IgnorePointer(
      child: Center(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _pinAnimationController,
            _fingerAnimationController,
          ]),
          builder: (context, child) {
            final movingProgress = _pinAnimationController.value;

            final tutorialValue = _fingerAnimationController.value;

            double tutorialLift = 0;

            if (_showLocationGuide && _showFingerAnimation && !_isMapMoving) {
              tutorialLift = sin(tutorialValue * pi * 4).abs() * 6;
            }

            final lift = movingProgress * 15 + tutorialLift;

            return Transform.translate(
              offset: Offset(0, -lift),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 8),
                      ],
                    ),
                    child: Text(
                      _isMapMoving ? "Move Map" : "Exact Delivery Location",
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Icon(
                    Icons.location_pin,
                    size: 54,
                    color: Colors.deepOrange,
                    shadows: [
                      Shadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 20 - movingProgress * 7,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // ANIMATED FINGER GUIDE
  // ============================================================

  Widget _buildRealMapFingerAnimation() {
    if (!_showLocationGuide || !_showFingerAnimation) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: true,
        child: AnimatedBuilder(
          animation: _fingerAnimationController,
          builder: (context, child) {
            final value = _fingerAnimationController.value;

            double dx = 0;
            double dy = 0;

            String direction = "";

            final phase = (value * 4).floor().clamp(0, 3);

            final phaseProgress = (value * 4 - phase).clamp(0.0, 1.0);

            final smooth = Curves.easeInOut.transform(phaseProgress);

            if (phase == 0) {
              dx = 90 - smooth * 180;
              dy = 65;
              direction = "Swipe Left";
            } else if (phase == 1) {
              dx = -90 + smooth * 180;
              dy = 65;
              direction = "Swipe Right";
            } else if (phase == 2) {
              dx = 75;
              dy = 120 - smooth * 160;
              direction = "Swipe Up";
            } else {
              dx = -75;
              dy = -40 + smooth * 160;
              direction = "Swipe Down";
            }

            final opacity = (sin(phaseProgress * pi) * 2).clamp(0.0, 1.0);

            return Center(
              child: Transform.translate(
                offset: Offset(dx, dy),
                child: Opacity(
                  opacity: opacity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          direction,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Transform.rotate(
                        angle: -0.28,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 91,
                              height: 91,
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.16),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.orange.withOpacity(0.65),
                                  width: 2,
                                ),
                              ),
                            ),
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.94),
                                shape: BoxShape.circle,
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 12,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.touch_app,
                              size: 53,
                              color: Colors.deepOrange,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          "Drag the Map",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // LOCATION GUIDE - AUTO CLOSE AFTER 5 SECONDS
  // ============================================================

  Widget _buildLocationGuide() {
    return Positioned(
      top: 10,
      left: 12,
      right: 12,
      child: !_showLocationGuide
          ? Align(
              alignment: Alignment.topRight,
              child: Material(
                color: Colors.white,
                elevation: 5,
                borderRadius: BorderRadius.circular(25),
                child: InkWell(
                  onTap: _openGuide,
                  borderRadius: BorderRadius.circular(25),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_circle_outline,
                          color: Colors.deepOrange,
                          size: 20,
                        ),
                        SizedBox(width: 6),
                        Text(
                          "Show Guide",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : Container(
              padding: const EdgeInsets.fromLTRB(13, 10, 7, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.shade300),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 14,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.touch_app,
                          color: Colors.deepOrange,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 9),
                      const Expanded(
                        child: Text(
                          "HOW TO SELECT YOUR LOCATION",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: "Close Guide",
                        onPressed: _closeGuide,
                        icon: const Icon(
                          Icons.close,
                          size: 23,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4E5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "1. Move the Map",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          "Touch and swipe the map with your "
                          "finger. Keep moving until the orange "
                          "pin is exactly over your home, "
                          "building, or delivery entrance.",
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.my_location, size: 19, color: Colors.blue),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "2. Tap Use My Current Location "
                          "to find your current position.",
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle, size: 19, color: Colors.green),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "3. When the pin points to the "
                          "correct location, tap Confirm Location.",
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Center(
                    child: Text(
                      "Follow the moving finger on the map",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.deepOrange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ============================================================
  // MAIN SCREEN
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Column(
            children: [
              SafeArea(child: _buildSearchBar()),
              Expanded(
                child: Stack(
                  children: [
                    // Google Map with touch detection.
                    Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _onMapPointerDown,
                      onPointerMove: _onMapPointerMove,
                      onPointerUp: _onMapPointerUp,
                      onPointerCancel: _onMapPointerCancel,
                      child: GoogleMap(
                        initialCameraPosition: _initialCamera,
                        myLocationEnabled: false,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        onMapCreated: _onMapCreated,
                        onCameraMoveStarted: () {
                          if (!mounted) return;

                          _addressRequestId++;

                          setState(() {
                            _isMapMoving = true;
                            _selectedLatLng = null;
                            _isServiceable = false;
                            _isCheckingLocation = true;
                          });

                          _pinAnimationController.forward();
                        },
                        onCameraMove: (position) {
                          _cameraPosition = position;
                        },
                        onCameraIdle: _onCameraIdle,
                      ),
                    ),

                    // Fixed orange location pin.
                    _buildAnimatedLocationPin(),

                    // Animated hand.
                    _buildRealMapFingerAnimation(),

                    // 5-second dismissible guide.
                    _buildLocationGuide(),
                  ],
                ),
              ),
            ],
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildConfirmButton(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // GOOGLE PLACES SEARCH
  // ============================================================

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: GooglePlaceAutoCompleteTextField(
        textEditingController: _searchController,
        googleAPIKey: _googleApiKey,
        countries: const ["in"],
        isLatLngRequired: true,
        debounceTime: 600,
        inputDecoration: InputDecoration(
          hintText: "Search area, street, or building...",
          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Colors.orange),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),

        itemClick: (prediction) {
          final description = prediction.description?.trim() ?? "";

          if (description.isEmpty) return;

          _searchController.text = description;

          _searchController.selection = TextSelection.fromPosition(
            TextPosition(offset: description.length),
          );

          _placeDetailReceived = false;

          final selectionId = ++_searchSelectionId;

          _searchFallback(description, selectionId);
        },

        getPlaceDetailWithLatLng: (prediction) async {
          final latStr = prediction.lat;
          final lngStr = prediction.lng;

          if (latStr == null || lngStr == null) {
            debugPrint("Places Details: missing coordinates");
            return;
          }

          final lat = double.tryParse(latStr);
          final lng = double.tryParse(lngStr);

          if (lat == null ||
              lng == null ||
              lat < -90 ||
              lat > 90 ||
              lng < -180 ||
              lng > 180) {
            _showMessage(
              "Invalid coordinates for this location.",
              isError: true,
            );
            return;
          }

          _placeDetailReceived = true;
          ++_searchSelectionId;

          await _selectSearchLocation(LatLng(lat, lng));
        },
      ),
    );
  }

  // ============================================================
  // CURRENT LOCATION BUTTON
  // ============================================================

  Widget _buildCurrentLocationButton() {
    return OutlinedButton.icon(
      onPressed: _isGettingLocation ? null : _getCurrentLocation,
      icon: _isGettingLocation
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.orange,
              ),
            )
          : const Icon(Icons.my_location, size: 22),
      label: Text(
        _isGettingLocation
            ? "Finding Current Location..."
            : "Use My Current Location",
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.deepOrange,
        minimumSize: const Size(double.infinity, 50),
        side: const BorderSide(color: Colors.orange, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ============================================================
  // BOTTOM BUTTONS
  // ============================================================

  Widget _buildConfirmButton() {
    final canConfirm =
        _selectedLatLng != null && _isServiceable && !_isCheckingLocation;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCurrentLocationButton(),

          const SizedBox(height: 10),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: canConfirm ? Colors.orange : Colors.grey,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey,
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: !canConfirm
                ? null
                : () async {
                    final selectedLatLng = _selectedLatLng;

                    if (selectedLatLng == null) return;

                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddressDetailsScreen(
                          address: _selectedAddress,
                          lat: selectedLatLng.latitude,
                          lng: selectedLatLng.longitude,
                        ),
                      ),
                    );

                    if (result != null && mounted) {
                      Navigator.pop(context, result);
                    }
                  },
            child: Text(
              _isCheckingLocation
                  ? "Checking Location..."
                  : _selectedLatLng == null
                  ? "Select Location"
                  : !_isServiceable
                  ? "Area Not Serviceable"
                  : "Confirm Location",
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// FASTEVER - ADDRESS DETAILS SCREEN
// EXISTING FIRESTORE STRUCTURE PRESERVED
// ============================================================

class AddressDetailsScreen extends StatefulWidget {
  final String address;
  final double lat;
  final double lng;

  const AddressDetailsScreen({
    Key? key,
    required this.address,
    required this.lat,
    required this.lng,
  }) : super(key: key);

  @override
  State<AddressDetailsScreen> createState() => _AddressDetailsScreenState();
}

class _AddressDetailsScreenState extends State<AddressDetailsScreen> {
  final _formKey = GlobalKey<FormState>();

  final nameCtrl = TextEditingController();
  final houseCtrl = TextEditingController();
  final streetCtrl = TextEditingController();
  final landmarkCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();

  String _selectedCategory = "Home";
  bool _isDefault = false;
  bool _isSaving = false;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  @override
  void dispose() {
    nameCtrl.dispose();
    houseCtrl.dispose();
    streetCtrl.dispose();
    landmarkCtrl.dispose();
    phoneCtrl.dispose();

    super.dispose();
  }

  // ============================================================
  // MAXIMUM 3 ADDRESSES
  // ============================================================

  Future<bool> _ensureUnderLimitOrDeleteOne(String uid) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('addresses')
        .orderBy('updatedAt', descending: true)
        .limit(3)
        .get();

    if (snapshot.size < 3) {
      return true;
    }

    if (!mounted) return false;

    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Saved Address Limit Reached"),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "You can save a maximum of 3 addresses. "
                "Delete an existing address to add a new one.",
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: snapshot.docs.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.grey.shade200),
                  itemBuilder: (itemContext, i) {
                    final data = snapshot.docs[i].data();

                    return ListTile(
                      dense: true,
                      title: Text(
                        data['category'] ?? "Saved",
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        data['full_display_address'] ?? "",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          try {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .collection('addresses')
                                .doc(snapshot.docs[i].id)
                                .delete();

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, true);
                            }
                          } catch (e) {
                            debugPrint("Delete address error: $e");

                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                  content: Text("Unable to delete address."),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                        child: const Text(
                          "Delete",
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, false);
            },
            child: const Text("Cancel"),
          ),
        ],
      ),
    );

    return deleted == true;
  }

  // ============================================================
  // SAVE ADDRESS TO FIRESTORE
  // ============================================================

  Future<void> _saveAddress() async {
    if (_isSaving) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final uid = _uid;

      final okToSave = await _ensureUnderLimitOrDeleteOne(uid);

      if (!mounted || !okToSave) {
        return;
      }

      final docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('addresses')
          .add({
            'recipient_name': nameCtrl.text,
            'house_no': houseCtrl.text,
            'street_area': streetCtrl.text,
            'landmark': landmarkCtrl.text,
            'phone': phoneCtrl.text,
            'category': _selectedCategory,
            'lat': widget.lat,
            'lng': widget.lng,
            'full_display_address': widget.address,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (_isDefault) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'defaultAddressId': docRef.id,
        });
      }

      if (!mounted) return;

      Navigator.pop(context, {
        'addressId': docRef.id,
        'category': _selectedCategory,
        'full_display_address': widget.address,
        'recipient_name': nameCtrl.text,
        'house_no': houseCtrl.text,
        'street_area': streetCtrl.text,
        'landmark': landmarkCtrl.text,
        'phone': phoneCtrl.text,
        'lat': widget.lat,
        'lng': widget.lng,
      });
    } catch (e) {
      debugPrint("Save address error: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Unable to save address. Please try again."),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ============================================================
  // ADDRESS DETAILS SCREEN UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Enter Address Details",
          style: TextStyle(
            fontSize: 18,
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.address,
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 25),

            _buildCategorySelector(),

            const SizedBox(height: 20),

            _buildSectionLabel("CONTACT DETAILS"),

            _buildField(
              nameCtrl,
              "Recipient Name *",
              Icons.person_outline,
              true,
            ),

            _buildField(
              phoneCtrl,
              "Phone Number (Optional)",
              Icons.phone_android_outlined,
              false,
              type: TextInputType.phone,
            ),

            const SizedBox(height: 10),

            _buildSectionLabel("ADDRESS DETAILS"),

            _buildField(
              houseCtrl,
              "House No. / Flat / Building *",
              Icons.apartment,
              true,
            ),

            _buildField(
              streetCtrl,
              "Street / Road / Area *",
              Icons.streetview,
              true,
            ),

            _buildField(
              landmarkCtrl,
              "Nearby Landmark (Optional)",
              Icons.assistant_navigation,
              false,
            ),

            const SizedBox(height: 10),

            CheckboxListTile(
              title: const Text(
                "Set as default address",
                style: TextStyle(fontSize: 14),
              ),
              value: _isDefault,
              onChanged: (val) {
                setState(() {
                  _isDefault = val ?? false;
                });
              },
              activeColor: Colors.orange,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _isSaving ? null : _saveAddress,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 2,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      "SAVE ADDRESS",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ADDRESS CATEGORY SELECTOR
  // ============================================================

  Widget _buildCategorySelector() {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: ["Home", "Office", "Other"].map((cat) {
        final isSelected = _selectedCategory == cat;

        return Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategory = cat;
              });
            },
            child: Column(
              children: [
                CircleAvatar(
                  backgroundColor: isSelected
                      ? Colors.orange
                      : Colors.grey.shade100,
                  child: Icon(
                    cat == "Home"
                        ? Icons.home
                        : cat == "Office"
                        ? Icons.work
                        : Icons.location_on,
                    color: isSelected ? Colors.white : Colors.grey,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  cat,
                  style: TextStyle(
                    color: isSelected ? Colors.orange : Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ============================================================
  // ADDRESS INPUT FIELD
  // ============================================================

  Widget _buildField(
    TextEditingController ctrl,
    String label,
    IconData icon,
    bool isMandatory, {
    TextInputType type = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20, color: Colors.orange.shade400),
          labelStyle: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.orange, width: 1.5),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
        validator: (v) {
          if (isMandatory && (v == null || v.trim().isEmpty)) {
            return "Field required";
          }

          return null;
        },
      ),
    );
  }
}
