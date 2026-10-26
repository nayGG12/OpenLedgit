import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'account/welcome.dart';
import 'account/collect_name.dart';
import 'account/pin_setup.dart';
import 'screens/splash_screen.dart';
import 'screens/app_lock_gate.dart';
import 'screens/accounts_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'services/plaid_service.dart';
import 'services/app_lock_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const String reset = "\u001B[0m";
  const String vert = "\u001B[32m";
  const String orange = "\u001B[38;5;208m";
  const String neon = "\u001B[38;5;46m"; // Vert néon

  print(
    "$neon.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:$reset",
  );
  print(
    "$neon:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.$reset",
  );
  print(
    "$neon.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:$reset",
  );
  print(
    "$neon:.:.:.:.:.:.:.:.:.    .:.:.:.:.:.:.:.   .:.:.:.:.:.:.:.:.:.$reset",
  );
  print(
    "$neon.:.:.:.:.:.:.:.:.:.    :.:.:.:.:.:.:.    .:.:.:.:.:.:.:.:.:.:$reset",
  );
  print(
    "$neon:.:.:.:.:.:.:.:.:.    .:.:.:.:.:.:    .:.:.:.:.:.:.:.:.:.:.$reset",
  );
  print(
    "$neon.:.:.:.:.:.:.:.:.:.    .:.:.:.:.:.    .:.:.:.:.:.:.:.:.:.:.:.$reset",
  );
  print(
    "$neon:.:.:.:.:.:.:.:.:.    .:.:.:.:    .:.:.:.:.:.:.:.:.:.:.:.:.$reset",
  );
  print(
    "$neon.:.:.:.:.:.:.:.:.:.    .:.:.:.     .:.:.:.:.:.:.:.:.:.:.:.:.:$reset",
  );
  print(
    "$neon:.:.:.:.:.:.:.:.:.    .:.:.    .:.:.:.:.:.:.:.:.:.:.:.:.:.:.$reset",
  );
  print(
    "$neon.:.:.:.:.:.:.:.:.:.    .:    .:.:.:.:.:.:.:.:.:.:.:.:.:.:.:$reset",
  );
  print(
    "$neon:.:.:.:.:.:.:.:.:.    .    .:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.$reset",
  );
  print(
    "$neon.:.:.:.:.:.:.:.:.:.       .:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:$reset",
  );
  print(
    "$neon:.:.:.:.:.:.:.:.:.      .:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.$reset",
  );
  print(
    "$neon.:.:.:.:.:.:.:.:.:.       .:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:$reset",
  );
  print(
    "$neon:.:.:.:.:.:.:.:.:.    .    .:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.$reset",
  );
  print(
    "$neon:.:.:.:.:.:.:.:.:.    .:    .:.:.:.:.:.:.:.:.:.:.:.:.:.:.:$reset",
  );
  print(
    "$neon.:.:.:.:.:.:.:.:.:.    .:.:.    .:.:.:.:.:.:.:.:.:.:.:.:.:.:.$reset",
  );
  print(
    "$neon:.:.:.:.:.:.:.:.:.    .:.:.:.     .:.:.:.:.:.:.:.:.:.:.:.:.:$reset",
  );
  print(
    "$neon:.:.:.:.:.:.:.:.:.    .:.:.:.:    .:.:.:.:.:.:.:.:.:.:.:.:.$reset",
  );
  print(
    "$neon.:.:.:.:.:.:.:.:.:.    .:.:.:.:.:.    .:.:.:.:.:.:.:.:.:.:.:.$reset",
  );
  print(
    "$neon:.:.:.:.:.:.:.:.:.    .:.:.:.:.:.:    .:.:.:.:.:.:.:.:.:.:.$reset",
  );
  print(
    "$neon.:.:.:.:.:.:.:.:.:.    .:.:.:.:.:.:.:.    .:.:.:.:.:.:.:.:.:.$reset",
  );
  print(
    "$neon:.:.:.:.:.:.:.:.:.    .:.:.:.:.:.:.:.   .:.:.:.:.:.:.:.:.:.$reset",
  );
  print(
    "$neon.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:$reset",
  );
  print(
    "$neon:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.$reset",
  );
  print("$neon                                                    :. $reset");
  print("$neon                                                    ::  $reset");
  print("$neon                                                     :   $reset");
  print("$neon                                                      .  $reset");

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print("$vert Firebase est bien initialisé.$reset");
  } catch (e) {
    print("$orange Firebase n'est pas initialisé : $e$reset");
  }

  try {
    await initializeDateFormatting('fr_FR', null);
    Intl.defaultLocale = 'fr_FR';
    print("$vert Formatage des dates initialisé.$reset");
  } catch (e) {
    print("$orange Formatage des dates non initialisé : $e$reset");
  }

  try {
    await StorageService.initDefaultDataIfNeeded();
    print("$vert StorageService est bien initialisé.$reset");
  } catch (e) {
    print("$orange StorageService n'est pas initialisé : $e$reset");
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const OpenLedgerApp());
}

