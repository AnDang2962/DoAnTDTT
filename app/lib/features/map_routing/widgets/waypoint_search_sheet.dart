import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../services/geocoding_api.dart';

class WaypointSearchSheet extends StatefulWidget {
  final void Function(mapbox.Position pos, String name) onSelected;

  const WaypointSearchSheet({super.key, required this.onSelected});

  @override
  State<WaypointSearchSheet> createState() => _WaypointSearchSheetState();
}

class _WaypointSearchSheetState extends State<WaypointSearchSheet> {
  final _ctrl = TextEditingController();
  List<GeocodedPlace> _suggestions = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _isSearching = true);
    final results = await GeocodingApi.searchAutocomplete(q);
    if (mounted) setState(() { _suggestions = results; _isSearching = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Thêm điểm dừng', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Tìm địa điểm...',
                prefixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : const Icon(Icons.search, color: Colors.blue),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25)),
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              ),
              onChanged: _search,
            ),
          ),
          if (_suggestions.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (_, i) {
                  final p = _suggestions[i];
                  return ListTile(
                    leading: const Icon(Icons.location_pin, color: Colors.blue),
                    title: Text(p.name),
                    subtitle: Text(p.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => widget.onSelected(mapbox.Position(p.lng, p.lat), p.name),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
