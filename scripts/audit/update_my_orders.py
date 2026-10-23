path = r'D:\BuildDo\Buildto\apps\customer_app\lib\screens\my_orders_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    code = f.read()

# Add imports
if "import 'package:provider/provider.dart';" not in code:
    code = "import 'package:provider/provider.dart';\n" + code
if "import '../providers/demo_orders_provider.dart';" not in code:
    code = "import '../providers/demo_orders_provider.dart';\n" + code

# Update _filteredOrders
old_filtered = '''  List<Map<String, dynamic>> _filteredOrders(String filter) {
    if (filter == 'all') return _demoOrders;
    if (filter == 'pending') return _demoOrders.where((o) => o['statusCode'] == 'pending').toList();
    if (filter == 'processing') return _demoOrders.where((o) => o['statusCode'] == 'processing').toList();
    if (filter == 'delivered') return _demoOrders.where((o) => o['statusCode'] == 'delivered').toList();
    if (filter == 'cancelled') return _demoOrders.where((o) => o['statusCode'] == 'cancelled').toList();
    return _demoOrders;
  }'''

new_filtered = '''  List<Map<String, dynamic>> _filteredOrders(String filter, List<Map<String, dynamic>> orders) {
    if (filter == 'all') return orders;
    if (filter == 'pending') return orders.where((o) => o['statusCode'] == 'pending').toList();
    if (filter == 'processing') return orders.where((o) => o['statusCode'] == 'processing').toList();
    if (filter == 'delivered') return orders.where((o) => o['statusCode'] == 'delivered').toList();
    if (filter == 'cancelled') return orders.where((o) => o['statusCode'] == 'cancelled').toList();
    return orders;
  }'''

code = code.replace(old_filtered, new_filtered)

old_build = '''  @override
  Widget build(BuildContext context) {
    return Scaffold('''

new_build = '''  @override
  Widget build(BuildContext context) {
    final demoOrders = context.watch<DemoOrdersProvider>();
    final allOrders = demoOrders.orders.map((o) => o.toMap()).toList();

    return Scaffold('''

code = code.replace(old_build, new_build)

code = code.replace("_buildOrdersList(_filteredOrders('all'))", "_buildOrdersList(_filteredOrders('all', allOrders))")
code = code.replace("_buildOrdersList(_filteredOrders('pending'))", "_buildOrdersList(_filteredOrders('pending', allOrders))")
code = code.replace("_buildOrdersList(_filteredOrders('processing'))", "_buildOrdersList(_filteredOrders('processing', allOrders))")
code = code.replace("_buildOrdersList(_filteredOrders('delivered'))", "_buildOrdersList(_filteredOrders('delivered', allOrders))")
code = code.replace("_buildOrdersList(_filteredOrders('cancelled'))", "_buildOrdersList(_filteredOrders('cancelled', allOrders))")

with open(path, 'w', encoding='utf-8') as f:
    f.write(code)

print('Updated my_orders_screen.dart successfully')
