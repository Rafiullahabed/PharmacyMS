import 'package:flutter_test/flutter_test.dart';

/// Render production shadows in review screenshots and keep binding invariants.
class VisualTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}
