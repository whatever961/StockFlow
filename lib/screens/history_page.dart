import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../database/db_helper.dart';
import '../models/transaction_model.dart';
import '../providers/settings_provider.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  // --- 狀態變數 ---
  bool _isLoading = true;
  List<StockTransaction> _transactions = [];
  
  // 搜尋與過濾
  final TextEditingController _searchController = TextEditingController();
  final List<String> _selectedFilters = []; // 存選中的 Filter Key
  
  // 分頁
  int _currentPage = 1;
  int _rowsPerPage = 10;
  int _totalRecords = 0;

  // 定義 Filter 選項
  final Map<String, String> _filterOptions = {
    'SPOT_BUY': '現股買',
    'SPOT_SELL': '現股賣',
    'DAY_BUY': '當沖買',
    'DAY_SELL': '當沖賣',
    'DEPOSIT': '入金',
    'WITHDRAWAL': '出金',
    'CASH_DIVIDEND': '現金股利',
    'STOCK_DIVIDEND': '股票股利',
  };

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  // --- 讀取資料 ---
  Future<void> _fetchData() async {
    setState(() => _isLoading = true);

    final offset = (_currentPage - 1) * _rowsPerPage;

    // 只呼叫一次 DB
    final result = await DatabaseHelper.instance.getTransactionsAndCount(
      keyword: _searchController.text,
      filters: _selectedFilters,
      limit: _rowsPerPage,
      offset: offset,
    );

    if (mounted) {
      setState(() {
        // 解構回傳的 Map
        _totalRecords = result['total'] as int;
        final dataList = result['data'] as List<Map<String, dynamic>>;
        _transactions = dataList.map((e) => StockTransaction.fromMap(e)).toList();
        _isLoading = false;
      });
    }
  }

  // 2. 顯示編輯備註的對話框
  void _showEditNoteDialog(StockTransaction tx) {
    final noteController = TextEditingController(text: tx.note);
    final settings = context.read<SettingsProvider>();
    final fontSize = settings.fontSize;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('編輯備註'),
          content: TextField(
            controller: noteController,
            autofocus: true, // 自動聚焦方便輸入
            decoration: const InputDecoration(
              hintText: '請輸入備註內容...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3, // 允許輸入多行
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                // 1. 更新資料庫
                await DatabaseHelper.instance.updateTransactionNote(tx.id, noteController.text);
                
                // 2. 關閉視窗並重新抓取資料以更新 UI
                if (mounted) {
                  Navigator.pop(context);
                  _fetchData(); 
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('備註已更新', style: TextStyle(fontSize: fontSize)), duration: Duration(milliseconds: 800)),
                  );
                }
              },
              child: const Text('儲存'),
            ),
          ],
        );
      },
    );
  }

  // --- UI 建構 ---
  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final fontSize = settings.fontSize;
    final totalPages = (_totalRecords / _rowsPerPage).ceil(); // 無條件進位

    return Column(
      children: [
        // === 1. 頂部控制列 (搜尋 | Filter | 每頁筆數) ===
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              // 搜尋欄
              Expanded(
                child: SizedBox(
                  // 稍微調整高度以適應大字體，或讓它自適應
                  height: fontSize * 3.0, 
                  child: TextField(
                    controller: _searchController,
                    // [修改] 輸入文字大小
                    style: TextStyle(fontSize: fontSize), 
                    decoration: InputDecoration(
                      labelText: '搜尋 (代號/名稱/備註/日期)',
                      // [修改] 標籤文字大小
                      labelStyle: TextStyle(fontSize: fontSize), 
                      border: const OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search, size: fontSize + 4), // Icon 跟著變大
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onSubmitted: (_) {
                      _currentPage = 1;
                      _fetchData();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              
              // 搜尋按鈕
              SizedBox(
                height: fontSize * 3.0, // 讓按鈕高度跟搜尋欄一致
                child: ElevatedButton(
                  onPressed: () {
                    _currentPage = 1;
                    _fetchData();
                  },
                  child: Text('搜尋', style: TextStyle(fontSize: fontSize)),
                ),
              ),
              const SizedBox(width: 16),

              // Filter 按鈕
              SizedBox(
                height: fontSize * 3.0,
                child: OutlinedButton.icon(
                  onPressed: _showFilterDialog,
                  icon: Icon(Icons.filter_list, 
                    size: fontSize + 4,
                    color: _selectedFilters.isNotEmpty ? Colors.blue : Colors.grey
                  ),
                  label: Text(
                    _selectedFilters.isEmpty ? '篩選' : '已選(${_selectedFilters.length})',
                    style: TextStyle(
                      fontSize: fontSize,
                      color: _selectedFilters.isNotEmpty ? Colors.blue : Colors.black
                    ),
                  ),
                ),
              ),
              
              const Spacer(), // 撐開空間

              // 每頁顯示筆數
              Text('每頁顯示: ', style: TextStyle(fontSize: fontSize)),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _rowsPerPage,
                style: TextStyle(fontSize: fontSize, color: Colors.black),
                items: [10, 30, 50].map((e) => DropdownMenuItem(value: e, child: Text('$e 筆', style: TextStyle(fontSize: fontSize)))).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _rowsPerPage = val;
                      _currentPage = 1; // 切換筆數後回到第一頁
                    });
                    _fetchData();
                  }
                },
              ),
            ],
          ),
        ),
        
        const Divider(height: 1),

        // === 2. 列表標題 (Header) ===
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.grey[100],
          child: _buildListHeader(settings.fontSize),
        ),
        const Divider(height: 1),

        // === 3. 資料列表 ===
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _transactions.isEmpty
                  ? const Center(child: Text('沒有符合的資料'))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _transactions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        return _buildHistoryRow(_transactions[index], settings);
                      },
                    ),
        ),

        // === 4. 底部換頁器 ===
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 上一頁
              IconButton(
                iconSize: fontSize + 8,
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 1 ? () => _changePage(_currentPage - 1) : null,
              ),
              
              // 頁碼顯示 (例如: 1 / 5)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Text(
                  '$_currentPage / ${totalPages == 0 ? 1 : totalPages} 頁 (共 $_totalRecords 筆)',
                  style: TextStyle(fontSize: fontSize),
                ),
              ),

              // 下一頁
              IconButton(
                iconSize: fontSize + 8,
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < totalPages ? () => _changePage(_currentPage + 1) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- 功能函式 ---
  
  void _changePage(int page) {
    setState(() => _currentPage = page);
    _fetchData();
  }

  // 顯示篩選 Dialog
  void _showFilterDialog() {
    final settings = context.read<SettingsProvider>(); 
    final fontSize = settings.fontSize;
    showDialog(
      context: context,
      builder: (context) {
        // 使用 StatefulBuilder 因為 Dialog 內部需要 setState 來更新勾選狀態
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('篩選交易類型'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _filterOptions.entries.map((entry) {
                    final isSelected = _selectedFilters.contains(entry.key);
                    return CheckboxListTile(
                      title: Text(entry.value, style: TextStyle(fontSize: fontSize)),
                      value: isSelected,
                      onChanged: (checked) {
                        setStateDialog(() {
                          if (checked == true) {
                            _selectedFilters.add(entry.key);
                          } else {
                            _selectedFilters.remove(entry.key);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    // 清除所有篩選
                    _selectedFilters.clear();
                    Navigator.pop(context);
                    _currentPage = 1;
                    _fetchData();
                  },
                  child: Text('清除篩選', style: TextStyle(color: Colors.red, fontSize: fontSize)),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _currentPage = 1;
                    _fetchData(); // 關閉後重新抓資料
                  },
                  child: Text('確定', style: TextStyle(fontSize: fontSize)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- Widget 建構 ---

  // 表頭 (跟 MainScreen 保持欄位一致)
  Widget _buildListHeader(double fontSize) {
    TextStyle headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize - 2, color: Colors.grey[700]);
    return Row(
      children: [
        Expanded(flex: 2, child: Text('日期', style: headerStyle)),
        Expanded(flex: 3, child: Text('股票代號及名稱', style: headerStyle)),
        Expanded(flex: 1, child: Text('價格', style: headerStyle, textAlign: TextAlign.right)),
        Expanded(flex: 1, child: Text('股數', style: headerStyle, textAlign: TextAlign.right)),
        Expanded(flex: 1, child: Text('手續費', style: headerStyle, textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text('總金額', style: headerStyle, textAlign: TextAlign.right)),
        const SizedBox(width: 16),
        Expanded(flex: 5, child: Text('備註', style: headerStyle, textAlign: TextAlign.center)),
      ],
    );
  }

  // 單筆資料列
  Widget _buildHistoryRow(StockTransaction tx, SettingsProvider settings) {
    final fmt = NumberFormat("#,##0");
    
    // 顏色與標籤邏輯 (完全沿用)
    Color mainColor;
    String tagText;

    if (tx.tradeType == 'CASH_DIVIDEND') {
      mainColor = Colors.blue; tagText = '現金股利';
    } else if (tx.tradeType == 'STOCK_DIVIDEND') {
      mainColor = Colors.orange; tagText = '股票股利';
    } else if (tx.tradeType == 'DEPOSIT') {
      mainColor = Colors.purple; tagText = '入金';
    } else if (tx.tradeType == 'WITHDRAWAL') {
      mainColor = Colors.brown; tagText = '出金';
    } else {
      final isBuy = tx.type == 'BUY';
      mainColor = isBuy ? settings.buyColor : settings.sellColor;
      final isDayTrade = tx.tradeType == 'DAY_TRADE';
      tagText = isDayTrade ? '當沖${isBuy ? "買" : "賣"}' : '${isBuy ? "現股買" : "現股賣"}';
    }

    // 數值格式化
    final priceStr = fmt.format(double.tryParse(tx.price.toString()) ?? 0);
    final sharesStr = fmt.format(double.tryParse(tx.shares.toString()) ?? 0);
    final feeStr = fmt.format(double.tryParse(tx.fee.toString()) ?? 0);
    final totalStr = fmt.format(double.tryParse(tx.totalAmount.toString()) ?? 0);
    final dateStr = DateFormat('yyyy/MM/dd').format(tx.date);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(dateStr, style: TextStyle(fontSize: settings.fontSize))),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${tx.stockCode} ${tx.stockName}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: settings.fontSize)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: mainColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(tagText, style: TextStyle(color: mainColor, fontSize: settings.fontSize - 4, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Expanded(flex: 1, child: Text(priceStr, textAlign: TextAlign.right, style: TextStyle(fontSize: settings.fontSize))),
          Expanded(flex: 1, child: Text(sharesStr, textAlign: TextAlign.right, style: TextStyle(fontSize: settings.fontSize))),
          Expanded(flex: 1, child: Text(feeStr, textAlign: TextAlign.right, style: TextStyle(fontSize: settings.fontSize - 2, color: Colors.grey))),
          Expanded(flex: 2, child: Text(totalStr, textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, color: mainColor, fontSize: settings.fontSize))),
          const SizedBox(width: 16),
          // 備註欄位：加上 InkWell 點擊事件與小圖示
          Expanded(
            flex: 5, 
            child: InkWell(
              onTap: () => _showEditNoteDialog(tx), // 點擊觸發編輯
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tx.note != null && tx.note!.isNotEmpty ? tx.note! : '-', // 若無備註顯示 -
                        style: TextStyle(
                          fontSize: settings.fontSize, 
                          color: tx.note != null && tx.note!.isNotEmpty 
                                 ? Colors.grey[700] 
                                 : Colors.grey[300] // 無備註時顏色淡一點
                        ), 
                        textAlign: TextAlign.center, 
                        overflow: TextOverflow.ellipsis, 
                        maxLines: 1
                      ),
                    ),
                    // 小鉛筆圖示，提示可編輯
                    const SizedBox(width: 4),
                    Icon(Icons.edit, size: 14, color: Colors.grey[400]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}