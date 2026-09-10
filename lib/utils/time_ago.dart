/// Format waktu relatif Indonesia, mis. "5 menit yang lalu", "Kemarin".
String timeAgo(DateTime time, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = ref.difference(time);
  if (diff.inSeconds < 60) return 'Baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes} menit yang lalu';
  if (diff.inHours < 24) return '${diff.inHours} jam yang lalu';
  if (diff.inDays == 1) return 'Kemarin';
  if (diff.inDays < 7) return '${diff.inDays} hari yang lalu';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];
  return '${time.day} ${months[time.month - 1]} ${time.year}';
}