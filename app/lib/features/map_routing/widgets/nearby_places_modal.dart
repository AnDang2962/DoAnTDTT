import 'package:flutter/material.dart';
import '../services/places_api.dart';

class NearbyPlacesModal extends StatelessWidget {
  final List<NearbyPlace> places;
  final String title;
  final void Function(NearbyPlace) onNavigateTo;
  final void Function(NearbyPlace)? onAddWaypoint;

  const NearbyPlacesModal({
    super.key,
    required this.places,
    required this.title,
    required this.onNavigateTo,
    this.onAddWaypoint,
  });

  static Future<void> show(
    BuildContext context, {
    required List<NearbyPlace> places,
    required String title,
    required void Function(NearbyPlace) onNavigateTo,
    void Function(NearbyPlace)? onAddWaypoint,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => NearbyPlacesModal(
        places: places,
        title: title,
        onNavigateTo: onNavigateTo,
        onAddWaypoint: onAddWaypoint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: places.isEmpty
                ? const Center(
                    child: Text(
                      'Không tìm thấy địa điểm nào gần đây.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: places.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final place = places[i];
                      return ListTile(
                        leading: const Icon(Icons.location_on, color: Colors.blue),
                        title: Text(
                          place.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          place.address.isNotEmpty ? place.address : place.categoryLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (onAddWaypoint != null)
                              IconButton(
                                icon: const Icon(Icons.add_location_alt, color: Colors.blue, size: 22),
                                tooltip: 'Thêm điểm dừng',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                onPressed: () {
                                  Navigator.pop(context);
                                  onAddWaypoint!(place);
                                },
                              ),
                            Text(
                              '${place.distanceKm} km',
                              style: const TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          onNavigateTo(place);
                        },
                      );
                    },
                  ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom +
                  MediaQuery.of(context).padding.bottom +
                  16,
            ),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
