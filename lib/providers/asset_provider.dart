import 'package:flutter/material.dart';
import 'package:decimal/decimal.dart';
import '../database/db_helper.dart';
import '../models/transaction_model.dart';
import '../models/asset_model.dart';
import '../services/asset_calculator.dart';
import '../services/stock_price_service.dart';

class AssetProvider with ChangeNotifier {
  PortfolioSnapshot? _snapshot;
  bool _isLoading = false;

  // 快取庫存狀態 (不含股價，只含股數與成本)
  // 這樣刷新股價時，就不用重新跑一次 DB 和 Calculator
  PortfolioSnapshot? _cachedHoldings;

  PortfolioSnapshot? get snapshot => _snapshot;
  bool get isLoading => _isLoading;

  // 情境 A: 資料變動時呼叫 (新增/刪除/匯入帳務後)
  // 這是一個比較「重」的操作，會讀 DB 並重算庫存
  Future<void> recalculateHoldings() async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1. 讀取所有交易 (重算庫存)
      final rawData = await DatabaseHelper.instance.getAllTransactionsForExport();
      final transactions = rawData.map((e) => StockTransaction.fromMap(e)).toList();

      // 2. 計算庫存 (此時傳入空的價格 Map，只為了算出股數和成本)
      // AssetCalculator 需要微調一下邏輯：如果沒有價格，市值就算 0，但不影響股數計算
      _cachedHoldings = AssetCalculator.calculate(transactions, {});
      
      // 3. 庫存變了，更新現價或直接顯示成本態
      // 先暫時用庫存狀態當作 snapshot，等待下一步刷新股價
      _snapshot = _cachedHoldings;

    } catch (e) {
      print("庫存重算錯誤: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
      
      // 庫存算完後，自動去抓一次最新股價
      refreshPrices(); 
    }
  }

  // 情境 B: 只有股價變動時呼叫 (下拉刷新)
  // 這是一個「輕」的操作，只聯網，不讀 DB
  Future<void> refreshPrices() async {
    // 防呆：如果還沒算過庫存，先算一次
    if (_cachedHoldings == null) {
      await recalculateHoldings();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // 1. 從快取的庫存中，撈出「股數 > 0」的股票代號
      final activeCodes = _cachedHoldings!.positions
          .where((p) => p.shares > Decimal.zero)
          .map((p) => p.stockCode)
          .toList();

      if (activeCodes.isEmpty) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      // 2. 抓股價 (包含上市櫃與興櫃)
      final priceService = StockPriceService();
      final prices = await priceService.getCurrentPrices(activeCodes);

      // 3. 更新快照：保留庫存資料，只更新現價與市值
      List<StockPosition> newPositions = [];
      Decimal totalMarketValue = Decimal.zero;

      for (var pos in _cachedHoldings!.positions) {
        Decimal currentPrice = prices[pos.stockCode] ?? pos.currentPrice; // 有新價用新價，沒新價用舊價
        
        // 建立新的 Position 物件 (更新市值與損益)
        var newPos = StockPosition(
          stockCode: pos.stockCode,
          stockName: pos.stockName,
          shares: pos.shares,
          averageCost: pos.averageCost,
          currentPrice: currentPrice,
        );
        
        newPositions.add(newPos);
        totalMarketValue += newPos.marketValue;
      }

      _snapshot = PortfolioSnapshot(
        totalCashBalance: _cachedHoldings!.totalCashBalance,
        totalStockCost: _cachedHoldings!.totalStockCost,
        totalMarketValue: totalMarketValue,
        positions: newPositions,
      );

    } catch (e) {
      print("股價更新錯誤: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}