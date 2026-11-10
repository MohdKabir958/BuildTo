import 'package:flutter/material.dart';
import '../api/supplier_v21_api.dart';
import '../auth/supplier_auth_controller.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import 'supplier_application_models.dart';
import 'supplier_applications_api.dart';
import 'supplier_registration_wizard.dart';
import 'supplier_evidence_link_sheet.dart';

/// Applicant-only registration and status workspace. Every server response is
/// checked against the current Clerk session by the S02 parent gate.
class SupplierOnboardingFlow extends StatefulWidget {
  const SupplierOnboardingFlow({
    super.key,
    required this.controller,
    required this.api,
    required this.onClose,
  });
  final SupplierAuthController controller;
  final SupplierApplicationsApi api;
  final VoidCallback onClose;
  @override
  State<SupplierOnboardingFlow> createState() => _SupplierOnboardingFlowState();
}

class _SupplierOnboardingFlowState extends State<SupplierOnboardingFlow> {
  List<SupplierApplicationSummary> applications = const [];
  SupplierApplicationDetail? details;
  bool loading = true, showWizard = false, linking = false;
  String? selectedId, error;
  int generation = 0;

  bool get sessionOk =>
      widget.controller.sessionKey != null &&
      (widget.controller.stage == SupplierAccessStage.authorized ||
          widget.controller.stage == SupplierAccessStage.noSupplier);

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  String errorMessage(Object e) {
    if (e is SupplierV21Exception) {
      return switch (e.problem) {
        SupplierV21Problem.authentication =>
          'Your Clerk session expired. Please sign in again.',
        SupplierV21Problem.forbidden =>
          'This account is not permitted to access that application.',
        SupplierV21Problem.conflict =>
          'The server rejected a duplicate or conflicting action. Refresh and review before retrying.',
        SupplierV21Problem.network =>
          'The request may have reached the server. Refresh to check the result before retrying.',
        _ => 'Could not load supplier applications. Please retry.',
      };
    }
    return 'The application response could not be verified. No approval or access is assumed.';
  }

  Future<void> load({String? openId}) async {
    final version = ++generation;
    final session = widget.controller.sessionKey;
    setState(() {
      loading = true;
      error = null;
      details = null;
      showWizard = false;
    });
    try {
      final records = await widget.api.list();
      final target = openId ?? selectedId;
      SupplierApplicationDetail? detail;
      if (target != null && records.any((record) => record.id == target)) {
        detail = await widget.api.detail(target);
      }
      if (!mounted ||
          version != generation ||
          !sessionOk ||
          session != widget.controller.sessionKey) {
        return;
      }
      setState(() {
        applications = records;
        details = detail;
        selectedId = detail?.summary.id;
        showWizard = records.isEmpty;
        loading = false;
      });
    } catch (e) {
      if (!mounted ||
          version != generation ||
          !sessionOk ||
          session != widget.controller.sessionKey) {
        return;
      }
      setState(() {
        error = errorMessage(e);
        loading = false;
      });
    }
  }

