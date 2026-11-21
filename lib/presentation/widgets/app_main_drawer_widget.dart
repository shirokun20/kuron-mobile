import 'package:material_ui/material_ui.dart';
import 'package:nhasixapp/presentation/widgets/app_drawer_content.dart';

class AppMainDrawerWidget extends StatelessWidget {
  const AppMainDrawerWidget({super.key, required this.context});

  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: const AppDrawerContent(isDrawer: true),
    );
  }
}
