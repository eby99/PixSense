import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_animate/flutter_animate.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;

  // Password validation states
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasDigit = false;
  bool _hasSpecialChar = false;

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Add listener to password field to validate in real-time
    _passwordController.addListener(_validatePassword);
  }

  void _validatePassword() {
    final password = _passwordController.text;

    setState(() {
      _hasMinLength = password.length >= 8;
      _hasUppercase = password.contains(RegExp(r'[A-Z]'));
      _hasLowercase = password.contains(RegExp(r'[a-z]'));
      _hasDigit = password.contains(RegExp(r'[0-9]'));
      _hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    });
  }

  bool get isPasswordValid =>
      _hasMinLength && _hasUppercase && _hasLowercase &&
          _hasDigit && _hasSpecialChar;

  Future<void> register() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      _showErrorSnackBar('Passwords do not match!');
      return;
    }

    if (!isPasswordValid) {
      _showErrorSnackBar('Please ensure your password meets all requirements');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Create user in Firebase Authentication
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      User? user = userCredential.user;

      if (user != null) {
        // Create user document in Firestore
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'username': _usernameController.text.trim(),
          'email': _emailController.text.trim(),
          'joinedDate': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          'profileCompleted': false,
          'uid': user.uid,
        });

        // Update user profile with username
        await user.updateDisplayName(_usernameController.text.trim());

        if (mounted) {
          _showSuccessSnackBar('Account created successfully!');

          Future.delayed(Duration(seconds: 1), () {
            Navigator.pop(context);
          });
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);

      String errorMessage = 'Registration failed';
      if (e is FirebaseAuthException) {
        if (e.code == 'weak-password') errorMessage = 'The password is too weak';
        else if (e.code == 'email-already-in-use') errorMessage = 'An account already exists for this email';
        else if (e.code == 'invalid-email') errorMessage = 'The email is not valid';
      }

      _showErrorSnackBar(errorMessage);
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Expanded(child: Text(message, style: TextStyle(fontSize: 16))),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(12),
        elevation: 6,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white),
            SizedBox(width: 12),
            Expanded(child: Text(message, style: TextStyle(fontSize: 16))),
          ],
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(12),
        elevation: 6,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Widget _buildPasswordRequirement(String text, bool isMet) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle : Icons.circle_outlined,
            color: isMet ? Colors.green : Colors.grey,
            size: 16,
          ),
          SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: isMet ? Colors.green : Colors.grey[700],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool isConfirmPassword = false,
    bool isUsername = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          obscureText: isPassword ? !_isPasswordVisible : isConfirmPassword ? !_isConfirmPasswordVisible : false,
          validator: (value) {
            if (value == null || value.isEmpty) return 'Please enter $label';
            if (isPassword && !isPasswordValid) return 'Password does not meet requirements';
            if (isConfirmPassword && value != _passwordController.text) return 'Passwords do not match';
            if (isUsername && value.length < 3) return 'Username must be at least 3 characters';
            return null;
          },
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: Color(0xFF673AB7)),
            suffixIcon: isPassword || isConfirmPassword
                ? IconButton(
              icon: Icon(
                isPassword ? (_isPasswordVisible ? Icons.visibility : Icons.visibility_off)
                    : (_isConfirmPasswordVisible ? Icons.visibility : Icons.visibility_off),
                color: Color(0xFF673AB7),
              ),
              onPressed: () => setState(() {
                if (isPassword) _isPasswordVisible = !_isPasswordVisible;
                if (isConfirmPassword) _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
              }),
            )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Color(0xFF673AB7), width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            filled: true,
            fillColor: Colors.grey[50],
            contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          ),
        ).animate().fadeIn(),

        // Show password requirements only when password field has focus or has text
        if (isPassword && (_passwordController.text.isNotEmpty || FocusScope.of(context).hasFocus))
          Padding(
            padding: const EdgeInsets.only(top: 12.0, left: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Password Requirements:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                SizedBox(height: 8),
                _buildPasswordRequirement('At least 8 characters', _hasMinLength),
                _buildPasswordRequirement('At least one uppercase letter (A-Z)', _hasUppercase),
                _buildPasswordRequirement('At least one lowercase letter (a-z)', _hasLowercase),
                _buildPasswordRequirement('At least one number (0-9)', _hasDigit),
                _buildPasswordRequirement('At least one special character (!@#\$%^&*)', _hasSpecialChar),
              ],
            ).animate().fadeIn(duration: 200.ms),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Color(0xFF673AB7)),
        title: Text(
          'Create Account',
          style: TextStyle(color: Color(0xFF673AB7), fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 20),
              Icon(Icons.person_add, size: 80, color: Color(0xFF673AB7))
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .scale(),
              SizedBox(height: 40),
              Text(
                'Join PixSense',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF673AB7)),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 200.ms),
              SizedBox(height: 8),
              Text(
                'Create an account to start your journey',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 300.ms),
              SizedBox(height: 40),

              // Username Field
              _buildTextField(
                controller: _usernameController,
                label: 'Username',
                icon: Icons.person,
                isUsername: true,
              ),
              SizedBox(height: 20),

              // Email Field
              _buildTextField(
                controller: _emailController,
                label: 'Email',
                icon: Icons.email,
              ),
              SizedBox(height: 20),

              // Password Field
              _buildTextField(
                controller: _passwordController,
                label: 'Password',
                icon: Icons.lock,
                isPassword: true,
              ),
              SizedBox(height: 20),

              // Confirm Password Field
              _buildTextField(
                controller: _confirmPasswordController,
                label: 'Confirm Password',
                icon: Icons.lock_outline,
                isConfirmPassword: true,
              ),
              SizedBox(height: 40),

              ElevatedButton(
                onPressed: _isLoading ? null : register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF673AB7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                child: _isLoading
                    ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation(Colors.white)),
                )
                    : Text('Create Account'),
              ).animate().fadeIn(delay: 700.ms).scale(begin: Offset(0.9, 0.9)),

              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Already have an account? ', style: TextStyle(color: Colors.grey[700])),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Login Here', style: TextStyle(color: Color(0xFF673AB7), fontWeight: FontWeight.bold)),
                  ),
                ],
              ).animate().fadeIn(delay: 800.ms),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Remove listener before disposing
    _passwordController.removeListener(_validatePassword);

    // Dispose of controllers to prevent memory leaks
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }
}