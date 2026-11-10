import 'package:flutter/material.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import 'supplier_application_models.dart';

typedef PrivateEvidenceSelection = ({
  String mediaId,
  SupplierEvidenceType type
});

/// Reference-only dialog for the existing private MediaAsset contract.
/// This widget deliberately has no photo picker, public URL or binary upload.
class PrivateEvidenceLinkSheet extends StatefulWidget {
  const PrivateEvidenceLinkSheet({super.key});

  @override
  State<PrivateEvidenceLinkSheet> createState() =>
      _PrivateEvidenceLinkSheetState();
}

class _PrivateEvidenceLinkSheetState extends State<PrivateEvidenceLinkSheet> {
  final keyForm = GlobalKey<FormState>();
  final reference = TextEditingController();
  SupplierEvidenceType type = SupplierEvidenceType.businessRegistration;

  @override
  void dispose() {
    reference.dispose();
    super.dispose();
  }

  void confirm() {
    if (keyForm.currentState?.validate() != true) {
      return;
    }
    Navigator.of(context).pop<PrivateEvidenceSelection>(
      (mediaId: reference.text.trim(), type: type),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
              child: Form(
            key: keyForm,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BuildToSectionHeading(
                  title: 'Link verified evidence',
                  subtitle: 'Private reference only — not a public upload.',
                ),
                const SizedBox(height: 14),
                const BuildToCard(
                    child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        color: BuildToPalette.navy),
                    SizedBox(width: 12),
                    Expanded(
                        child: Text(
                      'Your file must already exist as a private, SHA256-verified '
                      'MediaAsset owned by your Clerk account. Request the reference '
                      'through the approved Splyzo operations process.',
                    )),
                  ],
                )),
                const SizedBox(height: 18),
                DropdownButtonFormField<SupplierEvidenceType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Document type'),
                  items: SupplierEvidenceType.values
                      .map((value) => DropdownMenuItem(
                          value: value, child: Text(value.title)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => type = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: reference,
                  autocorrect: false,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    labelText: 'Private media reference',
                    helperText: 'Only a securely provisioned UUID. No URLs.',
                  ),
                  validator: (value) {
                    if (!RegExp(
                            r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
                        .hasMatch((value ?? '').trim())) {
                      return 'Enter the UUID issued by private evidence provisioning.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                BuildToPrimaryButton(
                  label: 'Link private document',
                  icon: Icons.attach_file_rounded,
                  onPressed: confirm,
                ),
              ],
            ),
          )),
        ),
      );
}
