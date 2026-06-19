import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/warning_marker.dart';

/// Quản lý dữ liệu cảnh báo nguy hiểm trên đường.
class WarningRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  /// LẤY CÁC CẢNH BÁO XUNG QUANH LỘ TRÌNH (tất cả nhóm — cross-group)
  ///
  /// Backend query theo vùng địa lý (polyline bounding box), không lọc theo roomId.
  /// Truyền [polyline] trực tiếp hoặc [roomId] (backend tự lấy route từ Firestore).
  Future<List<WarningMarker>> getRiskLabelsNearRoute({
    String? roomId,
    List<Map<String, double>>? polyline,
    double bufferKm = 1.0,
    double minSeverity = 0.1,
  }) async {
    assert(roomId != null || polyline != null,
        'Phải truyền roomId hoặc polyline');
    try {
      final callData = <String, dynamic>{
        'bufferKm': bufferKm,
        'minSeverity': minSeverity,
      };
      if (roomId != null) callData['roomId'] = roomId;
      if (polyline != null) callData['polyline'] = polyline;

      final result = await _functions
          .httpsCallable('getRiskLabelsNearRoute')
          .call<Map<String, dynamic>>(callData);
      
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
