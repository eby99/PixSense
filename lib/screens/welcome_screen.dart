import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({Key? key}) : super(key: key);

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeInAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Set preferred orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeInAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Interval(0.3, 0.8, curve: Curves.easeInOut),
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Interval(0.4, 0.9, curve: Curves.easeOutBack),
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions for responsive sizing
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/PiXsense1.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo space - the logo is part of the wallpaper, centered in the image
            SizedBox(height: screenHeight * 0.55), // This pushes content below the logo

            // Animated tagline text - white text, no background
            Padding(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.1),
              child: FadeTransition(
                opacity: _fadeInAnimation,
                child: AnimatedTextKit(
                  animatedTexts: [
                    TypewriterAnimatedText(
                      'Transform your images into stories with AI',
                      textStyle: TextStyle(
                        fontSize: screenWidth * 0.045,
                        fontFamily: 'Montserrat',
                        color: Colors.white,
                        letterSpacing: 0.5,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 5,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      speed: const Duration(milliseconds: 50),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  totalRepeatCount: 1,
                  displayFullTextOnTap: true,
                ),
              ),
            ),

            SizedBox(height: screenHeight * 0.04),

            // Get Started Button
            FadeTransition(
              opacity: _fadeInAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: GestureDetector(
                  onTap: () {
                    // Add a tactile feedback
                    HapticFeedback.mediumImpact();

                    // Navigate to login screen
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                          var curve = Curves.easeOutCubic;
                          var curveTween = CurveTween(curve: curve);

                          var fadeAnimation = Tween<double>(
                            begin: 0.0,
                            end: 1.0,
                          ).animate(animation);

                          var slideAnimation = Tween<Offset>(
                            begin: Offset(0, 0.2),
                            end: Offset.zero,
                          ).chain(curveTween).animate(animation);

                          return FadeTransition(
                            opacity: fadeAnimation,
                            child: SlideTransition(
                              position: slideAnimation,
                              child: child,
                            ),
                          );
                        },
                        transitionDuration: Duration(milliseconds: 700),
                      ),
                    );
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.08,
                      vertical: screenHeight * 0.016,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          spreadRadius: 0,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Get Started',
                          style: TextStyle(
                            color: Color(0xFF2196F3), // Matching the blue from wallpaper
                            fontSize: screenWidth * 0.045,
                            fontFamily: 'Montserrat',
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF2196F3),
                          size: screenWidth * 0.045,
                        ),
                      ],
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