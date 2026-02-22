import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import '../database/db_helper.dart';
import '../models/transaction_model.dart';
import '../models/asset_model.dart';
import '../providers/asset_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/add_transaction_dialog.dart';
import 'history_page.dart';
import 'settings_page.dart';
import 'analysis_page.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0; // 0:記帳, 1:歷史, 2:分析, 3:設定
  List<StockTransaction> _recentTransactions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // 1. 刷新首頁的交易列表
    _refreshData();
    // 2. 啟動時計算資產庫存
    // 使用 addPostFrameCallback 確保在 build 完成後才呼叫 Provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AssetProvider>().recalculateHoldings();
    });
  }

  // 重新讀取資料 (當新增帳務後呼叫)
  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.getRecentTransactions();
    if (mounted) {
      setState(() {
        _recentTransactions = data.map((e) => StockTransaction.fromMap(e)).toList();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 從 Provider 讀取全域設定
    final settings = context.watch<SettingsProvider>();
    final fontSize = settings.fontSize;

    return Scaffold(
      body: Row(
        children: [
          // --- 左側：導航欄 (NavigationRail) ---
          NavigationRail(
            extended: true,
            minExtendedWidth: 160,

            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() => _selectedIndex = index);
              if (index == 0){
                _refreshData();
                context.read<AssetProvider>().refreshPrices();
              }
            },
            // 使用設定中的字體大小來調整導航文字
            selectedLabelTextStyle: TextStyle(fontSize: fontSize - 2, fontWeight: FontWeight.bold, color: Colors.blue),
            unselectedLabelTextStyle: TextStyle(fontSize: fontSize - 4, color: Colors.black87, fontWeight: FontWeight.bold),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.edit_note),
                label: Text('記帳'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.history),
                label: Text('歷史記錄'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.analytics),
                label: Text('帳本分析'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('設定'),
              ),
            ],
          ),
          
          const VerticalDivider(thickness: 1, width: 1),

          // --- 右側：主要內容區 ---
          Expanded(
            child: _buildPageContent(_selectedIndex),
          ),
        ],
      ),
      
      // 懸浮按鈕 (只在記帳頁顯示)
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AddTransactionDialog(
                    onSaved: () {
                      _refreshData(); // 儲存後刷新列表
                      if (context.mounted) {
                        context.read<AssetProvider>().recalculateHoldings();
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('帳務已新增並更新列表', style: TextStyle(fontSize: fontSize))),
                      );
                    },
                  ),
                );
              },
              icon: const Icon(Icons.add),
              label: Text('新增帳務', style: TextStyle(fontSize: fontSize)),
              backgroundColor: Colors.black87, // 配合您的黑白簡約風格
              foregroundColor: Colors.white,
            )
          : null,
    );
  }
  // 頁面切換邏輯函式
  Widget _buildPageContent(int index) {
    // 取得設定以便 placeholder 使用一致的字體大小
    final settings = context.watch<SettingsProvider>();
    final fontSize = settings.fontSize;

    switch (index) {
      case 0:
        // 首頁 (記帳看板)
        return _DashboardView(
          transactions: _recentTransactions,
          isLoading: _isLoading,
        );
      case 1:
        // 歷史記錄頁
        return const HistoryPage(); 
      case 2:
        // 分析頁
        return const AnalysisPage();
      case 3:
        // 設定頁
        return const SettingsPage();
      default:
        return const Center(child: Text('未知頁面'));
    }
  }
}

