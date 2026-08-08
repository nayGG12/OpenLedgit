/// Indique si les données du ticket ont été extraites par une vraie IA
/// visuelle en ligne (Gemini) ou par l'analyse locale (ML Kit + heuristiques).
enum TicketSource { ai, local }

class ScannedTicketData {
  final String title;
  final DateTime? date;
  final double? amount;
  final String? category;
  final String? location;
  final TicketSource source;

  const ScannedTicketData({
    required this.title,
    this.date,
    this.amount,
    this.category,
    this.location,
    this.source = TicketSource.local,
  });
}