  Future<void> linkMedia(SupplierApplicationDetail current) async {
    if (linking || !sessionOk) return;
    final session = widget.controller.sessionKey;
    final selection = await showModalBottomSheet<PrivateEvidenceSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const PrivateEvidenceLinkSheet(),
    );
    if (!mounted ||
        !sessionOk ||
        session != widget.controller.sessionKey ||
        selection == null) {
      return;
    }
    setState(() {
      linking = true;
      error = null;
    });
    try {
      await widget.api.attachExistingEvidence(
        supplierId: current.summary.id,
        mediaId: selection.mediaId,
        type: selection.type,
      );
      if (!mounted || !sessionOk || session != widget.controller.sessionKey) {
        return;
      }
      await load(openId: current.summary.id);
    } catch (failure) {
      if (!mounted || !sessionOk || session != widget.controller.sessionKey) {
        return;
      }
      setState(() => error = errorMessage(failure));
    } finally {
      if (mounted) setState(() => linking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionOk) {
      return const Scaffold(
        body: SafeArea(
            child: Center(
                child: BuildToStatePanel(
          title: 'Secure account required',
          message:
              'Sign in with Clerk again before viewing your private applications.',
          icon: Icons.lock_outline_rounded,
        ))),
      );
    }
    final pending = applications.any((a) =>
        a.approval == SupplierApplicationStatus.pending ||
        a.approval == SupplierApplicationStatus.underReview);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supplier registration'),
        leading: IconButton(
            tooltip: 'Back',
            onPressed: widget.onClose,
            icon: const Icon(Icons.arrow_back_rounded)),
        actions: [
          IconButton(
              tooltip: 'Refresh applications',
              onPressed: loading ? null : () => load(),
              icon: const Icon(Icons.refresh_rounded))
        ],
      ),
      body: SafeArea(
          child: BuildToPageWidth(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
                        children: [
                          const BuildToSectionHeading(
                            title: 'Grow with BuildTo',
                            subtitle:
                                'Register your construction-material business and follow independent verification.',
                          ),
                          const SizedBox(height: 18),
                          _NavyBanner(email: widget.controller.signedInEmail),
                          const SizedBox(height: 22),
                          if (error != null) ...[
                            BuildToCard(
                                child: Row(children: [
                              const Icon(Icons.error_outline,
                                  color: BuildToPalette.danger),
                              const SizedBox(width: 10),
                              Expanded(child: Text(error!)),
                            ])),
                            const SizedBox(height: 14),
                          ],
                          if (showWizard)
                            SupplierRegistrationWizard(
                              email: widget.controller.signedInEmail,
                              cancel: () => setState(() => showWizard = false),
                              submit: widget.api.submit,
                              completed: (submitted) {
                                if (!mounted) return;
                                setState(() => selectedId = submitted.id);
                                load(openId: submitted.id);
                              },
                            )
                          else if (details != null) ...[
                            _ReviewDetail(
                                detail: details!,
                                onRefresh: () =>
                                    load(openId: details!.summary.id),
                                onRecheckAccess: widget.controller.refresh,
                                onLinkEvidence:
                                    linking ? null : () => linkMedia(details!)),
                            const SizedBox(height: 18),
                            OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    details = null;
                                    selectedId = null;
                                  });
                                },
                                icon: const Icon(Icons.list_alt_outlined),
                                label: const Text('All applications')),
                          ] else ...[
                            const BuildToSectionHeading(
                                title: 'Your applications'),
                            const SizedBox(height: 12),
                            if (applications.isEmpty)
                              const BuildToStatePanel(
                                  title: 'No application yet',
                                  message:
                                      'Start with your verified business and GST information. '
                                      'Only BuildTo operations can approve a supplier.',
                                  icon: Icons.storefront_outlined),
                            for (final app in applications) ...[
                              BuildToCard(
                                  child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.domain_rounded,
                                    color: BuildToPalette.navy),
                                title: Text(app.displayName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                subtitle: Text(app.approval.name
                                    .toUpperCase()
                                    .replaceAll('UNDERREVIEW', 'UNDER REVIEW')),
                                trailing:
                                    const Icon(Icons.chevron_right_rounded),
                                onTap: () => load(openId: app.id),
                              )),
                              const SizedBox(height: 10),
                            ],
                            const SizedBox(height: 20),
                            if (!pending)
                              BuildToPrimaryButton(
                                  label: 'Start supplier application',
                                  icon: Icons.add_business_rounded,
                                  onPressed: () =>
                                      setState(() => showWizard = true))
                            else
                              const BuildToCard(
                                  child: Text(
                                'An application is awaiting review. Open it to track progress. '
                                'The backend prevents another pending application for this owner.',
                              )),
                          ],
                        ],
                      )))),
    );
  }
}

class _NavyBanner extends StatelessWidget {
  const _NavyBanner({this.email});
  final String? email;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
                colors: [BuildToPalette.navyDeep, BuildToPalette.navy])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.verified_user_outlined, color: BuildToPalette.orange),
            SizedBox(width: 10),
            Expanded(
                child: Text('BUILDTO SUPPLIER',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2))),
          ]),
          const SizedBox(height: 12),
          const Text('Build your business with confidence.',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
              email == null || email!.isEmpty
                  ? 'A verified Clerk email is required.'
                  : 'Verified contact: ${email!}',
              style: const TextStyle(color: Color(0xFFE1EDFA), fontSize: 12)),
        ]),
      );
}

