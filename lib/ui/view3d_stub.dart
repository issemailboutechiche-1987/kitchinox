// Hors navigateur : pas de WebGL, la vue 3D dessinée (CustomPaint) est utilisée.
import 'package:flutter/widgets.dart';

import 'app_state.dart';

bool get webgl3dAvailable => false;

class Kitchen3dView extends StatelessWidget {
  final AppState state;
  const Kitchen3dView({super.key, required this.state});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
