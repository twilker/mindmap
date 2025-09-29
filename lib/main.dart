import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'src/screens/map_overview_page.dart';
import 'src/state/mind_map_storage.dart';
import 'src/theme/app_theme.dart';
import 'src/widgets/brand_loading_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final box = await Hive.openBox<String>('maps');
  runApp(
    ProviderScope(
      overrides: [
        mindMapStorageProvider.overrideWithValue(MindMapStorage(box)),
      ],
      child: const MindMapApp(),
    ),
  );
}

class MindMapApp extends StatefulWidget {
  const MindMapApp({super.key});

  @override
  State<MindMapApp> createState() => _MindMapAppState();
}

class _MindMapAppState extends State<MindMapApp> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() => _showSplash = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MindKite',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _showSplash
            ? const BrandLoadingScreen()
            : const MindMapOverviewPage(),
      ),
    );
  }
}
