import 'package:flutter/material.dart';

import '../layout/mind_map_layout.dart';
import '../theme/app_colors.dart';
import 'constants.dart';

class SvgExporter {
  SvgExporter({required this.layout, required this.bounds});

  final MindMapLayoutResult layout;
  final Rect bounds;

  String build() {
    final buffer = StringBuffer();
    final width = bounds.width == 0 ? 1 : bounds.width;
    final height = bounds.height == 0 ? 1 : bounds.height;
    buffer.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="${bounds.left} ${bounds.top} $width $height">',
    );
    final textColor = _colorHex(AppColors.nightNavy);
    final cardFill = _colorHex(AppColors.cloudWhite);
    buffer.writeln(
      '<defs><style>.node-text{font-family:"Inter","Helvetica Neue",Arial,sans-serif;font-size:${textStyle.fontSize}px;fill:$textColor;}</style></defs>',
    );

    for (final data in layout.nodes.values) {
      if (data.parentId == null) {
        continue;
      }
      final parent = layout.nodes[data.parentId];
      if (parent == null) {
        continue;
      }
      final color = _colorHex(
        branchColors[(data.branchIndex >= 0 ? data.branchIndex : 0) %
            branchColors.length],
      );
      final startX =
          parent.center.dx +
          (data.isLeft ? -parent.size.width / 2 : parent.size.width / 2);
      final startY = parent.center.dy;
      final endX =
          data.center.dx +
          (data.isLeft ? data.size.width / 2 : -data.size.width / 2);
      final endY = data.center.dy;
      final control = data.isLeft
          ? -nodeHorizontalGap / 2
          : nodeHorizontalGap / 2;
      buffer.writeln(
        '<path d="M $startX $startY C ${startX + control} $startY ${endX - control} $endY $endX $endY" stroke="$color" stroke-width="2" fill="none"/>',
      );
    }

    final lineHeight = (textStyle.fontSize ?? 16) * (textStyle.height ?? 1.3);
    for (final data in layout.nodes.values) {
      final stroke = _colorHex(
        branchColors[(data.branchIndex >= 0 ? data.branchIndex : 0) %
            branchColors.length],
      );
      final rectX = data.topLeft.dx;
      final rectY = data.topLeft.dy;
      buffer.writeln('<g>');
      final details = data.node.details.trim();
      if (details.isNotEmpty) {
        final escapedDetails =
            _escape(details).replaceAll('\n', '&#10;');
        buffer.writeln('<desc>$escapedDetails</desc>');
      }
      buffer.writeln(
        '<rect x="$rectX" y="$rectY" width="${data.size.width}" height="${data.size.height}" rx="16" ry="16" fill="$cardFill" stroke="$stroke" stroke-width="1.5"/>',
      );
      var textY = rectY + nodeVerticalPadding + (textStyle.fontSize ?? 16);
      final textX = data.center.dx;
      for (final line in data.lines) {
        final escaped = _escape(line);
        buffer.writeln(
          '<text x="$textX" y="$textY" text-anchor="middle" class="node-text">$escaped</text>',
        );
        textY += lineHeight;
      }
      buffer.writeln('</g>');
    }

    buffer.writeln('</svg>');
    return buffer.toString();
  }

  String _colorHex(Color color) {
    final argb = color.toARGB32();
    final rgb = argb & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  String _escape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}