class OpenLedgerApp extends StatefulWidget {
  const OpenLedgerApp({super.key});

  @override
  State<OpenLedgerApp> createState() => _OpenLedgerAppState();
}

class _OpenLedgerAppState extends State<OpenLedgerApp> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _listenForOAuthRedirect();
  }

  /// Écoute les Universal Links/App Links entrants pour reprendre le flux
  /// Plaid OAuth quand l'utilisateur revient de l'authentification de sa banque.
  void _listenForOAuthRedirect() {
    _linkSub = _appLinks.uriLinkStream.listen((uri) async {
      if (uri.toString().startsWith(PlaidService.oauthRedirectUri)) {
        await PlaidService.resumeFromOAuthRedirect(uri);
        // TODO : notifier AddBankAccountScreen que la connexion a repris
        // (StreamController partagé, Provider, ou callback global).
      }
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenLedger',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('fr', 'FR')],
      locale: const Locale('fr', 'FR'),
      theme: AppTheme.dark.copyWith(
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.iOS: _NoAnimationPageTransitionsBuilder(),
            TargetPlatform.android: _NoAnimationPageTransitionsBuilder(),
          },
        ),
      ),
      builder: (context, child) => HeroControllerScope.none(child: child!),
      home: const SplashScreen(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: SizedBox.shrink(),
          );
        }

        final user = snapshot.data;
        if (user == null) return const WelcomeScreen();
        if (!user.emailVerified) return const WelcomeScreen();

        return FutureBuilder<String?>(
          future: StorageService.getUserFullName(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Colors.black,
                body: SizedBox.shrink(),
              );
            }
            final localName = snap.data;
            if (localName == null || localName.trim().isEmpty) {
              return const CollectNameScreen();
            }
            return FutureBuilder<bool>(
              future: AppLockService.isSetupCompleted(),
              builder: (context, setupSnapshot) {
                if (setupSnapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    backgroundColor: Colors.black,
                    body: SizedBox.shrink(),
                  );
                }
                if (setupSnapshot.hasError) {
                  return const Scaffold(
                    backgroundColor: Colors.black,
                    body: Center(
                      child: Text(
                        'Impossible de vérifier la configuration de sécurité.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (setupSnapshot.data != true) {
                  return const PinSetupScreen();
                }
                return const AppLockGate(child: RootNavigation());
              },
            );
          },
        );
      },
    );
  }
}

class _NoAnimationPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimationPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

class RootNavigation extends StatefulWidget {
  const RootNavigation({super.key});

  @override
  State<RootNavigation> createState() => _RootNavigationState();
}

class _RootNavigationState extends State<RootNavigation> {
  int _index = 0;
  Key _homeKey = UniqueKey();

  final List<String> _titles = ['Accueil', 'Comptes', 'Paramètres'];

  void _onTap(int i) {
    setState(() {
      if (i == 0 && _index != 0) _homeKey = UniqueKey();
      _index = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(key: _homeKey),
      const AddBankAccountScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _onTap,
        items: [
          _navItem(Icons.home_outlined, Icons.home, _titles[0]),
          _navItem(
            Icons.account_balance_wallet_outlined,
            Icons.account_balance_wallet,
            _titles[1],
          ),
          _navItem(Icons.settings_outlined, Icons.settings, _titles[2]),
        ],
      ),
    );
  }

  BottomNavigationBarItem _navItem(
    IconData outline,
    IconData filled,
    String label,
  ) {
    return BottomNavigationBarItem(
      icon: Icon(outline),
      activeIcon: Icon(filled),
      label: label,
    );
  }
}
