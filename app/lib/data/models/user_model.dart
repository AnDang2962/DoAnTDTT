enum UserRole {
  leader,
  member,
  sweeper
}

class UserModel {
  final String id;
  final String name;
  final UserRole role;

  UserModel({
    required this.id,
    required this.name,
    this.role = UserRole.member,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'role': role.name,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      role: UserRole.values.firstWhere(
        (e) => e.name == map['role'],
        orElse: () => UserRole.member,
      ),
    );
  }
}
