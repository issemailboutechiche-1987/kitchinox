// Hors navigateur : pas de WebGL, la vue 3D dessinée (CustomPaint) est utilisée.
import 'package:flutter/widgets.dart';

import 'app_state.dart';

bool get webgl3dAvailable => false;
Future<String?> getWeb3dSnapshotPng() async => null;
Future<bool> startHdRender(int w, int h, int n) async => false;
Future<String?> hdRenderState() async => null;
Future<void> stopHdRender() async {}

// Réalité augmentée : seulement dans le navigateur (AR Quick Look de Safari).
bool get arQuickLookAvailable => false;
Future<String?> prepareArPackage(String optionsJson) async => null;
bool openArPackage() => false;
Future<bool> sendArToApp(String name) async => false;

class Kitchen3dView extends StatelessWidget {
  final AppState state;
  const Kitchen3dView({super.key, required this.state});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
