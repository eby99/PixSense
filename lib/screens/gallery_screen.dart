import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'dart:ui' as ui;
import 'package:lottie/lottie.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_html/html.dart' as html; // For web support
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:speech_to_text/speech_to_text.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({Key? key}) : super(key: key);

  @override
  _GalleryScreenState createState() => _GalleryScreenState();
}

class MediaItem {
  final Uint8List bytes;
  final String prompt;
  final DateTime timestamp;
  final String model;

  MediaItem({
    required this.bytes,
    required this.prompt,
    required this.timestamp,
    required this.model,
  });
}

class _GalleryScreenState extends State<GalleryScreen> with TickerProviderStateMixin {
  final TextEditingController _promptController = TextEditingController();
  MediaItem? _currentMedia; // Only store current media item
  bool _isGeneratingImage = false;
  bool _isDownloading = false;
  final String _apiKey = "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";
  SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;

  // Animation controllers
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Track model performance
  Map<String, bool> _modelPerformance = {};
  int _lastModelSwitchTime = 0;

  // Model selection - Added faster models
  final List<Map<String, String>> _imageModels = [
    {
      'name': 'Model A',
      'endpoint': 'stabilityai/stable-diffusion-2',
      'description': 'General purpose image generation (Fast)',
      'task': 'text-to-image',
      'timeout': '30', // Reduced timeout
      'speed': 'fast',
    },
    {
      'name': 'Model B',
      'endpoint': 'runwayml/stable-diffusion-v1-5',
      'description': 'Balanced quality and speed',
      'task': 'text-to-image',
      'timeout': '30',
      'speed': 'fast',
    },
    {
      'name': 'Model C',
      'endpoint': 'CompVis/ldm-text2im-large-256',
      'description': 'Very fast generation (lower resolution)',
      'task': 'text-to-image',
      'timeout': '20',
      'speed': 'very fast',
    },
    {
      'name': 'Model D',
      'endpoint': 'stabilityai/stable-diffusion-xl-base-1.0',
      'description': 'Higher quality, more detailed images',
      'task': 'text-to-image',
      'timeout': '45',
      'speed': 'medium',
    },
    {
      'name': 'Model E',
      'endpoint': 'SG161222/Realistic_Vision_V5.1_noVAE',
      'description': 'Photorealistic images (slower)',
      'task': 'text-to-image',
      'timeout': '90', // Extended timeout for this model
      'speed': 'slow',
    }
  ];

