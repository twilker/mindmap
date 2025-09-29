import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const Color primarySky = Color(0xFF2AA8FF);
  static const Color nightNavy = Color(0xFF0B1220);
  static const Color cloudWhite = Color(0xFFF7FAFF);
  static const Color lavenderLift = Color(0xFF9AA6FF);
  static const Color graphSlate = Color(0xFF334155);

  static const Gradient heroGradient = LinearGradient(
    colors: [Color(0xFF6D69FF), Color(0xFF00E5FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
