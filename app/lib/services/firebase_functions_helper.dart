import 'package:cloud_functions/cloud_functions.dart';

/// Helper: tất cả backend functions deploy ở region 'asia-southeast1'.
/// LUÔN dùng helper này khi gọi httpsCallable.
FirebaseFunctions get backendFunctions =>
    FirebaseFunctions.instanceFor(region: 'asia-southeast1');
