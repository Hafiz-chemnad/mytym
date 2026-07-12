import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoBubble extends StatefulWidget {
  final String mediaUrl;
  final String caption;
  
  const VideoBubble({
    super.key, 
    required this.mediaUrl, 
    required this.caption,
  });

  @override
  State<VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<VideoBubble> {
  VideoPlayerController? _controller;
  bool _initializing = false;
  bool _hasError = false;

  Future<void> _initAndPlay() async {
    if (_controller != null || _initializing) return;
    setState(() => _initializing = true);
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.mediaUrl));
      await controller.initialize();
      await controller.play();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
      controller.addListener(() => setState(() {}));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _hasError = true;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    
    if (_hasError) {
      return Container(
        width: 220, 
        height: 140, 
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B), 
          borderRadius: BorderRadius.circular(8)
        ), 
        child: const Center(
          child: Text(
            "Couldn't load video", 
            style: TextStyle(color: Colors.white70, fontSize: 12)
          )
        )
      );
    }
    
    if (controller == null || !controller.value.isInitialized) {
      return GestureDetector(
        onTap: _initAndPlay, 
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8), 
          child: Container(
            width: 220, 
            height: 140, 
            color: const Color(0xFF1E293B), 
            child: Center(
              child: _initializing 
                ? const CircularProgressIndicator(color: Colors.white70) 
                : Container(
                    padding: const EdgeInsets.all(14), 
                    decoration: const BoxDecoration(
                      color: Colors.black54, 
                      shape: BoxShape.circle
                    ), 
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32)
                  )
            )
          )
        )
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 220,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            AspectRatio(
              aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio, 
              child: VideoPlayer(controller)
            ),
            GestureDetector(
              onTap: () => setState(() => controller.value.isPlaying ? controller.pause() : controller.play()), 
              child: Container(
                color: Colors.transparent, 
                child: Center(
                  child: AnimatedOpacity(
                    opacity: controller.value.isPlaying ? 0 : 1, 
                    duration: const Duration(milliseconds: 200), 
                    child: Container(
                      padding: const EdgeInsets.all(10), 
                      decoration: const BoxDecoration(
                        color: Colors.black45, 
                        shape: BoxShape.circle
                      ), 
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28)
                    )
                  )
                )
              )
            ),
            VideoProgressIndicator(
              controller, 
              allowScrubbing: true, 
              padding: const EdgeInsets.all(4), 
              colors: const VideoProgressColors(
                playedColor: Color(0xFF0F172A), 
                bufferedColor: Colors.white38, 
                backgroundColor: Colors.white24
              )
            ),
          ],
        ),
      ),
    );
  }
}