import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart'; 
import 'dart:async'; // ✅ Added for the Timer
import '../home/home_screen.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  String _verificationId = "";
  bool _otpSent = false;
  bool _isLoading = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Timer variables
  Timer? _timer;
  int _secondsRemaining = 30;
  bool _canResend = false;

  final String _privacyUrl = "https://sites.google.com/view/fastever-privacy";
  final String _termsUrl = "https://sites.google.com/view/fastever-termsconditions/home";
  final String _shippingUrl = "https://sites.google.com/view/shipping-and-delivery-policy-k/home";
  final String _refundUrl = "https://sites.google.com/view/refundandcancellationpolicykee/home";

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _timer?.cancel(); // ✅ Cancel timer on dispose
    super.dispose();
  }

  // Timer Logic
  void _startTimer() {
    setState(() {
      _secondsRemaining = 30;
      _canResend = false;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining == 0) {
        setState(() {
          _canResend = true;
          _timer?.cancel();
        });
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  Future<void> _sendOTP() async {
    if (_phoneController.text.isEmpty || _phoneController.text.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            backgroundColor: Colors.red,
            content: Text("Please enter a valid 10-digit Indian number.")),
      );
      return;
    }

    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();

    final fullPhoneNumber = "+91${_phoneController.text.trim()}";

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: fullPhoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // ✅ AUTO-FILL LOGIC
          if (credential.smsCode != null) {
            setState(() {
              _otpController.text = credential.smsCode!;
            });
            await _signInWithCredential(credential);
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isLoading = false);
          String msg = e.message ?? "Verification Failed";
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.red, content: Text(msg)),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _otpSent = true;
            _isLoading = false;
          });
          _startTimer(); // ✅ Start 30s countdown
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                backgroundColor: Colors.green, content: Text("OTP Sent Successfully!")),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (mounted) {
            setState(() => _verificationId = verificationId);
          }
        },
        timeout: const Duration(seconds: 30),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  Future<void> _verifyOTP() async {
    if (_otpController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter the full 6-digit OTP.")),
      );
      return;
    }

    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();

    PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: _verificationId,
      smsCode: _otpController.text.trim(),
    );

    await _signInWithCredential(credential);
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      UserCredential userCredential = await _auth.signInWithCredential(credential);
      User? user = userCredential.user;

      if (user != null) {
        // ✅ Version 4: Removed Firestore profile check to reduce friction
        if (!mounted) return;

        // ✅ Redirect directly to HomeScreen for all users
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text(e.message ?? "Login Failed")),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint("Login Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 40),
                      const Text(
                        "Let's Sign you in.",
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Welcome to KEEVO.\nYou've been missed!",
                        style: TextStyle(fontSize: 24, color: Colors.grey),
                      ),
                      const SizedBox(height: 50),

                      if (!_otpSent) ...[
                        const Text("Phone Number", style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          style: const TextStyle(fontSize: 18, letterSpacing: 1.0),
                          decoration: InputDecoration(
                            prefixIcon: const Padding(
                              padding: EdgeInsets.all(15),
                              child: Text("+91", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ),
                            hintText: "Enter Phone Number",
                            counterText: "",
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _sendOTP,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text("Get OTP", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ] else ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Enter OTP", style: TextStyle(fontWeight: FontWeight.w600)),
                            TextButton(
                              onPressed: () => setState(() {
                                _otpSent = false;
                                _otpController.clear();
                                _timer?.cancel();
                              }), 
                              child: const Text("Change Number", style: TextStyle(color: Colors.blueAccent))
                            )
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _otpController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24, letterSpacing: 4.0, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: "• • • • • •",
                            counterText: "",
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                        ),
                        const SizedBox(height: 15),
                        // ⏳ TIMER & RESEND UI
                        Center(
                          child: _canResend
                              ? TextButton(
                                  onPressed: _isLoading ? null : _sendOTP,
                                  child: const Text("Resend OTP", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
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
                            onPressed: _isLoading ? null : _verifyOTP,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text("Verify & Login", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10.0, bottom: 10.0),
                  child: Column(
                    children: [
                      const Text(
                        "By continuing, you agree to our",
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => _launchURL(_termsUrl),
                            child: const Text("Terms", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                          ),
                          const Text("  •  ", style: TextStyle(color: Colors.grey)),
                          GestureDetector(
                            onTap: () => _launchURL(_privacyUrl),
                            child: const Text("Privacy", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                          ),
                          const Text("  •  ", style: TextStyle(color: Colors.grey)),
                          GestureDetector(
                            onTap: () => _launchURL(_shippingUrl),
                            child: const Text("Shipping", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => _launchURL(_refundUrl),
                        child: const Text(
                          "Refund & Cancellation Policy",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}