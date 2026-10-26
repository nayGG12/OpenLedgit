import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:plaid_flutter/plaid_flutter.dart';

/// Résultat d'une connexion bancaire réussie via Plaid.
class PlaidLinkResult {
  final String itemId;
  final List<PlaidAccountSummary> accounts;
  final List<PlaidTransactionSummary> transactions;

  PlaidLinkResult({
    required this.itemId,
    required this.accounts,
    required this.transactions,
  });
}

class PlaidAccountSummary {
  final String accountId;
  final String name;
  final String? mask;
  final String? officialName;
  final double? currentBalance;
  final double? availableBalance;
  final String? currency;

  PlaidAccountSummary({
    required this.accountId,
    required this.name,
    this.mask,
    this.officialName,
    this.currentBalance,
    this.availableBalance,
    this.currency,
  });

  factory PlaidAccountSummary.fromMap(Map<String, dynamic> map) {
    return PlaidAccountSummary(
      accountId: map['accountId'] as String,
      name: map['name'] as String,
      mask: map['mask'] as String?,
      officialName: map['officialName'] as String?,
      currentBalance: (map['currentBalance'] as num?)?.toDouble(),
      availableBalance: (map['availableBalance'] as num?)?.toDouble(),
      currency: map['currency'] as String?,
    );
  }
}

class PlaidTransactionSummary {
  final String transactionId;
  final String accountId;
  final String name;
  final double amount; // Plaid : positif = argent sorti du compte
  final DateTime date;
  final String? category;

  PlaidTransactionSummary({
    required this.transactionId,
    required this.accountId,
    required this.name,
    required this.amount,
    required this.date,
    this.category,
  });

  factory PlaidTransactionSummary.fromMap(Map<String, dynamic> map) {
    return PlaidTransactionSummary(
      transactionId: map['transactionId'] as String,
      accountId: map['accountId'] as String,
      name: map['name'] as String,
      amount: (map['amount'] as num).toDouble(),
      date: DateTime.parse(map['date'] as String),
      category: map['category'] as String?,
    );
  }
}

/// Gère toute l'intégration Plaid côté app :
/// - récupère un link_token auprès de la Cloud Function (jamais de secret ici)
/// - ouvre Plaid Link (l'utilisateur se connecte à SA vraie banque)
/// - si la banque exige une authentification OAuth (obligatoire pour la
///   plupart des banques européennes sous DSP2), Plaid ouvre le VRAI site
///   ou la VRAIE appli de la banque hors de ton app, puis revient via un
///   Universal Link/App Link — voir _resumeAfterOAuth ci-dessous.
/// - échange le public_token contre les données de compte via la Cloud Function
///
/// L'access_token Plaid ne transite JAMAIS par cette classe ni par l'app :
/// il reste stocké côté serveur (voir functions/index.js).
class PlaidService {
  static final _functions = FirebaseFunctions.instance;

  static StreamSubscription<LinkSuccess>? _successSub;
  static StreamSubscription<LinkExit>? _exitSub;
  static StreamSubscription<LinkEvent>? _eventSub;

  // Mémorisé pendant toute la session de connexion : nécessaire pour relancer
  // Link avec le MÊME token quand l'utilisateur revient de l'authentification
  // OAuth de sa banque (voir resumeFromOAuthRedirect).
  static String? _pendingLinkToken;

  /// L'URI de redirection déclarée dans ton dashboard Plaid (Team Settings
  /// -> API -> Allowed redirect URIs). DOIT être un Universal Link/App Link
  /// réel adossé à un domaine que tu possèdes — Plaid refuse les schémas
  /// personnalisés (ex: "openledger://...") pour ce flux.
  // Remplace l'ancienne URL par la nouvelle
  static const String oauthRedirectUri = 'https://klooz-open-ledger.web.app/plaid/oauth';

