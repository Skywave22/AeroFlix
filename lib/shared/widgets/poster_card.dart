import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

/// Poster tile. Also the focus unit for Android TV / d-pad and keyboard
/// navigation: it can take focus, shows a brand ring, and activates on the
/// remote's centre button.
class PosterCard extends StatefulWidget {
  final String imageUrl, title;
  final String? metadata;
  final VoidCallback? onTap;
  final double width;
  const PosterCard(
      {super.key,
      required this.imageUrl,
      required this.title,
      this.metadata,
      this.onTap,
      this.width = AppSpacing.posterWidth});

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final width = widget.width;
    final height = width * 1.5;

    return FocusableActionDetector(
      onShowFocusHighlight: (f) {
        if (f != _focused) setState(() => _focused = f);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap?.call();
          return null;
        }),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _focused ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: AppRadii.mdRadius,
                    border: Border.all(
                        color: _focused ? AppColors.accent : Colors.transparent,
                        width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadii.mdRadius,
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: _poster(),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.cardTitle.copyWith(fontSize: 13)),
                if (widget.metadata != null && widget.metadata!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(widget.metadata!, style: AppTypography.metadata),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _poster() {
    if (widget.imageUrl.isEmpty) {
      return Container(
        color: AppColors.surface,
        child: const Center(
            child: Icon(Icons.movie_creation_outlined,
                color: AppColors.textMuted, size: 28)),
      );
    }
    return CachedNetworkImage(
      imageUrl: widget.imageUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: AppColors.surface),
      errorWidget: (_, __, ___) => Container(
        color: AppColors.surface,
        child: const Center(
            child: Icon(Icons.image_not_supported_outlined,
                color: AppColors.textMuted, size: 28)),
      ),
    );
  }
}
