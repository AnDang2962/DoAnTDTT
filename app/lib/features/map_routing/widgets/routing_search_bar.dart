import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../../core/constants/env_keys.dart';
import 'voice_record_btn.dart'; // ĐÃ THÊM: Import nút ghi âm của bạn

/// Component Thanh Tìm kiếm Địa điểm (Sử dụng Mapbox Geocoding API)
class RoutingSearchBar extends StatefulWidget {
  final Function(mapbox.Position position, String placeName) onDestinationSelected;
  final VoidCallback onClear;
  // ĐÃ THÊM: Hàm callback để báo ra ngoài khi người dùng đọc lệnh xong
  final Function(String spokenText)? onVoiceCommand; 

  const RoutingSearchBar({
    Key? key,
    required this.onDestinationSelected,
    required this.onClear,
    this.onVoiceCommand, // ĐÃ THÊM
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

  /// Gọi API Mapbox để lấy gợi ý địa điểm (GIỮ NGUYÊN 100%)
  Future<void> _fetchSuggestions(String query) async {
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    
    final token = EnvKeys.mapboxPublicKey;
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
              hintText: 'Tìm điểm đến hoặc đọc lệnh...', // Sửa lại hint text 1 chút cho rõ ràng
              prefixIcon: const Icon(Icons.search, color: Colors.deepOrange),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              
              // ĐÃ SỬA: Gộp nút X (Clear) và Nút Micro vào chung 1 góc phải
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min, // Rất quan trọng để không bị lỗi layout
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Nút X: Chỉ hiện khi có chữ
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _suggestions = [];
                        });
                        widget.onClear();
                      },
                    ),
                  
                  // Nút Micro: Luôn hiện
                  Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: VoiceRecordButton(
                      onResult: (spokenText) {
                        // Điền chữ vào ô tìm kiếm nhưng không gọi Mapbox Suggestion
                        setState(() {
                          _searchController.text = spokenText;
                          _suggestions = []; 
                        });
                        // Bắn câu lệnh ra cho RoutingPanel xử lý AI
                        if (widget.onVoiceCommand != null) {
                          widget.onVoiceCommand!(spokenText);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            onChanged: _fetchSuggestions,
          ),
        ),
        
        // Danh sách gợi ý Mapbox (GIỮ NGUYÊN 100%)
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
                    FocusScope.of(context).unfocus(); 
                    setState(() {
                      _searchController.text = item['text'];
                      _suggestions = []; 
                    });
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