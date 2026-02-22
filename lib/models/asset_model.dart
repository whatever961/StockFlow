import 'package:decimal/decimal.dart';

// 單一檔股票的庫存狀態
class StockPosition {
  final String stockCode;
  final String stockName;
  final Decimal shares;       // 持有股數
  final Decimal averageCost;  // 平均成本 (單價)
  final Decimal currentPrice; // 現價 (收盤價) - 這需要另外抓取
  
  StockPosition({
    required this.stockCode,
    required this.stockName,
    required this.shares,
    required this.averageCost,
    Decimal? currentPrice,
  }) : currentPrice = currentPrice ?? Decimal.zero;

  // 計算：總成本
  Decimal get totalCost => shares * averageCost;

  // 計算：現值 (市值) = 股數 * 現價
  Decimal get marketValue => shares * currentPrice;

  // ==========================================
  // 券商級預估賣出成本計算 (未實現損益專用)
  // ==========================================
  
  // 1. 預估賣出證交稅 (千分之3，無條件捨去)
  Decimal get estimatedTax => (marketValue * Decimal.parse('0.003')).floor();

  // 2. 預估賣出手續費 (重點：無折讓！千分之1.425，無條件捨去)
  Decimal get estimatedFee {
    if (marketValue == Decimal.zero) return Decimal.zero;
    
    Decimal rawFee = marketValue * Decimal.parse('0.001425'); 
    Decimal fee = rawFee.floor();
    
    // 雙軌制低消判斷：零股(<1000) 1 元，整張(>=1000) 20 元
    Decimal minFee = shares < Decimal.parse('1000') ? Decimal.parse('1') : Decimal.parse('20');
    return fee < minFee ? minFee : fee;
  }

  // --- 真正的未實現淨損益 ---
  // 算法：現值 - 總成本 - 預估賣出稅 - 預估賣出手續費 (無折讓)
  Decimal get unrealizedProfit => marketValue - totalCost - estimatedTax - estimatedFee;

  // 計算：報酬率 (%)
  double get returnRate {
    if (totalCost == Decimal.zero) return 0.0;
    return (unrealizedProfit.toDouble() / totalCost.toDouble()) * 100;
  }
}

// 整體資產概況
class PortfolioSnapshot {
  final Decimal totalCashBalance;    // 現金餘額 (入金 - 出金 + 賣出 - 買入 + 現金股利)
  final Decimal totalStockCost;      // 股票總成本
  final Decimal totalMarketValue;    // 股票總市值
  final List<StockPosition> positions; // 各股庫存清單

  PortfolioSnapshot({
    required this.totalCashBalance,
    required this.totalStockCost,
    required this.totalMarketValue,
    required this.positions,
  });
  
  // 總資產 = 現金 + 股票市值
  Decimal get totalAssets => totalCashBalance + totalMarketValue;
  
  // 總未實現損益 (加總所有已經預扣「無折讓稅費」的庫存淨損益)
  Decimal get totalUnrealizedProfit {
    Decimal total = Decimal.zero;
    for (var pos in positions) {
      total += pos.unrealizedProfit;
    }
    return total;
  }
}