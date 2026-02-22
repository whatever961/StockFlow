import 'package:decimal/decimal.dart';
import '../models/transaction_model.dart';
import '../models/asset_model.dart';

class AssetCalculator {
  
  // 核心函式：計算資產
  // input: 所有交易紀錄, 當前股價表(Map<Code, Price>)
  static PortfolioSnapshot calculate(List<StockTransaction> transactions, Map<String, Decimal> currentPrices) {
    
    // 1. 初始化變數
    Decimal cashBalance = Decimal.zero;
    Map<String, _TempPosition> tempPositions = {}; // 暫存各股狀態

    // 2. 依照時間排序 (這很重要，必須從舊算到新)
    // 假設傳入的 transactions 已經是時間排序過的，或是這裡再排一次
    transactions.sort((a, b) => a.date.compareTo(b.date));

    for (var tx in transactions) {
      // 初始化該股票的暫存物件
      if (tx.stockCode != 'CASH' && !tempPositions.containsKey(tx.stockCode)) {
        tempPositions[tx.stockCode] = _TempPosition(tx.stockCode, tx.stockName);
      }
      
      var pos = tempPositions[tx.stockCode];

      switch (tx.tradeType) {
        case 'DEPOSIT': // 入金
          cashBalance += tx.totalAmount;
          break;
        case 'OPENING_CASH':
          cashBalance += tx.totalAmount;// 初始資金視同入金
          break;
        case 'WITHDRAWAL': // 出金
          cashBalance -= tx.totalAmount;
          break;
          
        case 'CASH_DIVIDEND': // 現金股利
          // 邏輯：現金增加 (實領金額)
          cashBalance += tx.totalAmount; 
          break;
          
        case 'STOCK_DIVIDEND': // 股票股利
          // 邏輯：股數增加，總成本不變 => 平均成本會被稀釋
          if (pos != null) {
            pos.shares += tx.shares; 
            // 總成本沒變，不需要加 money
          }
          break;

        default: // 一般買賣 (SPOT, DAY_TRADE)
          if (pos == null) break;

          if (tx.type == 'BUY' || tx.tradeType == 'OPENING_STOCK') {
            // === 買入或初始庫存邏輯 ===
            // 現金減少 (總金額含手續費)
            // 注意：若是初始庫存，通常不扣現金 (因為那是以前買的)，
            // 但為了資產總額 = 現金 + 股票，這裡有兩種流派：
            // 流派A：不扣現金 (假設這筆錢是憑空出現的資產)。
            // 流派B：假設初始現金是「未買股票前的總資金」，那就要扣。
            // 建議採用 流派A (不扣現金)，因為使用者分別輸入了「現有現金」和「現有股票」。
             
            if (tx.tradeType != 'OPENING_STOCK') {
              cashBalance -= tx.totalAmount; // 只有真的買入才扣現金
            }
            
            // 計算新平均成本 (加權平均)
            // 公式：(原總成本 + 本次買入總成本) / (原股數 + 本次股數)
            // 注意：庫存成本通常包含手續費
            Decimal costAdded = tx.totalAmount; // 買入總花費
            pos.totalCost += costAdded;
            pos.shares += tx.shares;
            
          } else if (tx.type == 'SELL') {
            // === 賣出邏輯 ===
            // 現金增加 (總金額已扣除稅費)
            cashBalance += tx.totalAmount;
            
            // 庫存減少
            // 注意：賣出時，庫存的「總成本」要依照比例減少
            // 例如：原本有1000股成本100元。賣掉500股。
            // 剩餘500股，成本還是100元。所以總成本要扣掉 (500 * 100)
            if (pos.shares > Decimal.zero) {
              Decimal avgCost = (pos.totalCost / pos.shares).toDecimal(scaleOnInfinitePrecision: 10);
              Decimal costReduced = avgCost * tx.shares; // 賣掉部分的成本
              
              pos.totalCost -= costReduced;
              pos.shares -= tx.shares;
            }
          }
          break;
      }
    }

    // 3. 將計算結果轉為正式 Model
    List<StockPosition> positions = [];
    Decimal totalStockCost = Decimal.zero;
    Decimal totalMarketValue = Decimal.zero;

    tempPositions.forEach((code, temp) {
      // 過濾掉已經清空的庫存 (股數為 0)
      if (temp.shares > Decimal.zero) {
        // 若 currentPrices[code] 為 null，則使用 (總成本/股數) 作為現價，並轉為 Decimal
        Decimal calculatedAvgCost = (temp.totalCost / temp.shares).toDecimal(scaleOnInfinitePrecision: 10);
        Decimal currentPrice = currentPrices[code] ?? calculatedAvgCost;
        
        // 建立正式 Position 物件
        var finalPos = StockPosition(
          stockCode: temp.code,
          stockName: temp.name,
          shares: temp.shares,
          averageCost: calculatedAvgCost, // 最終平均成本
          currentPrice: currentPrice,
        );

        positions.add(finalPos);
        totalStockCost += finalPos.totalCost;
        totalMarketValue += finalPos.marketValue;
      }
    });

    return PortfolioSnapshot(
      totalCashBalance: cashBalance,
      totalStockCost: totalStockCost,
      totalMarketValue: totalMarketValue,
      positions: positions,
    );
  }
}

// 內部使用的暫存類別
class _TempPosition {
  String code;
  String name;
  Decimal shares = Decimal.zero;
  Decimal totalCost = Decimal.zero;
  
  _TempPosition(this.code, this.name);
}