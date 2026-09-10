class Album {
  final String id;
  final String title;
  final String artist;
  final String? pictureUrl;
  final String? pictureMedium;

  const Album({
    required this.id,
    required this.title,
    required this.artist,
    this.pictureUrl,
    this.pictureMedium,
  });
}