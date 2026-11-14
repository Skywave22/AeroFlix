import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'router.dart';

class AeroFlixApp extends StatelessWidget {
  const AeroFlixApp({super.key});
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    return ProviderScope(
        child: MaterialApp.router(
            title: 'AeroFlix',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark(),
            routerConfig: appRouter));
  }
}
