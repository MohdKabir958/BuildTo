import 'package:flutter/material.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import 'supplier_application_models.dart';
import 'supplier_evidence_link_sheet.dart';

/// Four-step supplier application with the same navy, amber and card language
/// as the approved Splyzo customer design reference.
class SupplierRegistrationWizard extends StatefulWidget {
  const SupplierRegistrationWizard({
    super.key,
    required this.email,
    required this.submit,
    required this.cancel,
    required this.completed,
    this.uploadEvidence,
    this.attachEvidence,
    this.attachmentWarning,
  });
  final String? email;
  final Future<SupplierApplicationSummary> Function(SupplierRegistrationDraft)
      submit;
  final ValueChanged<SupplierApplicationSummary> completed;
  final VoidCallback cancel;
  final EvidenceUpload? uploadEvidence;
  final Future<void> Function(
    String supplierId,
    String mediaId,
    SupplierEvidenceType type,
  )? attachEvidence;
  final ValueChanged<String>? attachmentWarning;

  @override
  State<SupplierRegistrationWizard> createState() =>
      _SupplierRegistrationWizardState();
}

class _SupplierRegistrationWizardState
    extends State<SupplierRegistrationWizard> {
  final formKey = GlobalKey<FormState>();
  final legalName = TextEditingController();
  final displayName = TextEditingController();
  final phone = TextEditingController();
  final gstin = TextEditingController();
  final line1 = TextEditingController();
  final line2 = TextEditingController();
  final city = TextEditingController();
  final state = TextEditingController();
  final pinCode = TextEditingController();
  SupplierGstRegistration gst = SupplierGstRegistration.unregistered;
  int step = 0;
  bool busy = false;
  String? error;
  final Map<SupplierEvidenceType, String> documentMediaIds = {};

  Future<void> _chooseDocument(SupplierEvidenceType type) async {
    final uploader = widget.uploadEvidence;
    if (busy || uploader == null) return;
    final result = await showModalBottomSheet<PrivateEvidenceSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PrivateEvidenceLinkSheet(
        upload: uploader,
        fixedType: type,
      ),
    );
    if (mounted && result != null && result.type == type) {
      setState(() {
        documentMediaIds[type] = result.mediaId;
        error = null;
      });
    }
  }

  @override
  void dispose() {
    for (final c in [
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

  SupplierRegistrationDraft _draft() {
    final fromDisplay =
        SupplierRegistrationDraft.slugFromName(displayName.text);
    return SupplierRegistrationDraft(
      slug: fromDisplay.isNotEmpty
          ? fromDisplay
          : SupplierRegistrationDraft.slugFromName(legalName.text),
      legalName: legalName.text,
      displayName: displayName.text,
      contactEmail: widget.email ?? '',
      contactPhone: SupplierRegistrationDraft.normalizePhone(phone.text),
      gstRegistration: gst,
      gstin: gstin.text,
      line1: line1.text,
      line2: line2.text,
      city: city.text,
      state: state.text,
      pinCode: pinCode.text,
    );
  }

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
      if (step == 0 &&
          SupplierRegistrationDraft.validateSlug(_draft().slug) != null) {
        setState(() => error = 'Use a business name with letters or numbers.');
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
      // First create exactly one application, then attach the private
      // documents already uploaded inside this form. Never retry creation
      // if an attachment fails after the application was accepted.
      var failedAttachments = 0;
      final attach = widget.attachEvidence;
      if (attach != null) {
        for (final item in documentMediaIds.entries) {
          try {
            await attach(result.id, item.value, item.key);
          } catch (_) {
            failedAttachments++;
          }
        }
      }
      if (!mounted) return;
      if (failedAttachments > 0) {
        widget.attachmentWarning?.call(
            'Your application was submitted, but some documents could '
            'not be attached. Open the document checklist and try again.');
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
                'Phone & GST',
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
                        helper: 'This is the name customers will see.',
                        validator: (v) =>
                            SupplierRegistrationDraft.validateRequired(
                                v, 'Display name')),
                  ],
                  if (step == 1) ...[
                    const Text('Your verified email',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(widget.email ?? 'A verified email is required',
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 16),
                    _Field(
                        label: 'Mobile number *',
                        controller: phone,
                        keyboard: TextInputType.phone,
                        helper: 'Enter your 10-digit mobile number. '
                            'We will add +91 automatically.',
                        maxLength: 16,
                        validator: SupplierRegistrationDraft.validatePhone),
                    const Text('Is your business registered for GST?',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<SupplierGstRegistration>(
                      initialValue: gst,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'GST status',
                        helperText: 'Choose No if you do not have a GST number.',
                      ),
                      items: SupplierGstRegistration.values
                          .map((value) => DropdownMenuItem(
                              value: value, child: Text(switch (value) {
                                SupplierGstRegistration.unregistered =>
                                  'No, not registered for GST',
                                SupplierGstRegistration.regular =>
                                  'Yes, registered for GST',
                                SupplierGstRegistration.composition =>
                                  'Yes, composition scheme',
                                SupplierGstRegistration.exempt =>
                                  'GST-exempt business',
                              })))
                          .toList(),
                      onChanged: busy
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() {
                                  gst = value;
                                  if (!value.needsGstin) gstin.clear();
                                });
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    if (gst.needsGstin)
                      _Field(
                          label: 'GSTIN (15 characters) *',
                          controller: gstin,
                          helper: 'Only needed for a GST-registered business.',
                          validator: (v) =>
                              SupplierRegistrationDraft.validateGstin(v, gst)),
                    const SizedBox(height: 4),
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
                    _ReviewValue('Verified email', widget.email ?? 'Unavailable'),
                    _ReviewValue('Mobile number',
                        SupplierRegistrationDraft.normalizePhone(phone.text)),
                    _ReviewValue('GST registration', gst.apiValue),
                    if (gst.needsGstin)
                      _ReviewValue('GSTIN', gstin.text.toUpperCase()),
                    _ReviewValue('Billing city & PIN',
                        '${city.text}, ${state.text} ${pinCode.text}'),
                    if (widget.uploadEvidence != null &&
                        widget.attachEvidence != null) ...[
                      const SizedBox(height: 12),
                      Text('Documents for approval',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      const Text(
                          'You can add your documents now instead of doing '
                          'another upload after submitting. Documents stay private.'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => _chooseDocument(
                                SupplierEvidenceType.businessRegistration),
                        icon: Icon(
                            documentMediaIds.containsKey(
                                    SupplierEvidenceType.businessRegistration)
                                ? Icons.check_circle_outline
                                : Icons.attach_file_outlined),
                        label: Text(documentMediaIds.containsKey(
                                SupplierEvidenceType.businessRegistration)
                            ? 'Business document added'
                            : 'Add business registration document'),
                      ),
                      if (gst.needsGstin) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => _chooseDocument(
                                  SupplierEvidenceType.gstCertificate),
                          icon: Icon(documentMediaIds.containsKey(
                                  SupplierEvidenceType.gstCertificate)
                              ? Icons.check_circle_outline
                              : Icons.attach_file_outlined),
                          label: Text(documentMediaIds.containsKey(
                                  SupplierEvidenceType.gstCertificate)
                              ? 'GST certificate added'
                              : 'Add GST certificate'),
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    const BuildToStatePanel(
                      title: 'Independent verification required',
                      icon: Icons.fact_check_outlined,
                      message:
                          'Submit once. Our team will review your business. '
                          'A business registration document, and only for GST-registered '
                          'suppliers a GST certificate, are needed for approval.',
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
      this.helper,
      this.maxLength = 250});
  final String label;
  final TextEditingController controller;
  final String? helper;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;
  final int maxLength;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
            key: ValueKey('supplier-registration-$label'),
            controller: controller,
            validator: validator,
            keyboardType: keyboard,
            maxLength: maxLength,
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
