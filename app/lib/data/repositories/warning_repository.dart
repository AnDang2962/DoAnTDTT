import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/warning_marker.dart';

/// Quản lý dữ liệu về Các Rủi Ro/Cảnh báo trên đường và Tích hợp AI Giọng nói
class WarningRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // Trỏ thẳng đến khu vực chứa Cloud Function (asia-southeast1 để giảm độ trễ)
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  /// GỬI GIỌNG NÓI CHO AI PHÂN TÍCH (Sử dụng Cloud Function gọi Gemini)
  /// Người dùng chỉ cần bấm nút thu âm và nói (VD: "Có ổ gà bự chà bá phía trước").
  /// Backend sẽ gọi Gemini 2.5 Flash để dịch câu nói đó thành tọa độ và Icon hiển thị.
  Future<Map<String, dynamic>?> parseRiskFromVoice({
    required String roomId,
    required String voiceText,
    required double lat,
    required double lng,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('parseRiskFromVoice')
          .call<Map<String, dynamic>>({
        'roomId': roomId,
        'voiceText': voiceText,
        'lat': lat,
        'lng': lng,
      });
      
      final data = Map<String, dynamic>.from(result.data);
      debugPrint('[WarningRepository] AI Trả về: Loại=${data['category']} / Độ tin cậy=${data['confidence']} / Tự động lưu=${data['autoSaved']}');
      return data;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[WarningRepository] Lỗi Backend khi gọi AI: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[WarningRepository] Lỗi mạng/hệ thống khi gọi AI: $e');
      return null;
    }
  }

  /// LẤY CÁC CẢNH BÁO XUNG QUANH LỘ TRÌNH (Backend tính toán sẵn)
  /// Không cần tải toàn bộ cảnh báo trên mạng, Backend chỉ trả về những điểm nằm cách lộ trình tối đa 3km.
  Future<List<WarningMarker>> getRiskLabelsNearRoute({
    required String roomId,
    double bufferKm = 3.0,
    double minSeverity = 0.1,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('getRiskLabelsNearRoute')
          .call<Map<String, dynamic>>({
        'roomId': roomId,
        'bufferKm': bufferKm,
        'minSeverity': minSeverity,
      });
      
      final risksJson = (result.data['risks'] as List?) ?? [];
      final List<WarningMarker> warnings = [];
      
      for (final j in risksJson) {
        final data = j as Map;
        warnings.add(WarningMarker.fromJson(Map<String, dynamic>.from(data)));
      }
      
      debugPrint('[WarningRepository] Lấy được ${warnings.length} điểm cảnh báo trên đường.');
      return warnings;
    } catch (e) {
      debugPrint('[WarningRepository] Lỗi lấy cảnh báo: $e');
      return [];
    }
  }

  /// LẮNG NGHE CẢNH BÁO MỚI THEO THỜI GIAN THỰC (Realtime)
  /// Bất cứ khi nào 1 thành viên nói vào Mic và AI lưu thành công, tất cả các máy sẽ nhận được ngay lập tức.
  Stream<List<WarningMarker>> listenToRoomWarnings(String roomId) {
    return _firestore
        .collection('riskLabels')
        .where('reportedRoomId', isEqualTo: roomId)
        .snapshots()
        .map((snap) {
      final now = DateTime.now();
      final List<WarningMarker> warnings = [];

      for (final doc in snap.docs) {
        final data = doc.data();
        
        // Bỏ qua các cảnh báo quá cũ (đã hết hạn expiresAt)
        final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
        if (expiresAt != null && expiresAt.isBefore(now)) continue;

        // Thêm ID của document vào JSON rồi Parse
        data['id'] = doc.id;
        warnings.add(WarningMarker.fromJson(data));
      }
      
      return warnings;
    });
  }
}
