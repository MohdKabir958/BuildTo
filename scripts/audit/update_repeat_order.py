path = r'D:\BuildDo\Buildto\apps\customer_app\lib\screens\repeat_order_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    code = f.read()

if "import '../providers/demo_orders_provider.dart';" not in code:
    code = "import '../providers/demo_orders_provider.dart';\n" + code

old_build = '''  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    final repeatItems = ['''

new_build = '''  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final demoOrders = context.watch<DemoOrdersProvider>();
    final orderedList = demoOrders.frequentlyOrderedItems;

    final repeatItems = orderedList.isNotEmpty
        ? orderedList.map((it) {
            return {
              'id': it.name.toLowerCase().contains('cement') ? 'prod-cem-ultratech' : (it.name.toLowerCase().contains('tmt') ? 'prod-stl-tata-12' : 'prod-brk-red-clay'),
              'name': it.name,
              'price': it.price > 0 ? (it.qty > 0 ? it.price / it.qty : it.price) : 390.0,
              'unit': it.unit,
              'orderedTimes': 1,
              'lastOrdered': 'Recent Order',
              'image': it.imageUrl,
            };
          }).toList()
        : ['''

code = code.replace(old_build, new_build)

with open(path, 'w', encoding='utf-8') as f:
    f.write(code)

print('Updated repeat_order_screen.dart with dynamic frequently ordered items')
