import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:decimal/decimal.dart';
import 'package:syncfusion_flutter_charts/charts.dart'; 
import '../database/db_helper.dart';
import '../providers/settings_provider.dart';
import '../widgets/custom_date_picker.dart';
import '../widgets/custom_tooltip.dart';
import '../widgets/period_total_widget.dart';


class DayTradeChartData {
  DayTradeChartData(this.date, this.profit);
  final DateTime date;
  Decimal profit; // 淨損益
}

class CashFlowChartData {
  CashFlowChartData(this.date, this.deposit, this.withdrawal, this.dividend);
  final DateTime date;
  Decimal deposit;     // 入金 (+)
  Decimal withdrawal;  // 出金 (-)
  Decimal dividend;    // 現金股利 (+)

  // 根據勾選狀態，動態計算該時間段的「淨金流」
  Decimal getNetTotal(bool showDep, bool showWd, bool showDiv) {
    Decimal total = Decimal.zero;
    if (showDep) total += deposit;
    if (showWd) total += withdrawal; // 出金本身存為負數，所以直接加
    if (showDiv) total += dividend;
    return total;
  }
}

// --- 隱藏成本看板專用資料模型 ---
class HiddenCostChartData {
  HiddenCostChartData(this.date, this.fee, this.tax);
  final DateTime date;
  Decimal fee; // 手續費
  Decimal tax; // 證交稅

  // 計算單一柱狀體的總成本
  Decimal get total => fee + tax;
}

class RealizedProfitChartData {
  RealizedProfitChartData(this.date, this.profit);
  final DateTime date;
  Decimal profit; // 淨損益
}

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  // 控制外層是否允許滑動
  bool _isChartHovered = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final fontSize = settings.fontSize;

    return Scaffold(
      // 根據游標位置動態切換 ScrollPhysics
      body: SingleChildScrollView(
        physics: _isChartHovered 
            ? const NeverScrollableScrollPhysics() // 游標在圖表上時，鎖死外層滑動
            : const AlwaysScrollableScrollPhysics(), // 否則正常滑動
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 現金流與股利收入區塊
            CashFlowSection(
              onHoverChanged: (isHovered) {
                // 接收子元件傳來的游標狀態並更新畫面
                setState(() => _isChartHovered = isHovered);
              },
            ),
            const Divider(height: 64, thickness: 2),

            // 2. 當沖績效看板區塊
            DayTradeSection(
              onHoverChanged: (isHovered) {
                setState(() => _isChartHovered = isHovered);
              },
            ),
            const Divider(height: 64, thickness: 2),

            // 3. 隱藏成本區塊
            HiddenCostSection(
              onHoverChanged: (isHovered) {
                setState(() => _isChartHovered = isHovered);
              },
            ),
            const Divider(height: 64, thickness: 2),

            // 4. 每月已實現損益區塊 (預留位置)
            RealizedProfitSection(
              onHoverChanged: (isHovered) {
                setState(() => _isChartHovered = isHovered);
              },
            ),
          ],
        ),
      ),
    );
  }
}



// ============================================================================
// 區塊 1：現金流與股利收入
// ============================================================================
class CashFlowSection extends StatefulWidget {
  final ValueChanged<bool> onHoverChanged;
  const CashFlowSection({super.key, required this.onHoverChanged});
  

  @override
  State<CashFlowSection> createState() => _CashFlowSectionState();
}

class _CashFlowSectionState extends State<CashFlowSection> {
  // 狀態管理
  TimeUnit _selectedUnit = TimeUnit.day; // 預設為「日」
  DateTime _startDate = DateTime(DateTime.now().year, 1, 1);
  DateTime _endDate = DateTime.now();
  
  // Checkbox 狀態
  bool _showDeposit = true;
  bool _showWithdrawal = true;
  bool _showCashDiv = true;

  // 圖表平移與縮放控制器
  late ZoomPanBehavior _zoomPanBehavior;
  late TooltipBehavior _tooltipBehavior;

