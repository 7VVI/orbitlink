import 'package:flutter/widgets.dart';

import 'mobile_controller.dart';

class MobileScope extends InheritedNotifier<MobileController> {
  const MobileScope({
    super.key,
    required MobileController controller,
    required super.child,
  }) : super(notifier: controller);

  static MobileController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MobileScope>();
    assert(scope != null, 'MobileScope not found');
    return scope!.notifier!;
  }

  static MobileController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<MobileScope>();
    assert(scope != null, 'MobileScope not found');
    return scope!.notifier!;
  }
}
