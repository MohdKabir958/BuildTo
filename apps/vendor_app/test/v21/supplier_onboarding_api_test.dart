import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/v21/api/supplier_v21_api.dart';
import 'package:vendor_app/v21/onboarding/supplier_application_models.dart';
import 'package:vendor_app/v21/onboarding/supplier_applications_api.dart';

const supplier = '123e4567-e89b-12d3-a456-426614174000';
const evidence = '123e4567-e89b-12d3-a456-426614174001';

Map<String, Object?> application({String status = 'PENDING'}) => {
      'id': supplier,
      'slug': 'builder-materials',
      'legalName': 'Builder Materials Pvt Ltd',
      'displayName': 'Builder Materials',
      'approval': status,
      'gstRegistration': 'UNREGISTERED',
      'gstin': null,
      'verifiedAt': null,
      'suspendedAt': null,
      'createdAt': '2026-11-05T08:00:00.000Z',
    };

SupplierApplicationsApi api(http.Client client) =>
    SupplierApplicationsApi(SupplierV21Api(
        origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
        token: () async => 'test-only-clerk-session',
        httpClient: client));

void main() {
  test('server approval and document states are strictly parsed', () {
    expect(SupplierApplicationSummary.fromJson(application()).approval,
        SupplierApplicationStatus.pending);
    expect(
        () =>
            SupplierApplicationSummary.fromJson(application(status: 'UNKNOWN')),
        throwsFormatException);
    expect(
        () => SupplierApplicationSummary.fromJson(
            {...application(), 'id': 'not-a-uuid'}),
        throwsFormatException);
    expect(
        SupplierApplicationDetail.fromJson({
          ...application(),
          'documents': [
            {
              'id': evidence,
              'documentType': 'BUSINESS_REGISTRATION',
              'status': 'VERIFIED',
              'reviewNote': 'Checked by operations',
              'createdAt': '2026-11-05T08:15:00Z',
            }
          ],
        }).documents.single.status,
        SupplierEvidenceStatus.verified);
    expect(
        () => SupplierApplicationDetail.fromJson({
              ...application(),
              'documents': [
                {
                  'id': evidence,
                  'documentType': 'BUSINESS_REGISTRATION',
                  'status': 'GUESSED_APPROVED',
                  'createdAt': '2026-11-05T08:15:00Z',
                }
              ],
            }),
        throwsFormatException);
  });

  test('GST, slug, phone, address and PIN validation match backend shape', () {
    expect(
        SupplierRegistrationDraft.validateSlug('builders-materials'), isNull);
    expect(
        SupplierRegistrationDraft.validateSlug('Builder Materials'), isNotNull);
    expect(SupplierRegistrationDraft.validatePhone('+919876543210'), isNull);
    expect(SupplierRegistrationDraft.validatePhone('9876543210'), isNotNull);
    expect(SupplierRegistrationDraft.validatePinCode('500001'), isNull);
    expect(SupplierRegistrationDraft.validatePinCode('050001'), isNotNull);
    expect(
        SupplierRegistrationDraft.validateGstin(
            '', SupplierGstRegistration.regular),
        isNotNull);
    expect(
        SupplierRegistrationDraft.validateGstin(
            '', SupplierGstRegistration.unregistered),
        isNull);
    expect(
        SupplierRegistrationDraft.validateGstin(
            '36ABCDE1234F1Z5', SupplierGstRegistration.regular),
        isNull);
  });

  test('new supplier application sends exact registered contact and fields',
      () async {
    var postCount = 0;
    final provider = api(MockClient((request) async {
      expect(request.url.path, '/api/v2/supplier-applications');
      expect(request.method, 'POST');
      expect(
          request.headers['Authorization'], 'Bearer test-only-clerk-session');
      postCount++;
      final data = jsonDecode(request.body) as Map<String, dynamic>;
      expect(data['contactEmail'], 'applicant@example.com');
      expect(data['gstRegistration'], 'UNREGISTERED');
      expect(data['gstin'], isNull);
      expect(data['billingAddress']['pinCode'], '500001');
      return http.Response(
          jsonEncode({'data': application(), 'requestId': 'req-1'}), 201);
    }));
    final result = await provider.submit(const SupplierRegistrationDraft(
        slug: 'builder-materials',
        legalName: 'Builder Materials Pvt Ltd',
        displayName: 'Builder Materials',
        contactEmail: 'APPLICANT@EXAMPLE.COM',
        gstRegistration: SupplierGstRegistration.unregistered,
        line1: 'Industrial Estate Road',
        city: 'Hyderabad',
        state: 'Telangana',
        pinCode: '500001'));
    expect(result.approval, SupplierApplicationStatus.pending);
    expect(postCount, 1);
  });

  test('list and owned detail reject malformed or foreign supplier responses',
      () async {
    final provider = api(MockClient((request) async {
      if (request.url.path == '/api/v2/me/supplier-applications') {
        return http.Response(
            jsonEncode({
              'data': [application()]
            }),
            200);
      }
      return http.Response(
          jsonEncode({
            'data': {
              ...application(),
              'id': evidence,
              'documents': [],
            }
          }),
          200);
    }));
    expect((await provider.list()).single.id, supplier);
    await expectLater(provider.detail(supplier), throwsFormatException);
    await expectLater(provider.detail('not-uuid'), throwsFormatException);
  });

  test(
      'already-provisioned private media attachment uses only ID, not file URLs',
      () async {
    final provider = api(MockClient((request) async {
      expect(request.url.path,
          '/api/v2/supplier-applications/$supplier/documents');
      expect(request.method, 'POST');
      expect(jsonDecode(request.body), {
        'mediaId': evidence,
        'documentType': 'BUSINESS_REGISTRATION',
      });
      return http.Response(
          jsonEncode({
            'data': {
              'id': evidence,
              'documentType': 'BUSINESS_REGISTRATION',
              'status': 'UPLOADED',
              'createdAt': '2026-11-05T09:00:00.000Z',
            }
          }),
          201);
    }));
    final record = await provider.attachExistingEvidence(
        supplierId: supplier,
        mediaId: evidence,
        type: SupplierEvidenceType.businessRegistration);
    expect(record.status, SupplierEvidenceStatus.uploaded);
    await expectLater(
        provider.attachExistingEvidence(
            supplierId: supplier,
            mediaId: 'https://public.example/file.jpg',
            type: SupplierEvidenceType.businessRegistration),
        throwsFormatException);
  });

  test('backend conflict never becomes a false submitted success', () async {
    final provider = api(MockClient((request) async =>
        http.Response('{"error":{"code":"APPLICATION_ALREADY_OPEN"}}', 409)));
    await expectLater(
        provider.submit(const SupplierRegistrationDraft(
            slug: 'builder-materials',
            legalName: 'Builder Materials Pvt Ltd',
            displayName: 'Builder Materials',
            contactEmail: 'applicant@example.com',
            gstRegistration: SupplierGstRegistration.unregistered,
            line1: 'Industrial Estate Road',
            city: 'Hyderabad',
            state: 'Telangana',
            pinCode: '500001')),
        throwsA(isA<SupplierV21Exception>().having(
            (error) => error.problem, 'problem', SupplierV21Problem.conflict)));
  });
}
