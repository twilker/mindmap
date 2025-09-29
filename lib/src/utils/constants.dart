import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

const double appCornerRadius = 12;

const double nodeMaxWidth = 240;
const double nodeMinWidth = 80;
const double nodeMinHeight = 44;
const double nodeHorizontalPadding = 16;
const double nodeTextFieldPadding = 8;
const double nodeVerticalPadding = 12;
const double nodeBorderWidth = 1;
const double nodeSelectedBorderWidth = 2;
const double nodeCursorWidth = 2;
const double nodeCaretGap = 1;
const double nodeCaretMargin = nodeCursorWidth + nodeCaretGap;
const double nodeHorizontalGap = 80;
const double nodeVerticalGap = 24;
const double zoomMinScale = 0.2;
const double zoomMaxScale = 3.0;
const double boundsMargin = 80;
const double focusViewportMargin = 96;

const textStyle = TextStyle(
  fontSize: 16,
  height: 1.3,
  color: AppColors.nightNavy,
  fontFamily: 'Inter',
);

const List<Color> branchColors = [
  AppColors.primarySky,
  Color(0xFF6D69FF),
  AppColors.lavenderLift,
  Color(0xFF00E5FF),
  Color(0xFF7BCBFF),
  AppColors.graphSlate,
];
