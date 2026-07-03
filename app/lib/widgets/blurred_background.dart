import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class BlurredBackground extends StatelessWidget {
  final String? imageUrl;
  final double sigma;
  final double darken;

  const BlurredBackground({
    super.key,
    required this.imageUrl,
    this.sigma = 30,
    this.darken = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 800),
      child: imageUrl != null
          ? SizedBox.expand(
              key: ValueKey(imageUrl),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: sigma,
                      sigmaY: sigma,
                      tileMode: TileMode.decal,
                    ),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                    ),
                  ),
                  Container(color: Colors.black.withValues(alpha: darken)),
                ],
              ),
            )
          : SizedBox.expand(
              key: const ValueKey('empty'),
              child: Container(color: Colors.black),
            ),
    );
  }
}
