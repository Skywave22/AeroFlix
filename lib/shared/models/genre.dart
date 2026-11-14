import 'package:equatable/equatable.dart';

class Genre extends Equatable {
  final int id;
  final String name;
  const Genre({required this.id, required this.name});
  factory Genre.fromJson(Map<String, dynamic> j) =>
      Genre(id: j['id'] as int, name: (j['name'] ?? '') as String);
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  @override
  List<Object?> get props => [id, name];
}
