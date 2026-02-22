import 'package:flutter/services.dart';

/// 取得嚴格的數字輸入過濾器
/// 規則：
/// 1. 允許空字串 (方便刪除)
/// 2. 允許 "0", "0.x"
/// 3. 允許 "1-9" 開頭的整數與小數
/// 4. 禁止 "0" 開頭後接數字 (如 01, 05)
TextInputFormatter getStrictNumberFormatter() {
  return TextInputFormatter.withFunction((oldValue, newValue) {
    final text = newValue.text;
    
    // 1. 如果是空字串，允許
    if (text.isEmpty) return newValue;

    // 2. 嚴格 Regex 檢查
    try {
      final regExp = RegExp(r'^(0|([1-9][0-9]*))(\.[0-9]*)?$');
      if (regExp.hasMatch(text)) {
        return newValue;
      }
    } catch (e) {
      // 忽略錯誤
    }
    
    // 3. 不符合則回傳舊值 (擋住輸入)
    return oldValue;
  });
}