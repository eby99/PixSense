import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';

// Assuming you have a DashboardScreen for navigation
import 'dashboard_screen.dart';

class CapturedImage {
  final String path;
  final Uint8List bytes;
  final String caption;
  final DateTime timestamp;

  CapturedImage({
    required this.path,
    required this.bytes,
    required this.caption,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class AIImageCaptionerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Image Captioner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: CaptureScreen(),
    );
  }
}

class CaptureScreen extends StatefulWidget {
  @override
  _CaptureScreenState createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  List<CapturedImage> _capturedImages = [];

  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  bool _isCameraOn = true;
  String _errorMessage = '';
  int _currentCameraIndex = 0;

  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _initializeCamera();

    // Animation for processing indicator
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: 0, end: 1).animate(_animationController);
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        await _setupCamera(_currentCameraIndex);
      }
    } catch (e) {
      _handleError('Failed to initialize camera: $e');
    }
  }

  Future<void> _setupCamera(int cameraIndex) async {
    if (_cameras.isEmpty) return;

    // Dispose existing controller if it exists
    await _cameraController?.dispose();

    _cameraController = CameraController(
      _cameras[cameraIndex],
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _isCameraOn = true;
        });
      }
    } catch (e) {
      _handleError('Camera setup failed: $e');
    }
  }

  void _toggleCamera() {
    setState(() {
      if (_isCameraOn) {
        _cameraController?.dispose();
        _isCameraOn = false;
      } else {
        _initializeCamera();
      }
    });
  }

  void _switchCamera() {
    if (_cameras.length > 1) {
      _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;
      _setupCamera(_currentCameraIndex);
    }
  }

  Future<void> _captureAndAnalyzeImage() async {
    if (!_isCameraInitialized || _isProcessing || !_isCameraOn) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = '';
    });

    try {
      final XFile imageFile = await _cameraController!.takePicture();
      final Uint8List imageBytes = await imageFile.readAsBytes();

      // Generate caption with improved error handling
      String caption = await _generateImageCaption(imageBytes);

      setState(() {
        _capturedImages.insert(0, CapturedImage(
          path: imageFile.path,
          bytes: imageBytes,
          caption: caption,
        ));
        _isProcessing = false;
      });
    } catch (e) {
      _handleError('Image capture failed: $e');
    }
  }

  Future<String> _generateImageCaption(Uint8List imageBytes) async {
    // List of models to try in order of preference
    final models = [
      'microsoft/git-base-coco',
      'Salesforce/blip-image-captioning-large',
      'nlpconnect/vit-gpt2-image-captioning',
      'Xenova/vit-gpt2-image-captioning'
    ];

    // API key - Consider moving this to a secure environment variable
    final apiKey = const String.fromEnvironment('HUGGINGFACE_API_KEY',
        defaultValue: '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');

    for (String modelName in models) {
      try {
        String base64Image = base64Encode(imageBytes);

        final response = await http.post(
          Uri.parse('https://api-inference.huggingface.co/models/$modelName'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'inputs': base64Image,
            'wait_for_model': true  // Important: Wait for model to load if needed
          }),
        ).timeout(
          Duration(seconds: 45),  // Increased timeout
          onTimeout: () {
            throw TimeoutException('Caption generation timed out');
          },
        );

        if (response.statusCode == 200) {
          // More robust parsing of response
          dynamic responseBody = jsonDecode(response.body);

          // Handle different response formats
          String caption = '';
          if (responseBody is List) {
            caption = responseBody.isNotEmpty
                ? responseBody[0]['generated_text'] ?? ''
                : '';
          } else if (responseBody is Map) {
            caption = responseBody['generated_text'] ?? '';
          }

          // More comprehensive caption validation
          if (caption.isNotEmpty &&
              caption.length > 10 &&
              !caption.toLowerCase().contains('unable') &&
              !caption.toLowerCase().contains('error')) {
            return caption.trim();
          }
        } else {
          // Log the error response for debugging
          print('Model $modelName returned status code: ${response.statusCode}');
          print('Response body: ${response.body}');
        }
      } catch (e) {
        // More detailed error logging
        print('Error with model $modelName: $e');

        // Check for model loading error
        if (e.toString().contains('model is loading')) {
          await Future.delayed(Duration(seconds: 10));  // Wait and retry
          continue;
        }
      }
    }

    // More informative fallback message
    return 'Could not generate a meaningful caption. Please try again.';
  }

  void _handleError(String message) {
    setState(() {
      _errorMessage = message;
      _isProcessing = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            // Navigate back to dashboard
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => DashboardScreen()),
            );
          },
        ),
        title: Text(
          'AI Image Captioner',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.switch_camera),
            onPressed: _switchCamera,
            tooltip: 'Switch Camera',
          ),
          IconButton(
            icon: Icon(_isCameraOn ? Icons.power_settings_new : Icons.power),
            onPressed: _toggleCamera,
            tooltip: _isCameraOn ? 'Turn Off Camera' : 'Turn On Camera',
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Camera Preview
                Expanded(
                  flex: 3,
                  child: _buildCameraPreview(),
                ),

                // Captured Images Gallery
                Expanded(
                  flex: 2,
                  child: _buildCapturedImagesGallery(),
                ),

                // Capture Button
                _buildCaptureButton(),
              ],
            ),

            // Processing Overlay
            if (_isProcessing)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        RotationTransition(
                          turns: _animation,
                          child: Icon(
                            Icons.settings,
                            color: Colors.white,
                            size: 80,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Analyzing Image...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (!_isCameraInitialized || !_isCameraOn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_off,
              size: 80,
              color: Colors.grey[400],
            ),
            SizedBox(height: 16),
            Text(
              'Camera is turned off',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 15,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: CameraPreview(_cameraController!),
      ),
    );
  }

  Widget _buildCapturedImagesGallery() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: _capturedImages.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.camera_alt,
              size: 80,
              color: Colors.grey[400],
            ),
            SizedBox(height: 16),
            Text(
              'Capture images to see gallery',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ],
        ),
      )
          : ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _capturedImages.length,
        itemBuilder: (context, index) {
          final capture = _capturedImages[index];
          return Container(
            width: 250,
            margin: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(15),
                    ),
                    child: Image.memory(
                      capture.bytes,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Caption:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        capture.caption,
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 14,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCaptureButton() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: ElevatedButton.icon(
        onPressed: _isCameraOn ? _captureAndAnalyzeImage : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isCameraOn
              ? Theme.of(context).colorScheme.primary
              : Colors.grey,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        icon: Icon(Icons.camera_alt),
        label: Text(
          'Capture & Analyze',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _animationController.dispose();
    super.dispose();
  }
}

void main() {
  runApp(AIImageCaptionerApp());
}