import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faqs = [
    (
      q: 'RouteMate hoạt động như thế nào?',
      a: 'RouteMate giúp bạn điều hướng xe máy, cảnh báo nguy hiểm trên đường và đi nhóm an toàn. Bạn có thể đi solo hoặc tạo/tham gia phòng nhóm để di chuyển cùng bạn bè.',
    ),
    (
      q: 'Làm thế nào để tạo hoặc tham gia phòng nhóm?',
      a: 'Vào tab Nhóm → chọn "Tạo phòng" hoặc "Tham gia phòng". Để tham gia nhanh hơn, yêu cầu leader chia sẻ mã QR và dùng nút quét QR trong màn hình tham gia.',
    ),
    (
      q: 'Huy hiệu được tính như thế nào?',
      a: 'Huy hiệu dựa trên tổng số km bạn đã đi:\n• Đồng: 0 – 100 km\n• Bạc: 100 – 500 km\n• Vàng: 500 – 2000 km\n• Kim Cương: trên 2000 km',
    ),
    (
      q: 'Cảnh báo nguy hiểm đến từ đâu?',
      a: 'Cảnh báo được tổng hợp từ hai nguồn: báo cáo thực tế của các thành viên trong hệ thống và phân tích thời tiết theo tuyến đường. AI sẽ đánh giá mức độ nguy hiểm tự động.',
    ),
    (
      q: 'Lệnh thoại hoạt động như thế nào?',
      a: 'Nhấn nút micro màu đỏ ở giữa thanh điều hướng và nói lệnh. Ví dụ: "Đường đến Hội An", "Tình trạng đội hình", "Báo nguy hiểm". AI sẽ phân tích và thực hiện lệnh.',
    ),
    (
      q: 'Tại sao GPS không chính xác?',
      a: 'GPS có thể bị ảnh hưởng bởi địa hình, tòa nhà cao tầng hoặc thời tiết. Đảm bảo bạn đã cấp quyền vị trí "Luôn luôn" và tắt chế độ tiết kiệm pin khi sử dụng.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Trợ giúp', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, Color(0xFF1976D2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.help_outline_rounded, color: Colors.white, size: 32),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Câu hỏi thường gặp', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Nhấn vào câu hỏi để xem câu trả lời', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ..._faqs.map((faq) => _FaqTile(question: faq.q, answer: faq.a)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: const Column(
              children: [
                Icon(Icons.info_outline_rounded, color: AppTheme.primary, size: 28),
                SizedBox(height: 8),
                Text('RouteMate v1.0.0', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                SizedBox(height: 4),
                Text('Ứng dụng hỗ trợ an toàn phượt xe máy', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;
  const _FaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: const Icon(Icons.circle, color: AppTheme.primary, size: 8),
        title: Text(question, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        children: [
          Text(answer, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.6)),
        ],
      ),
    );
  }
}
