import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/settings_provider.dart';

enum TimeUnit { year, month, day }

class CustomDatePicker {
  // ==========================================
  // 工具 1：顯示自訂的 年/月/日 區間選擇對話框
  // ==========================================
  static Future<DateTimeRange?> show({
    required BuildContext context,
    required DateTime initialStart,
    required DateTime initialEnd,
    required TimeUnit unit,
  }) async {
    DateTime tempStart = initialStart;
    DateTime tempEnd = initialEnd;

    final List<int> years = List.generate(101, (index) => 2000 + index);
    final List<int> months = List.generate(12, (index) => index + 1);

    int getDaysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;
    final fontSize = context.read<SettingsProvider>().fontSize;

    return showDialog<DateTimeRange>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Widget buildDropdown(int value, List<int> items, String suffix, ValueChanged<int?> onChanged) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<int>(
                    value: value,
                    items: items.map((e) => DropdownMenuItem(value: e, child: Text(e.toString()))).toList(),
                    onChanged: onChanged,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  Text(suffix, style: TextStyle(fontSize: fontSize)),
                ],
              );
            }

            Widget buildDateRow(bool isStart) {
              DateTime current = isStart ? tempStart : tempEnd;
              List<int> days = List.generate(getDaysInMonth(current.year, current.month), (index) => index + 1);

              return Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  buildDropdown(current.year, years, '年', (v) {
                    setStateDialog(() {
                      int newMaxDay = getDaysInMonth(v!, current.month);
                      int newDay = current.day > newMaxDay ? newMaxDay : current.day;
                      if (isStart) tempStart = DateTime(v, current.month, newDay);
                      else tempEnd = DateTime(v, current.month, newDay);
                    });
                  }),
                  if (unit == TimeUnit.month || unit == TimeUnit.day)
                    buildDropdown(current.month, months, '月', (v) {
                      setStateDialog(() {
                        int newMaxDay = getDaysInMonth(current.year, v!);
                        int newDay = current.day > newMaxDay ? newMaxDay : current.day;
                        if (isStart) tempStart = DateTime(current.year, v, newDay);
                        else tempEnd = DateTime(current.year, v, newDay);
                      });
                    }),
                  if (unit == TimeUnit.day)
                    buildDropdown(current.day, days, '日', (v) {
                      setStateDialog(() {
                        if (isStart) tempStart = DateTime(current.year, current.month, v!);
                        else tempEnd = DateTime(current.year, current.month, v!);
                      });
                    }),
                ],
              );
            }

            String unitText = unit == TimeUnit.year ? "年份" : (unit == TimeUnit.month ? "月份" : "日期");

            return AlertDialog(
              title: Text('選擇$unitText區間', style: TextStyle(fontSize: fontSize + 2)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('起始時間', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize)),
                  const SizedBox(height: 4),
                  buildDateRow(true),
                  const Divider(height: 24),
                  Text('結束時間', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize)),
                  const SizedBox(height: 4),
                  buildDateRow(false),
                  const SizedBox(height: 16),
                  if (tempEnd.isBefore(tempStart))
                    Text('結束時間不能早於起始時間！', style: TextStyle(color: Colors.red, fontSize: fontSize - 2)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context), 
                  child: Text('取消', style: TextStyle(fontSize: fontSize))
                ),
                ElevatedButton(
                  onPressed: tempEnd.isBefore(tempStart)
                      ? null
                      : () {
                          // 按下確定時，處理時間對齊並回傳 DateTimeRange
                          DateTime finalEnd;
                          if (unit == TimeUnit.year) {
                            finalEnd = DateTime(tempEnd.year, 12, 31, 23, 59, 59);
                          } else if (unit == TimeUnit.month) {
                            finalEnd = DateTime(tempEnd.year, tempEnd.month + 1, 0, 23, 59, 59);
                          } else {
                            finalEnd = DateTime(tempEnd.year, tempEnd.month, tempEnd.day, 23, 59, 59);
                          }
                          Navigator.pop(context, DateTimeRange(start: tempStart, end: finalEnd));
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.black87, foregroundColor: Colors.white),
                  child: Text('確定', style: TextStyle(fontSize: fontSize)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================
  // 工具 2：產生按鈕上的格式化字串
  // ==========================================
  static String getFormattedString(DateTime start, DateTime end, TimeUnit unit) {
    if (unit == TimeUnit.year) {
      return '${DateFormat('yyyy').format(start)} ~ ${DateFormat('yyyy').format(end)}';
    } else if (unit == TimeUnit.month) {
      return '${DateFormat('yyyy/MM').format(start)} ~ ${DateFormat('yyyy/MM').format(end)}';
    } else {
      return '${DateFormat('yyyy/MM/dd').format(start)} ~ ${DateFormat('yyyy/MM/dd').format(end)}';
    }
  }

  // ==========================================
  // 工具 3：當切換 Radio 單位時，自動對齊時間頭尾
  // ==========================================
  static DateTimeRange alignDates(DateTime start, DateTime end, TimeUnit unit) {
    DateTime newStart;
    DateTime newEnd;

    if (unit == TimeUnit.year) {
      newStart = DateTime(start.year, 1, 1);
      newEnd = DateTime(end.year, 12, 31, 23, 59, 59);
    } else if (unit == TimeUnit.month) {
      newStart = DateTime(start.year, start.month, 1);
      newEnd = DateTime(end.year, end.month + 1, 0, 23, 59, 59);
    } else {
      newStart = DateTime(start.year, start.month, start.day, 0, 0, 0);
      newEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);
    }
    return DateTimeRange(start: newStart, end: newEnd);
  }
}

// ============================================================================
// 共用 UI 元件：時間單位 Radio 群組
// ============================================================================
class TimeUnitRadioGroup extends StatelessWidget {
  final TimeUnit currentUnit;
  final ValueChanged<TimeUnit> onUnitChanged;
  final double fontSize;

  const TimeUnitRadioGroup({
    super.key,
    required this.currentUnit,
    required this.onUnitChanged,
    required this.fontSize,
  });

  Widget _buildSingleRadio(TimeUnit value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<TimeUnit>(
          value: value,
          groupValue: currentUnit,
          onChanged: (TimeUnit? newValue) {
            if (newValue != null) {
              onUnitChanged(newValue);
            }
          },
          activeColor: Colors.black87,
        ),
        Text(label, style: TextStyle(fontSize: fontSize)),
        const SizedBox(width: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildSingleRadio(TimeUnit.year, '年'),
        _buildSingleRadio(TimeUnit.month, '月'),
        _buildSingleRadio(TimeUnit.day, '日'),
      ],
    );
  }
}