import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

/// Component Thanh Tìm kiếm Địa điểm (Sử dụng Mapbox Geocoding API)
/// Cho phép người dùng gõ tìm tên địa điểm và hiển thị danh sách gợi ý.
class RoutingSearchBar extends StatefulWidget {
  final Function(mapbox.Position position, String placeName) onDestinationSelected;
  final VoidCallback onClear;

  const RoutingSearchBar({
    Key? key,
    required this.onDestinationSelected,
    required this.onClear,
  }) : super(key: key);

  @override
  State<RoutingSearchBar> createState() => _RoutingSearchBarState();
}

class _RoutingSearchBarState extends State<RoutingSearchBar> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _suggestions = [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Gọi API Mapbox để lấy gợi ý địa điểm
  Future<void> _fetchSuggestions(String query) async {
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    
    final token = dotenv.env['MAPBOX_PUBLIC_KEY'] ?? '';
    // Giới hạn tìm kiếm ở Việt Nam (country=vn), hỗ trợ tiếng Việt (language=vi)
    final url =
        'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json'
        '?access_token=$token&country=vn&autocomplete=true&language=vi&limit=5';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _suggestions = json.decode(response.body)['features'];
          });
        }
      }
    } catch (e) {
      debugPrint('[RoutingSearchBar] Lỗi Geocoding: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Tìm điểm đến...',
              prefixIcon: const Icon(Icons.search, color: Colors.deepOrange),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _suggestions = [];
                        });
                        widget.onClear();
                      },
                    )
                  : null,
            ),
            onChanged: _fetchSuggestions,
          ),
        ),
        if (_suggestions.isNotEmpty)
          Card(
            elevation: 4,
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (ctx, idx) {
                final item = _suggestions[idx];
                return ListTile(
                  leading: const Icon(Icons.location_pin, color: Colors.deepOrange),
                  title: Text(item['text']),
                  subtitle: Text(item['place_name'], maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    FocusScope.of(context).unfocus(); // Tắt bàn phím
                    setState(() {
                      _searchController.text = item['text'];
                      _suggestions = []; // Ẩn danh sách gợi ý
                    });
                    // Bắn tọa độ ngược ra ngoài cho Map vẽ
                    final lng = item['center'][0].toDouble();
                    final lat = item['center'][1].toDouble();
                    widget.onDestinationSelected(mapbox.Position(lng, lat), item['text']);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
