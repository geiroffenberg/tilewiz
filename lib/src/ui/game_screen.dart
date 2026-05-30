import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/admob_config.dart';
import '../game/game_controller.dart';
import '../game/sound_manager.dart';
import 'ad_banner.dart';
import 'interstitial_ad_manager.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final GameController _controller;
  late final SoundManager _sound;
  late final InterstitialAdManager _interstitialAds;
  late final AnimationController _flashController;
  List<(int, int)> _activeFlashCells = const <(int, int)>[];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _controller = GameController();
    _sound = SoundManager();
    _interstitialAds = InterstitialAdManager();
    _interstitialAds.initialize();
    _initAsync();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _flashController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _activeFlashCells = const <(int, int)>[];
        });
      }
    });
    _controller.addListener(_onControllerUpdate);
  }

  Future<void> _initAsync() async {
    await _sound.initialize();
    await _controller.initialize();
  }

  void _onControllerUpdate() {
    // Handle sound events.
    final GameEvent? event = _controller.pendingEvent;
    if (event != null) {
      _controller.consumeEvent();
      switch (event) {
        case GameEvent.select:
          _sound.playSelect();
        case GameEvent.confirm:
          _sound.playConfirm();
        case GameEvent.reject:
          _sound.playReject();
        case GameEvent.points:
          _sound.playPoints();
        case GameEvent.tick:
          _sound.playTick();
        case GameEvent.gameOver:
          _sound.playDrop();
          _interstitialAds.markGameCompleted();
      }
    }

    // Handle flash cells.
    final List<(int, int)> flashes = _controller.flashCells;
    if (flashes.isNotEmpty) {
      _controller.consumeFlashCells();
      setState(() {
        _activeFlashCells = flashes;
      });
      _flashController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.disposeController();
    _controller.dispose();
    _flashController.dispose();
    _sound.dispose();
    _interstitialAds.dispose();
    super.dispose();
  }

  Future<void> _handlePlayAgain() async {
    await _interstitialAds.showIfEligible();
    _controller.startNewGame();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TileWiz',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF163833),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1D6A61),
          secondary: Color(0xFFD66A4A),
          surface: Color(0xFF163833),
        ),
      ),
      home: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, _) {
          return Scaffold(
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0xFF1A4A42), Color(0xFF112E28)],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: <Widget>[
                    _TopBar(controller: _controller),
                    _StatusBar(controller: _controller),
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: _BoardPanel(
                            controller: _controller,
                            sound: _sound,
                            flashController: _flashController,
                            activeFlashCells: _activeFlashCells,
                            onPlayAgainPressed: _handlePlayAgain,
                          ),
                        ),
                      ),
                    ),
                    _RackPanel(controller: _controller, sound: _sound),
                    _ActionBar(controller: _controller, sound: _sound),
                    if (AdMobConfig.adsEnabled) const AdBanner(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Top Bar ──────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: <Widget>[
          Text(
            'TileWiz',
            style: GoogleFonts.cormorantGaramond(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFF0E5D0),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 38,
            height: 38,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 28,
              icon: const Icon(
                Icons.info_outline_rounded,
                color: Color(0x99F0E5D0),
              ),
              onPressed: () => _showInfoDialog(context),
            ),
          ),
          const Spacer(),
          if (controller.countdownActive)
            _CountdownBadge(seconds: controller.countdownRemaining),
          if (controller.countdownActive) const SizedBox(width: 14),
          _MiniScore(label: 'SCORE', value: controller.score.toString()),
          const SizedBox(width: 14),
          _MiniScore(label: 'HIGH', value: controller.highScore.toString()),
        ],
      ),
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final bool urgent = seconds <= 10;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: urgent ? const Color(0xEED66A4A) : const Color(0xCC1D6A61),
        borderRadius: BorderRadius.circular(10),
        boxShadow: urgent
            ? <BoxShadow>[
                const BoxShadow(
                  color: Color(0x88D66A4A),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.timer_rounded,
            size: 18,
            color: urgent ? const Color(0xFFFFF0E0) : const Color(0xCCF0E5D0),
          ),
          const SizedBox(width: 4),
          Text(
            '${seconds}s',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFF0E5D0),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniScore extends StatelessWidget {
  const _MiniScore({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: const Color(0x99F0E5D0),
            letterSpacing: 1.2,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFF0E5D0),
          ),
        ),
      ],
    );
  }
}

