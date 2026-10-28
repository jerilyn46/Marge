import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Transparent system bars for edge-to-edge (Android 15+, targetSdk 35+).
/// Screens keep controls inside SafeArea; app bars handle the top inset.
const SystemUiOverlayStyle kMargeSystemUiStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarContrastEnforced: false,
  statusBarIconBrightness: Brightness.light,
  systemNavigationBarIconBrightness: Brightness.light,
);

/// Edge-to-edge setup. Call after runApp (nothing native before the first
/// frame). Never throws: failures are logged and ignored.
Future<void> applyEdgeToEdge() async {
  try {
    SystemChrome.setSystemUIOverlayStyle(kMargeSystemUiStyle);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  } catch (e) {
    debugPrint('main: edge-to-edge failed: $e');
  }
}
