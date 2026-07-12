import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class AudioBubble extends StatefulWidget {
  final String mediaUrl;
  final bool isMine;
  
  const AudioBubble({
    super.key, 
    required this.mediaUrl, 
    required this.isMine,
  });

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _loadError = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadAndPlay() async {
    setState(() => _isLoading = true);
    try {
      await _player.setUrl(widget.mediaUrl);
      if (!mounted) return;
      setState(() {
        _isLoaded = true;
        _isLoading = false;
      });
      _player.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = true;
        _isLoading = false;
      });
    }
  }

  String _fmt(Duration? d) {
    if (d == null) return "0:00";
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isMine ? const Color(0xFFD1FAE5) : const Color(0xFFF1F5F9);
    final borderColor = widget.isMine ? const Color(0xFFA7F3D0) : const Color(0xFFE2E8F0);

    if (_loadError) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor, 
          borderRadius: BorderRadius.circular(24), 
          border: Border.all(color: borderColor)
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min, 
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: Colors.redAccent), 
            SizedBox(width: 8), 
            Text("Couldn't load audio", style: TextStyle(fontSize: 12))
          ]
        ),
      );
    }

    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor, 
        borderRadius: BorderRadius.circular(24), 
        border: Border.all(color: borderColor)
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (context, snapshot) {
              final playing = snapshot.data?.playing ?? false;
              
              return GestureDetector(
                onTap: _isLoading ? null : () {
                  if (!_isLoaded) {
                    _loadAndPlay();
                  } else if (playing) {
                    _player.pause();
                  } else {
                    if (snapshot.data?.processingState == ProcessingState.completed) {
                      _player.seek(Duration.zero);
                    }
                    _player.play();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A), 
                    shape: BoxShape.circle
                  ),
                  child: _isLoading 
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                      : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 22),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                final total = _player.duration ?? Duration.zero;
                final maxMs = total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0;
                final valueMs = position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3, 
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5), 
                        overlayShape: SliderComponentShape.noOverlay, 
                        activeTrackColor: const Color(0xFF0F172A), 
                        inactiveTrackColor: const Color(0xFF0F172A).withOpacity(0.2), 
                        thumbColor: const Color(0xFF0F172A)
                      ),
                      child: Slider(
                        min: 0, 
                        max: maxMs, 
                        value: valueMs, 
                        onChanged: (v) {
                          if (_isLoaded) _player.seek(Duration(milliseconds: v.toInt()));
                        }
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4), 
                      child: Text(
                        _isLoaded ? "${_fmt(position)} / ${_fmt(total)}" : "Tap to load", 
                        style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))
                      )
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}