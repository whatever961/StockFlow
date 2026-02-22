import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:convert';
import 'database/db_helper.dart';
import 'providers/settings_provider.dart';
import 'providers/asset_provider.dart';
import 'screens/main_screen.dart';
import 'screens/onboarding_page.dart';

const int CURRENT_DATA_VERSION = 1;

// 等待設定和資料庫初始化
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1400, 700),          // 預設開啟時的視窗大小
    minimumSize: Size(1320, 700),     // 限制使用者能縮小的最小寬高
    center: true,                   // 讓視窗在螢幕正中間開啟
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: '股票記帳本',              // 視窗標題列文字
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  
  final prefs = await SharedPreferences.getInstance();
  // 預設為 true，如果找不到這個 key 代表是第一次
  final bool isFirstLaunch = prefs.getBool('is_first_launch') ?? true;

  final settingsProvider = SettingsProvider();
  await settingsProvider.loadSettings();
  await _checkAndInitializeData();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => settingsProvider),
        ChangeNotifierProvider(create: (_) => AssetProvider()),
      ],
      child: MyApp(isFirstLaunch: isFirstLaunch),
    ),
  );
}

class MyApp extends StatelessWidget {
  final bool isFirstLaunch;
  const MyApp({super.key, required this.isFirstLaunch});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '股票記帳本',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      // 設定多語言支援
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // 設定支援的語言
      supportedLocales: const [
        Locale('zh', 'TW'), // 繁體中文 (台灣)
        Locale('en', 'US'), // 英文 (備用)
      ],
      // (選用) 確保 App 優先使用繁體中文，即使系統語言不是中文
      locale: const Locale('zh', 'TW'),
      home: isFirstLaunch ? const OnboardingPage() : const MainScreen(),
      // 移除 debug 標籤 (選用)
      debugShowCheckedModeBanner: false,
    );
  }
}

// 檢查版本並決定是否匯入
Future<void> _checkAndInitializeData() async {
  final prefs = await SharedPreferences.getInstance();
  
  // 讀取上次儲存的版本號
  int savedVersion = prefs.getInt('stock_data_version') ?? 0;
  bool isDbEmpty = await DatabaseHelper.instance.isStockDataEmpty();
  
  print("檢查系統狀態: 版本($savedVersion vs $CURRENT_DATA_VERSION), 資料庫是否為空: $isDbEmpty");

  // 如果目前版本 > 儲存版本 OR 資料庫是空的，就執行匯入
  if (CURRENT_DATA_VERSION > savedVersion || isDbEmpty) {
    print("偵測到需更新資料，開始匯入...");
    await _loadStockData(); // 呼叫下方的匯入函式
    await prefs.setInt('stock_data_version', CURRENT_DATA_VERSION);
    print("系統初始化完成");
  } else {
    print("系統資料已是最新，跳過匯入。");
  }
}

// 實際執行 JSON 讀取與寫入
Future<void> _loadStockData() async {
  try {
    // 1. 讀取 assets 檔案
    final String response = await rootBundle.loadString('assets/stock_data.json');
    
    // 2. 解碼
    final List<dynamic> data = json.decode(response);
    
    // 3. 轉換
    List<Map<String, dynamic>> stocks = data.map((e) => {
      "code": e['股票代號'],
      "name": e['股票名稱'],
      "industry": e['產業別'],
      "market": e['市場別']
    }).toList();

    // 4. 寫入 DB
    await DatabaseHelper.instance.importStockList(stocks);
    print("股票清單匯入成功，共 ${stocks.length} 筆");
    
  } catch (e) {
    print("⚠️ 嚴重錯誤：股票清單匯入失敗: $e");
  }
}