  List<CashFlowChartData> _chartData = [];
  bool _isLoading = true;
  @override
  void initState() {
    super.initState();
    // 初始化縮放與平移行為
    _zoomPanBehavior = ZoomPanBehavior(
      enablePinching: true, // 允許兩指縮放
      enablePanning: true,  // 允許單指左右拖拉
      enableMouseWheelZooming: true, // 允許滑鼠滾輪縮放
      zoomMode: ZoomMode.x, // 限制只能 X 軸 (時間) 縮放平移，Y軸(金額)固定不動
    );
    _tooltipBehavior = TooltipBehavior(
      enable: true,
      // 當游標碰到柱子時，觸發自訂的畫面
      builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) {
        final CashFlowChartData d = data;
        return _buildCustomTooltip(d);
      },
    );
    _loadChartData();
  }

  Future<void> _loadChartData() async {
    setState(() => _isLoading = true);
    final db = await DatabaseHelper.instance.database;

    // 1. 撈出選定區間內所有的現金流交易
    final sql = '''
      SELECT date, trade_type, total_amount
      FROM transactions
      WHERE date >= ? AND date <= ?
        AND trade_type IN ('DEPOSIT', 'WITHDRAWAL', 'CASH_DIVIDEND')
    ''';

    final results = await db.rawQuery(sql, [
      _startDate.toIso8601String(),
      _endDate.toIso8601String()
    ]);

    // 2. 使用 Map 來合併同一時間單位的資料
    Map<String, CashFlowChartData> groupedData = {};

    for (var row in results) {
      String rawDate = row['date'] as String;
      DateTime parsedDate = DateTime.parse(rawDate);
      
      // 根據選定的單位產生 Group Key 與對齊的時間點
      String groupKey;
      DateTime alignDate;
      
      if (_selectedUnit == TimeUnit.year) {
        groupKey = '${parsedDate.year}';
        alignDate = DateTime(parsedDate.year, 1, 1);
      } else if (_selectedUnit == TimeUnit.month) {
        groupKey = '${parsedDate.year}-${parsedDate.month.toString().padLeft(2, '0')}';
        alignDate = DateTime(parsedDate.year, parsedDate.month, 1);
      } else {
        groupKey = '${parsedDate.year}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}';
        alignDate = DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
      }

      // 取得金額 (轉為 Decimal)
      Decimal amount = Decimal.tryParse(row['total_amount'].toString()) ?? Decimal.zero;
      String tradeType = row['trade_type'] as String;

      // 如果 Map 裡還沒有這個時間點，先初始化
      if (!groupedData.containsKey(groupKey)) {
        groupedData[groupKey] = CashFlowChartData(alignDate, Decimal.zero, Decimal.zero, Decimal.zero);
      }

      // 累加數值 (合併到同一根柱子)
      if (tradeType == 'DEPOSIT') {
        groupedData[groupKey]!.deposit += amount;
      } else if (tradeType == 'WITHDRAWAL') {
        groupedData[groupKey]!.withdrawal -= amount; // 出金存為負數向下畫
      } else if (tradeType == 'CASH_DIVIDEND') {
        groupedData[groupKey]!.dividend += amount;
      }
    }

    // 3. 將 Map 轉為 List 並確保按時間排序
    List<CashFlowChartData> newData = groupedData.values.toList();
    newData.sort((a, b) => a.date.compareTo(b.date));

    if (mounted) {
      setState(() {
        _chartData = newData;
        _isLoading = false;
      });
    }
  }

  // --- 動態日期選擇器邏輯 ---
  Future<void> _pickDateRange() async {
    final picked = await CustomDatePicker.show(
      context: context,
      initialStart: _startDate,
      initialEnd: _endDate,
      unit: _selectedUnit,
    );
    
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadChartData(); // 重撈資料
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final fontSize = settings.fontSize;

    Decimal periodNetTotal = Decimal.zero;
    for (var data in _chartData) {
      periodNetTotal += data.getNetTotal(_showDeposit, _showWithdrawal, _showCashDiv);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('現金流與股利收入', style: TextStyle(fontSize: fontSize + 2, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左側：圖表區塊 (佔 6 成寬度)
            Expanded(
              flex: 6,
              child: MouseRegion(
                onEnter: (_) => widget.onHoverChanged(true),  // 滑鼠進入圖表區：鎖定外層
                onExit: (_) => widget.onHoverChanged(false),  // 滑鼠離開圖表區：解鎖外層
                child: Container(
                  height: 350, 
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!, width: 1),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                  ),
                  padding: const EdgeInsets.all(8.0),
                  child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SfCartesianChart(
                      zoomPanBehavior: _zoomPanBehavior, 
                      tooltipBehavior: _tooltipBehavior,
                      primaryXAxis: DateTimeCategoryAxis(
                        dateFormat: _selectedUnit == TimeUnit.year
                            ? DateFormat('yyyy')
                            : (_selectedUnit == TimeUnit.month
                                ? DateFormat('yyyy/MM') 
                                : DateFormat('yyyy/MM/dd')),
                        majorGridLines: const MajorGridLines(width: 0),
                        labelPlacement: LabelPlacement.betweenTicks,
                        labelStyle: TextStyle(
                            fontSize: fontSize - 2, 
                            fontWeight: FontWeight.bold, 
                            color: Colors.black87,
                        ),
                      ),
                      primaryYAxis: NumericAxis(
                        numberFormat: NumberFormat.compact(), 
                        axisLine: const AxisLine(width: 0), 
                        labelStyle: TextStyle(
                            fontSize: fontSize - 2, 
                            fontWeight: FontWeight.bold, 
                            color: Colors.black87,
                        ),
                      ),
                      // 使用 StackedColumnSeries 疊加式柱狀圖
                      series: <CartesianSeries>[
                        // 1. 入金 (向上生長)
                        if (_showDeposit)
                          StackedColumnSeries<CashFlowChartData, DateTime>(
                            name: '入金',
                            dataSource: _chartData,
                            xValueMapper: (CashFlowChartData data, _) => data.date,
                            yValueMapper: (CashFlowChartData data, _) => data.deposit.toDouble(),
                            color: Colors.purple, // 配合您的介面配色
                          ),
                        // 2. 現金股利 (向上生長，疊在入金上面)
                        if (_showCashDiv)
                          StackedColumnSeries<CashFlowChartData, DateTime>(
                            name: '現金股利',
                            dataSource: _chartData,
                            xValueMapper: (CashFlowChartData data, _) => data.date,
                            yValueMapper: (CashFlowChartData data, _) => data.dividend.toDouble(),
                            color: Colors.blue,
                          ),
                        // 3. 出金 (向下生長)
                        if (_showWithdrawal)
                          StackedColumnSeries<CashFlowChartData, DateTime>(
                            name: '出金',
                            dataSource: _chartData,
                            xValueMapper: (CashFlowChartData data, _) => data.date,
                            yValueMapper: (CashFlowChartData data, _) => data.withdrawal.toDouble(),
                            color: Colors.brown,
                          ),
                        ],
                    ),
                ),
              ),
            ),
            
            const SizedBox(width: 24),
            
            // 右側：控制區塊 (佔 4 成寬度)
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 日期區間選擇按鈕
                  OutlinedButton.icon(
                    onPressed: _pickDateRange,
                    icon: const Icon(Icons.date_range, color: Colors.black87),
                    label: Text(CustomDatePicker.getFormattedString(_startDate, _endDate, _selectedUnit), style: TextStyle(fontSize: fontSize, color: Colors.black87)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      side: const BorderSide(color: Colors.black87, width: 2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 2. 時間間隔單位 (Radio)
                  Text('時間間隔單位', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
                  TimeUnitRadioGroup(
                    currentUnit: _selectedUnit,
                    fontSize: fontSize,
                    onUnitChanged: (newUnit) {
                        setState(() {
                          _selectedUnit = newUnit;
                          // 呼叫共用工具來對齊時間
                          final aligned = CustomDatePicker.alignDates(_startDate, _endDate, newUnit);
                          _startDate = aligned.start;
                          _endDate = aligned.end;
                        });
                        _loadChartData(); // 切換單位後自動重撈資料
                    },
                  ),
                  const SizedBox(height: 24),

                  // 3. 顯示圖表過濾器 (Checkbox)
                  Text('顯示圖表', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildCheckbox('入金', _showDeposit, (v) => setState(() => _showDeposit = v!))),
                          Expanded(child: _buildCheckbox('出金', _showWithdrawal, (v) => setState(() => _showWithdrawal = v!))),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(child: _buildCheckbox('現金股利', _showCashDiv, (v) => setState(() => _showCashDiv = v!))),
                          const Expanded(child: SizedBox()),
                        ],
                      ),
                    ],
                  ),
                  PeriodTotalWidget(
                    title: '區間總金流',
                    amount: periodNetTotal,
                    fontSize: fontSize,
                    // 記帳習慣：正向金流為綠色，負向金流為紅色
                    positiveColor: Colors.green[700]!, 
                    negativeColor: Colors.red[700]!,
                  ),
                ],
              ),
            )
          ],
        )
      ],
    );
  }

  // --- UI 元件：自訂浮動提示框 (Tooltip) ---
  Widget _buildCustomTooltip(CashFlowChartData data) {
    final fmt = NumberFormat("#,##0");
    final fontSize = context.read<SettingsProvider>().fontSize;
    
    // 計算總金流 (依據目前打勾的項目)
    Decimal netTotal = data.getNetTotal(_showDeposit, _showWithdrawal, _showCashDiv);

    // 格式化標題時間
    String timeLabel;
    if (_selectedUnit == TimeUnit.year) {
      timeLabel = "${data.date.year}年";
    } else if (_selectedUnit == TimeUnit.month) {
      timeLabel = "${data.date.year}年${data.date.month}月";
    } else {
      timeLabel = DateFormat('yyyy/MM/dd').format(data.date);
    }

    // 呼叫共用的 Tooltip 外殼
    return CustomTooltip(
      title: timeLabel,
      fontSize: fontSize,
      children: [
        if (_showDeposit && data.deposit != Decimal.zero) 
          Text('入金: ${fmt.format(data.deposit.toDouble())}', style: TextStyle(color: Colors.purple[200], fontSize: fontSize - 2)),
        
        if (_showCashDiv && data.dividend != Decimal.zero) 
          Text('現金股利: ${fmt.format(data.dividend.toDouble())}', style: TextStyle(color: Colors.blue[200], fontSize: fontSize - 2)),
        
        if (_showWithdrawal && data.withdrawal != Decimal.zero) 
          Text('出金: ${fmt.format(data.withdrawal.abs().toDouble())}', style: TextStyle(color: Colors.brown[200], fontSize: fontSize - 2)),
        
        const Divider(color: Colors.white54, height: 16),
        
        Text('總金流: ${fmt.format(netTotal.toDouble())}', 
          style: TextStyle(
            color: netTotal >= Decimal.zero ? Colors.greenAccent : Colors.redAccent, 
            fontWeight: FontWeight.bold, 
            fontSize: fontSize
          )
        ),
      ],
    );
  }

  // 輔助函式：建立 Checkbox
  Widget _buildCheckbox(String label, bool value, ValueChanged<bool?> onChanged) {
    final fontSize = context.read<SettingsProvider>().fontSize;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.black87,
        ),
        Text(label, style: TextStyle(fontSize: fontSize)),
      ],
    );
  }
}



