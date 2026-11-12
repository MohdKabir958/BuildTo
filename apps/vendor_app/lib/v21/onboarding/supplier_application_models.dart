/// Applicant-owned onboarding types. Unknown server status is never treated
/// as approved; all required fields must be present and validated.
enum SupplierApplicationStatus {
  draft,
  pending,
  underReview,
  approved,
  rejected,
  suspended;

  static SupplierApplicationStatus parse(Object? value) => switch (value) {
        'DRAFT' => draft,
        'PENDING' => pending,
        'UNDER_REVIEW' => underReview,
        'APPROVED' => approved,
        'REJECTED' => rejected,
        'SUSPENDED' => suspended,
        _ => throw const FormatException('Unknown supplier application status'),
      };

  bool get businessAccessCandidate => this == approved;
}

enum SupplierGstRegistration {
  regular,
  composition,
  unregistered,
  exempt;

  String get apiValue => name.toUpperCase();
  bool get needsGstin =>
      this == SupplierGstRegistration.regular ||
      this == SupplierGstRegistration.composition;

  static SupplierGstRegistration parse(Object? value) => switch (value) {
        'REGULAR' => regular,
        'COMPOSITION' => composition,
        'UNREGISTERED' => unregistered,
        'EXEMPT' => exempt,
        _ => throw const FormatException('Unknown GST registration'),
      };
}

enum SupplierEvidenceType {
  businessRegistration,
  gstCertificate;

  String get apiValue => switch (this) {
        businessRegistration => 'BUSINESS_REGISTRATION',
        gstCertificate => 'GST_CERTIFICATE',
      };

  String get title => switch (this) {
        businessRegistration => 'Business registration certificate',
        gstCertificate => 'GST registration certificate',
      };

  static SupplierEvidenceType parse(Object? value) => switch (value) {
        'BUSINESS_REGISTRATION' => businessRegistration,
        'GST_CERTIFICATE' => gstCertificate,
        _ => throw const FormatException('Unknown evidence type'),
      };
}

enum SupplierEvidenceStatus {
  uploaded,
  pending,
  reviewed,
  verified,
  rejected,
  expired;

  static SupplierEvidenceStatus parse(Object? value) => switch (value) {
        'UPLOADED' => uploaded,
        'PENDING' => pending,
        'REVIEWED' => reviewed,
        'VERIFIED' => verified,
        'REJECTED' => rejected,
        'EXPIRED' => expired,
        _ => throw const FormatException('Unknown evidence review status'),
      };
}

class SupplierApplicationSummary {
  const SupplierApplicationSummary({
    required this.id,
    required this.slug,
    required this.legalName,
    required this.displayName,
    required this.approval,
    required this.gstRegistration,
    required this.createdAt,
    this.gstin,
    this.verifiedAt,
    this.suspendedAt,
  });

  final String id, slug, legalName, displayName;
  final SupplierApplicationStatus approval;
  final SupplierGstRegistration gstRegistration;
  final DateTime createdAt;
  final String? gstin;
  final DateTime? verifiedAt, suspendedAt;

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
  );

  factory SupplierApplicationSummary.fromJson(Object? source) {
    if (source is! Map<String, dynamic>) {
      throw const FormatException('Supplier application is not an object');
    }
    final id = source['id'];
    final slug = source['slug'];
    final legalName = source['legalName'];
    final displayName = source['displayName'];
    final createdAt = DateTime.tryParse(
        source['createdAt'] is String ? source['createdAt'] as String : '');
    if (id is! String ||
        !_uuid.hasMatch(id) ||
        slug is! String ||
        slug.isEmpty ||
        legalName is! String ||
        legalName.isEmpty ||
        displayName is! String ||
        displayName.isEmpty ||
        createdAt == null ||
        (source['gstin'] != null && source['gstin'] is! String)) {
      throw const FormatException('Malformed supplier application response');
    }
    DateTime? optionalDate(String key) {
      final value = source[key];
      if (value == null) return null;
      if (value is! String) {
        throw const FormatException('Malformed review date');
      }
      return DateTime.tryParse(value) ??
          (throw const FormatException('Invalid review timestamp'));
    }

    return SupplierApplicationSummary(
      id: id,
      slug: slug,
      legalName: legalName,
      displayName: displayName,
      approval: SupplierApplicationStatus.parse(source['approval']),
      gstRegistration: SupplierGstRegistration.parse(source['gstRegistration']),
      gstin: source['gstin'] as String?,
      createdAt: createdAt,
      verifiedAt: optionalDate('verifiedAt'),
      suspendedAt: optionalDate('suspendedAt'),
    );
  }
}

class SupplierEvidenceReview {
  const SupplierEvidenceReview({
    required this.id,
    required this.type,
    required this.status,
    required this.createdAt,
    this.reviewNote,
  });

