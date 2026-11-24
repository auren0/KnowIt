import 'dart:math';

final Random _random = Random();

/// Generates a short, collision-resistant identifier for local records.
///
/// Time based prefix keeps ids roughly sortable, the random suffix makes
/// collisions practically impossible when several records are created in the
/// same millisecond.
String newId() {
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final salt = _random.nextInt(0x7fffffff).toRadixString(36);
  return '$time$salt';
}
