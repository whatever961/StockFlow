import 'package:flutter/material.dart';
import '../database/db_helper.dart';
class StockSearchInput extends StatelessWidget {
  final Function(String code, String name) onSelected;

  const StockSearchInput({super.key, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Map<String, dynamic>>(
      // 1. 設定選項顯示的字串 (例如顯示 "2330 台積電")
      displayStringForOption: (option) => '${option['code']} ${option['name']}',

      // 2. 設定搜尋邏輯
      optionsBuilder: (TextEditingValue textEditingValue) async {
        if (textEditingValue.text == '') {
          return const Iterable<Map<String, dynamic>>.empty();
        }
        // 去資料庫搜尋
        return await DatabaseHelper.instance.searchStocks(textEditingValue.text);
      },

      // (選用) 自訂下拉選單的樣式，讓它顯示產業
    optionsViewBuilder: (context, onSelected, options) {
        return Align(
        alignment: Alignment.topLeft,
            child: Material(
                elevation: 4.0,
                child: SizedBox(
                    width: 300, // 設定選單寬度
                    height: 300, // 限制高度，避免列表太長蓋住整個畫面
                    child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (BuildContext context, int index) {
                            final option = options.elementAt(index);
                            return ListTile(
                                title: Text('${option['code']} ${option['name']}'),
                                // 副標題顯示產業與市場，看起來更專業！
                                subtitle: Text('${option['industry'] ?? '未知產業'} | ${option['market'] ?? '未知市場'}',
                                style: TextStyle(color: Colors.grey[600], fontSize: 12),),
                                onTap: () {
                                    onSelected(option);
                                },
                            );
                        },
                    ),
                ),
            ),
        );
    },

      // 3. 當使用者選中某個選項時
      onSelected: (Map<String, dynamic> selection) {
        // 回傳選中的代號和名稱給外層
        onSelected(selection['code'], selection['name']);
        print('使用者選擇了: ${selection['name']}');
      },

      // 4. 自訂輸入框外觀
      fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onEditingComplete: onEditingComplete,
          decoration: const InputDecoration(
            labelText: '輸入代號或名稱 (如 2330)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
          ),
        );
      },
    );
  }
}