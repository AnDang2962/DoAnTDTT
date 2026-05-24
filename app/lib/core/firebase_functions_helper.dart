import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

FirebaseFunctions get backendFunctions {
  // Chỉ định rõ vùng asia-southeast1
  final instance = FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  // Tự động trỏ vào máy tính qua mạng Wifi khi ở chế độ Test
  if (kDebugMode) {
    // NHỚ THAY SỐ IP NÀY THÀNH SỐ WIFI THẬT CỦA MÁY TÍNH BẠN NHÉ
    instance.useFunctionsEmulator('172.16.71.145', 5001); 
  }
  
  return instance;
}