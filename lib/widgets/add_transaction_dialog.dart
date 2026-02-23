import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../database/db_helper.dart';
import '../models/transaction_model.dart';
import '../models/asset_model.dart';
import '../providers/settings_provider.dart';
import '../providers/asset_provider.dart';
import '../utils/formatters.dart';
import 'stock_search_input.dart';


class AddTransactionDialog extends StatefulWidget {
  final VoidCallback onSaved;

  const AddTransactionDialog({super.key, required this.onSaved});

  @override
  State<AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<AddTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  
  // 共用控制器：根據不同模式代表不同意義
  // _priceController -> 現股:單價, 現金股利:股利總額
  // _sharesController -> 現股:股數, 股票股利:配股股數
  final _priceController = TextEditingController();
  final _sharesController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  String? _selectedStockCode;
  String? _selectedStockName;
  String? _stockError;
  String? _cashError;

  // 交易狀態
  String _transactionType = 'BUY';   // BUY, SELL, DIVIDEND
  String _tradeType = 'SPOT';        
  
  // 是否扣除匯費 (現金股利專用)
  bool _deductRemittanceFee = true; 

  final Map<String, String> _tradeTypeOptions = {
    'SPOT': '現股',
    'DAY_TRADE': '當沖',
    'CASH_DIVIDEND': '現金股利',
    'STOCK_DIVIDEND': '股票股利',
    'DEPOSIT': '入金',
    'WITHDRAWAL': '出金',
  };

