import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import '../providers/settings_provider.dart';
import '../providers/asset_provider.dart';
import '../utils/app_dialogs.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  // --- 手續費折讓設定視窗 ---
  

  // --- 匯出功能 ---
  Future<void> _exportData(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final fontSize = settings.fontSize;
    final feeDiscountStr = settings.feeDiscount.toString();
    try {
      // 從資料庫撈資料並組裝
      final transactions = await DatabaseHelper.instance.getAllTransactionsForExport();
      final exportData = {
        'settings': {
          'fee_discount': feeDiscountStr,
        },
        'transactions': transactions,
      };

      final String jsonString = jsonEncode(exportData);

      // 讓使用者選擇存檔位置
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '匯出帳務備份',
        fileName: 'stock_backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (outputFile != null) {
        // 3. 寫入檔案
        final file = File(outputFile);
        await file.writeAsString(jsonString);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('匯出成功！路徑: $outputFile', style: TextStyle(fontSize: fontSize))),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('匯出失敗: $e', style: TextStyle(fontSize: fontSize)), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- 匯入功能 ---
  Future<void> _importData(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final fontSize = settings.fontSize;
    try {
      // 1. 選擇檔案
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String content = await file.readAsString();
        
        // 2. 解析 JSON (直接解析為 Map)
        Map<String, dynamic> importedData = jsonDecode(content);
        
        // 確保檔案內有 transactions 陣列
        if (!importedData.containsKey('transactions')) {
          throw Exception("無效的檔案格式：找不到帳務資料");
        }

        // 提取帳務資料
        List<dynamic> rawTransactions = importedData['transactions'];
        List<Map<String, dynamic>> transactions = rawTransactions.cast<Map<String, dynamic>>();

        // 提取設定資料 (如果有的話)
        Map<String, dynamic>? importedSettings = importedData['settings'];

        // 3. 跳出確認視窗 (因為會覆蓋資料)
        if (context.mounted) {
          bool? confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('確認匯入？', style: TextStyle(fontSize: fontSize + 2)),
              content: Text(
                '這將會「清空」目前所有帳務資料，並還原為檔案中的 ${transactions.length} 筆資料與相關設定。\n此動作無法復原。', 
                style: TextStyle(fontSize: fontSize - 2)
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('取消', style: TextStyle(fontSize: fontSize - 2)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('確認覆蓋', style: TextStyle(fontSize: fontSize - 2)),
                ),
              ],
            ),
          );

          if (confirm == true) {
            // 4. 執行寫入 (覆蓋資料庫)
            await DatabaseHelper.instance.importTransactions(transactions);

            // 5. 還原設定 (手續費折讓)
            if (importedSettings != null && importedSettings.containsKey('fee_discount')) {
              if (context.mounted) {
                // 呼叫 Provider 更新設定
                context.read<SettingsProvider>().setFeeDiscount(importedSettings['fee_discount'].toString());
              }
            }

            // 6. 標記為「非第一次開啟」
            // 避免使用者在「清除資料」後立刻「匯入」，重開 App 卻又進入初始頁面的怪現象
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('is_first_launch', false);

            // 7. 重算資產並通知成功
            if (context.mounted) {
              context.read<AssetProvider>().recalculateHoldings();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('匯入成功！資料與設定已還原', style: TextStyle(fontSize: fontSize))),
              );
            }
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('匯入失敗，請確認檔案格式正確。錯誤: $e', style: TextStyle(fontSize: fontSize)), 
            backgroundColor: Colors.red
          ),
        );
      }
    }
  }

  // --- 刪除所有資料 ---
  Future<void> _deleteAllData(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final fontSize = settings.fontSize;
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('警告：刪除所有資料', style: TextStyle(fontSize: fontSize + 2)),
        content: Text('您確定要刪除所有帳務紀錄嗎？\n此動作完全無法復原！', style: TextStyle(fontSize: fontSize - 2)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('取消', style: TextStyle(fontSize: fontSize - 2))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('確認刪除', style: TextStyle(fontSize: fontSize - 2)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.clearAllTransactions();

      // 清除第一次開啟的標記 (設為 true)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_first_launch', true); // 重置狀態

      if (context.mounted) {
        await context.read<SettingsProvider>().resetToDefault();
        context.read<AssetProvider>().recalculateHoldings();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('所有資料已清除，設定已還原', style: TextStyle(fontSize: fontSize - 2))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final fontSize = settings.fontSize;

    double discountVal = settings.feeDiscount.toDouble();
    String discountDisplay;
    if (discountVal >= 1.0) {
      discountDisplay = '無折扣 (10折)';
    } else {
      // 0.28 -> 2.8
      discountDisplay = '${(discountVal * 10).toStringAsFixed(2).replaceAll(RegExp(r"0*$"), "").replaceAll(RegExp(r"\.$"), "")} 折';
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // 1. 調整文字大小
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('調整文字大小', style: TextStyle(fontSize: fontSize)),
          trailing: SegmentedButton<double>(
            segments: [
              ButtonSegment(value: 15.0, label: Text('小', style: TextStyle(fontSize: fontSize - 2))),
              ButtonSegment(value: 18.0, label: Text('中', style: TextStyle(fontSize: fontSize - 2))),
              ButtonSegment(value: 21.0, label: Text('大', style: TextStyle(fontSize: fontSize - 2))),
            ],
            selected: {settings.fontSize},
            onSelectionChanged: (Set<double> newSelection) {
              context.read<SettingsProvider>().setFontSize(newSelection.first);
            },
          ),
        ),
        const Divider(),

        // 2. 買賣顯示顏色對調
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('買賣顯示顏色對調 (美股模式)', style: TextStyle(fontSize: fontSize)),
          subtitle: Text('開啟後：買入綠色 / 賣出紅色', style: TextStyle(fontSize: fontSize - 2, color: Colors.grey)),
          value: settings.buyColor.value == 0xFF4CAF50, // 檢查買入是否為綠色
          onChanged: (bool value) {
            if (value) {
              // 開啟：買綠賣紅
              context.read<SettingsProvider>().setColors(
                buy: Colors.green, 
                sell: Colors.red
              );
            } else {
              // 關閉：買紅賣綠 (台股預設)
              context.read<SettingsProvider>().setColors(
                buy: const Color(0xFFF44336), 
                sell: const Color(0xFF4CAF50)
              );
            }
          },
        ),
        const Divider(),

        // 3. 手續費折讓設定
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('手續費折讓設定', style: TextStyle(fontSize: fontSize)),
          subtitle: Text('目前設定: $discountDisplay', style: TextStyle(fontSize: fontSize - 2, color: Colors.blue)),
          trailing: OutlinedButton(
            onPressed: () => showDiscountDialog(context),
            child: Text('修改', style: TextStyle(fontSize: fontSize - 2)),
          ),
          onTap: () => showDiscountDialog(context),
        ),
        const Divider(),

        // 4. 匯入/匯出區塊
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('匯入帳務 JSON 檔', style: TextStyle(fontSize: fontSize)),
          trailing: OutlinedButton.icon(
            onPressed: () => _importData(context),
            icon: const Icon(Icons.file_upload_outlined),
            label: Text('選擇檔案', style: TextStyle(fontSize: fontSize - 2)),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('匯出帳務 JSON 檔', style: TextStyle(fontSize: fontSize)),
          trailing: OutlinedButton.icon(
            onPressed: () => _exportData(context),
            icon: const Icon(Icons.file_download_outlined),
            label: Text('選擇路徑', style: TextStyle(fontSize: fontSize - 2)),
          ),
        ),

        const Divider(),

        // 5. 危險區域
        const SizedBox(height: 20),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('刪除所有帳務資料並還原設定', style: TextStyle(fontSize: fontSize, color: Colors.red)),
          trailing: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => _deleteAllData(context),
            child: Text('刪除', style: TextStyle(fontSize: fontSize - 2)),
          ),
        ),
      ],
    );
  }
}