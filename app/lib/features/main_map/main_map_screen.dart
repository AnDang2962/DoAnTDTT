import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'providers/map_state_provider.dart';

/// Lớp Giao diện Bản đồ Chính (Main Map Screen)
/// Đây là lớp NỀN TẢNG (Background) của toàn bộ ứng dụng. 
/// Nó chỉ có nhiệm vụ duy nhất: Hiển thị Mapbox và báo cáo cho `MapStateProvider` biết khi nào nó load xong.
/// Hoàn toàn mù tịt về Firebase hay logic nhóm (Clean Architecture).
class MainMapScreen extends StatefulWidget {
  final mapbox.Position? initialCenter;
  
  const MainMapScreen({Key? key, this.initialCenter}) : super(key: key);

  @override
  State<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends State<MainMapScreen> {
  @override
  Widget build(BuildContext context) {
    // MapboxWidget cực kỳ tốn tài nguyên, nên ta không dùng Consumer bọc ngoài nó
    // để tránh việc nó bị rebuild (vẽ lại) mỗi khi Provider có thay đổi.
    // Việc cập nhật (vẽ marker, route) sẽ được Provider xử lý ngầm thông qua Manager.
    
    return mapbox.MapWidget(
      cameraOptions: mapbox.CameraOptions(
        center: mapbox.Point(
          // Mặc định ở khu vực Quận 1, TP.HCM nếu không có tọa độ GPS ban đầu
          coordinates: widget.initialCenter ?? mapbox.Position(106.681043, 10.762622),
        ),
        zoom: 14.0,
      ),
      // Sử dụng giao diện bản đồ đường phố tiêu chuẩn của Mapbox
      styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
      
      // Khi Mapbox khởi tạo xong bộ Engine C++ bên dưới, nó sẽ gọi hàm này.
      // Ta truyền cái bản đồ vừa tạo cho Provider cất giữ.
      onMapCreated: (mapboxMap) {
        // read() thay vì watch() vì ta chỉ gọi 1 lần, không cần lắng nghe thay đổi
        context.read<MapStateProvider>().onMapCreated(mapboxMap);
      },
    );
  }
}
