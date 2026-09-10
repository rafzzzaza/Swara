class Genre {
  final int id;
  final String name;
  final String? pictureUrl;

  const Genre({
    required this.id,
    required this.name,
    this.pictureUrl,
  });
}