import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'constants.dart';

class TouchModeResolver {
  const TouchModeResolver._();

  static bool isTouchOnly(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    final mouseConnected =
        RendererBinding.instance.mouseTracker.mouseIsConnected;
    if (!mouseConnected) {
      if (kIsWeb) {
        return true;
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
        case TargetPlatform.fuchsia:
        case TargetPlatform.iOS:
          return true;
        case TargetPlatform.linux:
        case TargetPlatform.macOS:
        case TargetPlatform.windows:
          break;
      }
    }

    if (!kIsWeb) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
        case TargetPlatform.fuchsia:
        case TargetPlatform.iOS:
          return true;
        case TargetPlatform.linux:
        case TargetPlatform.macOS:
        case TargetPlatform.windows:
          break;
      }
    }

    if (mediaQuery != null) {
      final size = mediaQuery.size;
      if (size.width > 0 && size.height > 0) {
        final diagonalInches =
            math.sqrt(size.width * size.width + size.height * size.height) /
            160.0;
        if (diagonalInches <= touchModeDiagonalInchesThreshold) {
          return true;
        }
      }
    }

    return false;
  }
}
