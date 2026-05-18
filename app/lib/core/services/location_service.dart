import 'package:geolocator/geolocator.dart';

/// file xin quyền lấy tọa độ GPS
class LocationService {
  /// yêu cầu cấp quyền và lấy tọa độ hiện tại
  Future<Position?> getCurrentPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Dịch vụ định vị bị vô hiệu.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Định vị bị từ chối');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return Future.error('Định vị bị từ chối vĩnh viễn.');
    } 

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }
  
  // TODO: Bên trên chỉ xin cấp quyền 1 lần. Cần viết thêm hàm để lắng nghe tọa độ khi thay đổi vị trí liên tục
}