// ============================================================================
// 區塊 2：當沖績效看板
// ============================================================================
class DayTradeSection extends StatefulWidget {
  final ValueChanged<bool> onHoverChanged;
  const DayTradeSection({super.key, required this.onHoverChanged});

  @override
  State<DayTradeSection> createState() => _DayTradeSectionState();
}

class _DayTradeSectionState extends State<DayTradeSection> {
  // --- 獨立狀態管理 ---
  TimeUnit _selectedUnit = TimeUnit.day; 
  DateTime _startDate = DateTime(DateTime.now().year, 1, 1);
  DateTime _endDate = DateTime.now();
  
  // 個股過濾
  String _selectedStockCode = 'ALL';
  List<Map<String, String>> _availableStocks = [{'code': 'ALL', 'name': '全部'}];

  // 績效統計
  int _winCount = 0;
  int _totalCount = 0;
  Decimal _totalTax = Decimal.zero;

  late ZoomPanBehavior _zoomPanBehavior;
  late TooltipBehavior _tooltipBehavior; 

  List<DayTradeChartData> _chartData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _zoomPanBehavior = ZoomPanBehavior(
      enablePinching: true, 
      enablePanning: true,  
      enableMouseWheelZooming: true, 
      zoomMode: ZoomMode.x, 
    );