// --- 記帳頁籤的內容視圖 (Dashboard) ---
class _DashboardView extends StatefulWidget {
  final List<StockTransaction> transactions;
  final bool isLoading;
  const _DashboardView({super.key, required this.transactions, required this.isLoading});

  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView> {
  bool _isListExpanded = false; // 控制 "..." 展開/收合的狀態
  int _touchedIndex = -1; // (選用) 控制圓餅圖點擊效果

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final fontSize = settings.fontSize;
    final assetProvider = context.watch<AssetProvider>();
    final snapshot = assetProvider.snapshot;
    final numberFormat = NumberFormat("#,##0");

    // 若資料還在讀取或是空的，顯示預設畫面
    if (assetProvider.isLoading || snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // 1. 準備數據
    final double totalAssets = snapshot.totalAssets.toDouble();
    final double cashValue = snapshot.totalCashBalance.toDouble();
    final double totalStockValue = snapshot.totalMarketValue.toDouble();
    
    // 2. 股票排序 (由大到小)
    final List<StockPosition> sortedStocks = List.from(snapshot.positions);
    sortedStocks.sort((a, b) => b.marketValue.compareTo(a.marketValue));

    // 3. 定義顏色池 (18種顏色，除了現金固定藍色外，其他股票依序取色)
    final List<Color> stockColors = [
      Colors.purple, Colors.orange, Colors.green, Colors.red,
      Colors.teal, Colors.amber, Colors.indigo, Colors.brown,
      Colors.pink, Colors.cyan, Colors.lime, Colors.deepPurple,
      Colors.lightBlue, Colors.blueGrey, Colors.deepOrange, Colors.lightGreen,
      const Color(0xFF8D6E63), const Color(0xFFFFD54F),
    ];

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === 上半部：資產資訊卡 ===
          SizedBox(
            // 高度根據列表展開狀況微調，或設為 null 讓其自適應 (建議自適應)
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 圓餅圖 (Pie Chart)
                Expanded(
                  flex: 13, // 1.3
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: totalAssets <= 0 
                    ? _buildEmptyChart(fontSize) // 若無資產顯示空圖
                    : PieChart(
                      PieChartData(
                        pieTouchData: PieTouchData(
                          touchCallback: (FlTouchEvent event, pieTouchResponse) {
                            setState(() {
                              if (!event.isInterestedForInteractions ||
                                  pieTouchResponse == null ||
                                  pieTouchResponse.touchedSection == null) {
                                _touchedIndex = -1;
                                return;
                              }
                              _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                            });
                          },
                        ),
                        borderData: FlBorderData(show: false),
                        sectionsSpace: 2, // 扇形之間的間隙
                        centerSpaceRadius: 30, // 中間挖空的半徑 (甜甜圈圖)
                        sections: _generatePieSections(
                          cashValue, 
                          sortedStocks, 
                          totalAssets, 
                          stockColors, 
                          fontSize
                        ),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(width: 24),

                // 2. 資產比例列表 (Legend List)
                Expanded(
                  flex: 35, //3.5
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('現有資產比例:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize)),
                      const SizedBox(height: 8),
                      
                      // A. 現金 (固定顯示)
                      if (cashValue > 0)
                        _buildAssetRow(
                          '現金', 
                          cashValue, 
                          totalAssets, 
                          Colors.blue, // 現金固定藍色
                          fontSize
                        ),

                      // B. 股票列表 (前3名 + 展開邏輯)
                      ..._buildStockList(sortedStocks, totalAssets, stockColors, fontSize),
                      
                    ],
                  ),
                ),

                // 3. 現有資產總市值 (靠右)
                Expanded(
                  flex: 30, //3.0
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('現有資產總市值', style: TextStyle(fontSize: fontSize, color: Colors.grey[700])),
                      Text(
                        '\$${numberFormat.format(totalAssets)}',
                        style: TextStyle(
                          fontSize: fontSize + 12, // 大字體
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 顯示總未實現損益
                      _buildProfitText(snapshot.totalUnrealizedProfit, settings),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(height: 48, thickness: 2),

          // === 下半部：近三日帳務列表 (維持原本邏輯) ===
          Text('近三日帳務資料', style: TextStyle(fontSize: fontSize + 2, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          
          // 表頭
          _buildListHeader(fontSize),
          const Divider(),

          // 列表內容
          Expanded(
            child: widget.isLoading
                ? const Center(child: CircularProgressIndicator())
                : widget.transactions.isEmpty
                    ? Center(child: Text('尚無資料', style: TextStyle(fontSize: fontSize)))
                    : ListView.separated(
                        itemCount: widget.transactions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          return _buildTransactionRow(widget.transactions[index], settings, numberFormat);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // --- 邏輯：生成圓餅圖區塊 ---
  List<PieChartSectionData> _generatePieSections(
    double cashValue, 
    List<StockPosition> stocks, 
    double totalAssets, 
    List<Color> colors,
    double fontSize
  ) {
    List<PieChartSectionData> sections = [];
    
    // 1. 現金區塊
    if (cashValue > 0) {
      final isTouched = _touchedIndex == 0;
      final radius = isTouched ? 30.0 : 20.0; // 點擊變大
      sections.add(PieChartSectionData(
        color: Colors.blue,
        value: cashValue,
        showTitle: false,
        radius: radius,
      ));
    }

    // 2. 股票區塊
    for (int i = 0; i < stocks.length; i++) {
      final stock = stocks[i];
      final isTouched = _touchedIndex == (cashValue > 0 ? i + 1 : i);
      final radius = isTouched ? 30.0 : 20.0;
      
      // 顏色循環使用
      final color = colors[i % colors.length];

      sections.add(PieChartSectionData(
        color: color,
        value: stock.marketValue.toDouble(),
        showTitle: false,
        radius: radius,
      ));
    }
    return sections;
  }

  // --- 邏輯：生成股票列表 (Top 3 + Expand) ---
  List<Widget> _buildStockList(
    List<StockPosition> stocks, 
    double totalAssets, 
    List<Color> colors, 
    double fontSize
  ) {
    List<Widget> listWidgets = [];
    
    // 決定要顯示幾筆
    // 展開顯示全部；未展開最多顯示 3 筆
    int showCount = _isListExpanded ? stocks.length : (stocks.length > 3 ? 3 : stocks.length);

    for (int i = 0; i < showCount; i++) {
      final stock = stocks[i];
      final color = colors[i % colors.length]; // 確保跟圓餅圖顏色一致
      
      listWidgets.add(_buildAssetRow(
        stock.stockName, // 顯示名稱
        stock.marketValue.toDouble(), 
        totalAssets, 
        color, 
        fontSize
      ));
    }

    // 股票總數超過 3 筆，顯示 "..." 按鈕
    if (stocks.length > 3) {
      listWidgets.add(
        InkWell(
          onTap: () {
            setState(() {
              _isListExpanded = !_isListExpanded; // 切換狀態
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center, // 置中
              children: [
                Icon(
                  _isListExpanded ? Icons.expand_less : Icons.expand_more, 
                  color: Colors.grey,
                  size: fontSize + 4,
                ),
                Text(
                  _isListExpanded ? '收合' : '...', 
                  style: TextStyle(color: Colors.grey, fontSize: fontSize, fontWeight: FontWeight.bold)
                ),
              ],
            ),
          ),
        )
      );
    }

    return listWidgets;
  }

  // --- UI 元件：單列資產比例 ---
  Widget _buildAssetRow(String name, double value, double total, Color color, double fontSize) {
    final percent = (value / total * 100).toStringAsFixed(2);
    final valueStr = NumberFormat("#,##0").format(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          // 色塊
          Container(
            width: 12, 
            height: 12, 
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          // 名稱
          Expanded(
            child: Text(name, style: TextStyle(fontSize: fontSize - 2), overflow: TextOverflow.ellipsis),
          ),
          // 比例
          Text('\$$valueStr ($percent%)', style: TextStyle(fontSize: fontSize - 2, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // --- UI 元件：損益顯示 ---
  Widget _buildProfitText(Decimal profitDec, SettingsProvider settings) {
    final fontSize = settings.fontSize;
    double profit = profitDec.toDouble();
    String prefix = profit > 0 ? '+' : '';
    Color color = profit > 0 
        ? settings.buyColor  // 賺錢用買入色 (紅/綠)
        : (profit < 0 ? settings.sellColor : Colors.grey); // 賠錢用賣出色

    return Text(
      '未實現: $prefix${NumberFormat("#,##0").format(profit)}',
      style: TextStyle(
        fontSize: fontSize,
        color: color,
        fontWeight: FontWeight.bold
      ),
    );
  }
  
  // --- UI 元件：空圖表 ---
  Widget _buildEmptyChart(double fontSize) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey[300]!, width: 20),
      ),
      child: Center(
        child: Text(
          '尚無\n資產',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: fontSize - 2),
        ),
      ),
    );
  }

  // --- UI 元件: 列表表頭 ---
  Widget _buildListHeader(double fontSize) {
    TextStyle headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize - 2, color: Colors.grey[700]);
    return Row(
      children: [
        Expanded(flex: 2, child: Text('日期', style: headerStyle)),
        Expanded(flex: 2, child: Text('股票代號及名稱', style: headerStyle)),
        Expanded(flex: 1, child: Text('價格', style: headerStyle, textAlign: TextAlign.right)),
        Expanded(flex: 1, child: Text('股數', style: headerStyle, textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text('手續費(已含稅)', style: headerStyle, textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text('總金額', style: headerStyle, textAlign: TextAlign.right)),
        Expanded(flex: 5, child: Text('備註', style: headerStyle, textAlign: TextAlign.center)),
      ],
    );
  }

  // --- UI 元件: 單筆交易列 ---
  Widget _buildTransactionRow(StockTransaction tx, SettingsProvider settings, NumberFormat fmt) {
    // 判斷顏色
    Color mainColor;
    String tagText;
    final fontSize = settings.fontSize;

    if (tx.tradeType == 'CASH_DIVIDEND') {
        // 1. 現金股利：藍色
        mainColor = Colors.blue; 
        tagText = '現金股利';
    } else if (tx.tradeType == 'STOCK_DIVIDEND') {
        // 2. 股票股利：橘色
        mainColor = Colors.orange; 
        tagText = '股票股利';
    } else if (tx.tradeType == 'DEPOSIT') {
        // 3. 入金：紫色
        mainColor = Colors.purple;
        tagText = '入金';
    } else if (tx.tradeType == 'WITHDRAWAL') {
        // 4. 出金：咖啡色
        mainColor = Colors.brown;
        tagText = '出金';
    } else {
        // 5. 一般買賣：依據設定 (紅/綠)
        final isBuy = tx.type == 'BUY';
        mainColor = isBuy ? settings.buyColor : settings.sellColor;
        
        final isDayTrade = tx.tradeType == 'DAY_TRADE';
        tagText = isDayTrade ? '當沖${isBuy ? "買" : "賣"}' : '${isBuy ? "現股買" : "現股賣"}';
    }
    
    // 格式化數字
    final priceStr = fmt.format(double.tryParse(tx.price.toString()) ?? 0);
    final sharesStr = fmt.format(double.tryParse(tx.shares.toString()) ?? 0);
    final feeStr = fmt.format(double.tryParse(tx.fee.toString()) ?? 0);
    final totalStr = fmt.format(double.tryParse(tx.totalAmount.toString()) ?? 0);
    final dateStr = DateFormat('yyyy/MM/dd').format(tx.date);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          // 1. 日期
          Expanded(
            flex: 2,
            child: Text(dateStr, style: TextStyle(fontSize: fontSize)),
          ),
          
          // 2. 代號名稱 + 標籤
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${tx.stockCode} ${tx.stockName}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize)),
                // 小標籤 (如草稿圖所示：紅色小字)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: mainColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    tagText,
                    style: TextStyle(color: mainColor, fontSize: fontSize - 4, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          
          // 3. 價格
          Expanded(
            flex: 1,
            child: Text(priceStr, textAlign: TextAlign.right, style: TextStyle(fontSize: fontSize)),
          ),
          
          // 4. 股數
          Expanded(
            flex: 1,
            child: Text(sharesStr, textAlign: TextAlign.right, style: TextStyle(fontSize: fontSize)),
          ),

          // 5. 手續費
          Expanded(
            flex: 2,
            child: Text(feeStr, textAlign: TextAlign.right, style: TextStyle(fontSize: fontSize - 2, color: Colors.grey)),
          ),

          // 6. 總金額
          Expanded(
            flex: 2,
            child: Text(
              totalStr, 
              textAlign: TextAlign.right, 
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                color: mainColor, // 總金額跟著買賣顏色變
                fontSize: fontSize
              ),
            ),
          ),

          // 7. 備註
          Expanded(
            flex: 5, 
            child: Padding(
              padding:  EdgeInsets.zero,
              child: Tooltip(
                // Tooltip: 滑鼠移上去或長按可以看到「完整」備註
                message: tx.note ?? '', 
                child: Text(
                  // 字串截斷邏輯
                  _truncateString(tx.note ?? '', 8), // 設定限制 8 個字

                  style: TextStyle(
                    fontSize: fontSize, 
                    color: Colors.grey[700]
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis, 
                  maxLines: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 輔助函式：如果字串太長，就截斷並加上 "..."
  String _truncateString(String text, int limit) {
  if (text.length <= limit) {
    return text;
  }
    return '${text.substring(0, limit)}...';
  }
}