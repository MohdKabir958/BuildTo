path = r'D:\BuildDo\Buildto\apps\customer_app\lib\screens\cancel_order_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    code = f.read()

if "import 'package:provider/provider.dart';" not in code:
    code = "import 'package:provider/provider.dart';\n" + code
if "import '../providers/demo_orders_provider.dart';" not in code:
    code = "import '../providers/demo_orders_provider.dart';\n" + code

old_cancel = '''                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.pushReplacement('''

new_cancel = '''                          onPressed: () {
                            Navigator.pop(ctx);
                            context.read<DemoOrdersProvider>().cancelOrder(widget.orderId, _selectedReason);
                            Navigator.pushReplacement('''

code = code.replace(old_cancel, new_cancel)

with open(path, 'w', encoding='utf-8') as f:
    f.write(code)

print('Updated cancel_order_screen.dart with dynamic cancellation')