// ─── Status Bar ───────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: const Color(0x22000000),
      child: Text(
        controller.statusMessage,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 18,
          color: const Color(0xCCF0E5D0),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ─── Board Panel ──────────────────────────────────────────────

class _BoardPanel extends StatelessWidget {
  const _BoardPanel({
    required this.controller,
    required this.sound,
    required this.flashController,
    required this.activeFlashCells,
    required this.onPlayAgainPressed,
  });

  final GameController controller;
  final SoundManager sound;
  final AnimationController flashController;
  final List<(int, int)> activeFlashCells;
  final VoidCallback onPlayAgainPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0E2420),
        borderRadius: BorderRadius.circular(14),
      ),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double cellSize = constraints.maxWidth / boardSize;

            return Stack(
              children: <Widget>[
                // Grid cells.
                GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: boardSize,
                  ),
                  itemCount: boardSize * boardSize,
                  itemBuilder: (BuildContext context, int index) {
                    final int row = index ~/ boardSize;
                    final int col = index % boardSize;
                    return _BoardCell(
                      row: row,
                      col: col,
                      controller: controller,
                      sound: sound,
                    );
                  },
                ),

                // Flash overlay.
                if (activeFlashCells.isNotEmpty)
                  AnimatedBuilder(
                    animation: flashController,
                    builder: (BuildContext context, _) {
                      final double glow =
                          1.0 - Curves.easeIn.transform(flashController.value);
                      return Stack(
                        children: activeFlashCells.map(((int, int) cell) {
                          final double x = cell.$2 * cellSize;
                          final double y = cell.$1 * cellSize;
                          return Positioned(
                            left: x + 2,
                            top: y + 2,
                            width: cellSize - 4,
                            height: cellSize - 4,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color.fromRGBO(
                                    255,
                                    255,
                                    255,
                                    glow * 0.7,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: Color.fromRGBO(
                                        255,
                                        215,
                                        0,
                                        glow * 0.6,
                                      ),
                                      blurRadius: 16 * glow,
                                      spreadRadius: 4 * glow,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),

                // Game overlays.
                if (!controller.isReady)
                  const _BoardOverlay(message: 'Loading...')
                else if (!controller.isRunning && !controller.isGameOver)
                  _BoardOverlay(
                    message: 'TileWiz',
                    detail: 'Tap Start to play',
                    actionLabel: 'Start',
                    onPressed: controller.startNewGame,
                  )
                else if (controller.isGameOver)
                  _BoardOverlay(
                    message: 'Game Over',
                    detail: 'Score: ${controller.score}',
                    actionLabel: 'Play Again',
                    onPressed: onPlayAgainPressed,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BoardCell extends StatelessWidget {
  const _BoardCell({
    required this.row,
    required this.col,
    required this.controller,
    required this.sound,
  });

  final int row;
  final int col;
  final GameController controller;
  final SoundManager sound;

  @override
  Widget build(BuildContext context) {
    final PlacedTile? permanent = controller.board[row][col];
    final PlacedTile? pending = _findPending();
    final CellMultiplier mult = boardMultipliers[row][col];
    final bool isCenter =
        row == centerCell &&
        col == centerCell &&
        permanent == null &&
        pending == null;
    final bool isHintCell = _isHintCell();

    return GestureDetector(
      onTap: () {
        sound.playTap();
        controller.tapCell(row, col);
      },
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: permanent != null
            ? _LetterFace(
                letter: permanent.letter,
                points: permanent.points,
                isBlank: permanent.isBlank,
              )
            : pending != null
            ? _PendingLetterFace(
                letter: pending.letter,
                points: pending.points,
                isBlank: pending.isBlank,
              )
            : _EmptyCell(
                multiplier: mult,
                isCenter: isCenter,
                isHint: isHintCell,
              ),
      ),
    );
  }

  PlacedTile? _findPending() {
    for (final PlacedTile p in controller.pendingPlacements) {
      if (p.row == row && p.column == col) return p;
    }
    return null;
  }

  bool _isHintCell() {
    final HintResult? hint = controller.activeHint;
    if (hint == null) return false;
    return hint.placements.any(
      (PlacedTile p) => p.row == row && p.column == col,
    );
  }
}

class _EmptyCell extends StatelessWidget {
  const _EmptyCell({
    required this.multiplier,
    required this.isCenter,
    required this.isHint,
  });

  final CellMultiplier multiplier;
  final bool isCenter;
  final bool isHint;

  @override
  Widget build(BuildContext context) {
    Color bgColor = const Color(0xFF1A3D36);
    String? label;

    if (isHint) {
      bgColor = const Color(0x55D66A4A);
    } else if (multiplier == CellMultiplier.triple3x) {
      bgColor = const Color(0xFF2D1A3D);
      label = '3×';
    } else if (multiplier == CellMultiplier.double2x) {
      bgColor = const Color(0xFF1A2D3D);
      label = '2×';
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x1888D5C4)),
      ),
      child: Center(
        child: isCenter
            ? Text(
                '★',
                style: GoogleFonts.cormorantGaramond(
                  fontSize: 20,
                  color: const Color(0x77F0E5D0),
                ),
              )
            : label != null
            ? Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0x66F0E5D0),
                ),
              )
            : null,
      ),
    );
  }
}

