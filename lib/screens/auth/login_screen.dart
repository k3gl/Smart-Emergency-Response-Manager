import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_logo.dart';
import '../../theme/aurora_background.dart';
import '../../theme/entrance_fade.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();
  
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 36),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  const EntranceFade(
                    child: Center(child: AppLogo(size: 84, showWordmark: true)),
                  ),
                  const SizedBox(height: 24),
                  EntranceFade(
                    delay: const Duration(milliseconds: 150),
                    child: Text(
                      'Welcome back',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textHi,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  EntranceFade(
                    delay: const Duration(milliseconds: 250),
                    child: Text(
                      'Sign in to access your dashboard',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppTheme.textLo),
                    ),
                  ),
                  const SizedBox(height: 32),
                  EntranceFade(
                    delay: const Duration(milliseconds: 350),
                    child: GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTextField(
                            label: 'Email',
                            icon: Icons.email_outlined,
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Please enter your email';
                              }
                              final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                  .hasMatch(val.trim());
                              return ok ? null : 'Enter a valid email address';
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            label: 'Password',
                            icon: Icons.lock_outline,
                            controller: _passwordController,
                            obscureText: true,
                          ),
                          const SizedBox(height: 24),
                          _isLoading
                              ? const Center(
                                  child: CircularProgressIndicator())
                              : ElevatedButton(
                                  onPressed: _handleLogin,
                                  child: const Text('Login'),
                                ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  EntranceFade(
                    delay: const Duration(milliseconds: 450),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Don't have an account?",
                            style: TextStyle(color: AppTheme.textLo)),
                        TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/register'),
                          child: const Text('Register',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      
      final response = await _authService.login(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      if (response != null && response.user != null) {
        // A Unit row (units.auth_user_id) wins over a profiles.role so an
        // Admin can never accidentally land on /unit, and a Unit can never
        // land on /admin.
        final destination =
            await _authService.resolveDestination(response.user!.id);

        if (!mounted) return;
        setState(() => _isLoading = false);

        switch (destination) {
          case LoginDestination.unit:
            Navigator.pushReplacementNamed(context, '/unit');
            break;
          case LoginDestination.admin:
            Navigator.pushReplacementNamed(context, '/admin');
            break;
          case LoginDestination.citizen:
            Navigator.pushReplacementNamed(context, '/citizen');
            break;
          case LoginDestination.none:
            await _authService.signOut();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Account is not provisioned or is disabled. Contact admin.'),
              ),
            );
            break;
        }
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login Failed. Check your credentials.')),
        );
      }
    }
  }

  Widget _buildTextField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
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
        prefixIcon: Icon(icon),
      ),
      validator: validator ?? (val) => (val == null || val.isEmpty) ? 'Please enter $label' : null,
    );
  }
}
