import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_logo.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _emergencyNameController = TextEditingController();
  final TextEditingController _emergencyPhoneController = TextEditingController();

  // Public sign-up creates Citizen accounts only. Admins and Response Units
  // are provisioned by an administrator, never through self-registration.
  final String _selectedRole = 'Citizen';
  bool _locationPermission = false;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                const Center(child: AppLogo(size: 72)),
                const SizedBox(height: 16),
                Text(
                  'Join the Network',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textHi,
                  ),
                ),
                const SizedBox(height: 24),
                _buildTextField(
                  label: 'Full Name',
                  icon: Icons.person_outline,
                  controller: _nameController,
                  hint: 'John Doe',
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  label: 'Email',
                  icon: Icons.email_outlined,
                  controller: _emailController,
                  hint: 'example@mail.com',
                  keyboardType: TextInputType.emailAddress,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Please enter your email';
                    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(val.trim());
                    return ok ? null : 'Enter a valid email address';
                  },
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  label: 'Password',
                  icon: Icons.lock_outline,
                  controller: _passwordController,
                  obscureText: true,
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Please enter a password';
                    if (val.length < 6) return 'Password must be at least 6 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                const Text('Emergency Contact Info',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey)),
                const SizedBox(height: 12),
                _buildTextField(
                  label: 'Emergency Contact Name',
                  icon: Icons.contact_emergency_outlined,
                  controller: _emergencyNameController,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  label: 'Emergency Contact Phone',
                  icon: Icons.phone_android_outlined,
                  controller: _emergencyPhoneController,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 24),
                SwitchListTile(
                  title: const Text('Enable Location Access',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  value: _locationPermission,
                  onChanged: (val) => setState(() => _locationPermission = val),
                  secondary: const Icon(Icons.location_on, color: Colors.blue),
                ),
                const SizedBox(height: 32),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _handleSignUp,
                        child: const Text('Create Account'),
                      ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_locationPermission) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enable location access')));
      return;
    }

    setState(() => _isLoading = true);
    final result = await _authService.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      name: _nameController.text.trim(),
      role: _selectedRole,
      emergencyName: _emergencyNameController.text.trim(),
      emergencyPhone: _emergencyPhoneController.text.trim(),
      locationEnabled: _locationPermission,
    );
    setState(() => _isLoading = false);

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Registration Successful!')));
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Registration Failed. Try again.')));
    }
  }

  Widget _buildTextField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    String? hint,
    bool obscureText = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
      validator: validator ?? (val) => (val == null || val.isEmpty) ? 'Please enter $label' : null,
    );
  }
}
