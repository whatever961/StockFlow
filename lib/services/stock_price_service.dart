import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:decimal/decimal.dart';
import '../database/db_helper.dart';

class StockPriceService {
  
  // 核心：取得即時股價
  // 支援 上市 (TSE)、上櫃 (OTC)、興櫃 (EMG)
  Future<Map<String, Decimal>> getCurrentPrices(List<String> stockCodes) async {
    if (stockCodes.isEmpty) return {};

    // 1. 先去資料庫查這些股票是 "上市" 還是 "上櫃"
    // 因為 API 參數格式不同：上市=tse_2330.tw, 上櫃=otc_8069.tw
    final marketMap = await DatabaseHelper.instance.getStockMarkets(stockCodes);

    // 2. 組合 API 請求參數 (ex_ch)
    // 上市、上櫃格式：tse_2330.tw|otc_8069.tw|...
    List<String> misCodes = []; // 上市、上櫃
    List<String> emgCodes = []; // 興櫃 (另一個網址)
    
    for (var code in stockCodes) {
      String market = marketMap[code] ?? '上市'; // 預設上市
      if (market == '興櫃') {
        emgCodes.add(code);
      } else {
        misCodes.add(code);
      }
    }

    // 2. 平行處理：同時發送兩個 API 請求
    final results = await Future.wait([
      _fetchMisPrices(misCodes, marketMap), // 舊的
      _fetchEmgPrices(emgCodes), // 新的 (興櫃)
    ]);

    // 3. 合併結果
    final combinedPrices = <String, Decimal>{};
    combinedPrices.addAll(results[0]);
    combinedPrices.addAll(results[1]);

    return combinedPrices;
  }

  // --- A. MIS API (上市/上櫃) ---
  Future<Map<String, Decimal>> _fetchMisPrices(List<String> codes, Map<String, String> marketMap) async {
    if (codes.isEmpty) return {};
    
    // 1. 組合 API 請求參數 (ex_ch)
    // 格式範例：tse_2330.tw|otc_8069.tw
    List<String> queryParams = [];
    
    for (String code in codes) {
      String market = marketMap[code] ?? '上市';
      String prefix = (market == '上櫃') ? 'otc' : 'tse';
      queryParams.add('${prefix}_$code.tw');
    }

    // 2. 發送請求
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final urlStr = 'https://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch=${queryParams.join("|")}&json=1&delay=0&_=$timestamp';
    
    try {
      final response = await http.get(Uri.parse(urlStr));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> msgArray = data['msgArray'] ?? [];

        Map<String, Decimal> prices = {};

        for (var item in msgArray) {
          String code = item['c']; // 股票代號
          String? priceStr = item['z']; // 最近成交價 (z)
          
          // 若無成交價 (可能是盤前或沒交易)，改用昨收價 (y)
          if (priceStr == null || priceStr == '-') {
            priceStr = item['y'];
          }

          if (priceStr != null && priceStr != '-') {
            try {
              prices[code] = Decimal.parse(priceStr);
            } catch (e) {
              print('MIS 解析失敗 $code: $priceStr');
            }
          }
        }
        return prices;
      } else {
        print('MIS API 請求失敗: ${response.statusCode}');
        return {};
      }
    } catch (e) {
      print('MIS 連線錯誤: $e');
      return {};
    }
  }

  // --- B. TPEX OpenAPI (興櫃) ---
  Future<Map<String, Decimal>> _fetchEmgPrices(List<String> targetCodes) async {
    if (targetCodes.isEmpty) return {};

    // 興櫃 API 網址
    const urlStr = "https://www.tpex.org.tw/openapi/v1/tpex_esb_latest_statistics";
    
    try {
      final response = await http.get(Uri.parse(urlStr));

      if (response.statusCode == 200) {
        // API 回傳的是一個大 List
        final List<dynamic> data = jsonDecode(response.body);
        Map<String, Decimal> prices = {};
        final targetSet = targetCodes.toSet(); // 轉 Set 加速比對

        for (var item in data) {
          String code = item['SecuritiesCompanyCode']; // 股票代號

          // 優化：只處理我們關注的股票
          if (targetSet.contains(code)) {
            // 優先使用 "Average" (均價)，若無則用 "PreviousAveragePrice"
            String? priceStr = item['Average'];
            
            // 防呆：如果當天完全沒成交 (Average 可能為空或 0.00?)，改用前日均價
            if (priceStr == null || priceStr == '' || priceStr == '0.00') {
               priceStr = item['PreviousAveragePrice'];
            }

            if (priceStr != null && priceStr.isNotEmpty) {
              try {
                prices[code] = Decimal.parse(priceStr);
              } catch (e) {
                print("興櫃解析錯誤 $code: $e");
              }
            }
          }
        }
        return prices;
      } else {
        print("興櫃 API 失敗: ${response.statusCode}");
        return {};
      }
    } catch (e) {
      print("興櫃連線錯誤: $e");
      return {};
    }
  }
}