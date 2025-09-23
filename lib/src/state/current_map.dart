import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks the name of the mind map that is currently open in the editor.
final currentMapNameProvider = StateProvider<String?>((ref) => null);
