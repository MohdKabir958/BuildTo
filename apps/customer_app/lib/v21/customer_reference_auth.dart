import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'customer_api.dart';
import 'customer_design.dart';
import 'customer_session.dart';
import 'customer_reference_home.dart';
import 'customer_workspace.dart';

class SplyzoReferenceAuthScreen extends StatefulWidget {
  const SplyzoReferenceAuthScreen({super.key, this.signUp = false});
  final bool signUp;

  @override
  State<SplyzoReferenceAuthScreen> createState() =>
      _SplyzoReferenceAuthScreenState();
}

class _SplyzoReferenceAuthScreenState extends State<SplyzoReferenceAuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  bool busy = false;
  String? _socialAction;
  bool agreed = false;
  bool _otp = false;
  String? _step;
  String? _attempt;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _phone,
      _email,
      _identifier,
      _password,
      _confirm,
      _code,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _mobile(String value) {
    final compact = value.trim().replaceAll(RegExp(r'[\s()-]'), '');
    if (RegExp(r'^\d{10}$').hasMatch(compact)) return '+91$compact';
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(compact) ? compact : null;
  }

  void _switchLoginMethod(bool otp) {
    setState(() {
      _otp = otp;
      _step = null;
      _attempt = null;
      _code.clear();
    });
  }

  Future<void> _runAuth({
    String? action,
    Map<String, String> fields = const {},
  }) async {
    if (busy) return;
    if (widget.signUp && !agreed) {
      notice(context,
          'Please accept the Terms & Conditions to create an account.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      _socialAction = action == 'google' || action == 'apple' ? action : null;
    });
    final session = CustomerScope.of(context);
    try {
      final auth = session.auth;
      await session.signIn(
        authenticate: auth is CustomerFormIdentity
            ? () async {
                if (action == null) {
                  return auth
                      .authenticateMode(widget.signUp ? 'signUp' : 'signIn');
                }
                final result = await auth.submitAuth(action, fields);
                if (!mounted) return result.step == 'complete';
                if (result.step == 'complete') return true;
                setState(() {
                  _step = result.step;
                  _attempt = result.attempt;
                  _code.clear();
                });
                return false;
              }
            : null,
      );
      if (mounted && session.signedIn && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (error is PlatformException && error.code == 'AUTH_CANCELLED') return;
      if (mounted) {
        notice(
          context,
          switch (error) {
            CustomerProblem() => error.message,
            PlatformException() =>
              error.message ?? 'Secure sign-in is unavailable.',
            _ => 'Secure sign-in could not connect. Please try again.',
          },
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          _socialAction = null;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final step = _step;
    if (step == 'continue') {
      await _runAuth();
    } else if (step != null) {
      await _runAuth(
        action: !widget.signUp && step == 'verifyPhone' ? 'verifyOtp' : step,
        fields: {'attempt': _attempt ?? '', 'code': _code.text.trim()},
      );
    } else if (widget.signUp) {
      await _runAuth(action: 'signUp', fields: {
        'name': _name.text.trim(),
        if (_phone.text.trim().isNotEmpty) 'phone': _mobile(_phone.text)!,
        'email': _email.text.trim(),
        'password': _password.text,
      });
    } else if (_otp) {
      await _runAuth(
          action: 'sendOtp', fields: {'phone': _mobile(_phone.text)!});
    } else {
      final identifier = _identifier.text.trim();
      await _runAuth(action: 'password', fields: {
        'identifier': _mobile(identifier) ?? identifier,
        'password': _password.text,
      });
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  Widget _credential({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    String? autofillHint,
    String? helperText,
    bool secret = false,
  }) =>
      _AuthField(
        key: Key('auth-field-$label'),
        icon: icon,
        label: label,
        controller: controller,
        validator: validator ?? _required,
        keyboardType: keyboardType,
        autofillHint: autofillHint,
        helperText: helperText,
        secret: secret,
        enabled: !busy,
      );

  List<Widget> _fields() {
    final step = _step;
    if (step != null) {
      final email = step.endsWith('Email');
      final destination = email ? _email.text.trim() : _mobile(_phone.text);
      if (step == 'continue') {
        return const [Text('Your account needs an additional security step.')];
      }
      return [
        Text(step.startsWith('verify')
            ? 'Enter the code sent to $destination.'
            : 'Send a verification code to $destination.'),
        if (step.startsWith('verify')) ...[
          const SizedBox(height: 12),
          _credential(
            icon: Icons.pin_outlined,
            label: 'Verification code',
            controller: _code,
            keyboardType: TextInputType.number,
            autofillHint: AutofillHints.oneTimeCode,
            validator: (value) => RegExp(r'^\d+$').hasMatch(value?.trim() ?? '')
                ? null
                : 'Enter the numeric code.',
          ),
          TextButton(
            onPressed: busy
                ? null
                : widget.signUp
                    ? () => _runAuth(
                          action: email ? 'sendEmail' : 'sendPhone',
                          fields: {'attempt': _attempt ?? ''},
                        )
                    : () => _switchLoginMethod(true),
            child: Text(widget.signUp
                ? 'Resend code'
                : 'Change number or request another code'),
          ),
        ],
      ];
    }
    return [
      if (widget.signUp) ...[
        _credential(
          icon: Icons.person_outline_rounded,
          label: 'Full Name',
          controller: _name,
          autofillHint: AutofillHints.name,
        ),
        const SizedBox(height: 12),
      ],
      if (widget.signUp || _otp)
        _credential(
          icon: Icons.phone_android_rounded,
          label: 'Mobile Number',
          controller: _phone,
          keyboardType: TextInputType.phone,
          autofillHint: AutofillHints.telephoneNumber,
          helperText: widget.signUp ? 'Optional' : null,
          validator: (value) {
            final number = value?.trim() ?? '';
            if (widget.signUp && number.isEmpty) return null;
            return _mobile(number) == null
                ? 'Enter a valid mobile number.'
                : null;
          },
        )
      else
        _credential(
          icon: Icons.phone_android_rounded,
          label: 'Mobile Number or Email',
          controller: _identifier,
          autofillHint: AutofillHints.username,
        ),
      if (widget.signUp) ...[
        const SizedBox(height: 12),
        _credential(
          icon: Icons.mail_outline_rounded,
          label: 'Email',
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHint: AutofillHints.email,
          validator: (value) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                  .hasMatch(value?.trim() ?? '')
              ? null
              : 'Enter a valid email address.',
        ),
      ],
      if (!_otp) ...[
        const SizedBox(height: 14),
        _credential(
          icon: Icons.lock_outline_rounded,
          label: 'Password',
          controller: _password,
          autofillHint: widget.signUp
              ? AutofillHints.newPassword
              : AutofillHints.password,
          validator: (value) =>
              value == null || value.isEmpty ? 'Enter your password.' : null,
          secret: true,
        ),
      ],
      if (widget.signUp) ...[
        const SizedBox(height: 12),
        _credential(
          icon: Icons.lock_outline_rounded,
          label: 'Confirm Password',
          controller: _confirm,
          secret: true,
          validator: (value) =>
              value == _password.text ? null : 'Passwords do not match.',
        ),
      ],
    ];
  }

  Widget _socialButton(String label, Widget emblem) => Expanded(
        child: OutlinedButton(
          onPressed: busy ? null : () => _runAuth(action: label.toLowerCase()),
          style: OutlinedButton.styleFrom(
            side:
                const BorderSide(color: SplyzoReferenceColors.border, width: 1),
            backgroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
              child: Form(
                key: _form,
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
                    ..._fields(),
                    if (signUp && _step == null) ...[
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
                    ] else if (!signUp && !_otp && _step == null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: busy ? null : _runAuth,
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
                        key: Key(
                            signUp ? 'reference-signup' : 'reference-login'),
                        onPressed: busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: SplyzoReferenceColors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                        child: busy && _socialAction == null
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
                                switch (_step) {
                                  'verifyEmail' ||
                                  'verifyPhone' =>
                                    'Verify code',
                                  'sendEmail' || 'sendPhone' => 'Send code',
                                  'continue' => 'Continue securely',
                                  _ => signUp
                                      ? 'Sign Up'
                                      : (_otp ? 'Send OTP' : 'Login'),
                                },
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                    if (!signUp)
                      TextButton(
                        onPressed:
                            busy ? null : () => _switchLoginMethod(!_otp),
                        child: Text(_otp
                            ? 'Login with password'
                            : 'Login with mobile OTP'),
                      ),
                    if (_step == null) ...[
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
                            const Icon(Icons.apple,
                                size: 27, color: Colors.black),
                          ),
                        ],
                      ),
                    ],
                    if (_socialAction != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _socialAction == 'google'
                            ? 'Connecting to Google…'
                            : 'Connecting to Apple…',
                        textAlign: TextAlign.center,
                      ),
                      if (CustomerScope.of(context).auth
                          is CustomerSocialAuthCancellation)
                        TextButton(
                          onPressed: () async {
                            final auth = CustomerScope.of(context).auth
                                as CustomerSocialAuthCancellation;
                            try {
                              await auth.cancelSocialAuth();
                            } on PlatformException {
                              if (context.mounted) {
                                notice(context,
                                    'Could not cancel yet. Please try again.');
                              }
                            }
                          },
                          child: const Text('Cancel sign-in'),
                        ),
                    ],
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
                          onTap: busy
                              ? null
                              : () => Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => SplyzoReferenceAuthScreen(
                                          signUp: !signUp),
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
      ),
    );
  }
}

class _AuthField extends StatefulWidget {
  const _AuthField({
    super.key,
    required this.icon,
    required this.label,
    required this.controller,
    required this.validator,
    required this.enabled,
    required this.secret,
    this.keyboardType,
    this.autofillHint,
    this.helperText,
  });

  final IconData icon;
  final String label;
  final TextEditingController controller;
  final String? Function(String?) validator;
  final bool enabled, secret;
  final TextInputType? keyboardType;
  final String? autofillHint, helperText;

  @override
  State<_AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<_AuthField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final hint = widget.autofillHint;
    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      obscureText: widget.secret && !_visible,
      autocorrect: false,
      enableSuggestions: !widget.secret,
      keyboardType: widget.keyboardType,
      autofillHints: hint == null ? null : [hint],
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        prefixIcon: Icon(widget.icon, color: SplyzoReferenceColors.navy),
        suffixIcon: widget.secret
            ? IconButton(
                tooltip: _visible ? 'Hide password' : 'Show password',
                onPressed: widget.enabled
                    ? () => setState(() => _visible = !_visible)
                    : null,
                icon: Icon(_visible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
              )
            : null,
        fillColor: SplyzoReferenceColors.field,
      ),
    );
  }
}
