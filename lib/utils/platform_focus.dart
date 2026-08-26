import 'package:flutter/foundation.dart';

/// Desktop forms are ready for keyboard entry as soon as they open. On mobile
/// we deliberately avoid automatic focus so the on-screen keyboard stays closed
/// until the user chooses an input.
bool get shouldAutofocusTextInput =>
    defaultTargetPlatform == TargetPlatform.windows;