    _tooltipBehavior = TooltipBehavior(
      enable: true,
      builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) {
        return _buildCustomTooltip(data as DayTradeChartData);
      },
    );

    _loadAvailableStocks();
    _loadChartData();
  }

  // 載入有過當沖紀錄的股票選單
  Future<void> _loadAvailableStocks() async {
    final db = await DatabaseHelper.instance.database;
    final results = await db.rawQuery('''
      SELECT DISTINCT stock_code, stock_name 
      FROM transactions 
      WHERE trade_type = 'DAY_TRADE' 
      ORDER BY stock_code
    ''');

    List<Map<String, String>> stocks = [{'code': 'ALL', 'name': '全部'}];
    for (var row in results) {
      stocks.add({
        'code': row['stock_code'] as String,
        'name': row['stock_name'] as String,
      });
    }

    if (mounted) {
      setState(() {
        _availableStocks = stocks;
      });
    }
  }

  // ==========================================
  // 載入當沖資料與 FIFO 先進先出勝率計算
  // ==========================================
  Future<void> _loadChartData() async {
    setState(() => _isLoading = true);
    final db = await DatabaseHelper.instance.database;

    String sql = '''
      SELECT date, stock_code, type, price, shares, fee, total_amount
      FROM transactions
      WHERE trade_type = 'DAY_TRADE' 
        AND date >= ? AND date <= ?
    ''';
    
    List<dynamic> args = [_startDate.toIso8601String(), _endDate.toIso8601String()];

    if (_selectedStockCode != 'ALL') {
      sql += ' AND stock_code = ?';
      args.add(_selectedStockCode);
    }

    sql += ' ORDER BY date ASC, id ASC';

    final results = await db.rawQuery(sql, args);

    Map<String, DayTradeChartData> groupedChartData = {};
    Decimal accumulatedTax = Decimal.zero;
    int totalWins = 0;
    int totalRounds = 0;

    // 1. 將資料依「日期_股票代號」分組 (Day Trade Session)
    Map<String, List<Map<String, dynamic>>> sessions = {};
    for (var row in results) {
      String rawDate = row['date'] as String;
      String code = row['stock_code'] as String;
      String sessionKey = '${rawDate.substring(0, 10)}_$code';
      
      if (!sessions.containsKey(sessionKey)) {
        sessions[sessionKey] = [];
      }
      sessions[sessionKey]!.add(row);
    }

    // 輔助函式：取得較小的 Decimal (用於股數配對)
    Decimal minDecimal(Decimal a, Decimal b) => a < b ? a : b;

    // 2. 在每個 Session 內進行 FIFO 股數搓合
    sessions.forEach((sessionKey, rows) {
      // 將買與賣分開排隊
      List<Map<String, dynamic>> buys = rows.where((r) => r['type'] == 'BUY').toList();
      List<Map<String, dynamic>> sells = rows.where((r) => r['type'] == 'SELL').toList();

      if (buys.isEmpty || sells.isEmpty) return; // 如果只有買或只有賣(留倉)，則不構成當沖

      int bIdx = 0;
      int sIdx = 0;

      Decimal bSharesLeft = Decimal.tryParse(buys[0]['shares'].toString()) ?? Decimal.zero;
      Decimal sSharesLeft = Decimal.tryParse(sells[0]['shares'].toString()) ?? Decimal.zero;

      Decimal dailySessionProfit = Decimal.zero;

      // 當買賣佇列都還有股票可以搓合時
      while (bIdx < buys.length && sIdx < sells.length) {
        if (bSharesLeft <= Decimal.zero) {
          bIdx++;
          if (bIdx < buys.length) bSharesLeft = Decimal.tryParse(buys[bIdx]['shares'].toString()) ?? Decimal.zero;
          continue;
        }
        if (sSharesLeft <= Decimal.zero) {
          sIdx++;
          if (sIdx < sells.length) sSharesLeft = Decimal.tryParse(sells[sIdx]['shares'].toString()) ?? Decimal.zero;
          continue;
        }

        // 決定這次可以搓合多少股 (取買賣中較小的數量)
        Decimal matchShares = minDecimal(bSharesLeft, sSharesLeft);

        // --- 依比例計算成本與營收 ---
        Decimal origBShares = Decimal.tryParse(buys[bIdx]['shares'].toString()) ?? Decimal.one;
        Decimal bTotal = Decimal.tryParse(buys[bIdx]['total_amount'].toString()) ?? Decimal.zero;
        double bRatio = matchShares.toDouble() / origBShares.toDouble();
        // 四捨五入模擬券商計算，避免 Decimal 除法產生無限小數報錯
        Decimal matchedBuyCost = Decimal.fromInt((bTotal.toDouble() * bRatio).round());

        Decimal origSShares = Decimal.tryParse(sells[sIdx]['shares'].toString()) ?? Decimal.one;
        Decimal sTotal = Decimal.tryParse(sells[sIdx]['total_amount'].toString()) ?? Decimal.zero;
        double sRatio = matchShares.toDouble() / origSShares.toDouble();
        Decimal matchedSellRev = Decimal.fromInt((sTotal.toDouble() * sRatio).round());

        // --- 依比例計算這筆搓合的證交稅 ---
        Decimal sPrice = Decimal.tryParse(sells[sIdx]['price'].toString()) ?? Decimal.zero;
        Decimal sFee = Decimal.tryParse(sells[sIdx]['fee'].toString()) ?? Decimal.zero;
        // 反推整筆賣單的原始稅金
        Decimal origTax = (sPrice * origSShares) - sFee - sTotal; 
        Decimal matchedTax = Decimal.fromInt((origTax.toDouble() * sRatio).round());
        accumulatedTax += matchedTax;

        // --- 結算這一個「回合」的損益 ---
        Decimal profit = matchedSellRev - matchedBuyCost;
        dailySessionProfit += profit;
        
        totalRounds++; // 成功配對一次就算一回合 (1總交易)
        if (profit > Decimal.zero) totalWins++;

        // 扣除已經搓合掉的股數
        bSharesLeft -= matchShares;
        sSharesLeft -= matchShares;
      }

      // 3. 將今天這個 Session 的「已沖銷損益」加進圖表
      if (totalRounds > 0) {
        String datePart = sessionKey.split('_')[0]; 
        DateTime parsedDate = DateTime.parse(datePart);
        
        String groupKey;
        DateTime alignDate;
        if (_selectedUnit == TimeUnit.year) {
          groupKey = '${parsedDate.year}';
          alignDate = DateTime(parsedDate.year, 1, 1);
        } else if (_selectedUnit == TimeUnit.month) {
          groupKey = '${parsedDate.year}-${parsedDate.month}';
          alignDate = DateTime(parsedDate.year, parsedDate.month, 1);
        } else {
          groupKey = datePart;
          alignDate = parsedDate;
        }

        if (!groupedChartData.containsKey(groupKey)) {
          groupedChartData[groupKey] = DayTradeChartData(alignDate, Decimal.zero);
        }
        groupedChartData[groupKey]!.profit += dailySessionProfit;
      }
    });

    List<DayTradeChartData> newData = groupedChartData.values.toList();
    newData.sort((a, b) => a.date.compareTo(b.date));

    if (mounted) {
      setState(() {
        _chartData = newData;
        _winCount = totalWins;      
        _totalCount = totalRounds;  
        _totalTax = accumulatedTax;
        _isLoading = false;
      });
    }
  }

  // --- 呼叫共用日期選擇器 ---
  Future<void> _pickDateRange() async {
    final picked = await CustomDatePicker.show(
      context: context,
      initialStart: _startDate,
      initialEnd: _endDate,
      unit: _selectedUnit,
    );
    
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadChartData(); 
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final fontSize = settings.fontSize;
    final fmt = NumberFormat("#,##0");

    Decimal periodTotalProfit = Decimal.zero;
    for (var data in _chartData) {
      periodTotalProfit += data.profit;
    }

    double winRate = _totalCount == 0 ? 0 : (_winCount / _totalCount) * 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('當沖績效看板', style: TextStyle(fontSize: fontSize + 2, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左側：圖表區塊
            Expanded(
              flex: 6,
              child: MouseRegion(
                onEnter: (_) => widget.onHoverChanged(true),  
                onExit: (_) => widget.onHoverChanged(false),  
                child: Container(
                  height: 350, 
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!, width: 1),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                  ),
                  padding: const EdgeInsets.all(8.0),
                  child: _isLoading 
                    ? const Center(child: CircularProgressIndicator()) 
                    : SfCartesianChart(
                        zoomPanBehavior: _zoomPanBehavior, 
                        tooltipBehavior: _tooltipBehavior, 
                        primaryXAxis: DateTimeCategoryAxis(
                          dateFormat: _selectedUnit == TimeUnit.year 
                              ? DateFormat('yyyy') 
                              : (_selectedUnit == TimeUnit.month 
                                  ? DateFormat('yyyy/MM') 
                                  : DateFormat('yyyy/MM/dd')),
                          majorGridLines: const MajorGridLines(width: 0),
                          labelPlacement: LabelPlacement.betweenTicks,
                          labelStyle: TextStyle(
                            fontSize: fontSize - 2, 
                            fontWeight: FontWeight.bold, 
                            color: Colors.black87,
                          ),
                        ),
                        primaryYAxis: NumericAxis(
                          numberFormat: NumberFormat.compact(), 
                          axisLine: const AxisLine(width: 0), 
                          labelStyle: TextStyle(
                            fontSize: fontSize - 2, 
                            fontWeight: FontWeight.bold, 
                            color: Colors.black87,
                          ),
                        ),
                        
                        series: <CartesianSeries>[
                          ColumnSeries<DayTradeChartData, DateTime>(
                            name: '當沖損益',
                            dataSource: _chartData,
                            xValueMapper: (DayTradeChartData data, _) => data.date,
                            yValueMapper: (DayTradeChartData data, _) => data.profit.toDouble(),
                            pointColorMapper: (DayTradeChartData data, _) => 
                                data.profit >= Decimal.zero ? settings.buyColor : settings.sellColor,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ],
                      ),
                ),
              ),
            ),
            
            const SizedBox(width: 24),
            
            // 右側：控制區塊
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 日期區間選擇按鈕 (使用共用工具格式化文字)
                  OutlinedButton.icon(
                    onPressed: _pickDateRange,
                    icon: const Icon(Icons.date_range, color: Colors.black87),
                    label: Text(
                      CustomDatePicker.getFormattedString(_startDate, _endDate, _selectedUnit), 
                      style: TextStyle(fontSize: fontSize, color: Colors.black87)
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      side: const BorderSide(color: Colors.black87, width: 2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text('時間間隔單位', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
                  
                  // 2. 時間單位 Radio (使用共用 Widget)
                  TimeUnitRadioGroup(
                    currentUnit: _selectedUnit,
                    fontSize: fontSize,
                    onUnitChanged: (newUnit) {
                      setState(() {
                        _selectedUnit = newUnit;
                        final aligned = CustomDatePicker.alignDates(_startDate, _endDate, newUnit);
                        _startDate = aligned.start;
                        _endDate = aligned.end;
                      });
                      _loadChartData(); 
                    },
                  ),
                  const SizedBox(height: 24),

                  Text('個股選擇', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  
                  // 個股下拉選單
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black87),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedStockCode,
                        items: _availableStocks.map((stock) {
                          String displayText = stock['code'] == 'ALL' 
                              ? stock['name']! 
                              : '${stock['code']} ${stock['name']}';
                          return DropdownMenuItem<String>(
                            value: stock['code'],
                            child: Text(displayText, style: TextStyle(fontSize: fontSize)),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() => _selectedStockCode = newValue);
                            _loadChartData(); 
                          }
                        },
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // 績效數據看板
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!)
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('勝率', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
                            Text('${winRate.toStringAsFixed(1)}%', style: TextStyle(fontSize: fontSize + 4, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('交易次數: $_winCount 勝 / $_totalCount 總交易', style: TextStyle(fontSize: fontSize - 2, color: Colors.grey[700])),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('總繳稅額', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
                            Text('\$${fmt.format(_totalTax.toDouble())}', style: TextStyle(fontSize: fontSize + 2, fontWeight: FontWeight.bold, color: Colors.black87)),
                          ],
                        ),

                        PeriodTotalWidget(
                          title: '區間總損益',
                          amount: periodTotalProfit,
                          fontSize: fontSize,
                          // 股市習慣：套用設定裡的「買入(紅)/賣出(綠)」顏色設定
                          positiveColor: settings.buyColor,
                          negativeColor: settings.sellColor,
                        ),
                      ],
                    ),
                  )
                ],
              ),
            )
          ],
        )
      ],
    );
  }

  // --- 使用共用 Tooltip ---
  Widget _buildCustomTooltip(DayTradeChartData data) {
    final fmt = NumberFormat("#,##0");
    final fontSize = context.read<SettingsProvider>().fontSize;
    final settings = context.read<SettingsProvider>();
    
    String timeLabel;
    if (_selectedUnit == TimeUnit.year) {
      timeLabel = "${data.date.year}年";
    } else if (_selectedUnit == TimeUnit.month) {
      timeLabel = "${data.date.year}年${data.date.month}月";
    } else {
      timeLabel = DateFormat('yyyy/MM/dd').format(data.date);
    }

    return CustomTooltip(
      title: timeLabel,
      fontSize: fontSize,
      children: [
        Text('淨損益: ${fmt.format(data.profit.toDouble())}', 
          style: TextStyle(
            color: data.profit >= Decimal.zero ? settings.buyColor : settings.sellColor, 
            fontWeight: FontWeight.bold, 
            fontSize: fontSize
          )
        ),
      ],
    );
  }
}




