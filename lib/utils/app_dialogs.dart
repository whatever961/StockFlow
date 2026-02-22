import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

void showDiscountDialog(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final fontSize = settings.fontSize;
    
    // 將儲存的倍率 (0.28) 轉回折數 (2.8) 顯示給使用者看
    // 邏輯: 0.28 * 10 = 2.8
    double currentZhe = settings.feeDiscount.toDouble() * 10;
    
    // 格式化字串：去掉尾數多餘的 .0 (例如 6.0 -> 6)
    String initText = currentZhe.toString().replaceAll(RegExp(r'\.0$'), '');
    
    final controller = TextEditingController(text: initText);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('設定手續費折數', style: TextStyle(fontSize: fontSize + 2)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(fontSize: fontSize),
              inputFormatters: [
                TextInputFormatter.withFunction((oldValue, newValue) {
                final text = newValue.text;
                
                // 1. 如果是刪除全部變成空字串，允許
                if (text.isEmpty) return newValue;

                // 2. 定義正則表達式規則：
                //    (A) "10" 開頭，後面只能接 .00... (例如 10, 10., 10.0)
                //    (B) "0-9" (個位數) 開頭，後面可接小數 (例如 2, 2.8, 0.5)
                //    注意：這裡不限制小數點後幾位，若需限制可在 \d* 加上數量
                final regExp = RegExp(r'^(10(\.0*)?|[0-9](\.\d*)?)?$');

                // 3. 判斷：如果新的文字符合規則，就允許 (return newValue)
                if (regExp.hasMatch(text)) {
                    return newValue;
                }
                
                // 4. 如果不符合 (例如打了 11, 10.1, 2..8)，就擋住 (回傳舊值 oldValue)
                return oldValue;
                }),
              ],
              decoration: InputDecoration(
                labelText: '輸入折數 (例如 2.8)',
                labelStyle: TextStyle(fontSize: fontSize),
                suffixText: '折',
                suffixStyle: TextStyle(fontSize: fontSize),
                hintText: '10 表示無折扣',
                hintStyle: TextStyle(
                fontSize: fontSize,
                
                // 方法 1 (推薦)：使用透明度 (0.0 ~ 1.0)
                // 0.5 代表 50% 透明度，數值越小越透明
                color: Colors.grey.withOpacity(0.6), 

                // 方法 2：直接使用更淺的顏色
                // color: Colors.grey[300], 
                ),
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Text(
              '常見折數說明：\n• 電子下單：2.8 折 ~ 6 折\n• 人工下單：通常無折扣 (輸入 10)',
              style: TextStyle(color: Colors.grey, fontSize: fontSize - 2),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('取消', style: TextStyle(fontSize: fontSize))),
          ElevatedButton(
            onPressed: () {
              final input = controller.text;
              if (input.isEmpty) return;
              try {
                double val = double.parse(input);
                
                // 防呆：折數必須在 0.1 ~ 10 之間
                if (val <= 0 || val > 10) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('折數輸入錯誤，請輸入 0.1 ~ 10 之間的數字', style: TextStyle(fontSize: fontSize))),
                  );
                  return;
                }
                
                // 轉換邏輯：輸入 2.8 -> 存入 0.28
                double multiplier = val / 10.0;
                settings.setFeeDiscount(multiplier.toString());
                
                Navigator.pop(ctx);
              } catch (e) {
                // 忽略非數字輸入
              }
            },
            child: Text('儲存', style: TextStyle(fontSize: fontSize)),
          ),
        ],
      ),
    );
  }