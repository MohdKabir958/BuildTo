path = r'D:\BuildDo\Buildto\apps\customer_app\lib\screens\support_help_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    code = f.read()

code = code.replace(
    "subtitle: '1800-BUILD-TO',",
    "subtitle: '+91 98765 00123',",
)
code = code.replace(
    "showKSnack(context, 'Calling Buildto Toll-Free Hotline (1800-BUILD-TO)...');",
    "showKSnack(context, 'Calling Buildto Dispatch Support Desk (+91 98765 00123)...');",
)
code = code.replace(
    "'Damaged materials reported during unloading are replaced within 24 hours. Pre-dispatch cancellations receive a 100% full refund.'",
    "'Damaged materials noted on delivery challans during unloading are inspected for replacement or credit note. Cancellations prior to yard dispatch are refunded via original payment mode within standard banking cycles (3-5 business days). In demo mode, no real money was charged.'",
)

with open(path, 'w', encoding='utf-8') as f:
    f.write(code)

print('Updated support_help_screen.dart fake claims sanitized')