  // Current selected model
  String _selectedImageModel = 'stabilityai/stable-diffusion-2';
  String _selectedImageModelName = 'Model A';
  int _modelTimeout = 30; // Default timeout
  bool _disableSlowModels = false; // Option to disable slow models

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);
    _animationController.forward();

    // Set initial timeout based on selected model
    _updateModelTimeout();

    // Initialize model performance tracking
    for (var model in _imageModels) {
      _modelPerformance[model['endpoint']!] =
      true; // Assume all models work initially
    }
  }

  void _updateModelTimeout() {
    final modelInfo = _imageModels.firstWhere(
          (model) => model['endpoint'] == _selectedImageModel,
      orElse: () => {'timeout': '30'},
    );
    _modelTimeout = int.parse(modelInfo['timeout'] ?? '30');
  }

  @override
  void dispose() {
    _animationController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  // Helper function to show error messages
  void _showErrorMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            _generateImage();
          },
        ),
      ),
    );
  }

  // Improved model selection logic to avoid unnecessary switching
  void _switchToRecommendedModel() {
    // Don't switch too frequently
    final currentTime = DateTime
        .now()
        .millisecondsSinceEpoch;
    if (currentTime - _lastModelSwitchTime < 5000) { // 5 second cooldown
      return;
    }
    _lastModelSwitchTime = currentTime;

    // Find a suitable model based on performance history
    String newModelEndpoint = '';
    String newModelName = '';

    // First try fast models that have worked well
    for (var model in _imageModels.where((m) =>
    m['speed'] == 'fast' || m['speed'] == 'very fast')) {
      if (_modelPerformance[model['endpoint']] == true) {
        newModelEndpoint = model['endpoint']!;
        newModelName = model['name']!;
        break;
      }
    }

    // If no fast model is available, try medium speed ones
    if (newModelEndpoint.isEmpty) {
      for (var model in _imageModels.where((m) => m['speed'] == 'medium')) {
        if (_modelPerformance[model['endpoint']] == true) {
          newModelEndpoint = model['endpoint']!;
          newModelName = model['name']!;
          break;
        }
      }
    }

    // Last resort - try anything that hasn't failed yet
    if (newModelEndpoint.isEmpty) {
      for (var model in _imageModels) {
        if (_modelPerformance[model['endpoint']] == true &&
            model['endpoint'] != _selectedImageModel) {
          newModelEndpoint = model['endpoint']!;
          newModelName = model['name']!;
          break;
        }
      }
    }

    // If still nothing, just use Model A as a fallback
    if (newModelEndpoint.isEmpty) {
      newModelEndpoint = 'stabilityai/stable-diffusion-2';
      newModelName = 'Model A';
      // Reset all models to try again
      for (var model in _imageModels) {
        _modelPerformance[model['endpoint']!] = true;
      }
    }

    if (newModelEndpoint != _selectedImageModel) {
      setState(() {
        _selectedImageModel = newModelEndpoint;
        _selectedImageModelName = newModelName;
        _updateModelTimeout();
      });

      _showSuccessMessage('Switched to $newModelName for better results');
    }
  }

  // Function to show success message
  void _showSuccessMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Enhanced prompt to improve results
  String _enhancePrompt(String originalPrompt) {
    // Add model-specific enhancements
    if (_selectedImageModel == 'stabilityai/stable-diffusion-2') {
      return "$originalPrompt, high quality, detailed, sharp focus, professional photography, 4k";
    } else if (_selectedImageModel == 'CompVis/ldm-text2im-large-256') {
      return "$originalPrompt, clear, well composed, centered";
    } else if (_selectedImageModel.contains('Realistic_Vision')) {
      return "$originalPrompt, photorealistic, detailed, professional photography, 8k";
    }
    return originalPrompt;
  }

  Future<void> _generateImage() async {
    if (_promptController.text.isEmpty) {
      _showErrorMessage('Please enter a prompt');
      return;
    }

    setState(() {
      _isGeneratingImage = true;
    });

    try {
      int maxRetries = 2; // Reduced retries to avoid excessive waiting
      int currentRetry = 0;
      bool success = false;

      // Skip Model E if user has disabled slow models
      if (_disableSlowModels &&
          _selectedImageModel.contains('Realistic_Vision')) {
        _showErrorMessage(
            'Slow models are disabled. Switching to a faster model.');
        _switchToRecommendedModel();
      }

      while (currentRetry < maxRetries && !success) {
        try {
          // Add randomness to prompts to ensure different results
          String prompt = _enhancePrompt(_promptController.text);
          if (currentRetry > 0) {
            // Add variations to prompt for different results
            final variations = [
              ", high quality, detailed",
              ", 4k, realistic",
              ", professional photography",
              ", artistic style"
            ];
            prompt += variations[currentRetry % variations.length];
          }

          final response = await http.post(
            Uri.parse(
                'https://api-inference.huggingface.co/models/${_selectedImageModel}'),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'inputs': prompt,
              'options': {
                'wait_for_model': true,
                'use_cache': false,
                'seed': DateTime
                    .now()
                    .millisecondsSinceEpoch % 100000
                // Random seed for variation
              }
            }),
          ).timeout(Duration(seconds: _modelTimeout));

          if (response.statusCode == 200) {
            setState(() {
              // Replace previous media with new one
              _currentMedia = MediaItem(
                bytes: response.bodyBytes,
                prompt: _promptController.text,
                timestamp: DateTime.now(),
                model: _selectedImageModelName,
              );
              _isGeneratingImage = false;
            });

            // Update model performance history
            _modelPerformance[_selectedImageModel] = true;

            _showSuccessMessage(
                'Image generated successfully with $_selectedImageModelName!');
            success = true;
          } else if (response.statusCode == 500 || response.statusCode == 503) {
            // Mark this model as problematic
            _modelPerformance[_selectedImageModel] = false;
            throw Exception('Model server error - trying different model');
          } else {
            throw Exception('Failed to generate image: ${response.statusCode}');
          }
        } catch (e) {
          currentRetry++;

          // Mark current model as problematic
          _modelPerformance[_selectedImageModel] = false;

          // If on last retry, try a different model
          if (currentRetry >= maxRetries - 1) {
            _switchToRecommendedModel();
          }

          // Wait before retrying
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      if (!success) {
        throw Exception('Failed after multiple attempts');
      }
    } catch (e) {
      setState(() {
        _isGeneratingImage = false;
      });
      String errorMessage = e.toString();
      if (errorMessage.contains('XMLHttpRequest')) {
        errorMessage =
        'Connection issue. Please check your internet and try again.';
      } else if (errorMessage.contains('500') || errorMessage.contains('503')) {
        errorMessage = 'Server is busy. Trying a different model might help.';
      } else if (errorMessage.contains('timeout')) {
        errorMessage = 'Request timed out. The model may be too busy.';
        // Mark as problematic
        _modelPerformance[_selectedImageModel] = false;
        // Auto-switch to a faster model
        _switchToRecommendedModel();
      }
      _showErrorMessage('Error generating image: $errorMessage');
    }
  }

  // Universal download function that works on both web and mobile
  Future<void> _downloadImage() async {
    if (_currentMedia == null) {
      _showErrorMessage('No image to download');
      return;
    }

    setState(() {
      _isDownloading = true;
    });

    try {
      if (kIsWeb) {
        await _downloadImageWeb();
      } else {
        await _downloadImageMobile();
      }
    } catch (e) {
      _showErrorMessage('Failed to save image: ${e.toString()}');
    } finally {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  // Web-specific download function
  Future<void> _downloadImageWeb() async {
    final timestamp = DateTime
        .now()
        .millisecondsSinceEpoch
        .toString();
    final safePrompt = _currentMedia!.prompt.replaceAll(RegExp(r'[^\w\s]'), '')
        .substring(0,
        _currentMedia!.prompt.length > 20 ? 20 : _currentMedia!.prompt.length)
        .trim().replaceAll(' ', '_');
    final fileName = 'ai_image_${safePrompt}_$timestamp.png';

    // Create a blob and download it
    final blob = html.Blob([_currentMedia!.bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..style.display = 'none';

    html.document.body!.children.add(anchor);
    anchor.click();

    // Clean up
    html.document.body!.children.remove(anchor);
    html.Url.revokeObjectUrl(url);

    _showSuccessMessage('Image downloaded successfully');
  }

  // Mobile-specific download function
  Future<void> _downloadImageMobile() async {
    // Request storage permission
    var status = await Permission.storage.request();
    if (!status.isGranted) {
      throw Exception('Storage permission denied');
    }

    // Get application directory for saving the file
    final appDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime
        .now()
        .millisecondsSinceEpoch
        .toString();
    final safePrompt = _currentMedia!.prompt.replaceAll(RegExp(r'[^\w\s]'), '')
        .substring(0,
        _currentMedia!.prompt.length > 20 ? 20 : _currentMedia!.prompt.length)
        .trim().replaceAll(' ', '_');

    final fileName = 'ai_image_${safePrompt}_$timestamp.png';
    final filePath = '${appDir.path}/$fileName';

    // Write the file
    final file = File(filePath);
    await file.writeAsBytes(_currentMedia!.bytes);

    _showSuccessMessage('Image saved to: $filePath');
  }

  // Model selector dialog with speed indicator
  Future<void> _showModelSelector() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          StatefulBuilder(
            builder: (context, setModalState) =>
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Select Image Generation Model",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),

                      // Option to disable slow models
                      SwitchListTile(
                        title: Text("Fast Models Only"),
                        subtitle: Text(
                            "Skip slower models for quicker generation"),
                        value: _disableSlowModels,
                        onChanged: (value) {
                          setModalState(() {
                            _disableSlowModels = value;
                          });
                          // Update in parent state too
                          setState(() {
                            _disableSlowModels = value;
                          });

                          // If enabling fast models only and current model is slow, switch
                          if (value && _imageModels.firstWhere(
                                (model) =>
                            model['endpoint'] == _selectedImageModel,
                            orElse: () => {'speed': 'fast'},
                          )['speed'] == 'slow') {
                            _switchToRecommendedModel();
                          }
                        },
                      ),

                      const SizedBox(height: 20),

                      // Model list with speed indicators
                      ..._imageModels
                          .where((model) =>
                      !_disableSlowModels || model['speed'] != 'slow')
                          .map((model) =>
                          _buildModelTile(
                            model,
                            _selectedImageModel == model['endpoint'],
                          )),
                    ],
                  ),
                ),
          ),
    );
  }

  // Improved model tile with speed indicator
  Widget _buildModelTile(Map<String, String> model, bool isSelected) {
    // Model speed indicator
    IconData speedIcon;
    Color speedColor;
    String speedText;

    switch (model['speed']) {
      case 'very fast':
        speedIcon = Icons.bolt;
        speedColor = Colors.green;
        speedText = "Very Fast";
        break;
      case 'fast':
        speedIcon = Icons.speed;
        speedColor = Colors.green.shade700;
        speedText = "Fast";
        break;
      case 'medium':
        speedIcon = Icons.timer;
        speedColor = Colors.orange;
        speedText = "Medium";
        break;
      case 'slow':
        speedIcon = Icons.hourglass_bottom;
        speedColor = Colors.red;
        speedText = " Slow";
        break;
      default:
        speedIcon = Icons.speed;
        speedColor = Colors.blue;
        speedText = "Standard";
    }

    return InkWell(
      onTap: () {
        setState(() {
          _selectedImageModel = model['endpoint']!;
          _selectedImageModelName = model['name']!;
          _updateModelTimeout();
        });
        Navigator.pop(context);
        _showSuccessMessage('Selected ${model['name']}');

        if (model['speed'] == 'slow') {
          _showWarningMessage('This model may be slower. Please be patient.');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.blue.shade300 : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? Colors.blue.shade100 : Colors.grey.shade100,
              ),
              child: Icon(
                speedIcon,
                size: 16,
                color: speedColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model['name'] ?? 'Unknown Model',
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight
                          .normal,
                      color: isSelected ? Colors.blue.shade700 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    model['description']!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(speedIcon, size: 12, color: speedColor),
                      const SizedBox(width: 4),
                      Text(
                        speedText,
                        style: TextStyle(
                          fontSize: 11,
                          color: speedColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: Colors.blue.shade500,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  void _showWarningMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildMediaView() {
    if (_currentMedia == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_search, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              "Enter a prompt and generate your first image",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Image display with download button - now in a SingleChildScrollView
    return SingleChildScrollView(
      child: Column(
        children: [
          InteractiveViewer(
            panEnabled: true,
            boundaryMargin: const EdgeInsets.all(20),
            minScale: 0.5,
            maxScale: 3.0,
            child: Image.memory(
              _currentMedia!.bytes,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            onPressed: _isDownloading ? null : _downloadImage,
            backgroundColor: Colors.blue.shade700,
            elevation: 4,
            mini: true,
            tooltip: 'Download Image',
            child: _isDownloading
                ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.download, size: 20),
          ),
          // Add padding at bottom to ensure content is visible
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _listenToSpeech() async {
    if (!_isListening) {
      bool available = await _speechToText.initialize(
        onStatus: (val) => print('onStatus: $val'),
        onError: (val) => print('onError: $val'),
      );
      if (available) {
        setState(() => _isListening = true);
        _speechToText.listen(
          onResult: (val) =>
              setState(() {
                _promptController.text = val.recognizedWords;
              }),
        );
      }
    } else {
      _speechToText.stop();
      setState(() => _isListening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use a ScrollView at the top level instead of nested Expanded widgets
    return Scaffold(
      appBar: AppBar(
        title: Text("AI Image Generator"),
        backgroundColor: Colors.blue.shade700,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade50, Colors.purple.shade50],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                // Main content area with FIXED height constraints
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Container(
                      // Keep your decoration
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Card(
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(
                                sigmaX: 10.0, sigmaY: 10.0),
                            child: Container(
                              padding: const EdgeInsets.all(20.0),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Title
                                  const Text(
                                    "Describe what you want to create",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // Prompt input with voice button next to it
                                  Container(
                                    height: 60, // Fixed height for text field
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _promptController,
                                            decoration: InputDecoration(
                                              hintText: "E.g., A sunset over mountains with a lake reflection...",
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius
                                                    .circular(15),
                                                borderSide: BorderSide.none,
                                              ),
                                              filled: true,
                                              fillColor: Colors.grey.shade100,
                                              prefixIcon: const Icon(
                                                  Icons.edit),
                                              contentPadding: const EdgeInsets
                                                  .symmetric(
                                                  vertical: 16, horizontal: 16),
                                            ),
                                            maxLines: 1, // Use a single line to save space
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.mic,
                                              color: _isListening
                                                  ? Colors.red
                                                  : Colors.blue.shade800),
                                          onPressed: _listenToSpeech,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // Model selection indicators
                                  Row(
                                    children: [
                                      Expanded(
                                        child: InkWell(
                                          onTap: () => _showModelSelector(),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8, horizontal: 12),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade50,
                                              borderRadius: BorderRadius
                                                  .circular(10),
                                              border: Border.all(
                                                  color: Colors.blue.shade200),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.image, size: 16,
                                                    color: Colors.blue
                                                        .shade700),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    _selectedImageModelName,
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.blue
                                                            .shade800),
                                                    overflow: TextOverflow
                                                        .ellipsis,
                                                  ),
                                                ),
                                                Icon(Icons.arrow_drop_down,
                                                    color: Colors.blue
                                                        .shade700),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 16),

                                  // Generate button
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _isGeneratingImage
                                              ? null
                                              : _generateImage,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blue
                                                .shade600,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 16),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius
                                                  .circular(15),
                                            ),
                                            elevation: 4,
                                          ),
                                          icon: _isGeneratingImage
                                              ? SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                              : const Icon(
                                              Icons.image, size: 20),
                                          label: Text(
                                            _isGeneratingImage
                                                ? "Creating..."
                                                : "Generate Image",
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),

                                  // Make the image display scrollable and take remaining space
                                  Expanded(
                                    child: _buildMediaView(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
