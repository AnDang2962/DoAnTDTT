import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../services/geocoding_api.dart';
import 'voice_record_btn.dart';

/// Thanh Tìm kiếm Địa điểm.
///
/// **Architecture:** Gọi backend `geocodePlace` thay vì Mapbox Geocoding trực tiếp.
/// - Type-ahead: autocomplete=true, limit=5
/// - Voice: backend trả 1 kết quả chính xác → callback onDestinationSelected
class RoutingSearchBar extends StatefulWidget {
  final Function(mapbox.Position position, String placeName)
      onDestinationSelected;
  final VoidCallback onClear;
  final Function(String spokenText)? onVoiceCommand;
  final String? destinationName;

  const RoutingSearchBar({
    Key? key,
    required this.onDestinationSelected,
    required this.onClear,
    this.onVoiceCommand,
    this.destinationName,
  }) : super(key: key);

  @override
  State<RoutingSearchBar> createState() => _RoutingSearchBarState();
}

class _RoutingSearchBarState extends State<RoutingSearchBar> {
  final TextEditingController _searchController = TextEditingController();
  List<GeocodedPlace> _suggestions = [];
  bool _isLoading = false;

  @override
  void didUpdateWidget(RoutingSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newName = widget.destinationName;
    if (newName != null && newName != oldWidget.destinationName && _searchController.text != newName) {
      _searchController.text = newName;
      _suggestions = [];
    }
    if (newName == null && oldWidget.destinationName != null) {
      _searchController.clear();
      _suggestions = [];
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Type-ahead — gọi backend geocodePlace với autocomplete=true.
  Future<void> _fetchSuggestions(String query) async {
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    final places = await GeocodingApi.searchAutocomplete(query);

    if (!mounted) return;
    setState(() {
      _suggestions = places;
      _isLoading = false;
    });
  }

  /// Khi user nói voice → tìm exact + auto-select kết quả đầu.
  Future<void> _handleVoiceText(String spokenText) async {
    // Hiển thị text vào search box
    setState(() {
      _searchController.text = spokenText;
      _suggestions = [];
      _isLoading = true;
    });

    // Gọi backend geocode với exact match
    final place = await GeocodingApi.findExact(spokenText);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (place == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không tìm thấy địa điểm "$spokenText"')),
      );
      return;
    }

    // Auto-select kết quả → callback vẽ route
    FocusScope.of(context).unfocus();
    widget.onDestinationSelected(
      mapbox.Position(place.lng, place.lat),
      place.name,
    );

    // Bắn signal cho RoutingPanel nếu cần
    if (widget.onVoiceCommand != null) {
      widget.onVoiceCommand!(spokenText);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Tìm điểm đến hoặc đọc lệnh...',
              prefixIcon: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.search, color: Colors.deepOrange),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
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
                  Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: VoiceRecordButton(
                      onResult: _handleVoiceText,
                    ),
                  ),
                ],
              ),
            ),
            onChanged: _fetchSuggestions,
          ),
        ),

        // Danh sách gợi ý từ backend
        if (_suggestions.isNotEmpty)
          Card(
            elevation: 4,
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (ctx, idx) {
                final place = _suggestions[idx];
                return ListTile(
                  leading:
                      const Icon(Icons.location_pin, color: Colors.deepOrange),
                  title: Text(place.name),
                  subtitle: Text(
                    place.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _searchController.text = place.name;
                      _suggestions = [];
                    });
                    widget.onDestinationSelected(
                      mapbox.Position(place.lng, place.lat),
                      place.name,
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
