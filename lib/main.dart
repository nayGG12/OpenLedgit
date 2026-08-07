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
import 'screens/splash_screen.dart';
import 'screens/accounts_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialisation de Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 2. Initialisation des données de formatage pour les locales
  await initializeDateFormatting('fr_FR', null);
  Intl.defaultLocale = 'fr_FR';

  // Initialisation des données locales
  await StorageService.initDefaultDataIfNeeded();

  // 3. Bloquer l'orientation en mode portrait uniquement sur toute l'application
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const OpenLedgerApp());
}

class OpenLedgerApp extends StatelessWidget {
  const OpenLedgerApp({super.key});

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
        // 3. Supprimer les animations de transition de page par défaut sur iOS (les rendre "brutes" sans effet de glissement)
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.iOS: _NoAnimationPageTransitionsBuilder(),
            TargetPlatform.android: _NoAnimationPageTransitionsBuilder(),
          },
        ),
      ),
      // Désactive le HeroController global : sans widget Hero explicite dans l'app,
      // la recherche récursive de Hero à chaque navigation (surtout avec l'IndexedStack
      // de RootNavigation qui garde tous les onglets montés) pouvait geler/planter l'app.
      builder: (context, child) => HeroControllerScope.none(child: child!),
      // AuthGate décide de la première page en combinant l'état Firebase et le nom local
      home: const AuthGate(),
    );
  }
}

/// Détermine la page de démarrage selon l'auth Firebase et la présence du nom local.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }

        final user = snapshot.data;

        // Si pas connecté, on affiche Welcome
        if (user == null) return const WelcomeScreen();

        // Si connecté mais email non vérifié, afficher l'écran de bienvenue (login flow gère la vérif)
        if (!user.emailVerified) return const WelcomeScreen();

        // Utilisateur connecté et email vérifié -> vérifier nom local
        return FutureBuilder<String?>(
          future: StorageService.getUserFullName(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SplashScreen();
            }
            final localName = snap.data;
            if (localName == null || localName.trim().isEmpty) {
              return const CollectNameScreen();
            }
            return const RootNavigation();
          },
        );
      },
    );
  }
}

// Classe personnalisée pour désactiver l'animation de transition de page
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
    // Retourne l'enfant directement sans appliquer d'animation de glissement
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

  // Clé pour forcer le rechargement de l'écran d'accueil quand on y revient.
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
      const AccountsScreen(),
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
