import 'package:flutter/material.dart';

class RoomLobbyScreen extends StatefulWidget {
  const RoomLobbyScreen({Key? key}) : super(key: key);

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen> {
  bool isCreatingRoom = true;
  String selectedRole = 'member'; // leader, member, sweeper

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Group Radar Lobby')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('Tạo phòng'),
                  selected: isCreatingRoom,
                  onSelected: (val) => setState(() => isCreatingRoom = true),
                ),
                const SizedBox(width: 16),
                ChoiceChip(
                  label: const Text('Vào phòng'),
                  selected: !isCreatingRoom,
                  onSelected: (val) => setState(() => isCreatingRoom = false),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              decoration: const InputDecoration(labelText: 'Tên hiển thị'),
            ),
            if (!isCreatingRoom) ...[
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(labelText: 'Mã phòng (Room ID)'),
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedRole,
              decoration: const InputDecoration(labelText: 'Vai trò trong đoàn'),
              items: const [
                DropdownMenuItem(value: 'leader', child: Text('Leader (Dẫn đoàn)')),
                DropdownMenuItem(value: 'member', child: Text('Member (Thành viên)')),
                DropdownMenuItem(value: 'sweeper', child: Text('Sweeper (Chốt đoàn)')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => selectedRole = val);
              },
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // TODO: Implement join/create room logic
                },
                child: Text(isCreatingRoom ? 'Tạo phòng ngay' : 'Vào phòng'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
