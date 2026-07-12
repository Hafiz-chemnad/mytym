import 'package:intl/intl.dart';

class DateFormatter {
  /// Returns a clean time string like "2:30 PM"
  static String formatMsgTime(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) return "";
    try {
      DateTime date = DateTime.parse(rawDate).toLocal();
      String period = date.hour >= 12 ? "PM" : "AM";
      int hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
      String minute = date.minute.toString().padLeft(2, '0');
      return "$hour:$minute $period";
    } catch (e) {
      return "";
    }
  }

  /// Returns "Today", "Yesterday", or a formatted date like "12 Aug 2026"
  static String getDateSeparator(DateTime current, DateTime previous) {
    if (current.year == previous.year && current.month == previous.month && current.day == previous.day) return "";
    final now = DateTime.now();
    if (current.year == now.year && current.month == now.month && current.day == now.day) return "Today";
    final yesterday = now.subtract(const Duration(days: 1));
    if (current.year == yesterday.year && current.month == yesterday.month && current.day == yesterday.day) return "Yesterday";
    return DateFormat('d MMM yyyy').format(current);
  }

  /// Returns relative time like "2h ago" or "Now"
  static String timeAgo(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) return "";
    try {
      DateTime date = DateTime.parse(rawDate).toLocal();
      Duration diff = DateTime.now().difference(date);
      if (diff.inDays > 1) return "${diff.inDays}d ago";
      if (diff.inDays == 1) return "1d ago";
      if (diff.inHours > 1) return "${diff.inHours}h ago";
      if (diff.inHours == 1) return "1h ago";
      if (diff.inMinutes > 1) return "${diff.inMinutes}m ago";
      if (diff.inMinutes == 1) return "1m ago";
      return "Now";
    } catch (e) {
      return "";
    }
  }
}