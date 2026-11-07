// Writes lib/l10n/english.g.dart from assets/l10n/en.txt and assets/l10n/app.en.txt.
//   dart run tool/gen_l10n.dart
import 'dart:io';

import 'package:tippani/l10n/locale_file.dart';

void main() {
  final server = File('assets/l10n/en.txt').readAsStringSync();
  final app = File('assets/l10n/app.en.txt').readAsStringSync();
  File('lib/l10n/english.g.dart').writeAsStringSync(englishTable(server, app));
  stdout.writeln('lib/l10n/english.g.dart written');
}
