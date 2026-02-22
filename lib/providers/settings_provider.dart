// lib/providers/settings_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:decimal/decimal.dart';

class SettingsProvider with ChangeNotifier {
  // --- 1. 定義預設值 ---
  static const double _defaultFontSize = 18.0;
  static const String _defaultFeeDiscount = '1.0'; // 不打折
  static const int _defaultBuyColor = 0xFFF44336;  // Colors.red[500]
  static const int _defaultSellColor = 0xFF4CAF50; // Colors.green[500]

  // --- 2. 內部變數 ---
  late SharedPreferences _prefs;
  double _fontSize = _defaultFontSize;
  Decimal _feeDiscount = Decimal.parse(_defaultFeeDiscount);
  Color _buyColor = Color(_defaultBuyColor);
  Color _sellColor = Color(_defaultSellColor);

  // --- 3. Getters (讓 UI 讀取用) ---
  double get fontSize => _fontSize;
  Decimal get feeDiscount => _feeDiscount;
  Color get buyColor => _buyColor;
  Color get sellColor => _sellColor;

  // --- 4. 初始化 (App 啟動時呼叫) ---
  Future<void> loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    
    _fontSize = _prefs.getDouble('font_size') ?? _defaultFontSize;
    
    String feeString = _prefs.getString('fee_discount') ?? _defaultFeeDiscount;
    _feeDiscount = Decimal.parse(feeString);

    _buyColor = Color(_prefs.getInt('buy_color') ?? _defaultBuyColor);
    _sellColor = Color(_prefs.getInt('sell_color') ?? _defaultSellColor);

    notifyListeners(); // 通知 UI 更新
  }

  // --- 5. Setters (設定頁呼叫用) ---
  
  // 設定字體大小
  Future<void> setFontSize(double size) async {
    _fontSize = size;
    await _prefs.setDouble('font_size', size);
    notifyListeners();
  }

  // 設定手續費折讓
  Future<void> setFeeDiscount(String rate) async {
    _feeDiscount = Decimal.parse(rate);
    await _prefs.setString('fee_discount', rate);
    notifyListeners();
  }

  // 設定買賣顏色 (例如切換美股模式)
  Future<void> setColors({required Color buy, required Color sell}) async {
    _buyColor = buy;
    _sellColor = sell;
    await _prefs.setInt('buy_color', buy.value);   // 存成 int
    await _prefs.setInt('sell_color', sell.value);
    notifyListeners();
  }

  Future<void> resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 重置手續費為 1.0 (10折)
    _feeDiscount = Decimal.parse('1.0');
    await prefs.setString('fee_discount', '1.0');
    
    // 通知所有聽眾 (包含 SettingsPage) 更新畫面
    notifyListeners();
  }
}