import 'package:flutter/material.dart';

class SosHistoryScreen extends StatelessWidget {
  const SosHistoryScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử SOS')),
      body: ListView.builder(
        itemCount: 0, // TODO: Load actual history
        itemBuilder: (context, index) {
          return const ListTile(
            leading: Icon(Icons.warning, color: Colors.red),
            title: Text('SOS Alert'),
            subtitle: Text('Time and Location'),
          );
        },
      ),
    );
  }
}
