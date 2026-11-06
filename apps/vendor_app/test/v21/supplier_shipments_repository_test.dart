import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/v21/api/supplier_v21_api.dart';
import 'package:vendor_app/v21/dashboard/supplier_dashboard_models.dart';
import 'package:vendor_app/v21/orders/supplier_orders_repository.dart';
import 'package:vendor_app/v21/shipments/supplier_shipments_repository.dart';

const supplier = '123e4567-e89b-42d3-a456-426614174000';
const orderId = '123e4567-e89b-42d3-a456-426614174001';
const purchaseId = '123e4567-e89b-42d3-a456-426614174002';
const lineId = '123e4567-e89b-42d3-a456-426614174003';
const warehouseId = '123e4567-e89b-42d3-a456-426614174004';
const shipmentId = '123e4567-e89b-42d3-a456-426614174005';
const shipmentLineId = '123e4567-e89b-42d3-a456-426614174006';

Map<String, Object?> orderDto() => {
  'id': orderId, 'purchaseOrderId': purchaseId, 'status': 'CONFIRMED',
  'createdAt': '2026-11-06T04:00:00.000Z', 'totalPaise': '100000',
  'items': [{'id':lineId,'sku':'BAG-CEMENT',
    'quantity':'40.000','unitCode':'BAG'}],
};

Map<String, Object?> shipmentDto({String status = 'PLANNED'}) => {
  'id':shipmentId, 'shipmentNumber':'SH-1001', 'supplierOrderId':orderId,
  'supplierId':supplier, 'warehouseId':warehouseId, 'status':status,
  'carrierName':null,'trackingReference':null,
  'handoverVerified':status == 'DELIVERED',
  'createdAt':'2026-11-06T04:10:00.000Z',
  'deliveredAt':status == 'DELIVERED'?'2026-11-06T07:10:00.000Z':null,
  'items':[{'id':shipmentLineId,'orderItemId':lineId,'quantity':'40.000',
    'deliveredQty':status == 'DELIVERED'?'40.000':'0',
    'rejectedQty':'0'}],
  'events':<Object>[],
};
http.Response ok(Object? data,{int status=200}) =>
    http.Response(jsonEncode({'data':data}), status);

SupplierShipmentsRepository repo(http.Client transport) =>
  SupplierShipmentsRepository(SupplierV21Api(
    origin:Uri.parse('https://buildto-v21-staging.onrender.com'),
    token:() async=>'clerk-session',httpClient:transport,
  ));

void main(){
  test('read scoped shipment and exact quantities', () async {
    final service = repo(MockClient((req) async {
      expect(req.url.path,
        '/api/v2/suppliers/$supplier/orders/$orderId/shipments');
      return ok([shipmentDto()]);
    }));
    final rows=await service.list(supplier,orderId);
    expect(rows.single.status,SupplierShipmentStatus.planned);
    expect(rows.single.items.single.quantity,'40.000');
    expect(() => SupplierShipment.parse({
       ...shipmentDto(),'supplierId':purchaseId,
    },supplierId:supplier,orderId:orderId),throwsFormatException);
  });

  test('plan shipment uses stable idempotency and warehouse item allocation',
      () async {
    final order=SupplierOrder.parse(orderDto());
    final service=repo(MockClient((req) async {
      expect(req.method,'POST');
      expect(req.headers['Idempotency-Key'],'shipment-intent-42');
      final body=jsonDecode(req.body) as Map<String,dynamic>;
      expect(body['warehouseId'],warehouseId);
      expect(body['lines'],[{'orderItemId':lineId,'quantity':'12.500'}]);
      return ok({...shipmentDto(),'items':[{
        'id':shipmentLineId,'orderItemId':lineId,'quantity':'12.500',
        'deliveredQty':'0','rejectedQty':'0'
      }]},status:201);
    }));
    final created=await service.plan(
      supplierId:supplier,order:order,warehouseId:warehouseId,
      lines:[const SupplierShipmentPlanLine(lineId,'12.500')],
      intent:'shipment-intent-42',
    );
    expect(created.status,SupplierShipmentStatus.planned);
  });

  test('progress only permits next server state',() async {
    final shipment=SupplierShipment.parse(shipmentDto(),
      supplierId:supplier,orderId:orderId);
    final service=repo(MockClient((req) async {
      expect(req.url.path.endsWith('/pack'),isTrue);
      return ok({'id':shipmentId,'status':'PACKED','replayed':false});
    }));
    final done=await service.progress(
      supplierId:supplier,shipment:shipment,stage:'pack');
    expect(done.status,SupplierShipmentStatus.packed);
    await expectLater(service.progress(supplierId:supplier,shipment:shipment,
        stage:'dispatch'),throwsStateError);
  });

  test('customer-issued OTP only; wrong code never treated as delivery',() async {
    final shipment=SupplierShipment.parse(
      shipmentDto(status:'OUT_FOR_DELIVERY'),
      supplierId:supplier,orderId:orderId);
    final service=repo(MockClient((req) async {
      expect(req.url.path.endsWith('/handover'),isTrue);
      final body=jsonDecode(req.body) as Map<String,dynamic>;
      expect(body['method'],'OTP');
      expect(body['otp'],'123456');
      return http.Response('{"error":{"code":"OTP_INCORRECT"}}',422);
    }));
    await expectLater(service.verifyCustomerOtp(
      supplierId:supplier,shipment:shipment,otp:'123456',
    ),throwsA(isA<SupplierV21Exception>().having(
      (e)=>e.problem,'problem',SupplierV21Problem.validation)));
    await expectLater(service.verifyCustomerOtp(
      supplierId:supplier,shipment:shipment,otp:'12345',
    ),throwsFormatException);
  });

  test('invalid shipment quantity cannot exceed order line',() async {
    final service=repo(MockClient((req) async => ok(shipmentDto(),status:201)));
    await expectLater(service.plan(
      supplierId:supplier,order:SupplierOrder.parse(orderDto()),
      warehouseId:warehouseId,
      lines:[const SupplierShipmentPlanLine(lineId,'40.001')],
      intent:'some-idempotency',
    ),throwsFormatException);
  });
}
