import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/navigation/deep_link_handler.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'router.dart';

class AeroFlixApp extends StatefulWidget {
  const AeroFlixApp({super.key});
  @override
  State<AeroFlixApp> createState() => _AeroFlixAppState();
}

class _AeroFlixAppState extends State<AeroFlixApp> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
        child: DeepLinkHandler(
            router: appRouter,
            child: MaterialApp.router(
                title: 'AeroFlix',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.dark(),
                routerConfig: appRouter)));
  }
}
