import 'package:flutter/material.dart';

class RoutingPanel extends StatefulWidget {
  final Function(String start, String destination) onRouteRequested;

  const RoutingPanel({Key? key, required this.onRouteRequested}) : super(key: key);

  @override
  State<RoutingPanel> createState() => _RoutingPanelState();
}

class _RoutingPanelState extends State<RoutingPanel> {
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _startController,
            decoration: const InputDecoration(
              labelText: 'Điểm bắt đầu',
              prefixIcon: Icon(Icons.my_location),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _destController,
            decoration: const InputDecoration(
              labelText: 'Điểm đến',
              prefixIcon: Icon(Icons.location_on),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              widget.onRouteRequested(_startController.text, _destController.text);
            },
            child: const Text('Tìm đường'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _startController.dispose();
    _destController.dispose();
    super.dispose();
  }
}