// ============================================================================
// 區塊 3：隱藏成本 (手續費與證交稅) 看板
// ============================================================================
class HiddenCostSection extends StatefulWidget {
  final ValueChanged<bool> onHoverChanged;
  const HiddenCostSection({super.key, required this.onHoverChanged});

  @override
  State<HiddenCostSection> createState() => _HiddenCostSectionState();
}

class _HiddenCostSectionState extends State<HiddenCostSection> {
  // --- 狀態管理 ---
  TimeUnit _selectedUnit = TimeUnit.day; 
  DateTime _startDate = DateTime(DateTime.now().year, 1, 1);
  DateTime _endDate = DateTime.now();
  
  late ZoomPanBehavior _zoomPanBehavior;
  late TooltipBehavior _tooltipBehavior; 

  List<HiddenCostChartData> _chartData = [];
  bool _isLoading = true;

  // 區間總計 (顯示於右側面板)
  Decimal _periodTotalFee = Decimal.zero;
  Decimal _periodTotalTax = Decimal.zero;

  @override
  void initState() {
    super.initState();
    _zoomPanBehavior = ZoomPanBehavior(
      enablePinching: true, 
      enablePanning: true,  
      enableMouseWheelZooming: true, 
      zoomMode: ZoomMode.x, 
    );

    _tooltipBehavior = TooltipBehavior(
      enable: true,
      builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) {
        return _buildCustomTooltip(data as HiddenCostChartData);
      },
    );

