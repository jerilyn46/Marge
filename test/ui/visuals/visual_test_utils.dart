import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Decode every listed asset for real (outside fake async) so goldens and
/// frame checks see the Designer art, not blank boxes. Call it BEFORE
/// pumping the widget under test so every Image resolves synchronously.
Future<void> precacheAssets(WidgetTester tester, List<String> assets) async {
  await tester.pumpWidget(feltHost(const SizedBox()));
  final ctx = tester.element(find.byType(Directionality).first);
  await tester.runAsync(() async {
    for (final a in assets) {
      await precacheImage(AssetImage(a), ctx);
    }
  });
  // Let the image streams deliver to their listeners, then paint.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
  await tester.pump();
}

/// Felt-table backdrop used by every visual golden.
Widget feltHost(Widget child, {bool reduceMotion = false, Size? size}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MediaQuery(
      data: MediaQueryData(
        size: size ?? const Size(360, 280),
        disableAnimations: reduceMotion,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF2A6E44),
        body: Center(child: RepaintBoundary(child: child)),
      ),
    ),
  );
}
