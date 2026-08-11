import 'package:flutter/material.dart';
import '../services/ai_receipt_service.dart';
import '../theme/app_theme.dart';

class OcrScanScreen extends StatefulWidget {
  const OcrScanScreen({super.key});

  @override
  State<OcrScanScreen> createState() => _OcrScanScreenState();
}

class _OcrScanScreenState extends State<OcrScanScreen> {
  final AiReceiptService _aiReceiptService = AiReceiptService();
  bool _isLoading = false;
  Map<String, dynamic>? _scanResult;

  Future<void> _startScan() async {
    setState(() {
      _isLoading = true;
      _scanResult = null;
    });

    try {
      // Appel du service IA multimodal pour obtenir le JSON
      final result = await _aiReceiptService.processReceiptWithAI();
      setState(() {
        _scanResult = result;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors du scan : $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner un ticket'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Bouton pour lancer la caméra et l'analyse IA
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _startScan,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scanner avec l\'IA'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            const SizedBox(height: 20),

            // Indicateur de chargement pendant que l'IA analyse l'image
            if (_isLoading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.green),
                ),
              ),

            // Affichage du JSON brut ou structuré une fois terminé
            if (!_isLoading && _scanResult != null)
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.green.withOpacity(0.3)),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      _scanResult.toString(),
                      style: const TextStyle(
                        color: AppColors.green,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}