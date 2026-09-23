import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'app/app_router.dart';
import 'app/auth_state_controller.dart';
import 'app/permission_service.dart';
import 'features/auth/services/auth_repository.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthRepository>(
          create: (_) => AuthRepository(),
        ),
        Provider<PermissionService>(
          create: (_) => PermissionService(),
        ),
        ChangeNotifierProvider<AuthStateController>(
          create: (context) => AuthStateController(
            authRepository: context.read<AuthRepository>(),
            permissionService: context.read<PermissionService>(),
          ),
        ),
      ],
      child: Builder(
        builder: (context) {
          final authState = context.watch<AuthStateController>();
          final router = buildRouter(authState);
          return MaterialApp.router(
            title: 'Emergency Response System',
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
              useMaterial3: true,
            ),
            routerConfig: router,
          );
        },
      ),
    );
  }
}