import 'dart:math' show pi;
import 'package:flutter/material.dart';

class GaugeBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 4;

    // fill paint for the background
    final fillPaint = Paint()
      ..color = Color.fromARGB(223, 36, 160, 231)
      ..style = PaintingStyle.fill;

    // fraw the filled circle background
    canvas.drawCircle(
      center,
      radius,
      fillPaint,
    );

    // stroke paint for the border between the circle and the progression steps
    final strokePaint = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // draw the circle border
    canvas.drawCircle(
      center,
      radius,
      strokePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GaugeIndicatorPainter extends CustomPainter {
  final double confidence;

  GaugeIndicatorPainter({required this.confidence});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 3.2;

    // define total steps and calculate current step
    const totalSteps = 20;
    final currentStep = (confidence * totalSteps).round();
    final stepAngle = (2 * pi) / totalSteps;

    // create gradient for steps
    final gradient = SweepGradient(
      startAngle: -pi / 2,
      endAngle: 3 * pi / 2,
      colors: [
        Colors.green,
        Colors.green,
      ],
      stops: [0.0, 1.0],
    );

   
    final unselectedPaint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;


    final selectedPaint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;


    for (var i = 0; i < totalSteps; i++) {
      final startAngle = pi / 2 + (i * stepAngle);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        stepAngle * 0.8,
        false,
        unselectedPaint,
      );
    }


    for (var i = 0; i < currentStep; i++) {
      final startAngle = pi / 2 + (i * stepAngle);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        stepAngle * 0.8,
        false,
        selectedPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