  final _numberFormat = NumberFormat("#,##0.##");

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000), // 允許選到最早 2000 年
      lastDate: DateTime(2100),  // 允許選到最晚 2100 年
      locale: const Locale('zh', 'TW'), // 確保日曆是繁體中文
      builder: (context, child) {
        // (選用) 自訂日曆顏色以配合 App 主題
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.purple, // 日曆頭部顏色
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      final now = DateTime.now();
      setState(() {
        _selectedDate = DateTime(
          picked.year, 
          picked.month, 
          picked.day,
          now.hour,
          now.minute,
          now.second,
          now.millisecond
        );
      });
    }
  }

  // --- 核心計算邏輯 (含稅、手續費、二代健保) ---
  Map<String, Decimal> _calculateDetails() {
    final settings = context.read<SettingsProvider>();
    final discount = settings.feeDiscount;

    // 1. 取得輸入數值 (若為空則視為 0)
    final inputPrice = Decimal.tryParse(_priceController.text) ?? Decimal.zero;
    final inputShares = Decimal.tryParse(_sharesController.text) ?? Decimal.zero;

    Decimal total = Decimal.zero;
    Decimal fee = Decimal.zero;
    Decimal tax = Decimal.zero;

    // --- 分流計算 ---
    if (_tradeType == 'DEPOSIT' || _tradeType == 'WITHDRAWAL') {
      // 直接把輸入的 "金額" 當作總額
      total = inputPrice;
      // 手續費與稅金設為 0 (或日後依需求增加匯費邏輯)
      fee = Decimal.zero;
      tax = Decimal.zero;
    } else if (_tradeType == 'CASH_DIVIDEND') {
      // === 現金股利計算 ===
      // 輸入欄位是 "股利總額"
      final grossAmount = inputPrice; 
      
      // A. 二代健保：單筆 >= 20,000 扣 2.11%
      Decimal healthTax = Decimal.zero;
      if (grossAmount >= Decimal.parse('20000')) {
        healthTax = (grossAmount * Decimal.parse('0.0211')).floor();
      }

      // B. 匯費：10元
      Decimal remittance = _deductRemittanceFee ? Decimal.parse('10') : Decimal.zero;

      // 總費用 = 二代健保 + 匯費
      fee = healthTax + remittance;
      
      // 實領金額 = 總額 - 費用
      total = grossAmount - fee;
      
    } else if (_tradeType == 'STOCK_DIVIDEND') {
      // === 股票股利計算 ===
      // 只有股數增加，沒有現金流
      total = Decimal.zero;
      fee = Decimal.zero;
      
    } else {
      // === 現股 / 當沖 計算 (原邏輯) ===
      final rawAmount = inputPrice * inputShares;

      if (rawAmount > Decimal.zero) {
        // 1. 先算出「未打折」的原始手續費
        Decimal rawFee = rawAmount * Decimal.parse('0.001425') * discount;
        // 2. 依照台灣券商慣例：無條件捨去小數點
        fee = rawFee.floor();
        // 3. 判斷低消門檻：零股(<1000股)低消 1 元，整張(>=1000股)低消 20 元
        Decimal minFee = inputShares < Decimal.parse('1000') 
            ? Decimal.parse('1') 
            : Decimal.parse('20');
        // 4. 如果算出來的手續費低於該門檻，就以最低門檻計收
        if (fee < minFee) {
          fee = minFee;
        }
      } else {
        fee = Decimal.zero;
      }
      // 證交稅
      if (_transactionType == 'SELL') {
        final taxRate = _tradeType == 'DAY_TRADE' ? '0.0015' : '0.003';
        tax = (rawAmount * Decimal.parse(taxRate)).floor();
      }

      if (_transactionType == 'BUY') {
        total = rawAmount + fee;
      } else {
        total = rawAmount - fee - tax;
      }
    }

    return {'total': total, 'fee': fee, 'tax': tax};
  }

  Future<void> _saveTransaction() async {
    setState(() {
      _stockError = null;
      _cashError = null;
    });

    // 特殊處理：入金/出金不需要選股票，我們自動填入虛擬代號
    if (_tradeType == 'DEPOSIT' || _tradeType == 'WITHDRAWAL') {
      _selectedStockCode = 'CASH';
      _selectedStockName = '帳戶資金';
    }

    if (_selectedStockCode == null) {
      setState(() => _stockError = '請先搜尋並選擇股票');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final calcs = _calculateDetails();
    final totalAmount = calcs['total']!;

    // ==========================================
    // 庫存檢查邏輯 (防止手滑多打0)
    // ==========================================
    final assetProvider = context.read<AssetProvider>();
    final snapshot = assetProvider.snapshot;

    // 情境 A: 賣股票 (檢查持股只有「現股」且「賣出」時才檢查)
    if (_tradeType == 'SPOT' && _transactionType == 'SELL') {
      // 1. 取得使用者輸入的股數
      final inputShares = Decimal.tryParse(_sharesController.text) ?? Decimal.zero;
      
      // 2. 取得目前資產庫存
      final assetProvider = context.read<AssetProvider>();
      // 注意：snapshot 可能為 null (如果尚未初始化)，給個空陣列防爆
      final positions = assetProvider.snapshot?.positions ?? [];
      
      Decimal currentShares = Decimal.zero;
      try {
        // 尋找這支股票的持倉
        final pos = positions.firstWhere((p) => p.stockCode == _selectedStockCode);
        currentShares = pos.shares; // 假設 StockPosition 模型裡有 shares 欄位
      } catch (e) {
        // 找不到表示庫存為 0
        currentShares = Decimal.zero;
      }

      // 3. 比對：如果要賣的 > 現有的，就擋下來
      if (inputShares > currentShares) {
        setState(() => _stockError = '庫存不足！現有: $currentShares 股');
        return; // 中斷，不繼續執行存檔
      }
    }

    // 情境 B: 買股票 或 出金 (檢查現金)
    // 如果是「現股買入」或是「出金」，都需要扣錢
    if ((_tradeType == 'SPOT' && _transactionType == 'BUY') || 
        (_tradeType == 'WITHDRAWAL')) {
      
      final currentCash = snapshot?.totalCashBalance ?? Decimal.zero;

      if (totalAmount > currentCash) {
        final errorMsg = '現金不足！餘額: \$${NumberFormat("#,##0.##").format(currentCash.toDouble())}，需: \$${NumberFormat("#,##0.##").format(totalAmount.toDouble())}';

        if (_tradeType == 'SPOT') {
          setState(() => _stockError = errorMsg);
        } else {
          setState(() =>_cashError = errorMsg);
        }
        return; // 中斷存檔
      }
    }

    // 判斷存檔的 type (如果是股利，強制設為 DIVIDEND)
    String finalType = _transactionType;
    if (_tradeType == 'CASH_DIVIDEND' || _tradeType == 'STOCK_DIVIDEND') {
      finalType = 'DIVIDEND';
    } else if (_tradeType == 'DEPOSIT' || _tradeType == 'WITHDRAWAL') {
      finalType = _tradeType; // 直接存 DEPOSIT 或 WITHDRAWAL
    }

    // 處理存檔數值 mapping
    Decimal savePrice = Decimal.parse(_priceController.text.isEmpty ? '0' : _priceController.text);
    Decimal saveShares = Decimal.parse(_sharesController.text.isEmpty ? '0' : _sharesController.text);

    // 特殊處理：
    // 1. 入/出金：把 "金額" 存在 totalAmount
    // 2. 股票股利：單價存 0，股數存配股數
    // 3. 現金股利：單價存 0 (或存每股股利? 這裡先存0，總額存 totalAmount)，股數存 0
    if (_tradeType == 'DEPOSIT' || _tradeType == 'WITHDRAWAL') {
      savePrice = Decimal.zero; 
      saveShares = Decimal.zero;
    } else if (_tradeType == 'STOCK_DIVIDEND') {
      savePrice = Decimal.zero; 
      // saveShares 使用輸入值
    } else if (_tradeType == 'CASH_DIVIDEND') {
      savePrice = Decimal.zero;
      saveShares = Decimal.zero;
    }

    final newTx = StockTransaction(
      id: const Uuid().v4(),
      stockCode: _selectedStockCode!,
      stockName: _selectedStockName!,
      type: finalType,
      tradeType: _tradeType,
      price: savePrice,
      shares: saveShares,
      fee: calcs['fee']!,
      totalAmount: calcs['total']!,
      date: _selectedDate,
      updatedAt: DateTime.now(),
      note: _noteController.text.isNotEmpty 
            ? _noteController.text 
            : (_tradeType == 'DAY_TRADE' ? '當沖' : ''),
    );

    // 1. 將新交易存入資料庫
    await DatabaseHelper.instance.insertTransaction(newTx.toMap());

    // 2. 觸發歷史成本回溯運算引擎
    // 只要有新增現股或配股，就叫引擎重新整理這檔股票的歷史損益
    if (_tradeType == 'SPOT' || _tradeType == 'STOCK_DIVIDEND' || _tradeType == 'DAY_TRADE') {
      await DatabaseHelper.instance.recalculateProfit(newTx.stockCode);
    }

    // 只要使用者手動新增了一筆帳務，就不再是「第一次開啟」
    // 這樣即使是從「清除資料」後過來的，下次開啟也不會跳 Onboarding
    final prefs = await SharedPreferences.getInstance();
    // 檢查一下，避免每次都寫入，雖然寫入成本很低
    if (prefs.getBool('is_first_launch') ?? false) {
      await prefs.setBool('is_first_launch', false);
    }

    if (mounted) {
      widget.onSaved();
      Navigator.of(context).pop();
    }
  }

  // --- UI 建構子 ---
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final labelSize = settings.fontSize;
    final valueSize = settings.fontSize + 2.0;

    // 計算預覽數值
    final calcResult = _calculateDetails();
    final totalPreview = calcResult['total'];
    final feePreview = calcResult['fee'];
    
    // 判斷是否為一般交易模式 (顯示買賣Radio)
    final isNormalTrade = _tradeType == 'SPOT' || _tradeType == 'DAY_TRADE';
    final isCashOp = _tradeType == 'DEPOSIT' || _tradeType == 'WITHDRAWAL'; // 是否為資金操作
    // 判斷顏色
    Color currentColor = Colors.black;
    if (_tradeType == 'CASH_DIVIDEND') {
      currentColor = Colors.blue;   // 現金股利用藍色
    } else if (_tradeType == 'STOCK_DIVIDEND') {
      currentColor = Colors.orange; // 股票股利用橘色
    } else if (_tradeType == 'DEPOSIT') {
      currentColor = Colors.purple; // 入金紫色
    } else if (_tradeType == 'WITHDRAWAL') {
      currentColor = Colors.brown;  // 出金咖啡色
    } else {
      // 一般買賣
      currentColor = _transactionType == 'BUY' ? settings.buyColor : settings.sellColor;
    }

    return AlertDialog(
      title: Text('新增帳務', style: TextStyle(fontSize: labelSize + 4)),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 500,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 第一排：交易類別 (左) + 日期選擇 (右)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左邊：交易類別 (佔 3/5)
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: _tradeType,
                        decoration: InputDecoration(
                          labelText: '交易類別',
                          labelStyle: TextStyle(fontSize: labelSize),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        style: TextStyle(fontSize: labelSize, color: Colors.black87),
                        items: _tradeTypeOptions.entries.map((entry) {
                          return DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _tradeType = newValue;
                              _priceController.clear();
                              _sharesController.clear();
                            });
                          }
                        },
                      ),
                    ),
                    
                    const SizedBox(width: 12),
                    
                    // 右邊：日期選擇 (佔 2/5)
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        onTap: _pickDate, // 點擊觸發日期選擇器
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: '日期',
                            labelStyle: TextStyle(fontSize: labelSize),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            suffixIcon: const Icon(Icons.calendar_today, size: 20), // 小日曆圖示
                          ),
                          child: Text(
                            DateFormat('yyyy/MM/dd').format(_selectedDate),
                            style: TextStyle(fontSize: labelSize),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),

                // 2. 買賣切換 (只有現股/當沖才顯示)
                if (isNormalTrade) ...[
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: Text('買入', style: TextStyle(color: settings.buyColor, fontSize: labelSize + 16, fontWeight: FontWeight.bold)),
                          value: 'BUY',
                          groupValue: _transactionType,
                          onChanged: (v) => setState(() => _transactionType = v!),
                          activeColor: settings.buyColor,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: Text('賣出', style: TextStyle(color: settings.sellColor, fontSize: labelSize + 16, fontWeight: FontWeight.bold)),
                          value: 'SELL',
                          groupValue: _transactionType,
                          onChanged: (v) => setState(() => _transactionType = v!),
                          activeColor: settings.sellColor,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                ],

                // 3. 股票搜尋
                if (!isCashOp) ...[
                  StockSearchInput(
                    onSelected: (code, name) => setState(() {
                      _selectedStockCode = code;
                      _selectedStockName = name;
                      _stockError = null;
                    }),
                  ),
                  if (_stockError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 12.0),
                      child: Text(
                        _stockError!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: labelSize - 4),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],

                // 4. 動態輸入區塊 (依照類別顯示不同欄位)
                _buildDynamicInputFields(labelSize, valueSize),

                const SizedBox(height: 16),

                // 5. 備註欄
                TextFormField(
                  controller: _noteController,
                  style: TextStyle(fontSize: labelSize),
                  decoration: InputDecoration(
                    labelText: '備註',
                    labelStyle: TextStyle(fontSize: labelSize),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),

                const SizedBox(height: 24),

                // 6. 總金額預覽
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!)
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _tradeType == 'STOCK_DIVIDEND' ? '總價值(0):' : (_tradeType == 'CASH_DIVIDEND' ? '實領金額:' : '預估總金額:'),
                            style: TextStyle(fontSize: labelSize)
                          ),
                          Text(
                            '\$${_numberFormat.format(double.tryParse(totalPreview.toString()) ?? 0)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: valueSize,
                              color: currentColor,
                            ),
                          ),
                        ],
                      ),
                      
                      // 費用詳情小字
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _buildFooterNote(feePreview ?? Decimal.zero, calcResult['tax'] ?? Decimal.zero, labelSize),
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        ElevatedButton(onPressed: _saveTransaction, child: const Text('儲存')),
      ],
    );
  }

  // --- 輔助：動態欄位生成器 ---
  Widget _buildDynamicInputFields(double labelSize, double valueSize) {
    // A. 入金 / 出金 (只有一個金額欄位)
    if (_tradeType == 'DEPOSIT' || _tradeType == 'WITHDRAWAL') {
       return TextFormField(
        controller: _priceController, // 重用 priceController 存 "金額"
        style: TextStyle(fontSize: valueSize),
        decoration: InputDecoration(
          labelText: _tradeType == 'DEPOSIT' ? '入金金額' : '出金金額',
          labelStyle: TextStyle(fontSize: labelSize),
          suffixText: '元',
          border: const OutlineInputBorder(),
          errorText: _cashError,
          errorMaxLines: 2,
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [getStrictNumberFormatter()],
        validator: (v) => v!.isEmpty ? '請輸入金額' : null,
        onChanged: (_) {
          setState(() {
            _cashError = null;
          });
        },
      );
    }
    // B. 現金股利模式
    else if (_tradeType == 'CASH_DIVIDEND') {
      return Column(
        children: [
          TextFormField(
            controller: _priceController, // 這裡當作 "股利總額"
            style: TextStyle(fontSize: valueSize),
            decoration: InputDecoration(
              labelText: '現金股利總額 (收到通知書上的金額)',
              labelStyle: TextStyle(fontSize: labelSize),
              suffixText: '元',
              border: const OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [getStrictNumberFormatter()],
            validator: (v) => v!.isEmpty ? '請輸入金額' : null,
            onChanged: (_) => setState(() {}),
          ),
          // 匯費開關
          Row(
            children: [
              Checkbox(
                value: _deductRemittanceFee,
                onChanged: (v) => setState(() => _deductRemittanceFee = v!),
              ),
              Text('扣除匯費 (10元)', style: TextStyle(fontSize: labelSize)),
            ],
          )
        ],
      );
    } 
    // C. 股票股利模式
    else if (_tradeType == 'STOCK_DIVIDEND') {
      return TextFormField(
        controller: _sharesController, // 這裡當作 "配股數"
        style: TextStyle(fontSize: valueSize),
        decoration: InputDecoration(
          labelText: '配股股數 (增加的股數)',
          labelStyle: TextStyle(fontSize: labelSize),
          suffixText: '股',
          border: const OutlineInputBorder(),
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [getStrictNumberFormatter()],
        validator: (v) => v!.isEmpty ? '請輸入股數' : null,
        onChanged: (_) => setState(() {}),
      );
    }
    // D. 一般交易模式 (現股/當沖)
    else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: _priceController,
              style: TextStyle(fontSize: valueSize),
              decoration: InputDecoration(
                labelText: '單價',
                labelStyle: TextStyle(fontSize: labelSize),
                suffixText: '元',
                border: const OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [getStrictNumberFormatter()],
              validator: (v) => v!.isEmpty ? '必填' : null,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextFormField(
              controller: _sharesController,
              style: TextStyle(fontSize: valueSize),
              decoration: InputDecoration(
                labelText: '股數',
                labelStyle: TextStyle(fontSize: labelSize),
                suffixText: '股',
                border: const OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [getStrictNumberFormatter()],
              validator: (v) => v!.isEmpty ? '必填' : null,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      );
    }
  }

  // --- 輔助：底部小字 ---
  Widget _buildFooterNote(Decimal fee, Decimal tax, double fontSize) {
    if (_tradeType == 'CASH_DIVIDEND') {
      return Text(
        '(內含二代健保補充保費與匯費: $fee)',
        style: TextStyle(color: Colors.grey, fontSize: fontSize - 4),
      );
    } else if (_tradeType == 'STOCK_DIVIDEND') {
      return Text(
        '(僅增加股數，無現金流)',
        style: TextStyle(color: Colors.grey, fontSize: fontSize - 4),
      );
    } else {
      return Text(
        '(含手續費: $fee, 證交稅: $tax)',
        style: TextStyle(color: Colors.grey, fontSize: fontSize - 4),
      );
    }
  }
}