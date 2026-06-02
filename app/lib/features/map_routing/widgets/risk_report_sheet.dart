import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

class RiskReportSheet extends StatefulWidget {
  final String roomId;
  final double lat;
  final double lng;

  const RiskReportSheet({
    super.key,
    required this.roomId,
    required this.lat,
    required this.lng,
  });

  static Future<bool> show(
    BuildContext context, {
    required String roomId,
    required double lat,
    required double lng,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RiskReportSheet(roomId: roomId, lat: lat, lng: lng),
    );
    return result ?? false;
  }

  @override
  State<RiskReportSheet> createState() => _RiskReportSheetState();
}

typedef _Subtype = ({String subtype, String label});
typedef _Category = ({
  String category,
  String emoji,
  String label,
  Color color,
  List<_Subtype> subtypes,
});

class _RiskReportSheetState extends State<RiskReportSheet> {
  static const _categoryColors = {
    'WEATHER': Colors.blue,
    'ACCIDENT': Colors.red,
    'ROAD_BAD': Colors.brown,
    'POLICE': Colors.indigo,
    'HAZARD_OTHER': Colors.orange,
  };

  // Giữ đúng thứ tự hiển thị bất kể JSON deserialization.
  static const _categoryOrder = [
    'WEATHER',
    'ACCIDENT',
    'ROAD_BAD',
    'POLICE',
    'HAZARD_OTHER',
  ];

  List<_Category>? _categories;
  bool _isLoadingTaxonomy = true;
  int _step = 0;
  int _selectedCategory = -1;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadTaxonomy();
  }

  Future<void> _loadTaxonomy() async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('getRiskTaxonomy')
          .call();
      final data = Map<String, dynamic>.from(result.data as Map);

      final parsed = <String, _Category>{};
      for (final entry in data.entries) {
        final key = entry.key;
        if (key == 'allSubtypes') continue;
        final cat = Map<String, dynamic>.from(entry.value as Map);
        final subtypes = (cat['subtypes'] as List).map((s) {
          final sub = Map<String, dynamic>.from(s as Map);
          return (subtype: sub['subtype'] as String, label: sub['vi'] as String);
        }).toList();
        parsed[key] = (
          category: key,
          emoji: cat['icon'] as String,
          label: cat['vi'] as String,
          color: _categoryColors[key] ?? Colors.grey,
          subtypes: subtypes,
        );
      }

      final ordered = _categoryOrder
          .where(parsed.containsKey)
          .map((k) => parsed[k]!)
          .toList();

      if (mounted) {
        setState(() {
          _categories = ordered;
          _isLoadingTaxonomy = false;
        });
      }
    } catch (e) {
      debugPrint('[RiskReport] Lỗi load taxonomy: $e');
      if (mounted) setState(() => _isLoadingTaxonomy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.35,
      maxChildSize: 0.75,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (_step == 1)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() => _step = 0),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                if (_step == 1) const SizedBox(width: 8),
                Text(
                  _step == 0
                      ? 'Báo cáo sự cố'
                      : (_categories?[_selectedCategory].label ?? ''),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildBody(controller)),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  Widget _buildBody(ScrollController controller) {
    if (_isLoadingTaxonomy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_categories == null || _categories!.isEmpty) {
      return const Center(child: Text('Không thể tải danh sách sự cố.'));
    }
    return _step == 0
        ? _buildCategoryGrid(controller)
        : _buildSubtypeList(controller);
  }

  Widget _buildCategoryGrid(ScrollController controller) {
    return GridView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2.6,
      ),
      itemCount: _categories!.length,
      itemBuilder: (_, i) {
        final cat = _categories![i];
        return InkWell(
          onTap: () => setState(() {
            _selectedCategory = i;
            _step = 1;
          }),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: cat.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cat.color.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(cat.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    cat.label,
                    style: TextStyle(fontWeight: FontWeight.w600, color: cat.color),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubtypeList(ScrollController controller) {
    final cat = _categories![_selectedCategory];
    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: cat.subtypes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final sub = cat.subtypes[i];
        return SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isSubmitting
                ? null
                : () => _submit(cat.category, sub.subtype),
            style: ElevatedButton.styleFrom(
              backgroundColor: cat.color.withValues(alpha: 0.1),
              foregroundColor: cat.color,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: cat.color.withValues(alpha: 0.4)),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    sub.label,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        );
      },
    );
  }

  Future<void> _submit(String category, String subtype) async {
    setState(() => _isSubmitting = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('reportRiskLabel')
          .call({
        'roomId': widget.roomId,
        'category': category,
        'subtype': subtype,
        'lat': widget.lat,
        'lng': widget.lng,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[RiskReport] Lỗi submit: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể gửi báo cáo. Vui lòng thử lại.')),
        );
      }
    }
  }
}
