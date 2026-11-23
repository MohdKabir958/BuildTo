import 'package:flutter/material.dart';

import 'customer_api.dart';
import 'customer_design.dart';
import 'customer_session.dart';
import 'customer_reference_home.dart';
import 'customer_workspace.dart';

/// Pixel-aligned Splyzo customer authentication entry screens.
///
/// Clerk's native Android SDK owns passwords, email/phone verification,
/// social login and account recovery. Tapping the styled credential surface
/// opens that secure flow; we never collect credentials into a fake Flutter
/// form or silently discard user-entered passwords.
class SplyzoReferenceAuthScreen extends StatefulWidget {
  const SplyzoReferenceAuthScreen({super.key, this.signUp = false});
  final bool signUp;

  @override
  State<SplyzoReferenceAuthScreen> createState() =>
      _SplyzoReferenceAuthScreenState();
}

class _SplyzoReferenceAuthScreenState extends State<SplyzoReferenceAuthScreen> {
  bool busy = false;
  bool agreed = false;

  Future<void> _openSecureAuth({String? mode}) async {
    if (busy) return;
    if (widget.signUp && !agreed) {
      notice(
        context,
        'Please accept the Terms & Conditions to create an account.',
      );
      return;
    }
    setState(() => busy = true);
    final s = CustomerScope.of(context);
    try {
      if (s.auth is NativeCustomerIdentity) {
        final native = s.auth as NativeCustomerIdentity;
        await native.initialize();
        final authenticated = await native.sessions.authenticate(
          mode: mode ?? (widget.signUp ? 'signUp' : 'signIn'),
        );
        if (authenticated) await s.restore();
      } else {
        // Real test seam: fakes use their own sign-in implementation.
        await s.signIn();
      }
      if (!mounted) return;
      if (s.signedIn) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      } else if (s.authNotice != null) {
        notice(context, s.authNotice!);
      }
    } catch (error) {
      if (mounted) {
        notice(
          context,
          error is CustomerProblem
              ? error.message
              : 'Secure sign-in could not open. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _credential({
    required IconData icon,
    required String label,
    bool obscured = false,
  }) => Semantics(
    button: true,
    label: '$label. Opens secure ${widget.signUp ? 'registration' : 'sign-in'}',
    child: Material(
      color: const Color(0xFFEFF5FF),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: Key('auth-field-$label'),
        borderRadius: BorderRadius.circular(18),
        onTap: busy ? null : _openSecureAuth,
        child: Container(
          constraints: const BoxConstraints(minHeight: 55),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: SplyzoReferenceColors.border),
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF6FAFF), Color(0xFFE8F0FC)],
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: SplyzoReferenceColors.navy, size: 22),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: SplyzoReferenceColors.secondary,
                  ),
                ),
              ),
              if (obscured)
                const Icon(
                  Icons.visibility_outlined,
                  size: 21,
                  color: SplyzoReferenceColors.secondary,
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _socialButton(String label, Widget emblem) => Expanded(
    child: OutlinedButton(
      onPressed: busy ? null : () => _openSecureAuth(),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: SplyzoReferenceColors.border, width: 1),
        backgroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        minimumSize: const Size.fromHeight(52),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          emblem,
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                color: SplyzoReferenceColors.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final signUp = widget.signUp;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(15, 24, 15, 23),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: SplyzoReferenceLogo(large: true)),
                  const SizedBox(height: 24),
                  const SplyzoReferenceBanner(auth: true),
                  SizedBox(height: signUp ? 23 : 32),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 6,
                        height: 33,
                        margin: const EdgeInsets.only(top: 1),
                        decoration: BoxDecoration(
                          color: SplyzoReferenceColors.orange,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              signUp ? 'Create Account' : 'Welcome Back',
                              style: const TextStyle(
                                fontFamily: 'packages/kraveo_ui/Bricolage',
                                fontWeight: FontWeight.w800,
                                fontSize: 29,
                                height: 1.12,
                                letterSpacing: -.8,
                                color: SplyzoReferenceColors.navy,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              signUp
                                  ? 'Sign up to order building materials from trusted suppliers.'
                                  : 'Login to continue shopping building materials.',
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: SplyzoReferenceColors.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: signUp ? 20 : 29),
                  if (signUp) ...[
                    _credential(
                      icon: Icons.person_outline_rounded,
                      label: 'Full Name',
                    ),
                    const SizedBox(height: 12),
                    _credential(
                      icon: Icons.phone_android_rounded,
                      label: 'Mobile Number',
                    ),
                    const SizedBox(height: 12),
                    _credential(
                      icon: Icons.mail_outline_rounded,
                      label: 'Email',
                    ),
                    const SizedBox(height: 12),
                  ] else
                    _credential(
                      icon: Icons.phone_android_rounded,
                      label: 'Mobile Number or Email',
                    ),
                  const SizedBox(height: 14),
                  _credential(
                    icon: Icons.lock_outline_rounded,
                    label: 'Password',
                    obscured: true,
                  ),
                  if (signUp) ...[
                    const SizedBox(height: 12),
                    _credential(
                      icon: Icons.lock_outline_rounded,
                      label: 'Confirm Password',
                      obscured: true,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          key: const Key('auth-terms-checkbox'),
                          value: agreed,
                          activeColor: SplyzoReferenceColors.orange,
                          onChanged: busy
                              ? null
                              : (value) =>
                                    setState(() => agreed = value ?? false),
                          visualDensity: VisualDensity.compact,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 9),
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Text(
                                  'I agree to the ',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: SplyzoReferenceColors.navy,
                                  ),
                                ),
                                InkWell(
                                  onTap: () => push(
                                    context,
                                    const ContentPage(
                                      'terms-and-conditions',
                                      'Terms & Conditions',
                                    ),
                                  ),
                                  child: const Text(
                                    'Terms & Conditions',
                                    style: TextStyle(
                                      color: SplyzoReferenceColors.orange,
                                      decoration: TextDecoration.underline,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                                const Text(
                                  ' and ',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: SplyzoReferenceColors.navy,
                                  ),
                                ),
                                InkWell(
                                  onTap: () => push(
                                    context,
                                    const ContentPage(
                                      'privacy-policy',
                                      'Privacy Policy',
                                    ),
                                  ),
                                  child: const Text(
                                    'Privacy Policy',
                                    style: TextStyle(
                                      color: SplyzoReferenceColors.orange,
                                      decoration: TextDecoration.underline,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: busy
                            ? null
                            : () => _openSecureAuth(mode: 'signIn'),
                        style: TextButton.styleFrom(
                          foregroundColor: SplyzoReferenceColors.orange,
                        ),
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  SizedBox(height: signUp ? 13 : 8),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      key: Key(signUp ? 'reference-signup' : 'reference-login'),
                      onPressed: busy ? null : _openSecureAuth,
                      style: FilledButton.styleFrom(
                        backgroundColor: SplyzoReferenceColors.orange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(17),
                        ),
                      ),
                      child: busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              signUp ? 'Sign Up' : 'Login',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  const Row(
                    children: [
                      Expanded(child: Divider(color: Color(0xFFAAB9D5))),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 9),
                        child: Text(
                          'or continue with',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: SplyzoReferenceColors.secondary,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Color(0xFFAAB9D5))),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _socialButton(
                        'Google',
                        const Text(
                          'G',
                          style: TextStyle(
                            fontSize: 26,
                            color: Color(0xFF4285F4),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 11),
                      _socialButton(
                        'Apple',
                        const Icon(Icons.apple, size: 27, color: Colors.black),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        signUp
                            ? 'Already have an account? '
                            : 'Don’t have an account? ',
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: SplyzoReferenceColors.navy,
                        ),
                      ),
                      InkWell(
                        key: const Key('auth-switch-mode'),
                        onTap: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) =>
                                SplyzoReferenceAuthScreen(signUp: !signUp),
                          ),
                        ),
                        child: Text(
                          signUp ? 'Login' : 'Sign Up',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: SplyzoReferenceColors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Credentials and verification are handled by secure Clerk sign-in.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: SplyzoReferenceColors.secondary.withValues(
                          alpha: .78,
                        ),
                        fontSize: 9,
                      ),
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
}
