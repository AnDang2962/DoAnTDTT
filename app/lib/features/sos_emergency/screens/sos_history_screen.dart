import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:provider/provider.dart';

// 🔥 1. Thêm dòng này để dùng được biến mapbox.Position truyền cho M2
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox; 

// Import Provider bản đồ của M2
import 'package:route_mate_app/features/main_map/providers/map_state_provider.dart';

class SosHistoryScreen extends StatelessWidget {
  const SosHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    timeago.setLocaleMessages('vi', timeago.ViMessages());

    final List<Map<String, dynamic>> mockData = [
      {'name': 'M2', 'time': DateTime.now().subtract(const Duration(minutes: 5)), 'lat': 10.762622, 'lng': 106.660172},
      {'name': 'Sweeper', 'time': DateTime.now().subtract(const Duration(hours: 2)), 'lat': 10.776019, 'lng': 106.695843},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử SOS')),
      body: ListView.builder(
        itemCount: mockData.length,
        itemBuilder: (context, index) {
          final item = mockData[index];
          return ListTile(
            leading: const Icon(Icons.warning, color: Colors.red),
            title: Text(item['name']),
            subtitle: Text(timeago.format(item['time'], locale: 'vi')),
            trailing: ElevatedButton(
              onPressed: () {
                // 1. Đóng màn hình lịch sử
                Navigator.pop(context);
                
                // 2. Dùng thẳng hàm flyTo ĐÃ CÓ SẴN của M2
                // Lưu ý: M2 quy định truyền mapbox.Position(kinh độ lng, vĩ độ lat)
                Provider.of<MapStateProvider>(context, listen: false)
                    .flyTo(mapbox.Position(item['lng'], item['lat']), zoom: 16.0);
              },
              child: const Text('Đến đó'),
            ),
          );
        },
      ),
    );
  }
}