  /// Lance le flux complet : récupère le link_token, ouvre Plaid Link,
  /// et retourne les données de compte une fois la connexion réussie.
  /// Retourne null si l'utilisateur annule (LinkExit sans erreur bloquante).
  static Future<PlaidLinkResult?> connectBankAccount({
    void Function(String status)? onStatusUpdate,
  }) async {
    onStatusUpdate?.call('Préparation de la connexion...');
    final linkToken = await _fetchLinkToken();
    _pendingLinkToken = linkToken;

    onStatusUpdate?.call('Ouverture de Plaid Link...');
    final publicToken = await _openLinkAndWaitForResult(linkToken);

    if (publicToken == null) {
      // Annulé, échec côté banque (déjà affiché nativement), ou l'app a été
      // fermée pendant la redirection OAuth (l'utilisateur devra relancer).
      return null;
    }

    _pendingLinkToken = null;
    onStatusUpdate?.call('Récupération des comptes et transactions...');
    return await _exchangeAndFetch(publicToken);
  }

  /// À appeler quand l'app est rouverte via l'Universal Link/App Link de
  /// retour OAuth (voir main.dart : écoute des app_links entrantes).
  /// Relance Plaid Link avec le MÊME token pour terminer proprement la
  /// connexion là où la banque l'a laissée.
  static Future<PlaidLinkResult?> resumeFromOAuthRedirect(Uri incomingUri) async {
    final token = _pendingLinkToken;
    if (token == null) {
      // Pas de session Plaid en attente : lien reçu hors contexte, on ignore.
      return null;
    }

    final publicToken = await _openLinkAndWaitForResult(token);
    _pendingLinkToken = null;

    if (publicToken == null) return null;
    return await _exchangeAndFetch(publicToken);
  }

  static Future<String> _fetchLinkToken() async {
    final callable = _functions.httpsCallable('createLinkToken');
    final result = await callable.call();
    return result.data['linkToken'] as String;
  }

  static Future<String?> _openLinkAndWaitForResult(String linkToken) async {
    final completer = Completer<String?>();

    _successSub?.cancel();
    _exitSub?.cancel();
    _eventSub?.cancel();

    _successSub = PlaidLink.onSuccess.listen((event) {
      if (!completer.isCompleted) completer.complete(event.publicToken);
    });

    _exitSub = PlaidLink.onExit.listen((event) {
      if (!completer.isCompleted) completer.complete(null);
    });

    // Utile pour du debug : Plaid émet des événements à chaque étape
    // (ex: OPEN_OAUTH quand la redirection vers la banque démarre).
    _eventSub = PlaidLink.onEvent.listen((event) {
      // debugPrint('[Plaid event] ${event.name}');
    });

    final configuration = LinkTokenConfiguration(token: linkToken);
    await PlaidLink.create(configuration: configuration);
    PlaidLink.open();

    final result = await completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => null,
    );

    await _successSub?.cancel();
    await _exitSub?.cancel();
    await _eventSub?.cancel();

    return result;
  }

  static Future<PlaidLinkResult> _exchangeAndFetch(String publicToken) async {
    final callable = _functions.httpsCallable('exchangeAndFetch');
    final result = await callable.call({'publicToken': publicToken});
    final data = Map<String, dynamic>.from(result.data as Map);

    return PlaidLinkResult(
      itemId: data['itemId'] as String,
      accounts: (data['accounts'] as List)
          .map((a) => PlaidAccountSummary.fromMap(Map<String, dynamic>.from(a as Map)))
          .toList(),
      transactions: (data['transactions'] as List)
          .map((t) => PlaidTransactionSummary.fromMap(Map<String, dynamic>.from(t as Map)))
          .toList(),
    );
  }

  /// Rafraîchit les données d'un compte déjà connecté (pull-to-refresh).
  static Future<PlaidLinkResult> refreshItem(String itemId) async {
    final callable = _functions.httpsCallable('refreshItem');
    final result = await callable.call({'itemId': itemId});
    final data = Map<String, dynamic>.from(result.data as Map);

    return PlaidLinkResult(
      itemId: itemId,
      accounts: (data['accounts'] as List)
          .map((a) => PlaidAccountSummary.fromMap(Map<String, dynamic>.from(a as Map)))
          .toList(),
      transactions: (data['transactions'] as List)
          .map((t) => PlaidTransactionSummary.fromMap(Map<String, dynamic>.from(t as Map)))
          .toList(),
    );
  }
}