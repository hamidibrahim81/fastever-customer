import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../home/home_screen.dart';
import '../profile/profile_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _verificationId = "";
  bool _otpSent = false;

  bool _isLoading = false;
  bool _otpRequestLocked = false;
  bool _isSendingOtp = false;
  bool _isVerifyingOtp = false;

  String _loadingTitle = "Please wait...";
  String _loadingSubtitle = "This may take a few seconds.";

  Timer? _timer;
  int _secondsRemaining = 30;
  bool _canResend = false;

  final String _privacyUrl = "https://sites.google.com/view/fastever-privacy";
  final String _termsUrl =
      "https://sites.google.com/view/fastever-termsconditions/home";
  final String _shippingUrl =
      "https://sites.google.com/view/shipping-and-delivery-policy-k/home";
  final String _refundUrl =
      "https://sites.google.com/view/refundandcancellationpolicykee/home";

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _setLoading({
    required bool value,
    String title = "Please wait...",
    String subtitle = "This may take a few seconds.",
  }) {
    if (!mounted) return;
    setState(() {
      _isLoading = value;
      _loadingTitle = title;
      _loadingSubtitle = subtitle;
    });
  }

  void _resetLoadingStates() {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isSendingOtp = false;
      _isVerifyingOtp = false;
      _otpRequestLocked = false;
    });
  }

  void _startTimer() {
    if (!mounted) return;

    setState(() {
      _secondsRemaining = 30;
      _canResend = false;
    });

    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      if (_secondsRemaining <= 0) {
        setState(() {
          _canResend = true;
        });
        timer.cancel();
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  Future<void> _launchURL(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("URL launch error: $e");
    }
  }

  Future<void> _sendOTP() async {
    if (_otpRequestLocked) return;

    final phone = _phoneController.text.trim();

    if (phone.length != 10) {
      _showError("Please enter a valid 10-digit phone number.");
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _isSendingOtp = true;
      _otpRequestLocked = true;
      _loadingTitle = "Sending OTP...";
      _loadingSubtitle = "Please wait while we verify your phone number.";
    });

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: "+91$phone",
        timeout: const Duration(seconds: 30),

        verificationCompleted: (PhoneAuthCredential credential) async {
          if (!mounted) return;

          if (credential.smsCode != null) {
            setState(() {
              _otpController.text = credential.smsCode!;
              _isVerifyingOtp = true;
              _loadingTitle = "Verifying OTP...";
              _loadingSubtitle = "Signing you in securely.";
            });
          }

          await _signInWithCredential(credential);
        },

        verificationFailed: (FirebaseAuthException e) {
          _resetLoadingStates();
          _showError(e.message ?? "OTP verification failed. Please try again.");
        },

        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;

          setState(() {
            _verificationId = verificationId;
            _otpSent = true;
            _isLoading = false;
            _isSendingOtp = false;
            _otpRequestLocked = false;
          });

          _startTimer();

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Text("OTP sent successfully."),
            ),
          );
        },

        codeAutoRetrievalTimeout: (String verificationId) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _otpRequestLocked = false;
          });
        },
      );
    } catch (e) {
      debugPrint("Send OTP Error: $e");
      _resetLoadingStates();
      _showError("Unable to send OTP. Please check your internet and try again.");
    }
  }

  Future<void> _verifyOTP() async {
    final otp = _otpController.text.trim();

    if (_verificationId.isEmpty) {
      _showError("Please request OTP again.");
      return;
    }

    if (otp.length != 6) {
      _showError("Please enter the full 6-digit OTP.");
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _isVerifyingOtp = true;
      _loadingTitle = "Verifying OTP...";
      _loadingSubtitle =
          "Please wait. This may take a few seconds.";
    });

    final PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: _verificationId,
      smsCode: otp,
    );

    await _signInWithCredential(credential);
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      final UserCredential userCredential = await _auth
          .signInWithCredential(credential)
          .timeout(const Duration(seconds: 15));

      final User? user = userCredential.user;

      if (user == null) {
        _resetLoadingStates();
        _showError("Login failed. Please try again.");
        return;
      }

      bool isProfileComplete = false;

      try {
        final prefs = await SharedPreferences.getInstance()
            .timeout(const Duration(seconds: 5));

        isProfileComplete = prefs.getBool('profile_${user.uid}') ?? false;

        if (!isProfileComplete) {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get()
              .timeout(const Duration(seconds: 5));

          final data = doc.data();
          final name = data?['name']?.toString().trim();

          if (doc.exists && name != null && name.isNotEmpty) {
            isProfileComplete = true;
            await prefs.setBool('profile_${user.uid}', true);
          }
        }
      } catch (e) {
        debugPrint("Profile check error: $e");
        isProfileComplete = true;
      }

      if (!mounted) return;

      _resetLoadingStates();

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) =>
              isProfileComplete ? const HomeScreen() : const ProfileScreen(),
        ),
        (route) => false,
      );
    } on TimeoutException {
      _resetLoadingStates();

      if (!mounted) return;

      _showError("Login is taking longer than usual. Please try again.");

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      _resetLoadingStates();
      _showError(e.message ?? "Login failed. Please try again.");
    } catch (e) {
      debugPrint("Login Error: $e");

      _resetLoadingStates();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  void _showError(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(msg),
      ),
    );
  }

  void _changeNumber() {
    if (!mounted) return;

    setState(() {
      _otpSent = false;
      _otpController.clear();
      _verificationId = "";
      _otpRequestLocked = false;
      _isLoading = false;
      _isSendingOtp = false;
      _isVerifyingOtp = false;
    });

    _timer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 40),
                          const Text(
                            "Let's sign you in.",
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "Welcome to FASTever.\nContinue with your phone number.",
                            style: TextStyle(
                              fontSize: 22,
                              color: Colors.grey,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 50),
                          AnimatedCrossFade(
                            duration: const Duration(milliseconds: 350),
                            firstChild: _buildPhoneInput(),
                            secondChild: _buildOtpInput(),
                            crossFadeState: _otpSent
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildFooter(),
                ],
              ),
            ),
          ),
          if (_isLoading) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.38),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.78),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 18),
              Text(
                _loadingTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _loadingSubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneInput() {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Phone Number",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            maxLength: 10,
            enabled: !_isSendingOtp && !_isLoading,
            style: const TextStyle(fontSize: 18, letterSpacing: 1.0),
            decoration: InputDecoration(
              prefixIcon: const Padding(
                padding: EdgeInsets.all(15),
                child: Text(
                  "+91",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              hintText: "Enter phone number",
              counterText: "",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed:
                  (_isSendingOtp || _otpRequestLocked || _isLoading)
                      ? null
                      : _sendOTP,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                disabledBackgroundColor: Colors.black54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSendingOtp
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      "Get OTP",
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpInput() {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Enter OTP",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              TextButton(
                onPressed: _isLoading ? null : _changeNumber,
                child: const Text(
                  "Change Number",
                  style: TextStyle(color: Colors.blueAccent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            enabled: !_isVerifyingOtp && !_isLoading,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              letterSpacing: 4.0,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              hintText: "• • • • • •",
              counterText: "",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          const SizedBox(height: 15),
          Center(
            child: _canResend
                ? TextButton(
                    onPressed:
                        (_isSendingOtp || _otpRequestLocked || _isLoading)
                            ? null
                            : _sendOTP,
                    child: const Text(
                      "Resend OTP",
                      style: TextStyle(
                        color: Colors.blueAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : Text(
                    "Resend OTP in $_secondsRemaining seconds",
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: (_isVerifyingOtp || _isLoading) ? null : _verifyOTP,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                disabledBackgroundColor: Colors.black54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isVerifyingOtp
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      "Verify & Login",
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          children: [
            const Text(
              "By continuing, you agree to our",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                _link("Terms", _termsUrl),
                const Text(
                  "  •  ",
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
                _link("Privacy", _privacyUrl),
                const Text(
                  "  •  ",
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
                _link("Shipping", _shippingUrl),
              ],
            ),
            const SizedBox(height: 4),
            _link("Refund & Cancellation Policy", _refundUrl),
          ],
        ),
      ),
    );
  }

  Widget _link(String label, String url) {
    return GestureDetector(
      onTap: () => _launchURL(url),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.underline,
          color: Colors.black87,
        ),
      ),
    );
  }
}