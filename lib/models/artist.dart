class Artist {
  final String id;
  final String name;
  final String? pictureUrl;

  const Artist({
    required this.id,
    required this.name,
    this.pictureUrl,
  });
}