    _loadChartData();
  }

  // ==========================================
  // 載入資料並計算手續費與證交稅
  // ==========================================
  Future<void> _loadChartData() async {
    setState(() => _isLoading = true);
    final db = await DatabaseHelper.instance.database;

    // 撈出所有有買賣行為的交易 (排除股利、出入金)
    // 您的資料庫中，實際買賣股票會有 fee 欄位，且 type 為 BUY 或 SELL
    final sql = '''
      SELECT date, type, price, shares, fee, total_amount
      FROM transactions
      WHERE type IN ('BUY', 'SELL')
        AND date >= ? AND date <= ?
    ''';
    
    final results = await db.rawQuery(sql, [
      _startDate.toIso8601String(),
      _endDate.toIso8601String()
    ]);

    Map<String, HiddenCostChartData> groupedData = {};
    Decimal totalFee = Decimal.zero;
    Decimal totalTax = Decimal.zero;

    for (var row in results) {
      String rawDate = row['date'] as String;
      String type = row['type'] as String;
      
      Decimal price = Decimal.tryParse(row['price'].toString()) ?? Decimal.zero;
      Decimal shares = Decimal.tryParse(row['shares'].toString()) ?? Decimal.zero;
      Decimal fee = Decimal.tryParse(row['fee'].toString()) ?? Decimal.zero;
      Decimal totalAmount = Decimal.tryParse(row['total_amount'].toString()) ?? Decimal.zero;
      
      Decimal tax = Decimal.zero;
      
      // [關鍵邏輯] 只有「賣出」時才會被扣證交稅
      if (type == 'SELL') {
        Decimal rawAmount = price * shares;
        tax = rawAmount - fee - totalAmount; 
      }

      // 如果這筆交易既沒有手續費也沒有稅，就跳過不畫
      if (fee == Decimal.zero && tax == Decimal.zero) continue;

      totalFee += fee;
      totalTax += tax;

      // --- 處理時間分組 ---
      DateTime parsedDate = DateTime.parse(rawDate);
      String groupKey;
      DateTime alignDate;

      if (_selectedUnit == TimeUnit.year) {
        groupKey = '${parsedDate.year}';
        alignDate = DateTime(parsedDate.year, 1, 1);
      } else if (_selectedUnit == TimeUnit.month) {
        groupKey = '${parsedDate.year}-${parsedDate.month}';
        alignDate = DateTime(parsedDate.year, parsedDate.month, 1);
      } else {
        groupKey = '${parsedDate.year}-${parsedDate.month}-${parsedDate.day}';
        alignDate = DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
      }

      if (!groupedData.containsKey(groupKey)) {
        groupedData[groupKey] = HiddenCostChartData(alignDate, Decimal.zero, Decimal.zero);
      }
      
      groupedData[groupKey]!.fee += fee;
      groupedData[groupKey]!.tax += tax;
    }

    List<HiddenCostChartData> newData = groupedData.values.toList();
    newData.sort((a, b) => a.date.compareTo(b.date));

    if (mounted) {
      setState(() {
        _chartData = newData;
        _periodTotalFee = totalFee;
        _periodTotalTax = totalTax;
        _isLoading = false;
      });
    }
  }

  // --- 日期選擇器 ---
  Future<void> _pickDateRange() async {
    final picked = await CustomDatePicker.show(
      context: context,
      initialStart: _startDate,
      initialEnd: _endDate,
      unit: _selectedUnit,
    );
    
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadChartData(); 
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final fontSize = settings.fontSize;
    final fmt = NumberFormat("#,##0");

    // 建議顏色配置
    final Color feeColor = Colors.orange[600]!;
    final Color taxColor = Colors.indigo[400]!;
    final Decimal grandTotalCost = _periodTotalFee + _periodTotalTax;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('隱藏成本 (手續費與證交稅)', style: TextStyle(fontSize: fontSize + 2, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左側：圖表區塊
            Expanded(
              flex: 6,
              child: MouseRegion(
                onEnter: (_) => widget.onHoverChanged(true),  
                onExit: (_) => widget.onHoverChanged(false),  
                child: Container(
                  height: 350, 
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!, width: 1),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                  ),
                  padding: const EdgeInsets.all(8.0),
                  child: _isLoading 
                    ? const Center(child: CircularProgressIndicator()) 
                    : SfCartesianChart(
                        zoomPanBehavior: _zoomPanBehavior, 
                        tooltipBehavior: _tooltipBehavior, 
                        primaryXAxis: DateTimeCategoryAxis(
                          dateFormat: _selectedUnit == TimeUnit.year 
                              ? DateFormat('yyyy') 
                              : (_selectedUnit == TimeUnit.month 
                                  ? DateFormat('yyyy/MM') 
                                  : DateFormat('yyyy/MM/dd')),
                          majorGridLines: const MajorGridLines(width: 0),
                          labelPlacement: LabelPlacement.betweenTicks,
                          labelStyle: TextStyle(fontSize: fontSize - 2, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        primaryYAxis: NumericAxis(
                          numberFormat: NumberFormat.compact(), 
                          axisLine: const AxisLine(width: 0), 
                          labelStyle: TextStyle(fontSize: fontSize - 2, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        
                        // 使用疊加圖表 StackedColumnSeries，讓稅和手續費累加顯示高度
                        series: <CartesianSeries>[
                          StackedColumnSeries<HiddenCostChartData, DateTime>(
                            name: '手續費',
                            dataSource: _chartData,
                            xValueMapper: (HiddenCostChartData data, _) => data.date,
                            yValueMapper: (HiddenCostChartData data, _) => data.fee.toDouble(),
                            color: feeColor,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(0)), // 疊在下面不用圓角
                          ),
                          StackedColumnSeries<HiddenCostChartData, DateTime>(
                            name: '證交稅',
                            dataSource: _chartData,
                            xValueMapper: (HiddenCostChartData data, _) => data.date,
                            yValueMapper: (HiddenCostChartData data, _) => data.tax.toDouble(),
                            color: taxColor,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)), // 最上面要有圓角
                          ),
                        ],
                      ),
                ),
              ),
            ),
            
            const SizedBox(width: 24),
            
            // 右側：控制與總計區塊
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickDateRange,
                    icon: const Icon(Icons.date_range, color: Colors.black87),
                    label: Text(
                      CustomDatePicker.getFormattedString(_startDate, _endDate, _selectedUnit), 
                      style: TextStyle(fontSize: fontSize, color: Colors.black87)
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      side: const BorderSide(color: Colors.black87, width: 2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text('時間間隔單位', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
                  TimeUnitRadioGroup(
                    currentUnit: _selectedUnit,
                    fontSize: fontSize,
                    onUnitChanged: (newUnit) {
                      setState(() {
                        _selectedUnit = newUnit;
                        final aligned = CustomDatePicker.alignDates(_startDate, _endDate, newUnit);
                        _startDate = aligned.start;
                        _endDate = aligned.end;
                      });
                      _loadChartData(); 
                    },
                  ),
                  const SizedBox(height: 24),

                  // 區間成本數據看板 (符合草圖設計)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!)
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 共用總額 Widget，統一顯示大寫總額
                        PeriodTotalWidget(
                          title: '區間總成本',
                          amount: grandTotalCost,
                          fontSize: fontSize,
                          // 成本皆視為負面消耗，這裡設定統一顏色 (如警示紅)
                          positiveColor: Colors.redAccent, 
                          negativeColor: Colors.redAccent,
                        ),
                        const Divider(height: 24),
                        // 依照草圖顯示細項
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.circle, size: 12, color: feeColor),
                                const SizedBox(width: 8),
                                Text('手續費', style: TextStyle(fontSize: fontSize)),
                              ],
                            ),
                            Text('\$${fmt.format(_periodTotalFee.toDouble())}', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.circle, size: 12, color: taxColor),
                                const SizedBox(width: 8),
                                Text('證交稅', style: TextStyle(fontSize: fontSize)),
                              ],
                            ),
                            Text('\$${fmt.format(_periodTotalTax.toDouble())}', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  )
                ],
              ),
            )
          ],
        )
      ],
    );
  }

  // --- 使用共用的 Tooltip ---
  Widget _buildCustomTooltip(HiddenCostChartData data) {
    final fmt = NumberFormat("#,##0");
    final fontSize = context.read<SettingsProvider>().fontSize;
    
    String timeLabel;
    if (_selectedUnit == TimeUnit.year) {
      timeLabel = "${data.date.year}年";
    } else if (_selectedUnit == TimeUnit.month) {
      timeLabel = "${data.date.year}年${data.date.month}月";
    } else {
      timeLabel = DateFormat('yyyy/MM/dd').format(data.date);
    }

    return CustomTooltip(
      title: timeLabel,
      fontSize: fontSize,
      children: [
        if (data.fee > Decimal.zero)
          Text('手續費: \$${fmt.format(data.fee.toDouble())}', style: TextStyle(color: Colors.orange[300], fontSize: fontSize - 2)),
        
        if (data.tax > Decimal.zero)
          Text('證交稅: \$${fmt.format(data.tax.toDouble())}', style: TextStyle(color: Colors.indigo[300], fontSize: fontSize - 2)),
        
        const Divider(color: Colors.white54, height: 16),
        
        Text('總隱藏成本: \$${fmt.format(data.total.toDouble())}', 
          style: TextStyle(
            color: Colors.redAccent, // 成本屬消耗，統一標紅色
            fontWeight: FontWeight.bold, 
            fontSize: fontSize
          )
        ),
      ],
    );
  }
}




