import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:math' as math;
import 'package:flutter_tts/flutter_tts.dart';

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() {
    return 'TimeoutException: $message';
  }
}

class StoryPage extends StatefulWidget {
  final String caption;
  final String? imageUrl;
  final File? imageFile;
  final String? base64Image;

  const StoryPage({
    Key? key,
    required this.caption,
    this.imageUrl,
    this.imageFile,
    this.base64Image,
  }) : super(key: key);

  @override
  _StoryPageState createState() => _StoryPageState();
}

class _StoryPageState extends State<StoryPage> with SingleTickerProviderStateMixin {
  String? _story;
  bool _isLoading = false;
  String? _error;
  String _progressStatus = 'Initializing...';
  FlutterTts flutterTts = FlutterTts();
  bool _isSpeaking = false;
  int _storyAttempt = 0; // Counter to force new story generation
  late AnimationController _animationController;
  late Animation<double> _animation;
  final ScrollController _scrollController = ScrollController();

  // Improved fallback stories with more variety
  final List<String> _fallbackStories = [
    "The image captured a moment of pure serenity. Sunlight filtered through ancient trees, casting dappled shadows on the forest floor. A small stream meandered through moss-covered rocks, its gentle burbling the only sound breaking the silence. For anyone who discovered this hidden spot, time seemed to stand still, offering a brief respite from the chaos of everyday life.",

    "The bustling city street came alive at twilight. Neon signs flickered to life, painting the rain-slicked pavement in blues and purples. People hurried past, collars turned up against the drizzle, while street vendors called out their wares. Among them walked a lone figure, unhurried and observant, seeing beauty where others saw only routine.",

    "The old lighthouse stood sentinel over the churning sea below. For generations, it had guided sailors safely to shore, its beam cutting through the densest fog. Now automated, it still performed its duty faithfully, though the keeper's quarters remained empty. Local legends claimed that on stormy nights, one could still see the silhouette of the last keeper in the tower window, ensuring all was well.",

    "In the heart of the garden, colors danced in the gentle breeze. Flowers of every hue swayed rhythmically, their petals catching sunlight and transforming it into a kaleidoscope of natural beauty. A tiny creature moved almost imperceptibly among them, its skin changing colors to match each blossom it visited, a master of disguise in a world of vibrant wonder.",

    "The mountain lake reflected the sky so perfectly that it was impossible to tell where one ended and the other began. Surrounded by towering pines and rugged peaks, this hidden gem remained untouched by time, a sanctuary for wildlife and weary travelers alike. As the evening approached, the water's surface turned to liquid gold, capturing the day's final moments in its serene embrace."
  ];

  @override
  void initState() {
    super.initState();
    _initTts();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
    _startGeneratingStory();
  }

  @override
  void dispose() {
    _stopSpeaking();
    flutterTts.stop();
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);

    flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
      });
    });
  }

  Future<void> _startSpeaking() async {
    if (_story != null) {
      setState(() {
        _isSpeaking = true;
      });
      await flutterTts.speak(_story!);
    }
  }

  Future<void> _stopSpeaking() async {
    if (_isSpeaking) {
      setState(() {
        _isSpeaking = false;
      });
      await flutterTts.stop();
    }
  }

  Future<void> _startGeneratingStory() async {
    if (!mounted) return;

    // Stop any ongoing narration
    _stopSpeaking();

    setState(() {
      _isLoading = true;
      _error = null;
      _story = null;
      _progressStatus = 'Starting story generation...';
    });

    // Increment the story attempt counter to ensure we get a different story
    _storyAttempt++;

    try {
      await _generateStory();
    } catch (e) {
      debugPrint('Error in _startGeneratingStory: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
          _story = null;
        });
      }
    }
  }

  Future<void> _generateStory() async {
    try {
      _updateProgress('Creating a story based on the image...');

      // Create a more detailed and structured prompt that emphasizes completeness
      final String caption = widget.caption.trim();
      final prompt = "Write a complete, self-contained short story (200-250 words) inspired by this image description: \"$caption\". Include sensory details, emotions, and ensure the story has a clear beginning, middle, and end. Do not truncate or leave the story incomplete.";

      try {
        // Add the attempt number to ensure different results each time
        final response = await _makeHuggingFaceApiRequest("$prompt (Attempt: $_storyAttempt)");
        if (!mounted) return;

        setState(() {
          _story = _formatStory(response.trim());
          _isLoading = false;
          _error = null;
        });

        // Scroll to top when new story is loaded
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }

      } catch (e) {
        debugPrint('API error: $e - Falling back to local story generation');
        _updateProgress('API unavailable. Using local story generation...');

        // Fallback to local story generation
        await _generateLocalStory();
      }

    } catch (e, stackTrace) {
      debugPrint('Error in _generateStory: $e');
      debugPrint('Stack trace: $stackTrace');

      // Final fallback - use a pre-written story
      if (mounted) {
        _updateProgress('Falling back to pre-written story...');
        await Future.delayed(const Duration(seconds: 1));

        if (mounted) {
          setState(() {
            // Select a random fallback story that best matches the caption
            // Use the attempt counter as additional randomization factor
            _story = _selectBestFallbackStory(_storyAttempt);
            _story = _story! + "\n\n[Note: This is a pre-written story as the story generation API is currently unavailable.]";
            _isLoading = false;
            _error = null;
          });
        }
      }
    }
  }

  String _formatStory(String rawStory) {
    // Clean up story text while preserving all content
    String story = rawStory.trim();

    // Remove any potential instruction text or prefixes
    if (story.contains("[/INST]")) {
      story = story.split("[/INST]").last.trim();
    }

    // Remove any potential AI model completion markers
    story = story
        .replaceAll("<eos>", "")
        .replaceAll("<EOS>", "")
        .replaceAll("[END]", "")
        .replaceAll("[STOP]", "");

    // Normalize newlines for better display (but don't reduce them too much)
    story = story.replaceAll(RegExp(r'\n{4,}'), '\n\n\n');

    // If story is too short, add a note
    if (story.length < 100) {
      story += "\n\n[Note: The story generation API provided a brief response. You can try again for a longer story.]";
    }

    return story;
  }

  String _selectBestFallbackStory(int attempt) {
    // Extract keywords from caption
    final keywords = widget.caption
        .toLowerCase()
        .split(RegExp(r'[ ,\.!?]'))
        .where((word) => word.length > 3)
        .toList();

    // Score each fallback story based on keyword matches
    Map<int, int> storyScores = {};

    for (int i = 0; i < _fallbackStories.length; i++) {
      int score = 0;
      String storyLower = _fallbackStories[i].toLowerCase();

      for (final keyword in keywords) {
        if (storyLower.contains(keyword)) {
          score += 1;
        }
      }

      storyScores[i] = score;
    }

    // Find the story with the highest score
    int bestStoryIndex = 0;
    int highestScore = -1;

    storyScores.forEach((index, score) {
      if (score > highestScore) {
        highestScore = score;
        bestStoryIndex = index;
      }
    });

    // If no good match found or we're regenerating, force a different story
    if (highestScore <= 0 || attempt > 1) {
      // Use the attempt number to ensure we get a different story each time
      bestStoryIndex = (attempt % _fallbackStories.length);
    }

    return _fallbackStories[bestStoryIndex];
  }

  Future<void> _generateLocalStory() async {
    if (!mounted) return;

    _updateProgress('Processing image description...');
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;
    _updateProgress('Creating characters...');
    await Future.delayed(const Duration(milliseconds: 700));

    if (!mounted) return;
    _updateProgress('Building narrative...');
    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;

    // Extract keywords from caption
    final keywords = widget.caption
        .toLowerCase()
        .split(RegExp(r'[ ,\.!?]'))
        .where((word) => word.length > 3)
        .toList();

    // Generate a more customized story based on keywords and attempt number
    final storyElements = _generateStoryElements(keywords);
    final generatedStory = _createStoryFromElements(storyElements, widget.caption, _storyAttempt);

    if (!mounted) return;

    setState(() {
      _story = generatedStory;
      _isLoading = false;
      _error = null;
    });
  }

  Map<String, dynamic> _generateStoryElements(List<String> keywords) {
    // Define some story building blocks
    final settings = [
      'forest', 'beach', 'mountain', 'city', 'village', 'desert',
      'castle', 'farm', 'island', 'cabin', 'space station', 'garden',
      'meadow', 'riverbank', 'ancient ruins', 'marketplace', 'library'
    ];

    final times = [
      'dawn', 'morning', 'noon', 'afternoon', 'evening',
      'twilight', 'night', 'midnight', 'dusk', 'sunrise'
    ];

    final weathers = [
      'sunny', 'cloudy', 'rainy', 'stormy', 'snowy', 'foggy', 'windy',
      'misty', 'humid', 'clear', 'crisp', 'balmy', 'frosty'
    ];

    final characters = [
      'traveler', 'artist', 'scientist', 'child', 'elder',
      'musician', 'teacher', 'doctor', 'writer', 'explorer',
      'gardener', 'photographer', 'naturalist', 'poet', 'student'
    ];

    final emotions = [
      'joy', 'wonder', 'courage', 'serenity', 'hope',
      'determination', 'curiosity', 'satisfaction', 'awe',
      'contentment', 'inspiration', 'nostalgia', 'anticipation'
    ];

    // Try to match keywords with story elements
    String setting = _findMatchOrRandom(keywords, settings);
    String time = _findMatchOrRandom(keywords, times);
    String weather = _findMatchOrRandom(keywords, weathers);
    String character = _findMatchOrRandom(keywords, characters);
    String emotion = _findMatchOrRandom(keywords, emotions);

    return {
      'setting': setting,
      'time': time,
      'weather': weather,
      'character': character,
      'emotion': emotion
    };
  }

  String _findMatchOrRandom(List<String> keywords, List<String> options) {
    // Try to find a matching element from keywords
    for (final keyword in keywords) {
      for (final option in options) {
        if (keyword.contains(option) || option.contains(keyword)) {
          return option;
        }
      }
    }

    // If no match, return random element
    return options[DateTime.now().millisecond % options.length];
  }

  String _createStoryFromElements(Map<String, dynamic> elements, String caption, int attempt) {
    // Rotate through different story structures based on attempt number
    final storyFormats = [
      _createNarrativeFormat,
      _createReflectiveFormat,
      _createMysteriousFormat,
      _createAdventureFormat,
      _createDreamlikeFormat,
    ];

    // Use attempt number to select a different story format each time
    final formatIndex = attempt % storyFormats.length;
    return storyFormats[formatIndex](elements, caption);
  }

  String _createNarrativeFormat(Map<String, dynamic> elements, String caption) {
    final setting = elements['setting'];
    final time = elements['time'];
    final weather = elements['weather'];
    final character = elements['character'];
    final emotion = elements['emotion'];

    final intro = "It was a $weather $time in the $setting. ";
    final characterIntro = "A $character wandered through the scenery, filled with a sense of $emotion. ";
    final body = "The $character paused to take in the view. ${_createSentenceFromCaption(caption)} ";
    final reflection = "This moment stirred something deep within the $character's heart. ";
    final conclusion = "As the $time slowly shifted, the $character knew this was a memory that would last forever, a perfect snapshot of $emotion captured in time.";

    return intro + characterIntro + body + reflection + conclusion;
  }

  String _createReflectiveFormat(Map<String, dynamic> elements, String caption) {
    final setting = elements['setting'];
    final time = elements['time'];
    final weather = elements['weather'];
    final character = elements['character'];
    final emotion = elements['emotion'];

    final intro = "The $character had often visited the $setting, but never during a $weather $time. ";
    final observation = "Today felt different. ${_createSentenceFromCaption(caption)} ";
    final reflection = "Standing there, a sense of $emotion washed over the $character unexpectedly. ";
    final memory = "It reminded them of distant memories, almost forgotten until this very moment. ";
    final conclusion = "Sometimes the most profound revelations come when we least expect them, in places we thought we knew well.";

    return intro + observation + reflection + memory + conclusion;
  }

  String _createMysteriousFormat(Map<String, dynamic> elements, String caption) {
    final setting = elements['setting'];
    final time = elements['time'];
    final weather = elements['weather'];
    final character = elements['character'];
    final emotion = elements['emotion'];

    final intro = "Nobody had warned the $character about the $setting during $time, especially in $weather conditions. ";
    final discovery = "${_createSentenceFromCaption(caption)} The sight was both enchanting and unsettling. ";
    final mystery = "A strange sense of $emotion crept over the $character. Was this place truly as it appeared? ";
    final question = "Something seemed to call from within the depths of the scene, something ancient and knowing. ";
    final conclusion = "The $character left with more questions than answers, but would certainly return when the time was right.";

    return intro + discovery + mystery + question + conclusion;
  }

  String _createAdventureFormat(Map<String, dynamic> elements, String caption) {
    final setting = elements['setting'];
    final time = elements['time'];
    final weather = elements['weather'];
    final character = elements['character'];
    final emotion = elements['emotion'];

    final intro = "The journey had brought the $character far from home to this $weather $setting at $time. ";
    final challenge = "After overcoming numerous obstacles, the destination was finally in sight. ";
    final reward = "${_createSentenceFromCaption(caption)} It was more magnificent than any description had suggested. ";
    final feeling = "A profound sense of $emotion filled the $character's chest, making every hardship worthwhile. ";
    final conclusion = "Some treasures can only be found by those brave enough to venture beyond the familiar, into the unknown.";

    return intro + challenge + reward + feeling + conclusion;
  }

  String _createDreamlikeFormat(Map<String, dynamic> elements, String caption) {
    final setting = elements['setting'];
    final time = elements['time'];
    final weather = elements['weather'];
    final character = elements['character'];
    final emotion = elements['emotion'];

    final intro = "The $character couldn't be certain if this was reality or a dream - the $weather $setting at $time had an otherworldly quality. ";
    final surreal = "Colors seemed more vivid, sounds more musical, time itself moved differently here. ";
    final vision = "${_createSentenceFromCaption(caption)} The scene before them defied ordinary explanation. ";
    final feeling = "An overwhelming sense of $emotion enveloped the $character like a warm embrace. ";
    final conclusion = "Whether real or imagined, some experiences transform us forever, leaving an imprint on our souls that remains long after we wake.";

    return intro + surreal + vision + feeling + conclusion;
  }

  String _createSentenceFromCaption(String caption) {
    // Extract nouns and adjectives (approximation)
    final words = caption.split(' ');
    final descriptiveWords = words.where((word) => word.length > 4).toList();

    if (descriptiveWords.isEmpty) {
      return "The scene was exactly as pictured - beautiful and serene.";
    }

    // Use some of these words to create a descriptive sentence
    final selectedWords = <String>[];
    final maxWords = math.min(descriptiveWords.length, 3);

    for (var i = 0; i < maxWords; i++) {
      selectedWords.add(descriptiveWords[i]);
    }

    return "The ${selectedWords.join(' and ')} created a scene of breathtaking beauty.";
  }

  void _updateProgress(String status) {
    if (mounted) {
      setState(() {
        _progressStatus = status;
      });
    }
  }

  Future<String> _makeHuggingFaceApiRequest(String prompt) async {
    // Use a better instruction-following model
    final endpoint = 'https://api-inference.huggingface.co/models/mistralai/Mistral-7B-Instruct-v0.2';
    final apiKey = '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';

    // More structured prompt formatting for instruction models
    final requestBody = {
      'inputs': "<s>[INST] $prompt [/INST]",
      'parameters': {
        'max_new_tokens': 500,  // Increased from 250 for longer stories
        'temperature': 0.7,     // Good balance between creativity and coherence
        'return_full_text': false,
      },
    };

    try {
      debugPrint('Making API request with prompt: $prompt');
      debugPrint('Request body: ${jsonEncode(requestBody)}');

      // Increased timeout for larger model
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30)); // Increased from 20 to 30 seconds

      debugPrint('Response status code: ${response.statusCode}');
      // Log the full response for debugging
      debugPrint('Full response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final decoded = jsonDecode(response.body);
          String generatedText = '';

          if (decoded is List && decoded.isNotEmpty) {
            generatedText = decoded.first['generated_text'] ?? 'No text generated.';
          } else if (decoded is Map && decoded.containsKey('generated_text')) {
            generatedText = decoded['generated_text'];
          } else {
            throw Exception('Unexpected response format');
          }

          // Remove any potential truncation indicators from the API
          generatedText = generatedText
              .replaceAll("[INCOMPLETE]", "")
              .replaceAll("...", "");

          return generatedText;
        } catch (e) {
          debugPrint('Error decoding JSON: $e');

          // If we can't parse JSON but have text, just use the text directly
          if (response.body.isNotEmpty) {
            return response.body;
          }
          throw Exception('Failed to parse response: $e');
        }
      } else if (response.statusCode == 503) {
        // Model is loading
        throw Exception('Model is currently loading. Please try again in a moment.');
      } else {
        // Capture detailed error message
        var errorDetails = response.body;
        try {
          final errorJson = jsonDecode(response.body);
          if (errorJson is Map && errorJson.containsKey('error')) {
            errorDetails = errorJson['error'];
          }
        } catch (_) {}

        throw Exception('API request failed: ${response.statusCode} - $errorDetails');
      }
    } catch (e) {
      debugPrint('Error in _makeHuggingFaceApiRequest: $e');
      throw Exception('Failed to generate text: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Gradient background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.blue.shade50,
                  Colors.indigo.shade50,
                ],
              ),
            ),
          ),

          // Background pattern
          Opacity(
            opacity: 0.05,
            child: Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/pattern.png'),
                  repeat: ImageRepeat.repeat,
                ),
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // App bar
                SliverAppBar(
                  title: const Text(
                    'Your Story',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  floating: true,
                  backgroundColor: Colors.white.withOpacity(0.9),
                  elevation: 0,
                  actions: [
                    if (_story != null)
                      IconButton(
                        icon: const Icon(Icons.share),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Share functionality to be implemented'))
                          );
                        },
                      ),
                  ],
                ),

                // Content
                SliverToBoxAdapter(
                  child: FadeTransition(
                    opacity: _animation,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Image with animation
                          Hero(
                            tag: 'story_image',
                            child: _buildImageWidget(),
                          ),
                          const SizedBox(height: 24),

                          // Content (loading, error, or story)
                          if (_isLoading) ...[
                            _buildLoadingDisplay(),
                          ] else if (_error != null) ...[
                            _buildErrorDisplay(),
                          ] else if (_story != null) ...[
                            _buildStoryDisplay(),
                          ] else ...[
                            const Text('No story available', style: TextStyle(fontSize: 16, color: Colors.grey)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageWidget() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 280,
          height: 280,
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.white,
              width: 4,
            ),
          ),
          child: _getImageWidget(),
        ),
      ),
    );
  }

  Widget _buildLoadingDisplay() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              SizedBox(
                height: 60,
                width: 60,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo.shade400),
                  backgroundColor: Colors.grey.shade200,
                  strokeWidth: 4,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _progressStatus,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.indigo.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Creating a unique story just for you...",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStoryDisplay() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity, // Ensure the container takes full width
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Based on "${widget.caption}"',
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Colors.indigo.shade700,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _story!,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.6,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Action buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Listen button
            Expanded(
              child: ElevatedButton.icon(
                icon: Icon(_isSpeaking ? Icons.stop : Icons.volume_up),
                label: Text(_isSpeaking ? 'Stop' : 'Listen'),
                onPressed: () {
                  if (_isSpeaking) {
                    _stopSpeaking();
                  } else {
                    _startSpeaking();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isSpeaking ? Colors.red.shade400 : Colors.indigo.shade400,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Generate new story button
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Generate New Story'),
                onPressed: _startGeneratingStory,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade400,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
  Widget _buildErrorDisplay() {
    return Column(
      children: [
        const Icon(
          Icons.error_outline,
          size: 48,
          color: Colors.red,
        ),
        const SizedBox(height: 16),
        Text(
          'Oops! Something went wrong.',
          style: TextStyle(
            fontSize: 18,
            color: Colors.red.shade700,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _error ?? 'An unknown error occurred.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: Colors.red.shade600,
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _startGeneratingStory,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade400,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Try Again'),
        ),
      ],
    );
  }

  Widget _getImageWidget() {
    if (widget.imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: widget.imageUrl!,
        fit: BoxFit.cover,
        placeholder: (context, url) => const Center(
          child: CircularProgressIndicator(),
        ),
        errorWidget: (context, url, error) => const Icon(Icons.error),
      );
    } else if (widget.imageFile != null) {
      return Image.file(
        widget.imageFile!,
        fit: BoxFit.cover,
      );
    } else if (widget.base64Image != null) {
      return Image.memory(
        base64Decode(widget.base64Image!),
        fit: BoxFit.cover,
      );
    } else {
      return const Center(
        child: Icon(Icons.image, size: 100, color: Colors.grey),
      );
    }
  }
}