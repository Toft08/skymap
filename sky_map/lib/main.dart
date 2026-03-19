import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/sky_provider.dart';
import 'screens/sky_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => SkyProvider(),
      child: const SkyApp(),
    ),
  );
}

class SkyApp extends StatelessWidget {
  const SkyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Sky Map',
      debugShowCheckedModeBanner: false,
      home: SkyScreen(),
    );
  }
}