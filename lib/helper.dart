import 'package:timezone/standalone.dart';

String formatDate(TZDateTime date) {
  return date.toIso8601String().split('T')[0];
}