// ─── Rack Panel ───────────────────────────────────────────────

class _RackPanel extends StatelessWidget {
  const _RackPanel({required this.controller, required this.sound});

  final GameController controller;
  final SoundManager sound;

  @override
  Widget build(BuildContext context) {
    if (!controller.isRunning && !controller.isGameOver) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List<Widget>.generate(controller.rack.length, (int index) {
          final RackTile tile = controller.rack[index];
          final bool isSelected = controller.selectedRackIndex == index;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              onTap: () {
                controller.selectRackTile(index);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 48,
                height: 54,
                transform: isSelected
                    ? (Matrix4.identity()
                        ..translateByDouble(0.0, -6.0, 0.0, 1.0))
                    : Matrix4.identity(),
                child: _LetterFace(
                  letter: tile.letter,
                  points: tile.points,
                  isBlank: tile.isBlank,
                  highlighted: isSelected,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Action Bar ───────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.controller, required this.sound});

  final GameController controller;
  final SoundManager sound;

  @override
  Widget build(BuildContext context) {
    if (!controller.isRunning && !controller.isGameOver) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: <Widget>[
          _SmallActionButton(
            label: 'Confirm',
            accent: true,
            onPressed: controller.hasPendingPlacements
                ? () {
                    controller.confirmMove();
                  }
                : null,
          ),
          const SizedBox(width: 8),
          _SmallActionButton(
            label: 'Recall',
            onPressed: controller.hasPendingPlacements
                ? () {
                    sound.playTap();
                    controller.recallPlacements();
                  }
                : null,
          ),
          const Spacer(),
          _SmallActionButton(
            label: 'Hint (${controller.hintsRemaining})',
            onPressed: controller.isRunning && controller.hintsRemaining > 0
                ? () {
                    sound.playTap();
                    controller.useHint();
                  }
                : null,
          ),
          const SizedBox(width: 8),
          _SmallActionButton(
            label: 'Give Up',
            onPressed: controller.isRunning
                ? () {
                    sound.playTap();
                    controller.giveUp();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────

class _LetterFace extends StatelessWidget {
  const _LetterFace({
    required this.letter,
    required this.points,
    this.isBlank = false,
    this.highlighted = false,
  });

  final String letter;
  final int points;
  final bool isBlank;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isBlank
              ? const <Color>[Color(0xFFE0D8F0), Color(0xFFB0A0C8)]
              : const <Color>[Color(0xFFFBEBCB), Color(0xFFE0B86F)],
        ),
        borderRadius: BorderRadius.circular(7),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: highlighted
                ? const Color(0x88D66A4A)
                : const Color(0x33000000),
            blurRadius: highlighted ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: highlighted
            ? Border.all(color: const Color(0xFFD66A4A), width: 2)
            : null,
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  letter,
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: isBlank
                        ? const Color(0xFF4A3060)
                        : const Color(0xFF55321A),
                    height: 1.0,
                  ),
                ),
                Text(
                  '$points',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isBlank
                        ? const Color(0x994A3060)
                        : const Color(0x9955321A),
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingLetterFace extends StatelessWidget {
  const _PendingLetterFace({
    required this.letter,
    required this.points,
    this.isBlank = false,
  });

  final String letter;
  final int points;
  final bool isBlank;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isBlank
              ? const <Color>[Color(0xCCE0D8F0), Color(0xCCB0A0C8)]
              : const <Color>[Color(0xCCFBEBCB), Color(0xCCE0B86F)],
        ),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: const Color(0xAAD66A4A),
          width: 1.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x44D66A4A),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  letter == '?' ? '★' : letter,
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: isBlank
                        ? const Color(0xFF4A3060)
                        : const Color(0xFF55321A),
                    height: 1.0,
                  ),
                ),
                Text(
                  '$points',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isBlank
                        ? const Color(0x994A3060)
                        : const Color(0x9955321A),
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    required this.label,
    required this.onPressed,
    this.accent = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    if (accent) {
      return SizedBox(
        height: 42,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFD66A4A),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0x44D66A4A),
            disabledForegroundColor: const Color(0x66FFFFFF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 42,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xCCF0E5D0),
          disabledForegroundColor: const Color(0x44F0E5D0),
          side: BorderSide(
            color: onPressed != null
                ? const Color(0x44F0E5D0)
                : const Color(0x22F0E5D0),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─── Board Overlay ────────────────────────────────────────────

class _BoardOverlay extends StatelessWidget {
  const _BoardOverlay({
    required this.message,
    this.detail,
    this.actionLabel,
    this.onPressed,
  });

  final String message;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xCC0E2420),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFF0E5D0),
                  ),
                ),
                if (detail != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    detail!,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      color: const Color(0xAAF0E5D0),
                    ),
                  ),
                ],
                if (actionLabel != null && onPressed != null) ...<Widget>[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: onPressed,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD66A4A),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Info Dialog ──────────────────────────────────────────────

void _showInfoDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return Dialog(
        backgroundColor: const Color(0xFF1A3D36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Text(
                  'TileWiz',
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFF0E5D0),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'A word-building board game',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    color: const Color(0xAAF0E5D0),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _infoHeading('How to Play'),
              _infoParagraph(
                'Select a letter from your rack, then tap a board cell to '
                'place it. Your first tile must cross the center star (★). '
                'After that, tiles must be placed next to existing tiles.',
              ),
              const SizedBox(height: 12),
              _infoHeading('Confirming Words'),
              _infoParagraph(
                'Once you\'ve placed tiles, tap Confirm. The game checks if '
                'valid words (2+ letters) are formed horizontally or vertically. '
                'If no word is found, tiles return to your rack.',
              ),
              const SizedBox(height: 12),
              _infoHeading('Scoring'),
              _infoParagraph(
                'Each letter has a Scrabble-style point value. '
                'Cells marked 2× or 3× multiply the entire word score '
                'when a newly placed tile lands on them.',
              ),
              const SizedBox(height: 12),
              _infoHeading('Blank Tiles  ★'),
              _infoParagraph(
                'Blank tiles are worth 0 points but automatically become '
                'whichever letter scores the most at that position.',
              ),
              const SizedBox(height: 12),
              _infoHeading('Hints'),
              _infoParagraph(
                'You get 3 hints per game. A hint highlights a cell where '
                'you can place a letter to form a word.',
              ),
              const SizedBox(height: 12),
              _infoHeading('Timer'),
              _infoParagraph(
                'After 60 seconds of inactivity, a 30-second countdown starts. '
                'Make a move before time runs out!',
              ),
              const SizedBox(height: 12),
              _infoHeading('Game Over'),
              _infoParagraph(
                'The game ends when the board is full, no moves are possible, '
                'time runs out, or you give up. Beat your high score!',
              ),
              const SizedBox(height: 20),
              Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD66A4A),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _infoHeading(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: GoogleFonts.cormorantGaramond(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: const Color(0xFFF0E5D0),
      ),
    ),
  );
}

Widget _infoParagraph(String text) {
  return Text(
    text,
    style: GoogleFonts.spaceGrotesk(
      fontSize: 15,
      color: const Color(0xCCF0E5D0),
      height: 1.5,
    ),
  );
}