class _ReviewDetail extends StatelessWidget {
  const _ReviewDetail(
      {required this.detail,
      required this.onRefresh,
      required this.onRecheckAccess,
      required this.onLinkEvidence});
  final SupplierApplicationDetail detail;
  final VoidCallback onRefresh, onRecheckAccess;
  final VoidCallback? onLinkEvidence;
  @override
  Widget build(BuildContext context) {
    final application = detail.summary;
    final (statusLabel, statusStyle) = switch (application.approval) {
      SupplierApplicationStatus.draft => ('Draft', BuildToStatus.neutral),
      SupplierApplicationStatus.pending => (
          'Pending review',
          BuildToStatus.pending
        ),
      SupplierApplicationStatus.underReview => (
          'Under review',
          BuildToStatus.warning
        ),
      SupplierApplicationStatus.approved => ('Approved', BuildToStatus.success),
      SupplierApplicationStatus.rejected => ('Rejected', BuildToStatus.danger),
      SupplierApplicationStatus.suspended => (
          'Suspended',
          BuildToStatus.danger
        ),
    };
    final canLink = [
      SupplierApplicationStatus.pending,
      SupplierApplicationStatus.underReview,
      SupplierApplicationStatus.rejected,
    ].contains(application.approval);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BuildToCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const BuildToSectionHeading(title: 'Application progress'),
        const SizedBox(height: 14),
        Text(application.displayName,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10),
        BuildToStatusChip(label: statusLabel, status: statusStyle),
        const SizedBox(height: 16),
        const _StepStatus(
            'Application received', 'Your registration was submitted.', true),
        _StepStatus(
            'Business evidence review',
            'BuildTo verifies your documents.',
            application.approval == SupplierApplicationStatus.underReview ||
                application.approval == SupplierApplicationStatus.approved),
        _StepStatus(
            'Independent approval',
            'Only an approved supplier receives business access.',
            application.approval == SupplierApplicationStatus.approved),
        const SizedBox(height: 10),
        if (application.approval == SupplierApplicationStatus.approved)
          BuildToPrimaryButton(
              label: 'Verify active supplier access',
              onPressed: onRecheckAccess,
              icon: Icons.shield_outlined)
        else
          OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh review status')),
      ])),
      const SizedBox(height: 22),
      const BuildToSectionHeading(
        title: 'Document checklist',
        subtitle:
            'Actual reviewer decisions. Private media object keys are never displayed.',
      ),
      const SizedBox(height: 12),
      _EvidenceCard(
          type: SupplierEvidenceType.businessRegistration,
          documents: detail.documents),
      if (application.gstRegistration.needsGstin) ...[
        const SizedBox(height: 10),
        _EvidenceCard(
            type: SupplierEvidenceType.gstCertificate,
            documents: detail.documents),
      ],
      const SizedBox(height: 14),
      const BuildToCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.lock_outline_rounded, color: BuildToPalette.navy),
        SizedBox(width: 12),
        Expanded(
            child: Text('V2.1 does not provide raw private file uploads. '
                'Only an account-owned, already-provisioned private asset can be linked. '
                'Never use public KYC links.')),
      ])),
      if (canLink) ...[
        const SizedBox(height: 14),
        OutlinedButton.icon(
            onPressed: onLinkEvidence,
            icon: const Icon(Icons.attach_file_rounded),
            label: const Text('Link pre-provisioned private evidence')),
      ],
    ]);
  }
}

class _StepStatus extends StatelessWidget {
  const _StepStatus(this.title, this.note, this.complete);
  final String title, note;
  final bool complete;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
              complete
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              color: complete ? BuildToPalette.success : BuildToPalette.muted),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(note, style: Theme.of(context).textTheme.bodySmall),
              ])),
        ]),
      );
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.type, required this.documents});
  final SupplierEvidenceType type;
  final List<SupplierEvidenceReview> documents;
  @override
  Widget build(BuildContext context) {
    final matching = documents.where((d) => d.type == type).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final last = matching.isEmpty ? null : matching.first;
    final (label, status) = switch (last?.status) {
      SupplierEvidenceStatus.verified => ('Verified', BuildToStatus.success),
      SupplierEvidenceStatus.rejected => ('Rejected', BuildToStatus.danger),
      SupplierEvidenceStatus.expired => ('Expired', BuildToStatus.danger),
      SupplierEvidenceStatus.uploaded => ('Received', BuildToStatus.pending),
      SupplierEvidenceStatus.pending => ('Pending', BuildToStatus.pending),
      SupplierEvidenceStatus.reviewed => ('Reviewed', BuildToStatus.pending),
      null => ('Not attached', BuildToStatus.neutral),
    };
    return BuildToCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.description_outlined, color: BuildToPalette.navy),
        const SizedBox(width: 10),
        Expanded(
            child: Text(type.title,
                style: Theme.of(context).textTheme.titleMedium)),
      ]),
      const SizedBox(height: 10),
      BuildToStatusChip(label: label, status: status),
      if (last?.reviewNote?.trim().isNotEmpty == true) ...[
        const SizedBox(height: 10),
        Text('Reviewer feedback: ${last!.reviewNote!}',
            style: Theme.of(context).textTheme.bodyMedium),
      ],
    ]));
  }
}
