import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:decimal/decimal.dart';
import 'dart:io';

class DatabaseHelper {
  // 單例模式，確保 App 只會打開一個資料庫連線
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    
    // 初始化 PC 端的 SQLite 環境
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    
    _database = await _initDB('my_stock_book.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    // 取得電腦的應用程式資料夾路徑
    // final dbPath = await getDatabasesPath();
    // final path = join(dbPath, filePath);
    // print('🛑 資料庫檔案路徑在這裡: $path');
    // final directory = await getApplicationSupportDirectory();
    // print('設定檔路徑: ${directory.path}');

    String finalPath;
    
    if (Platform.isWindows) {
      // 取得執行檔 (.exe) 所在的當前目錄
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      finalPath = join(exeDir, filePath); 
    } else {
      final dbPath = await getDatabasesPath();
      finalPath = join(dbPath, filePath);
    }

    return await openDatabase(
      finalPath, 
      version: 1, 
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // 建立交易表
    // id 設為 TEXT 是因為我們要存 UUID 字串
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        stock_code TEXT NOT NULL,
        stock_name TEXT NOT NULL,
        type TEXT NOT NULL,
        trade_type TEXT DEFAULT 'SPOT', -- SPOT(現股) / DAY_TRADE(當沖)

        price TEXT NOT NULL,
        shares TEXT NOT NULL,
        fee TEXT NOT NULL,           -- 手續費 (分開存，方便未來統計)
        total_amount TEXT NOT NULL,

        date TEXT NOT NULL,
        note TEXT,
        updated_at TEXT NOT NULL,
        realized_profit REAL DEFAULT 0.0
      )
    ''');
    
    await db.execute('''
      CREATE TABLE stock_info (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        industry TEXT,
        market TEXT,
        last_price TEXT,           -- 上次更新的收盤價
        last_update_time TEXT      -- 價格更新時間
      )
    ''');
    // 建立日期索引，預先計算好每天的日期字串並排序存起來
    await db.execute(
      'CREATE INDEX idx_transactions_date_day ON transactions(substr(date, 1, 10))'
    );
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 1) {
      await db.execute('ALTER TABLE transactions ADD COLUMN realized_profit REAL DEFAULT 0.0');
    }
  }

  Future<bool> isStockDataEmpty() async {
    final db = await instance.database;
    // 計算 stock_info 表裡有幾筆資料
    final result = await db.rawQuery('SELECT 1 FROM stock_info LIMIT 1');
    return result.isEmpty; // 如果是 0，回傳 true (代表是空的)
  }

  Future<void> importStockList(List<Map<String, dynamic>> stocks) async {
    final db = await instance.database;
    final batch = db.batch(); // 使用 Batch 批次處理，效能才會好
    
    for (var stock in stocks) {
      batch.insert(
        'stock_info',
        stock,
        conflictAlgorithm: ConflictAlgorithm.replace, // 如果代號重複就覆蓋
      );
    }
    await batch.commit(noResult: true);
  }

  // 搜尋函式：輸入關鍵字 (代號或名稱或產業)，回傳符合的股票
  Future<List<Map<String, dynamic>>> searchStocks(String query) async {
    final db = await instance.database;
    return await db.query(
      'stock_info',
      where: 'code LIKE ? OR name LIKE ? OR industry LIKE ? OR market LIKE ?',
      whereArgs: [
      '%$query%', // 對應 code
      '%$query%', // 對應 name
      '%$query%', // 對應 industry
      '%$query%'  // 對應 market
      ],
      limit: 20, // 數量稍微提高，因為搜產業可能會跑出比較多筆
    );
  }

  // 測試用：新增一筆交易
  Future<void> insertTransaction(Map<String, dynamic> row) async {
    final db = await instance.database;
    await db.insert('transactions', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearAllTransactions() async {
    final db = await instance.database;
    // 刪除 transactions 表的所有資料
    await db.delete('transactions'); 
    print('所有交易紀錄已清除');
  }
  
  // 測試用：讀取所有交易
  Future<List<Map<String, dynamic>>> getAllTransactions() async {
    final db = await instance.database;
    return await db.query('transactions', orderBy: 'date DESC');
  }

  // 取得「最近三個交易日」的所有帳務
  Future<List<Map<String, dynamic>>> getRecentTransactions() async {
    final db = await instance.database;
    
    // 優化後的邏輯：
    // 1. 內部查詢 (Subquery) 會直接命中 idx_transactions_date_day 索引，
    //    極速抓出「扣除初始資料後」最近的三個「有交易的日期」，完全不需掃描 Table。
    // 2. 外部查詢再抓出這三天內的所有資料，並再次過濾初始資料 (雙重保險)。
    return await db.rawQuery('''
      SELECT * FROM transactions 
      WHERE substr(date, 1, 10) IN (
          SELECT substr(date, 1, 10) 
          FROM transactions
          GROUP BY substr(date, 1, 10) 
          ORDER BY substr(date, 1, 10) DESC 
          LIMIT 3
      ) 
      ORDER BY date DESC
    ''');
  }

  // 合併查詢：同時取得資料與總筆數 (已過濾掉初始資料)
  Future<Map<String, dynamic>> getTransactionsAndCount({
    String? keyword,
    List<String>? filters,
    required int limit,
    required int offset,
  }) async {
    final db = await instance.database;
    final whereClause = _buildWhereClause(keyword, filters);

    // 關鍵語法：COUNT(*) OVER() AS total_count
    // 這會算出符合 WHERE 條件的總筆數，並附加在每一行結果中
    final sql = '''
      SELECT *, COUNT(*) OVER() AS total_count 
      FROM transactions 
      ${whereClause.sql} 
      ORDER BY date DESC
      LIMIT ? OFFSET ?
    ''';

    final results = await db.rawQuery(
      sql,
      [...whereClause.args, limit, offset],
    );

    int total = 0;
    if (results.isNotEmpty) {
      // 從第一筆資料中抓出總筆數 (因為每一筆都會有這個欄位)
      total = results.first['total_count'] as int;
    }

    return {
      'data': results,
      'total': total,
    };
  }

  _SqlBuilder _buildWhereClause(String? keyword, List<String>? filters) {
    // 1. 預設條件：
    List<String> conditions = [];
    List<dynamic> args = [];

    // 1. 關鍵字搜尋 (日期、代號、名稱、備註)
    if (keyword != null && keyword.isNotEmpty) {
      // 嘗試將使用者的輸入 (如 2/15, 20260215) 轉換成標準格式 (02-15, 2026-02-15)
      String? fuzzyDate = _tryNormalizeDate(keyword);

      if (fuzzyDate != null) {
        // 如果成功轉換成日期格式，多加一個 date LIKE 條件
        conditions.add('(date LIKE ? OR stock_code LIKE ? OR stock_name LIKE ? OR note LIKE ? OR date LIKE ?)');
        args.addAll(['%$keyword%', '%$keyword%', '%$keyword%', '%$keyword%', '%$fuzzyDate%']);
      } else {
        // 如果不是日期格式，維持原本的搜尋
        conditions.add('(date LIKE ? OR stock_code LIKE ? OR stock_name LIKE ? OR note LIKE ?)');
        args.addAll(['%$keyword%', '%$keyword%', '%$keyword%', '%$keyword%']);
      }
    }

    // 2. 過濾器 (現股買、現股賣、當沖買、當沖賣、入金、出金)
    // 我們在 UI 層會定義好這些 key，這裡負責轉成 SQL
    if (filters != null && filters.isNotEmpty) {
      List<String> typeConditions = [];
      for (var f in filters) {
        switch (f) {
          case 'OPENING_STOCK':
            typeConditions.add("(trade_type = 'OPENING_STOCK')");
            break;
          case 'OPENING_CASH':
            typeConditions.add("(trade_type = 'OPENING_CASH')");
            break;
          case 'SPOT_BUY':
            typeConditions.add("(trade_type = 'SPOT' AND type = 'BUY')");
            break;
          case 'SPOT_SELL':
            typeConditions.add("(trade_type = 'SPOT' AND type = 'SELL')");
            break;
          case 'DAY_BUY':
            typeConditions.add("(trade_type = 'DAY_TRADE' AND type = 'BUY')");
            break;
          case 'DAY_SELL':
            typeConditions.add("(trade_type = 'DAY_TRADE' AND type = 'SELL')");
            break;
          case 'DEPOSIT':
            typeConditions.add("(trade_type = 'DEPOSIT')");
            break;
          case 'WITHDRAWAL':
            typeConditions.add("(trade_type = 'WITHDRAWAL')");
            break;
          case 'CASH_DIVIDEND':
            typeConditions.add("(trade_type = 'CASH_DIVIDEND')");
            break;
          case 'STOCK_DIVIDEND':
            typeConditions.add("(trade_type = 'STOCK_DIVIDEND')");
            break;
        }
      }
      if (typeConditions.isNotEmpty) {
        // 使用 OR 連接各個過濾條件 (例如: 既是現股買 OR 當沖買)
        conditions.add('(${typeConditions.join(' OR ')})');
      }
    }

    String sql = '';
    if (conditions.isNotEmpty) {
      sql = 'WHERE ${conditions.join(' AND ')}';
    }

    return _SqlBuilder(sql, args);
  }

  // 輔助函式：嘗試將各種日期輸入轉為 YYYY-MM-DD 或 MM-DD 格式
  String? _tryNormalizeDate(String input) {
    input = input.trim();
    
    // 1. 純數字處理 (保持不變)
    if (RegExp(r'^\d{8}$').hasMatch(input)) {
      return '${input.substring(0, 4)}-${input.substring(4, 6)}-${input.substring(6, 8)}';
    }
    if (RegExp(r'^\d{4}$').hasMatch(input)) {
      return '-${input.substring(0, 2)}-${input.substring(2, 4)}';
    }

    // 2. 混用分隔號處理
    if (input.contains(RegExp(r'[-/.\s]'))) {
      List<String> parts = input.split(RegExp(r'[-/.\s]+'));
      
      // 情況 A: 只有兩段 (可能輸入 "2/15" 或 "2026/2")
      if (parts.length == 2) {
        String p1 = parts[0];
        String p2 = parts[1].padLeft(2, '0');

        // [優化] 判斷第一段是不是年份 (4位數)
        if (p1.length == 4) {
          // 輸入 "2026/2" -> 轉成 "2026-02" (搜特定年份月份)
          return '$p1-$p2';
        } else {
          // 輸入 "2/15" -> 轉成 "-02-15" (搜每年2月15日)
          // 前面加 - 是為了確保不會搜到年份 (如輸入 12/01 不會去搜 2012年)
          return '-${p1.padLeft(2, '0')}-$p2'; 
        }
      }
      
      // 情況 B: 有三段 (可能輸入 "2026.2-15" 或 "2026/02.15")
      if (parts.length == 3) {
        String p1 = parts[0];
        String p2 = parts[1].padLeft(2, '0');
        String p3 = parts[2].padLeft(2, '0');
        // 重新組裝成標準 YYYY-MM-DD
        return '$p1-$p2-$p3';
      }
    }

    return null;
  }

  // 更新單筆交易的備註
  Future<void> updateTransactionNote(String id, String newNote) async {
    final db = await instance.database;
    await db.update(
      'transactions',
      {
        'note': newNote,
        'updated_at': DateTime.now().toIso8601String(), // 記得更新修改時間
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 批次匯入交易記錄 (用於還原備份)
  Future<void> importTransactions(List<Map<String, dynamic>> dataList) async {
    final db = await instance.database;
    
    await db.transaction((txn) async {
      // 1. 先清空現有資料 (Overwrite 策略)
      await txn.delete('transactions');
      
      // 2. 批次寫入
      final batch = txn.batch();
      for (var row in dataList) {
        batch.insert('transactions', row);
      }
      await batch.commit(noResult: true);
    });
  }

  // 取得所有資料並轉為 List (用於匯出備份)
  Future<List<Map<String, dynamic>>> getAllTransactionsForExport() async {
    final db = await instance.database;
    // 撈出所有資料，不分頁
    return await db.query('transactions', orderBy: 'date DESC');
  }

  // 批次查詢股票的市場別 (上市/上櫃/興櫃)
  // 回傳 Map: key=股票代號, value=市場別字串 (e.g. "上市", "上櫃", "興櫃")
  Future<Map<String, String>> getStockMarkets(List<String> codes) async {
    final db = await instance.database;
    if (codes.isEmpty) return {};

    // 建立 SQL: WHERE code IN ('2330', '0050', ...)
    String whereClause = codes.map((e) => "'$e'").join(',');
    
    final result = await db.rawQuery(
      "SELECT code, market FROM stock_info WHERE code IN ($whereClause)"
    );

    Map<String, String> marketMap = {};
    for (var row in result) {
      marketMap[row['code'] as String] = row['market'] as String;
    }
    return marketMap;
  }



  // ==============================================================
  // 券商級 EOD (End of Day) 日結算回溯引擎
  // ==============================================================
  Future<void> recalculateProfit(String stockCode) async {
    final db = await instance.database;

    // 1. 撈出這檔股票所有的現股、當沖與配股紀錄 (依時間排序)
    final results = await db.query(
      'transactions',
      where: "stock_code = ? AND trade_type IN ('SPOT', 'DAY_TRADE', 'STOCK_DIVIDEND')",
      whereArgs: [stockCode],
      orderBy: 'date ASC, id ASC',
    );

    final batch = db.batch();
    
    // 全域移動平均庫存池
    Decimal inventoryShares = Decimal.zero;
    Decimal inventoryCost = Decimal.zero;

    // 2. 依日期分組，模擬每天的盤後結算
    Map<String, List<Map<String, dynamic>>> dailyTrades = {};
    for (var row in results) {
      String dateStr = row['date'].toString().substring(0, 10);
      dailyTrades.putIfAbsent(dateStr, () => []).add(row);
    }

    var sortedDates = dailyTrades.keys.toList()..sort();

    for (var date in sortedDates) {
      var trades = dailyTrades[date]!;

      // --- A. 處理當天的當沖 (Day Trade) 搓合 ---
      // 將資料複製成可修改的 Map，方便紀錄已實現損益
      var dayBuys = trades.where((t) => t['trade_type'] == 'DAY_TRADE' && t['type'] == 'BUY').map((e) => Map<String, dynamic>.from(e)).toList();
      var daySells = trades.where((t) => t['trade_type'] == 'DAY_TRADE' && t['type'] == 'SELL').map((e) => Map<String, dynamic>.from(e)).toList();

      int bIdx = 0, sIdx = 0;
      Decimal bLeft = dayBuys.isNotEmpty ? (Decimal.tryParse(dayBuys[0]['shares'].toString()) ?? Decimal.zero) : Decimal.zero;
      Decimal sLeft = daySells.isNotEmpty ? (Decimal.tryParse(daySells[0]['shares'].toString()) ?? Decimal.zero) : Decimal.zero;

      // A-1. 優先搓合有買有賣的當沖
      while (bIdx < dayBuys.length && sIdx < daySells.length) {
        if (bLeft <= Decimal.zero) {
          bIdx++;
          if (bIdx < dayBuys.length) bLeft = Decimal.tryParse(dayBuys[bIdx]['shares'].toString()) ?? Decimal.zero;
          continue;
        }
        if (sLeft <= Decimal.zero) {
          sIdx++;
          if (sIdx < daySells.length) sLeft = Decimal.tryParse(daySells[sIdx]['shares'].toString()) ?? Decimal.zero;
          continue;
        }

        Decimal matchShares = bLeft < sLeft ? bLeft : sLeft;

        // 計算此回合搓合的成本與收入
        Decimal origB = Decimal.tryParse(dayBuys[bIdx]['shares'].toString()) ?? Decimal.one;
        Decimal bTotal = Decimal.tryParse(dayBuys[bIdx]['total_amount'].toString()) ?? Decimal.zero;
        Decimal matchedCost = Decimal.fromInt((bTotal.toDouble() * (matchShares.toDouble() / origB.toDouble())).round());

        Decimal origS = Decimal.tryParse(daySells[sIdx]['shares'].toString()) ?? Decimal.one;
        Decimal sTotal = Decimal.tryParse(daySells[sIdx]['total_amount'].toString()) ?? Decimal.zero;
        Decimal matchedRev = Decimal.fromInt((sTotal.toDouble() * (matchShares.toDouble() / origS.toDouble())).round());

        // 當沖損益寫入該筆 SELL 紀錄
        Decimal profit = matchedRev - matchedCost;
        double currentProfit = (daySells[sIdx]['realized_profit'] ?? 0.0) as double;
        daySells[sIdx]['realized_profit'] = currentProfit + profit.toDouble();

        bLeft -= matchShares;
        sLeft -= matchShares;
      }

      // 寫回當沖賣出的損益到 Batch
      for (var s in daySells) {
        batch.update('transactions', {'realized_profit': s['realized_profit']}, where: 'id = ?', whereArgs: [s['id']]);
      }
      
      // A-2. 當沖留倉處理 (沒沖掉的買單，自動轉入現股庫存池！)
      while (bIdx < dayBuys.length) {
        Decimal sharesToAdd = bLeft;
        Decimal origB = Decimal.tryParse(dayBuys[bIdx]['shares'].toString()) ?? Decimal.one;
        Decimal bTotal = Decimal.tryParse(dayBuys[bIdx]['total_amount'].toString()) ?? Decimal.zero;
        Decimal costToAdd = Decimal.fromInt((bTotal.toDouble() * (sharesToAdd.toDouble() / origB.toDouble())).round());

        inventoryShares += sharesToAdd;
        inventoryCost += costToAdd;

        bIdx++;
        if (bIdx < dayBuys.length) bLeft = Decimal.tryParse(dayBuys[bIdx]['shares'].toString()) ?? Decimal.zero;
      }

      // --- B. 處理當天的現股 (SPOT) 與配股 ---
      var others = trades.where((t) => t['trade_type'] != 'DAY_TRADE').toList();
      for (var row in others) {
        String id = row['id'] as String;
        String type = row['type'] as String;
        String tradeType = row['trade_type'] as String;
        Decimal shares = Decimal.tryParse(row['shares'].toString()) ?? Decimal.zero;
        Decimal totalAmount = Decimal.tryParse(row['total_amount'].toString()) ?? Decimal.zero;

        double realizedProfit = 0.0;

        if (tradeType == 'STOCK_DIVIDEND') {
          inventoryShares += shares; // 配股攤平平均成本
        } else if (type == 'BUY') {
          inventoryShares += shares;
          inventoryCost += totalAmount; // 買進增加庫存與總成本
        } else if (type == 'SELL') {
          // 賣出結算已實現損益
          if (inventoryShares > Decimal.zero) {
            double ratio = shares.toDouble() / inventoryShares.toDouble();
            Decimal costOfSold = Decimal.fromInt((inventoryCost.toDouble() * ratio).round());
            Decimal profit = totalAmount - costOfSold;
            realizedProfit = profit.toDouble();

            inventoryShares -= shares;
            inventoryCost -= costOfSold;

            if (inventoryShares <= Decimal.zero) {
              inventoryShares = Decimal.zero;
              inventoryCost = Decimal.zero;
            }
          } else {
            realizedProfit = totalAmount.toDouble();
          }
          batch.update('transactions', {'realized_profit': realizedProfit}, where: 'id = ?', whereArgs: [id]);
        }
      }
    }

    await batch.commit(noResult: true);
  }
}

// 簡單的輔助類別，用來回傳 SQL 字串和參數
class _SqlBuilder {
  final String sql;
  final List<dynamic> args;
  _SqlBuilder(this.sql, this.args);
}