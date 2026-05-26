import 'package:cloud_functions/cloud_functions.dart';

/// Emulator được cấu hình một lần duy nhất trong main.dart.
/// Helper này chỉ trả về instance đã được cấu hình sẵn.
FirebaseFunctions get backendFunctions =>
    FirebaseFunctions.instanceFor(region: 'asia-southeast1');