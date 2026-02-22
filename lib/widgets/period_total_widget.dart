import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:decimal/decimal.dart';

class PeriodTotalWidget extends StatelessWidget {
  final String title;
  final Decimal amount;
  final double fontSize;
  final Color positiveColor;
  final Color negativeColor;

  const PeriodTotalWidget({
    super.key,
    required this.title,
    required this.amount,
    required this.fontSize,
    required this.positiveColor,
    required this.negativeColor,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat("#,##0");
    final isPositive = amount >= Decimal.zero;
    
    // 使用 Divider 與上方內容自然隔開
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24, thickness: 1),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
            Text(
              // 如果是負數，格式化會自動帶負號；這裡加上錢字號
              '\$${fmt.format(amount.toDouble())}', 
              style: TextStyle(
                fontSize: fontSize + 2, 
                fontWeight: FontWeight.bold, 
                color: isPositive ? positiveColor : negativeColor,
              )
            ),
          ],
        ),
      ],
    );
  }
}