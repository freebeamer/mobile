import 'package:flutter/material.dart';

import 'presentation/screens/tuners_screen.dart';
import 'presentation/widgets/deep_link_listener.dart';

/// Module-level so it's created exactly once for the app's lifetime —
/// DeepLinkListener needs a stable key to navigate from outside the
/// widget that built it (an incoming link can arrive from anywhere,
/// not just from the currently-visible screen).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class FreeBeamerMobileApp extends StatelessWidget {
  const FreeBeamerMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'FreeBeamer',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: DeepLinkListener(
        navigatorKey: appNavigatorKey,
        child: const TunersScreen(),
      ),
    );
  }
}