// ============================================================================
// 區塊 4：已實現損益看板
// ============================================================================
class RealizedProfitSection extends StatefulWidget {
  final ValueChanged<bool> onHoverChanged;
  const RealizedProfitSection({super.key, required this.onHoverChanged});

  @override
  State<RealizedProfitSection> createState() => _RealizedProfitSectionState();
}

class _RealizedProfitSectionState extends State<RealizedProfitSection> {
  // --- 狀態管理 ---
  TimeUnit _selectedUnit = TimeUnit.day; 
  DateTime _startDate = DateTime(DateTime.now().year, 1, 1);
  DateTime _endDate = DateTime.now();
  
  late ZoomPanBehavior _zoomPanBehavior;
  late TooltipBehavior _tooltipBehavior; 

  List<RealizedProfitChartData> _chartData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _zoomPanBehavior = ZoomPanBehavior(
      enablePinching: true, 
      enablePanning: true,  
      enableMouseWheelZooming: true, 
      zoomMode: ZoomMode.x, 
    );

    _tooltipBehavior = TooltipBehavior(
      enable: true,
      builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) {
        return _buildCustomTooltip(data as RealizedProfitChartData);
      },
    );

    _loadChartData();
  }

  // ==========================================
  // 載入資料：直接讀取引擎算好的 realized_profit
  // ==========================================
  Future<void> _loadChartData() async {
    setState(() => _isLoading = true);
    final db = await DatabaseHelper.instance.database;

    // 聯合查詢現股與當沖的損益
    // 1. 現股賣出：讀取引擎算好的 realized_profit
    // 2. 當沖賣出：視為正向現金流入 (+total_amount)
    // 3. 當沖買入：視為負向現金流出 (-total_amount)
    // 當沖買賣同日互抵後，剩下的淨額就會自動變成當沖已實現損益！
    final sql = '''
      SELECT date, realized_profit
      FROM transactions
      WHERE type = 'SELL' 
        AND trade_type IN ('SPOT', 'DAY_TRADE')
        AND date >= ? AND date <= ?
    ''';
    
    final results = await db.rawQuery(sql, [
      _startDate.toIso8601String(),
      _endDate.toIso8601String()
    ]);

    Map<String, RealizedProfitChartData> groupedData = {};

    for (var row in results) {
      String rawDate = row['date'] as String;
      Decimal profit = Decimal.tryParse(row['realized_profit'].toString()) ?? Decimal.zero;
      
      if (profit == Decimal.zero) continue;

      // --- 處理時間分組 ---
      DateTime parsedDate = DateTime.parse(rawDate);
      String groupKey;
      DateTime alignDate;

      if (_selectedUnit == TimeUnit.year) {
        groupKey = '${parsedDate.year}';
        alignDate = DateTime(parsedDate.year, 1, 1);
      } else if (_selectedUnit == TimeUnit.month) {
        groupKey = '${parsedDate.year}-${parsedDate.month}';
        alignDate = DateTime(parsedDate.year, parsedDate.month, 1);
      } else {
        groupKey = '${parsedDate.year}-${parsedDate.month}-${parsedDate.day}';
        alignDate = DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
      }

      if (!groupedData.containsKey(groupKey)) {
        groupedData[groupKey] = RealizedProfitChartData(alignDate, Decimal.zero);
      }
      
      // 合併同一時間單位的損益
      groupedData[groupKey]!.profit += profit;
    }

    List<RealizedProfitChartData> newData = groupedData.values.toList();
    newData.sort((a, b) => a.date.compareTo(b.date));

    if (mounted) {
      setState(() {
        _chartData = newData;
        _isLoading = false;
      });
    }
  }

  // --- 日期選擇器 ---
  Future<void> _pickDateRange() async {
    final picked = await CustomDatePicker.show(
      context: context,
      initialStart: _startDate,
      initialEnd: _endDate,
      unit: _selectedUnit,
    );
    
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadChartData(); 
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final fontSize = settings.fontSize;
    
    // 動態計算區間總損益
    Decimal periodTotalProfit = Decimal.zero;
    for (var data in _chartData) {
      periodTotalProfit += data.profit;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('已實現損益', style: TextStyle(fontSize: fontSize + 2, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左側：圖表區塊
            Expanded(
              flex: 6,
              child: MouseRegion(
                onEnter: (_) => widget.onHoverChanged(true),  
                onExit: (_) => widget.onHoverChanged(false),  
                child: Container(
                  height: 350, 
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!, width: 1),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                  ),
                  padding: const EdgeInsets.all(8.0),
                  child: _isLoading 
                    ? const Center(child: CircularProgressIndicator()) 
                    : SfCartesianChart(
                        zoomPanBehavior: _zoomPanBehavior, 
                        tooltipBehavior: _tooltipBehavior, 
                        primaryXAxis: DateTimeCategoryAxis(
                          dateFormat: _selectedUnit == TimeUnit.year 
                              ? DateFormat('yyyy') 
                              : (_selectedUnit == TimeUnit.month 
                                  ? DateFormat('yyyy/MM') 
                                  : DateFormat('yyyy/MM/dd')),
                          majorGridLines: const MajorGridLines(width: 0),
                          labelPlacement: LabelPlacement.betweenTicks,
                          labelStyle: TextStyle(fontSize: fontSize - 2, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        primaryYAxis: NumericAxis(
                          numberFormat: NumberFormat.compact(), 
                          axisLine: const AxisLine(width: 0), 
                          labelStyle: TextStyle(fontSize: fontSize - 2, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        
                        series: <CartesianSeries>[
                          ColumnSeries<RealizedProfitChartData, DateTime>(
                            name: '損益',
                            dataSource: _chartData,
                            xValueMapper: (RealizedProfitChartData data, _) => data.date,
                            yValueMapper: (RealizedProfitChartData data, _) => data.profit.toDouble(),
                            // 大於等於0標示買入色(紅/綠)，小於0標示賣出色
                            pointColorMapper: (RealizedProfitChartData data, _) => 
                                data.profit >= Decimal.zero ? settings.buyColor : settings.sellColor,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ],
                      ),
                ),
              ),
            ),
            
            const SizedBox(width: 24),
            
            // 右側：控制與總計區塊
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickDateRange,
                    icon: const Icon(Icons.date_range, color: Colors.black87),
                    label: Text(
                      CustomDatePicker.getFormattedString(_startDate, _endDate, _selectedUnit), 
                      style: TextStyle(fontSize: fontSize, color: Colors.black87)
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      side: const BorderSide(color: Colors.black87, width: 2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text('時間間隔單位', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
                  TimeUnitRadioGroup(
                    currentUnit: _selectedUnit,
                    fontSize: fontSize,
                    onUnitChanged: (newUnit) {
                      setState(() {
                        _selectedUnit = newUnit;
                        final aligned = CustomDatePicker.alignDates(_startDate, _endDate, newUnit);
                        _startDate = aligned.start;
                        _endDate = aligned.end;
                      });
                      _loadChartData(); 
                    },
                  ),
                  const SizedBox(height: 24),

                  // 區間總計數據看板
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!)
                    ),
                    child: PeriodTotalWidget(
                      title: '區間總損益',
                      amount: periodTotalProfit,
                      fontSize: fontSize,
                      // 使用設定裡的顏色 (符合台股紅綠邏輯)
                      positiveColor: settings.buyColor,
                      negativeColor: settings.sellColor,
                    ),
                  )
                ],
              ),
            )
          ],
        )
      ],
    );
  }

  // --- 使用共用的 Tooltip ---
  Widget _buildCustomTooltip(RealizedProfitChartData data) {
    final fmt = NumberFormat("#,##0");
    final fontSize = context.read<SettingsProvider>().fontSize;
    final settings = context.read<SettingsProvider>();
    
    String timeLabel;
    if (_selectedUnit == TimeUnit.year) {
      timeLabel = "${data.date.year}年";
    } else if (_selectedUnit == TimeUnit.month) {
      timeLabel = "${data.date.year}年${data.date.month}月";
    } else {
      timeLabel = DateFormat('yyyy/MM/dd').format(data.date);
    }

    return CustomTooltip(
      title: timeLabel,
      fontSize: fontSize,
      children: [
        Text('已實現損益: \$${fmt.format(data.profit.toDouble())}', 
          style: TextStyle(
            color: data.profit >= Decimal.zero ? settings.buyColor : settings.sellColor, 
            fontWeight: FontWeight.bold, 
            fontSize: fontSize
          )
        ),
      ],
    );
  }
}