  final String id;
  final SupplierEvidenceType type;
  final SupplierEvidenceStatus status;
  final DateTime createdAt;
  final String? reviewNote;

  factory SupplierEvidenceReview.fromJson(Object? source) {
    if (source is! Map<String, dynamic>) {
      throw const FormatException('Evidence is not an object');
    }
    final id = source['id'];
    final created = DateTime.tryParse(
        source['createdAt'] is String ? source['createdAt'] as String : '');
    if (id is! String ||
        !SupplierApplicationSummary._uuid.hasMatch(id) ||
        created == null ||
        (source['reviewNote'] != null && source['reviewNote'] is! String)) {
      throw const FormatException('Invalid evidence review record');
    }
    return SupplierEvidenceReview(
      id: id,
      type: SupplierEvidenceType.parse(source['documentType']),
      status: SupplierEvidenceStatus.parse(source['status']),
      createdAt: created,
      reviewNote: source['reviewNote'] as String?,
    );
  }
}

class SupplierApplicationDetail {
  const SupplierApplicationDetail(this.summary, this.documents);
  final SupplierApplicationSummary summary;
  final List<SupplierEvidenceReview> documents;

  factory SupplierApplicationDetail.fromJson(Object? source) {
    if (source is! Map<String, dynamic>) {
      throw const FormatException('Invalid application detail');
    }
    final docs = source['documents'];
    if (docs is! List<dynamic> || docs.length > 100) {
      throw const FormatException('Invalid supplier evidence records');
    }
    return SupplierApplicationDetail(
      SupplierApplicationSummary.fromJson(source),
      List.unmodifiable(docs.map(SupplierEvidenceReview.fromJson)),
    );
  }
}

/// Exact server-supported fields. Verified contact email MUST equal the
/// synced Clerk user email; backend independently checks it before creating.
class SupplierRegistrationDraft {
  const SupplierRegistrationDraft({
    required this.slug,
    required this.legalName,
    required this.displayName,
    required this.contactEmail,
    required this.gstRegistration,
    required this.line1,
    required this.city,
    required this.state,
    required this.pinCode,
    this.line2,
    this.contactPhone,
    this.gstin,
  });

  final String slug, legalName, displayName, contactEmail;
  final String? contactPhone, gstin, line2;
  final SupplierGstRegistration gstRegistration;
  final String line1, city, state, pinCode;

  static String? validateSlug(String? value) {
    final slug = (value ?? '').trim().toLowerCase();
    return slug.length < 3 ||
            slug.length > 100 ||
            !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(slug)
        ? 'Use 3–100 lowercase letters, numbers and hyphens.'
        : null;
  }

  /// Builds the private business id from a name the supplier already typed.
  static String slugFromName(String? value) {
    var slug = (value ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.length > 100) {
      slug = slug.substring(0, 100).replaceAll(RegExp(r'-+$'), '');
    }
    return validateSlug(slug) == null ? slug : '';
  }

  static String? validateRequired(String? value, String label,
      {int min = 3, int max = 200}) {
    final text = (value ?? '').trim();
    return text.length < min ||
            text.length > max ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)
        ? '$label needs $min–$max characters.'
        : null;
  }

  static String? validatePhone(String? value) {
    final phone = (value ?? '').trim();
    return phone.isNotEmpty && !RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)
        ? 'Use international E.164 format, e.g. +919876543210.'
        : null;
  }

  static String? validatePinCode(String? value) =>
      RegExp(r'^[1-9]\d{5}$').hasMatch((value ?? '').trim())
          ? null
          : 'Enter a valid six-digit Indian PIN code.';

  static String? validateGstin(String? value, SupplierGstRegistration status) {
    final gstin = (value ?? '').trim().toUpperCase();
    if (!status.needsGstin) {
      return gstin.isNotEmpty
          ? 'GSTIN is not allowed for unregistered or exempt businesses.'
          : null;
    }
    return RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$')
            .hasMatch(gstin)
        ? null
        : 'Enter a valid 15-character GSTIN.';
  }

  Map<String, Object?> toJson() => {
        'slug': slug.trim().toLowerCase(),
        'legalName': legalName.trim(),
        'displayName': displayName.trim(),
        'contactEmail': contactEmail.trim().toLowerCase(),
        if (contactPhone?.trim().isNotEmpty ?? false)
          'contactPhone': contactPhone!.trim(),
        'gstRegistration': gstRegistration.apiValue,
        if (gstin?.trim().isNotEmpty ?? false)
          'gstin': gstin!.trim().toUpperCase(),
        'billingAddress': <String, String>{
          'line1': line1.trim(),
          if (line2?.trim().isNotEmpty ?? false) 'line2': line2!.trim(),
          'city': city.trim(),
          'state': state.trim(),
          'pinCode': pinCode.trim(),
        },
      };
}
