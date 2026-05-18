import 'package:flutter/material.dart';
import '../../../data/models/user_model.dart';

class MemberListCard extends StatelessWidget {
  final List<UserModel> members;

  const MemberListCard({Key? key, required this.members}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: members.length,
        itemBuilder: (context, index) {
          final member = members[index];
          return ListTile(
            leading: CircleAvatar(
              child: Text(member.name.substring(0, 1).toUpperCase()),
            ),
            title: Text(member.name),
            subtitle: Text(member.role.name.toUpperCase()),
            trailing: const Icon(Icons.location_on, color: Colors.green),
          );
        },
      ),
    );
  }
}
