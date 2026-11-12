import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../api/supplier_v21_api.dart';
import '../design/buildto_components.dart';
import 'supplier_application_models.dart';

typedef PrivateEvidenceSelection = ({
  String mediaId,
  SupplierEvidenceType type
});
typedef EvidenceUpload = Future<String> Function(
    Uint8List bytes, String mimeType);

class PrivateEvidenceLinkSheet extends StatefulWidget {
  const PrivateEvidenceLinkSheet(
      {super.key, required this.upload, this.pickFile});
  final EvidenceUpload upload;
  final Future<XFile?> Function()? pickFile;
  @override
  State<PrivateEvidenceLinkSheet> createState() =>
      _PrivateEvidenceLinkSheetState();
}

class _PrivateEvidenceLinkSheetState extends State<PrivateEvidenceLinkSheet> {
  SupplierEvidenceType type = SupplierEvidenceType.businessRegistration;
  XFile? file;
  bool busy = false;
  String? error;

  Future<void> choose() async {
    try {
      final selected = await (widget.pickFile?.call() ??
          openFile(acceptedTypeGroups: [
            const XTypeGroup(label: 'Verification documents', extensions: [
              'pdf',
              'jpg',
              'jpeg',
              'png'
            ], mimeTypes: [
              'application/pdf',
              'image/jpeg',
              'image/png'
            ], uniformTypeIdentifiers: [
              'com.adobe.pdf',
              'public.jpeg',
              'public.png'
            ]),
          ]));
      if (!mounted || selected == null) return;
      final length = await selected.length();
      if (!mounted) return;
      if (length == 0 || length > 10 * 1024 * 1024) {
        setState(() => error = 'Choose a file up to 10 MB.');
        return;
      }
      setState(() {
        file = selected;
        error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not open the file picker. Try again.');
      }
    }
  }

  Future<void> confirm() async {
    final selected = file;
    if (busy || selected == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final extension = selected.name.split('.').last.toLowerCase();
      final mime = switch (extension) {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        _ => throw const FormatException(),
      };
      final id = await widget.upload(await selected.readAsBytes(), mime);
      if (mounted) {
        Navigator.of(context)
            .pop<PrivateEvidenceSelection>((mediaId: id, type: type));
      }
    } on SupplierV21Exception catch (failure) {
      if (mounted) {
        setState(() => error = switch (failure.problem) {
              SupplierV21Problem.authentication =>
                'Your session expired. Sign in again.',
              SupplierV21Problem.network =>
                'Upload was interrupted. Check your connection and retry.',
              SupplierV21Problem.rateLimited =>
                'Upload limit reached. Please try later.',
              _ =>
                'Could not upload this document. Please retry or contact support.',
            });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Choose a valid PDF, JPEG or PNG up to 10 MB.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !busy,
        child: SafeArea(
            child: Padding(
          padding: EdgeInsets.fromLTRB(
              24, 12, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
          child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                const BuildToSectionHeading(
                    title: 'Upload verification document',
                    subtitle: 'Private PDF, JPEG or PNG • Up to 10 MB'),
                const SizedBox(height: 20),
                DropdownButtonFormField<SupplierEvidenceType>(
                  initialValue: type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Document type'),
                  items: SupplierEvidenceType.values
                      .map((value) => DropdownMenuItem(
                          value: value, child: Text(value.title, maxLines: 2)))
                      .toList(),
                  onChanged: busy
                      ? null
                      : (value) {
                          if (value != null) setState(() => type = value);
                        },
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                    onPressed: busy ? null : choose,
                    icon: const Icon(Icons.attach_file_rounded),
                    label: Text(
                        file == null ? 'Choose document' : 'Change document')),
                if (file != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(file!.name,
                          maxLines: 3, overflow: TextOverflow.ellipsis)),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Semantics(
                          liveRegion: true,
                          child: Text(error!,
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.error)))),
                const SizedBox(height: 16),
                BuildToPrimaryButton(
                    label: 'Upload document',
                    icon: Icons.cloud_upload_outlined,
                    busy: busy,
                    onPressed: file == null ? null : confirm),
                const SizedBox(height: 12),
                const Text(
                    'Only your account and authorized reviewers can access this file. Uploading does not approve your business.'),
              ])),
        )),
      );
}
