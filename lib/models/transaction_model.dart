import 'package:decimal/decimal.dart';

class StockTransaction {
  final String id;          // UUID，同步時的唯一識別證
  final String stockCode;   // 股票代號 (如 2330)
  final String stockName;   // 股票名稱
  final String type;        // 'BUY', 'SELL', 'DIVIDEND'
  final String tradeType; 
  final Decimal price;       // 單價
  final Decimal shares;         // 股數
  final Decimal fee;          // 手續費
  final Decimal totalAmount; // 總金額 (含手續費/稅)
  final DateTime date;      // 交易日期
  final double realizedProfit;
  
  final String? note;       // 備註 (紀錄為何買賣)

  // --- 同步專用欄位 ---
  final DateTime updatedAt; // 最後修改時間

  StockTransaction({
    required this.id,
    required this.stockCode,
    required this.stockName,
    required this.type,
    required this.tradeType,
    required this.price,
    required this.shares,
    required this.fee,
    required this.totalAmount,
    required this.date,
    this.note,
    required this.updatedAt,
    this.realizedProfit = 0.0,
  });

  // 將資料轉為 Map 存入 SQLite
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'stock_code': stockCode,
      'stock_name': stockName,
      'type': type,
      'trade_type': tradeType,
      'price': price.toString(),
      'shares': shares.toString(),
      'fee': fee.toString(),
      'total_amount': totalAmount.toString(),
      'date': date.toIso8601String(),
      'note': note,
      'updated_at': updatedAt.toIso8601String(),
      'realized_profit': realizedProfit,
    };
  }

  // 從 SQLite 讀取資料轉回物件
  factory StockTransaction.fromMap(Map<String, dynamic> map) {
    return StockTransaction(
      id: map['id'],
      stockCode: map['stock_code'],
      stockName: map['stock_name'],
      type: map['type'],
      tradeType: map['trade_type'] ?? 'SPOT',
      price: Decimal.parse(map['price']),
      shares: Decimal.parse(map['shares']),
      fee: Decimal.parse(map['fee'] ?? '0'),
      totalAmount: Decimal.parse(map['total_amount']),
      date: DateTime.parse(map['date']),
      note: map['note'],
      updatedAt: DateTime.parse(map['updated_at']),
      realizedProfit: (map['realized_profit'] as num?)?.toDouble() ?? 0.0,
    );
  }
}