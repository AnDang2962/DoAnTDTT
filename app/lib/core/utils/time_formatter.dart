// Chứa 2 hàm tiện ích dùng chung.

class TimeFormatter {
  /// đổi số giây thành chuỗi "Giờ Phút" ví dụ 1h 30m cho tính năng routing
  static String formatDuration(int durationInSeconds) {
    final hours = durationInSeconds ~/ 3600;
    final minutes = (durationInSeconds % 3600) ~/ 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  /// đôi thời gian thành chuỗi "Giờ:Phút - Ngày/Tháng/Năm" áp dụng cho tất cả các module
  static String formatTimestamp(DateTime time) {
    // sau này có thể thay đổi nếu cần 
    return "${time.hour}:${time.minute.toString().padLeft(2, '0')} - ${time.day}/${time.month}/${time.year}";
  }
}
