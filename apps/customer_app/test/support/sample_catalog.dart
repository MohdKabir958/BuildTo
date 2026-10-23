// ignore_for_file: prefer_const_constructors
// Construction catalog for Buildto tests and preview.
import 'package:customer_app/models/dhaba.dart';
import 'package:customer_app/models/menu_item.dart';
import 'package:customer_app/models/sample_construction_data.dart';
import 'package:customer_app/providers/dhaba_provider.dart';

DhabaProvider sampleCatalogProvider() =>
    DhabaProvider(dhabas: sampleDhabas(), menus: sampleMenus());

List<Dhaba> sampleDhabas() => sampleConstructionStores();

Map<String, List<MenuItemModel>> sampleMenus() => sampleConstructionProducts();
