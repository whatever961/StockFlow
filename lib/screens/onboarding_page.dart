import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:decimal/decimal.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';
import '../database/db_helper.dart';
import '../models/transaction_model.dart';
import '../providers/asset_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/stock_search_input.dart';
import '../utils/app_dialogs.dart';
import '../utils/formatters.dart';
import 'main_screen.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  double get fontSize => context.watch<SettingsProvider>().fontSize;
  int _currentStep = 0;
  final PageController _pageController = PageController();
  
  // 初始資產暫存
  final TextEditingController _cashController = TextEditingController(text: '0');
  final List<Map<String, dynamic>> _initialStocks = [];

  // 股票輸入暫存
  final _stockCodeCtrl = TextEditingController();
  final _stockNameCtrl = TextEditingController();
  final _stockPriceCtrl = TextEditingController();
  final _stockSharesCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 進度條
            LinearProgressIndicator(
              value: (_currentStep + 1) / 3,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.black87),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // 禁止滑動，只能按按鈕
                children: [
                  _buildIntroStep(),
                  _buildCashStep(),
                  _buildStockStep(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 步驟 1: 歡迎頁
  Widget _buildIntroStep() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.account_balance_wallet, size: 80, color: Colors.black87),
          const SizedBox(height: 24),
          Text(
            "歡迎使用股票記帳本",
            style: TextStyle(fontSize: fontSize + 4, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            "這是一個專為股票投資人設計的簡約記帳工具。\n除了抓取收盤價做為未實現損益的計算以外，「完全離線」。\n絕對不會抓取任何使用者資訊。\n\n在開始之前，讓我們花 1 分鐘設定您的「初始資產狀態」。\n\n這些設定只會用來計算總資產與庫存，不會出現在您的日常記帳流水帳中。",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: fontSize, color: Colors.black87, height: 1.5),
          ),
          const Spacer(),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
            ),
            onPressed: _nextPage,
            child: Text("開始設定", style: TextStyle(fontSize: fontSize - 2)),
          ),
        ],
      ),
    );
  }

  // 步驟 2: 設定初始現金
  Widget _buildCashStep() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("1. 設定帳戶現金", style: TextStyle(fontSize: fontSize + 4, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("請輸入您目前證券交割戶中的現金餘額。", style: TextStyle(fontSize: fontSize + 4, color: Colors.grey)),
          const SizedBox(height: 32),
          TextField(
            controller: _cashController,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [getStrictNumberFormatter()],
            decoration: InputDecoration(
              labelText: "現金餘額",
              labelStyle: TextStyle(fontSize: fontSize + 4),
              prefixText: "\$ ",
              border: OutlineInputBorder(),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              TextButton(onPressed: _prevPage, child: Text("上一步", style: TextStyle(fontSize: fontSize))),
              const Spacer(),
              ElevatedButton(
                onPressed: _nextPage,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black87, foregroundColor: Colors.white),
                child: Text("下一步", style: TextStyle(fontSize: fontSize)),
              ),
            ],
          )
        ],
      ),
    );
  }

  // 步驟 3: 設定初始持股 + 手續費折讓
  Widget _buildStockStep() {
    final settings = context.watch<SettingsProvider>();
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("2. 設定現有持股", style: TextStyle(fontSize: fontSize + 4, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("如果您目前手上有股票，請新增至此。\n這將作為您的「庫存成本」。", style: TextStyle(fontSize: fontSize + 4, color: Colors.grey)),
          const SizedBox(height: 24),

          // 手續費設定區塊
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("手續費折數", style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize)),
                      const SizedBox(height: 4),
                      Text("影響未實現損益計算", style: TextStyle(color: Colors.grey, fontSize: fontSize - 2)),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => showDiscountDialog(context), // 呼叫設定對話框
                  icon: const Icon(Icons.edit, size: 16),
                  label: Text(
                    "${settings.feeDiscount.toDouble() * 10} 折", // 顯示目前折數
                    style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // 持股列表
          Expanded(
            child: _initialStocks.isEmpty
                ? Center(
                    child: TextButton.icon(
                      onPressed: _showAddStockDialog,
                      icon: const Icon(Icons.add_circle_outline),
                      label: Text("新增第一筆持股", style: TextStyle(fontSize: fontSize)),
                    ),
                  )
                : ListView.builder(
                    itemCount: _initialStocks.length,
                    itemBuilder: (context, index) {
                      final item = _initialStocks[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Text("${item['code']} ${item['name']}", style: TextStyle(fontSize: fontSize)),
                          subtitle: Text("成本: ${item['price']} x ${item['shares']}股", style: TextStyle(fontSize: fontSize)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setState(() => _initialStocks.removeAt(index));
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
          
          if (_initialStocks.isNotEmpty)
            Center(
              child: TextButton.icon(
                onPressed: _showAddStockDialog,
                icon: const Icon(Icons.add),
                label: Text("繼續新增持股", style: TextStyle(fontSize: fontSize)),
              ),
            ),

          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(onPressed: _prevPage, child: Text("上一步", style: TextStyle(fontSize: fontSize))),
              const Spacer(),
              ElevatedButton(
                onPressed: _finishOnboarding,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87, 
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: Text("完成設定，進入主畫面", style: TextStyle(fontSize: fontSize)),
              ),
            ],
          )
        ],
      ),
    );
  }

  // 顯示新增股票視窗 (已整合搜尋功能)
  void _showAddStockDialog() {
    _stockCodeCtrl.clear();
    _stockNameCtrl.clear();
    _stockPriceCtrl.clear();
    _stockSharesCtrl.clear();
    
    // 定義錯誤訊息變數，初始為 null
    String? localErrorText;

    showDialog(
      context: context,
      builder: (ctx) {
        // 使用 StatefulBuilder 讓我們可以在 Dialog 內部使用 setState 更新錯誤訊息
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text("新增持股", style: TextStyle(fontSize: fontSize + 4)),
              
              content: SizedBox(
                width: 700,
                child: Column(
                  mainAxisSize: MainAxisSize.min, // 讓高度隨內容自適應
                  children: [
                    StockSearchInput(
                      onSelected: (code, name) {
                        _stockCodeCtrl.text = code;
                        _stockNameCtrl.text = name;
                        // 選擇股票後，清除錯誤訊息
                        setStateDialog(() => localErrorText = null);
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _stockPriceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [getStrictNumberFormatter()],
                            decoration: const InputDecoration(labelText: "總成本 (券商APP顯示的付出總額)", suffixText: '元', border: OutlineInputBorder()),
                            onChanged: (_) => setStateDialog(() => localErrorText = null),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _stockSharesCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [getStrictNumberFormatter()],
                            decoration: const InputDecoration(labelText: "持有股數", border: OutlineInputBorder()),
                            onChanged: (_) => setStateDialog(() => localErrorText = null),
                          ),
                        ),
                      ],
                    ),
                    
                    // 顯示錯誤訊息 (如果有)
                    if (localErrorText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, size: 16, color: Colors.red),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                localErrorText!,
                                style: TextStyle(color: Colors.red, fontSize: fontSize - 2),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx), 
                  child: Text("取消", style: TextStyle(fontSize: fontSize - 2))
                ),
                ElevatedButton(
                  onPressed: () {
                    // 驗證邏輯
                    if (_stockCodeCtrl.text.isEmpty) {
                      setStateDialog(() => localErrorText = "請先搜尋並選擇股票");
                      return;
                    }
                    if (_stockPriceCtrl.text.isEmpty || _stockSharesCtrl.text.isEmpty) {
                      setStateDialog(() => localErrorText = "請輸入成本與股數");
                      return;
                    }
                    
                    // 通過驗證，新增資料
                    setState(() {
                      _initialStocks.add({
                        'code': _stockCodeCtrl.text,
                        'name': _stockNameCtrl.text,
                        'price': _stockPriceCtrl.text,
                        'shares': _stockSharesCtrl.text,
                      });
                    });
                    Navigator.pop(ctx);
                  },
                  child: Text("加入", style: TextStyle(fontSize: fontSize - 2)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _nextPage() {
    _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    setState(() => _currentStep++);
  }

  void _prevPage() {
    _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    setState(() => _currentStep--);
  }

  // === 核心邏輯：儲存初始資料並標記為已完成 ===
  Future<void> _finishOnboarding() async {
    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();

    // 1. 儲存初始現金 (類別: OPENING_CASH)
    if (_cashController.text.isNotEmpty) {
      final amount = double.tryParse(_cashController.text) ?? 0;
      if (amount > 0) {
        batch.insert('transactions', {
          'id': const Uuid().v4(),
          'stock_code': 'CASH',
          'stock_name': '初始資金',
          'trade_type': 'OPENING_CASH', // 特殊類別
          'type': 'DEPOSIT', // 視為入金的一種
          'price': 1,
          'shares': amount, // 用 shares 存金額或 total_amount 存皆可，這裡依照您的邏輯統一
          'fee': 0,
          'total_amount': amount,
          'date': now,
          'note': '初始設定',
          'updated_at': now,
        });
      }
    }

    // 2. 儲存初始持股 (類別: OPENING_STOCK)
    for (var stock in _initialStocks) {
      final totalCost = double.parse(stock['price']);
      final shares = double.parse(stock['shares']);
      // 反推精確的單價
      final precisePrice = shares > 0 
          ? double.parse((totalCost / shares).toStringAsFixed(4)) 
          : 0.0;

      batch.insert('transactions', {
        'id': const Uuid().v4(),
        'stock_code': stock['code'],
        'stock_name': stock['name'],
        'trade_type': 'OPENING_STOCK', // 特殊類別
        'type': 'BUY', // 視為買入的一種
        'price': precisePrice,
        'shares': shares,
        'fee': 0, // 初始庫存通常不計手續費，或已含在成本內
        'total_amount': totalCost,
        'date': now,
        'note': '初始持股',
        'updated_at': now,
      });
    }

    await batch.commit();

    // 3. 標記為「非第一次開啟」
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_launch', false);

    // 4. 重算資產並跳轉主頁
    if (mounted) {
      context.read<AssetProvider>().recalculateHoldings();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    }
  }
}