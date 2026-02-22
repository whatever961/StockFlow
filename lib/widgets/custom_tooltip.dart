import 'package:flutter/material.dart';

class CustomTooltip extends StatelessWidget {
  final String title;
  final double fontSize;
  final List<Widget> children;

  const CustomTooltip({
    super.key,
    required this.title,
    required this.fontSize,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87, 
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 統一的標題格式 (日期)
          Text(
            title, 
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: fontSize)
          ),
          const Divider(color: Colors.white54, height: 16),
          
          // 這裡塞入各版面專屬的內容
          ...children,
        ],
      ),
    );
  }
}