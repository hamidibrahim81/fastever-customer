
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../home/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _verificationId = "";

  int? _resendToken;

  bool _otpSent = false;

  bool _isLoading = false;
  bool _otpRequestLocked = false;
  bool _isSendingOtp = false;
  bool _isVerifyingOtp = false;

  String _loadingTitle = "Please wait...";
  String _loadingSubtitle = "This may take a few seconds.";

  Timer? _timer;
  Timer? _requestWatchdog;
  int _requestGeneration = 0;
  bool _loginCompleted = false;
  bool _signInInProgress = false;

  int _secondsRemaining = 0;

  bool _canResend = true;
  bool _cooldownReady = false;

  DateTime? _nextOtpAllowedAt;

  static const String _otpCooldownKey =
      'fastever_next_otp_allowed_at';

  static const int _otpCooldownDuration = 30;
  static const Duration _requestWaitLimit = Duration(seconds: 45);

  // FASTever Brand Color
  static const Color _brandYellow = Color(0xFFFFC400);

  final String _privacyUrl =
      "https://sites.google.com/view/fastever-privacy";

  final String _termsUrl =
      "https://sites.google.com/view/fastever-termsconditions/home";

  final String _shippingUrl =
      "https://sites.google.com/view/shipping-and-delivery-policy-k/home";

  final String _refundUrl =
      "https://sites.google.com/view/refundandcancellationpolicykee/home";

  @override
  void initState() {
    super.initState();
    _restoreOtpCooldown();
  }

  Future<void> _restoreOtpCooldown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_otpCooldownKey);
      if (!mounted) return;
      if (saved != null) {
        final restored = DateTime.fromMillisecondsSinceEpoch(saved);
        // Never replace a newer in-memory deadline with an older saved one.
        if (_nextOtpAllowedAt == null ||
            restored.isAfter(_nextOtpAllowedAt!)) {
          _nextOtpAllowedAt = restored;
        }
      }
    } catch (e) {
      debugPrint('OTP cooldown restore error: $e');
      _nextOtpAllowedAt ??= DateTime.now().add(
        const Duration(seconds: _otpCooldownDuration),
      );
    }
    if (!mounted) return;
    setState(() => _cooldownReady = true);
    _startTimer();
  }

  @override
  void dispose() {
    _requestGeneration++;
    _requestWatchdog?.cancel();
    _timer?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
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

  int get _remainingCooldownSeconds {
    final deadline = _nextOtpAllowedAt;
    if (deadline == null) return 0;
    final milliseconds = deadline.difference(DateTime.now()).inMilliseconds;
    return milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }

  String get _countdownText {
    final seconds = _secondsRemaining;
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }

  void _startTimer() {
    _timer?.cancel();
    if (!mounted) return;

    void update() {
      if (!mounted) return;
      final remaining = _remainingCooldownSeconds;
      setState(() {
        _secondsRemaining = remaining;
        _canResend = remaining == 0;
      });
      if (remaining == 0) _timer?.cancel();
    }

    update();
    if (_remainingCooldownSeconds > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => update());
    }
  }

  // Starts on request attempt, not only after codeSent. This is a UX guard,
  // NOT a security boundary or a server-enforced SMS quota.
  Future<void> _beginOtpCooldown() async {
    final deadline = DateTime.now().add(
      const Duration(seconds: _otpCooldownDuration),
    );
    _nextOtpAllowedAt = deadline;
    _startTimer();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_otpCooldownKey, deadline.millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('OTP cooldown save error: $e');
    }
  }

  bool _isCurrentRequest(int generation) =>
      mounted && !_loginCompleted && generation == _requestGeneration;

  void _stopRequestWait() {
    _requestWatchdog?.cancel();
    _requestWatchdog = null;
  }

  String _friendlyFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'Invalid phone number. Please check and try again.';
      case 'too-many-requests':
      case 'quota-exceeded':
        return 'Too many OTP requests. Please wait before trying again.';
      case 'invalid-verification-code':
        return 'Incorrect OTP. Please check the code and try again.';
      case 'session-expired':
      case 'invalid-verification-id':
        return 'OTP expired. Please request a new code.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'app-not-authorized':
      case 'invalid-app-credential':
      case 'captcha-check-failed':
        return 'App verification failed. Please contact FASTever support.';
      default:
        return e.message ?? 'Verification failed. Please try again.';
    }
  }

  Future<void> _launchURL(String url) async {
    try {
      final Uri uri = Uri.parse(url);

      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint("URL launch error: $e");
    }
  }

  Future<void> _sendOTP() async {
    if (!_cooldownReady || _otpRequestLocked || _isLoading ||
        _loginCompleted || _signInInProgress) return;

    final remaining = _remainingCooldownSeconds;
    if (remaining > 0) {
      _showError('Please wait $remaining seconds before requesting another OTP.');
      _startTimer();
      return;
    }

    final phone = _phoneController.text.trim();
    if (!RegExp(r'^[0-9]{10}$').hasMatch(phone)) {
      _showError('Please enter a valid 10-digit phone number.');
      return;
    }

    FocusScope.of(context).unfocus();
    final generation = ++_requestGeneration;
    final token = _otpSent ? _resendToken : null;
    setState(() {
      _isLoading = true;
      _isSendingOtp = true;
      _otpRequestLocked = true;
      _loadingTitle = 'Sending OTP...';
      _loadingSubtitle = 'Please wait while we verify your phone number.';
    });

    // Lock immediately, including cases where Firebase never calls codeSent.
    unawaited(_beginOtpCooldown());

    _stopRequestWait();
    _requestWatchdog = Timer(_requestWaitLimit, () {
      if (!_isCurrentRequest(generation) || !_isSendingOtp) return;
      // Invalidate callbacks from the timed-out request.
      _requestGeneration++;
      _resetLoadingStates();
      _showError('OTP request is taking too long. Check your SMS and retry after the timer.');
    });

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: '+91$phone',
        timeout: const Duration(seconds: 30),
        forceResendingToken: token,
        verificationCompleted: (PhoneAuthCredential credential) {
          if (!_isCurrentRequest(generation)) return;
          _stopRequestWait();
          // On supported Android devices Firebase can verify without manual OTP.
          unawaited(_signInWithCredential(credential));
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!_isCurrentRequest(generation) || _signInInProgress) return;
          _stopRequestWait();
          _resetLoadingStates();
          _showError(_friendlyFirebaseError(e));
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!_isCurrentRequest(generation) || _signInInProgress) return;
          _stopRequestWait();
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _otpSent = true;
            _otpController.clear();
            _isLoading = false;
            _isSendingOtp = false;
            _otpRequestLocked = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.black87,
              content: Text('OTP requested. Delivery may take a moment.',
                  style: TextStyle(color: _brandYellow)),
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!_isCurrentRequest(generation) || _signInInProgress) return;
          // Do not overwrite a newer verification ID from another request.
          if (_verificationId.isEmpty) _verificationId = verificationId;
        },
      );
    } on FirebaseAuthException catch (e) {
      if (!_isCurrentRequest(generation) || _signInInProgress) return;
      _stopRequestWait();
      _resetLoadingStates();
      _showError(_friendlyFirebaseError(e));
    } catch (e) {
      if (!_isCurrentRequest(generation) || _signInInProgress) return;
      _stopRequestWait();
      debugPrint('Send OTP error: $e');
      _resetLoadingStates();
      _showError('Unable to request OTP. Check your connection and try later.');
    }
  }

  Future<void> _verifyOTP() async {
    if (_signInInProgress || _loginCompleted || _isLoading) return;
    final otp = _otpController.text.trim();
    if (_verificationId.isEmpty) {
      _showError('Please request OTP again.');
      return;
    }
    if (!RegExp(r'^[0-9]{6}$').hasMatch(otp)) {
      _showError('Please enter the full 6-digit OTP.');
      return;
    }
    FocusScope.of(context).unfocus();
    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId,
      smsCode: otp,
    );
    await _signInWithCredential(credential);
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    if (_signInInProgress || _loginCompleted || !mounted) return;
    _signInInProgress = true;
    _stopRequestWait();
    setState(() {
      _isLoading = true;
      _isSendingOtp = false;
      _isVerifyingOtp = true;
      _loadingTitle = 'Verifying OTP...';
      _loadingSubtitle = 'Please wait. This may take a few seconds.';
    });
    try {
      final userCredential = await _auth.signInWithCredential(credential);
      if (!mounted) return;
      if (userCredential.user == null) {
        _showError('Login failed. Please try again.');
        return;
      }
      _loginCompleted = true;
      ++_requestGeneration;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) _showError(_friendlyFirebaseError(e));
    } catch (e) {
      debugPrint('Login error: $e');
      if (mounted) _showError('Login failed. Please try again.');
    } finally {
      _signInInProgress = false;
      if (mounted && !_loginCompleted) _resetLoadingStates();
    }
  }

  void _showError(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.black87,
        content: Text(
          msg,
          style: const TextStyle(
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  void _changeNumber() {
    if (!mounted || _isLoading || _signInInProgress) return;
    ++_requestGeneration;
    _stopRequestWait();

    setState(() {
      _otpSent = false;

      _otpController.clear();

      _verificationId = "";
      _resendToken = null;

      _otpRequestLocked = false;

      _isLoading = false;
      _isSendingOtp = false;
      _isVerifyingOtp = false;
    });

    // Existing cooldown is intentionally preserved.
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _brandYellow,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 40),

                          const Text(
                            "Let's sign you in.",
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                              letterSpacing: -0.5,
                            ),
                          ),

                          const SizedBox(height: 10),

                          const Text(
                            "Welcome to FASTever.\nContinue with your phone number.",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                              height: 1.3,
                            ),
                          ),

                          const SizedBox(height: 45),

                          AnimatedCrossFade(
                            duration: const Duration(
                              milliseconds: 350,
                            ),
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
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: 28,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 26,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                color: Colors.black,
              ),

              const SizedBox(height: 20),

              Text(
                _loadingTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                _loadingSubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black54,
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
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.black,
            ),
          ),

          const SizedBox(height: 8),

          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            autofillHints: const [
              AutofillHints.telephoneNumber,
            ],
            maxLength: 10,
            enabled: !_isSendingOtp && !_isLoading,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            style: const TextStyle(
              fontSize: 18,
              letterSpacing: 1.0,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            decoration: InputDecoration(
              prefixIcon: const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 15,
                ),
                child: Text(
                  "+91",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              hintText: "Enter phone number",
              hintStyle: const TextStyle(
                color: Colors.black38,
                fontWeight: FontWeight.normal,
              ),
              counterText: "",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Colors.black12,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Colors.black,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: (
                _isSendingOtp ||
                _otpRequestLocked ||
                _isLoading ||
                !_cooldownReady ||
                _remainingCooldownSeconds > 0
              )
                  ? null
                  : _sendOTP,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: _brandYellow,
                disabledBackgroundColor: Colors.black45,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isSendingOtp
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        color: _brandYellow,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      _remainingCooldownSeconds > 0
                          ? 'Wait $_countdownText'
                          : 'Get OTP',
                      style: const TextStyle(
                        fontSize: 18,
                        color: _brandYellow,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),

          if (_remainingCooldownSeconds > 0) ...[
            const SizedBox(height: 12),

            Center(
              child: Text(
                'Please wait $_countdownText before requesting another OTP.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
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
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Enter OTP",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.black,
                ),
              ),

              TextButton(
                onPressed: _isLoading
                    ? null
                    : _changeNumber,
                child: const Text(
                  "Change Number",
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            autofillHints: const [
              AutofillHints.oneTimeCode,
            ],
            maxLength: 6,
            enabled: !_isVerifyingOtp && !_isLoading,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              letterSpacing: 6.0,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            decoration: InputDecoration(
              hintText: "\u2022 \u2022 \u2022 \u2022 \u2022 \u2022",
              hintStyle: const TextStyle(
                color: Colors.black38,
                letterSpacing: 6.0,
              ),
              counterText: "",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Colors.black12,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Colors.black,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),

          const SizedBox(height: 15),

          Center(
            child: (_canResend && _cooldownReady)
                ? TextButton(
                    onPressed: (
                      _isSendingOtp ||
                      _otpRequestLocked ||
                      _isLoading
                    )
                        ? null
                        : _sendOTP,
                    child: const Text(
                      "Resend OTP",
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  )
                : Column(
                    children: [
                      Text(
                        "Resend OTP in $_countdownText",
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 5),

                      const Text(
                        "You can request a new OTP when the timer reaches zero.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
          ),

          const SizedBox(height: 15),

          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: (
                _isVerifyingOtp || _isLoading
              )
                  ? null
                  : _verifyOTP,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: _brandYellow,
                disabledBackgroundColor: Colors.black45,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isVerifyingOtp
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        color: _brandYellow,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      "Verify & Login",
                      style: TextStyle(
                        fontSize: 18,
                        color: _brandYellow,
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
              style: TextStyle(
                fontSize: 11,
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 4),

            Wrap(
              alignment: WrapAlignment.center,
              children: [
                _link("Terms", _termsUrl),

                const Text(
                  "  \u2022  ",
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 11,
                  ),
                ),

                _link("Privacy", _privacyUrl),

                const Text(
                  "  \u2022  ",
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 11,
                  ),
                ),

                _link("Shipping", _shippingUrl),
              ],
            ),

            const SizedBox(height: 4),

            _link(
              "Refund & Cancellation Policy",
              _refundUrl,
            ),
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
          color: Colors.black,
        ),
      ),
    );
  }
}
