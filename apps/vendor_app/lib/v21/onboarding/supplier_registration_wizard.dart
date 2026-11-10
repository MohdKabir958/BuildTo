import 'package:flutter/material.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import 'supplier_application_models.dart';

/// Four-step supplier application with the same navy, amber and card language
/// as the approved Splyzo customer design reference.
class SupplierRegistrationWizard extends StatefulWidget {
  const SupplierRegistrationWizard({
    super.key,
    required this.email,
    required this.submit,
    required this.cancel,
    required this.completed,
  });
  final String? email;
  final Future<SupplierApplicationSummary> Function(SupplierRegistrationDraft)
      submit;
  final ValueChanged<SupplierApplicationSummary> completed;
  final VoidCallback cancel;

  @override
  State<SupplierRegistrationWizard> createState() =>
      _SupplierRegistrationWizardState();
}

class _SupplierRegistrationWizardState
    extends State<SupplierRegistrationWizard> {
  final formKey = GlobalKey<FormState>();
  final slug = TextEditingController();
  final legalName = TextEditingController();
  final displayName = TextEditingController();
  final phone = TextEditingController();
  final gstin = TextEditingController();
  final line1 = TextEditingController();
  final line2 = TextEditingController();
  final city = TextEditingController();
  final state = TextEditingController();
  final pinCode = TextEditingController();
  SupplierGstRegistration gst = SupplierGstRegistration.regular;
  int step = 0;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    for (final c in [
      slug,
      legalName,
      displayName,
      phone,
      gstin,
      line1,
      line2,
      city,
      state,
      pinCode
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  SupplierRegistrationDraft _draft() => SupplierRegistrationDraft(
        slug: slug.text,
        legalName: legalName.text,
        displayName: displayName.text,
        contactEmail: widget.email ?? '',
        contactPhone: phone.text,
        gstRegistration: gst,
        gstin: gstin.text,
        line1: line1.text,
        line2: line2.text,
        city: city.text,
        state: state.text,
        pinCode: pinCode.text,
      );

  bool _allValid() {
    final d = _draft();
    return (widget.email?.isNotEmpty ?? false) &&
        SupplierRegistrationDraft.validateSlug(d.slug) == null &&
        SupplierRegistrationDraft.validateRequired(d.legalName, 'Legal name',
                max: 250) ==
            null &&
        SupplierRegistrationDraft.validateRequired(
                d.displayName, 'Display name') ==
            null &&
        SupplierRegistrationDraft.validatePhone(d.contactPhone) == null &&
        SupplierRegistrationDraft.validateGstin(d.gstin, gst) == null &&
        SupplierRegistrationDraft.validateRequired(d.line1, 'Address',
                min: 5, max: 250) ==
            null &&
        SupplierRegistrationDraft.validateRequired(d.city, 'City',
                min: 2, max: 100) ==
            null &&
        SupplierRegistrationDraft.validateRequired(d.state, 'State',
                min: 2, max: 100) ==
            null &&
        SupplierRegistrationDraft.validatePinCode(d.pinCode) == null;
  }

  void _next() {
    if (busy) {
      return;
    }
    if (step < 3) {
      if (formKey.currentState?.validate() != true) {
        return;
      }
      setState(() {
        step++;
        error = null;
      });
      return;
    }
    if (!_allValid()) {
      setState(
          () => error = 'One or more details are invalid. Review all steps.');
      return;
    }
    _submit();
  }

  Future<void> _submit() async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.submit(_draft());
      if (!mounted) {
        return;
      }
      widget.completed(result);
    } catch (e) {
      if (!mounted) {
        return;
      }
      if (e is FormatException) {
        error =
            'Unexpected application response. Refresh your applications before trying again.';
      } else {
        // Network timeouts may occur *after* the server has submitted it.
        // Never automatically retry a POST on an uncertain outcome.
        error =
            'Could not confirm submission. Return to applications and refresh before retrying.';
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => BuildToCard(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('STEP ${step + 1} / 4',
              style: const TextStyle(
                  color: BuildToPalette.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
          const SizedBox(height: 10),
          LinearProgressIndicator(
              value: (step + 1) / 4,
              minHeight: 6,
              color: BuildToPalette.orange,
              backgroundColor: BuildToPalette.outline,
              borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: 18),
          Text(
              const [
                'Your business',
                'GST & contact',
                'Billing address',
                'Review & submit'
              ][0 + step],
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (step == 0) ...[
                    _Field(
                        label: 'Registered legal name',
                        controller: legalName,
                        validator: (v) =>
                            SupplierRegistrationDraft.validateRequired(
                                v, 'Legal name',
                                max: 250)),
                    _Field(
                        label: 'Supplier display name',
                        controller: displayName,
                        validator: (v) =>
                            SupplierRegistrationDraft.validateRequired(
                                v, 'Display name')),
                    _Field(
                        label: 'Unique business slug',
                        controller: slug,
                        helper:
                            'Letters, numbers and hyphens; at least 3 characters.',
                        validator: SupplierRegistrationDraft.validateSlug),
                  ],
                  if (step == 1) ...[
                    const Text('Your verified Clerk email',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(widget.email ?? 'A verified email is required',
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<SupplierGstRegistration>(
                      initialValue: gst,
                      decoration:
                          const InputDecoration(labelText: 'GST registration'),
                      items: SupplierGstRegistration.values
                          .map((value) => DropdownMenuItem(
                              value: value, child: Text(value.apiValue)))
                          .toList(),
                      onChanged: busy
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => gst = value);
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    if (gst.needsGstin)
                      _Field(
                          label: '15-character GSTIN',
                          controller: gstin,
                          validator: (v) =>
                              SupplierRegistrationDraft.validateGstin(v, gst)),
                    _Field(
                        label: 'Phone (optional)',
                        controller: phone,
                        keyboard: TextInputType.phone,
                        helper: 'E.164 format, e.g. +919876543210',
                        validator: SupplierRegistrationDraft.validatePhone),
                  ],
                  if (step == 2) ...[
                    _Field(
                        label: 'Billing address line 1',
                        controller: line1,
                        validator: (v) =>
                            SupplierRegistrationDraft.validateRequired(
                                v, 'Address',
                                min: 5, max: 250)),
                    _Field(
                        label: 'Address line 2 (optional)', controller: line2),
                    _Field(
                        label: 'City',
                        controller: city,
                        validator: (v) =>
                            SupplierRegistrationDraft.validateRequired(
                                v, 'City',
                                min: 2, max: 100)),
                    _Field(
                        label: 'State',
                        controller: state,
                        validator: (v) =>
                            SupplierRegistrationDraft.validateRequired(
                                v, 'State',
                                min: 2, max: 100)),
                    _Field(
                        label: '6-digit PIN',
                        controller: pinCode,
                        keyboard: TextInputType.number,
                        validator: SupplierRegistrationDraft.validatePinCode),
                  ],
                  if (step == 3) ...[
                    _ReviewValue('Registered name', legalName.text),
                    _ReviewValue('Display name', displayName.text),
                    _ReviewValue('Business slug', slug.text),
                    _ReviewValue('Clerk email', widget.email ?? 'Unavailable'),
                    _ReviewValue('GST registration', gst.apiValue),
                    if (gst.needsGstin)
                      _ReviewValue('GSTIN', gstin.text.toUpperCase()),
                    _ReviewValue('Billing city & PIN',
                        '${city.text}, ${state.text} ${pinCode.text}'),
                    const SizedBox(height: 12),
                    const BuildToStatePanel(
                      title: 'Independent verification required',
                      icon: Icons.fact_check_outlined,
                      message:
                          'Submission creates a PENDING supplier application, not an approved business. '
                          'Splyzo operations will independently verify your documents.',
                    ),
                  ],
                ],
              )),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: BuildToPalette.danger)),
          ],
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
                child: OutlinedButton(
              onPressed: busy
                  ? null
                  : () {
                      if (step == 0) {
                        widget.cancel();
                      } else {
                        setState(() {
                          step--;
                          error = null;
                        });
                      }
                    },
              child: Text(step == 0 ? 'Cancel' : 'Back'),
            )),
            const SizedBox(width: 12),
            Expanded(
                child: BuildToPrimaryButton(
                    label: step == 3 ? 'Submit application' : 'Continue',
                    onPressed: _next,
                    busy: busy)),
          ]),
        ],
      ));
}

class _Field extends StatelessWidget {
  const _Field(
      {required this.label,
      required this.controller,
      this.validator,
      this.keyboard,
      this.helper});
  final String label;
  final TextEditingController controller;
  final String? helper;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
            key: ValueKey('supplier-registration-$label'),
            controller: controller,
            validator: validator,
            keyboardType: keyboard,
            maxLength: 250,
            decoration: InputDecoration(labelText: label, helperText: helper)),
      );
}

class _ReviewValue extends StatelessWidget {
  const _ReviewValue(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ]),
      );
}
