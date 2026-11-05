import '../api/supplier_v21_api.dart';
import 'supplier_application_models.dart';

/// Client for existing owner-only application APIs plus the S03 read-only
/// applicant detail route. All requests use the S02 native Clerk token.
class SupplierApplicationsApi {
  const SupplierApplicationsApi(this.client);
  final SupplierV21Api client;

  static final RegExp _uuid =
      RegExp(r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$');

  Future<List<SupplierApplicationSummary>> list() async {
    final response = await client.get('/api/v2/me/supplier-applications');
    final value = response.data;
    if (value is! List<dynamic> || value.length > 50) {
      throw const FormatException('Invalid supplier application list');
    }
    return List.unmodifiable(value.map(SupplierApplicationSummary.fromJson));
  }

  Future<SupplierApplicationDetail> detail(String supplierId) async {
    if (!_uuid.hasMatch(supplierId)) {
      throw const FormatException('Invalid supplier application ID');
    }
    final response = await client.get(
      '/api/v2/me/supplier-applications/$supplierId',
    );
    final result = SupplierApplicationDetail.fromJson(response.requireObject());
    if (result.summary.id != supplierId) {
      throw const FormatException('Supplier response scope mismatch');
    }
    return result;
  }

  Future<SupplierApplicationSummary> submit(SupplierRegistrationDraft draft) async {
    final response = await client.request(
      'POST',
      '/api/v2/supplier-applications',
      body: draft.toJson(),
    );
    final result = SupplierApplicationSummary.fromJson(response.requireObject());
    // Never trust a client side success message if the backend did not create
    // the expected pending application.
    if (result.approval != SupplierApplicationStatus.pending) {
      throw const FormatException('Unexpected supplier application transition');
    }
    return result;
  }

  /// This links a *previously provisioned*, privately owned media record.
  /// It does not upload a file, create a MediaAsset or expose the media key.
  Future<SupplierEvidenceReview> attachExistingEvidence({
    required String supplierId,
    required String mediaId,
    required SupplierEvidenceType type,
  }) async {
    if (!_uuid.hasMatch(supplierId) || !_uuid.hasMatch(mediaId)) {
      throw const FormatException('Invalid private evidence reference');
    }
    final response = await client.request(
      'POST',
      '/api/v2/supplier-applications/$supplierId/documents',
      body: {'mediaId': mediaId, 'documentType': type.apiValue},
    );
    return SupplierEvidenceReview.fromJson(response.requireObject());
  }
}
