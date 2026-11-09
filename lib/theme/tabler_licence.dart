import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Lists the icon set among the app's open-source licences (Settings, the version line at the bottom).
void registerTablerLicence() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/tabler/LICENSE');
    yield LicenseEntryWithLineBreaks([
      'Tabler Icons (https://tabler.io/icons)',
    ], text);
  });
}
