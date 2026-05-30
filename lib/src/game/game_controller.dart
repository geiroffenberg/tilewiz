import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'word_dictionary.dart';

const int boardSize = 7;
const int rackSize = 7;
const int centerCell = 3; // boardSize ~/ 2
const int hintLimit = 3;
const int hintShardThreshold = 3;
const int gameMoveTimerSeconds = 60;
const String highScoreKey = 'tilewiz_high_score';

/// Sound events the UI should react to.
enum GameEvent { select, confirm, reject, points, tick, gameOver }

/// Board cell multipliers.
enum CellMultiplier { none, double2x, triple3x }

/// The multiplier layout for the 7×7 board.
/// 3× in corners, 2× in a ring closer to center.
final List<List<CellMultiplier>> boardMultipliers = _buildMultiplierGrid();

List<List<CellMultiplier>> _buildMultiplierGrid() {
  final List<List<CellMultiplier>> grid = List<List<CellMultiplier>>.generate(
    boardSize,
    (_) => List<CellMultiplier>.filled(boardSize, CellMultiplier.none),
  );

  // 3× corners.
  grid[0][0] = CellMultiplier.triple3x;
  grid[0][boardSize - 1] = CellMultiplier.triple3x;
  grid[boardSize - 1][0] = CellMultiplier.triple3x;
  grid[boardSize - 1][boardSize - 1] = CellMultiplier.triple3x;

  // 2× positions — 8 cells forming a ring.
  grid[1][1] = CellMultiplier.double2x;
  grid[1][boardSize - 2] = CellMultiplier.double2x;
  grid[boardSize - 2][1] = CellMultiplier.double2x;
  grid[boardSize - 2][boardSize - 2] = CellMultiplier.double2x;
  grid[0][centerCell] = CellMultiplier.double2x;
  grid[boardSize - 1][centerCell] = CellMultiplier.double2x;
  grid[centerCell][0] = CellMultiplier.double2x;
  grid[centerCell][boardSize - 1] = CellMultiplier.double2x;

  return grid;
}

class PlacedTile {
  const PlacedTile({
    required this.letter,
    required this.points,
    required this.row,
    required this.column,
    this.isBlank = false,
  });

  final String letter;
  final int points;
  final int row;
  final int column;
  final bool isBlank;
}

class ScoredWord {
  const ScoredWord({
    required this.word,
    required this.baseScore,
    required this.multiplier,
    required this.cells,
  });

  final String word;
  final int baseScore;
  final int multiplier;
  final List<(int, int)> cells;

  int get totalScore => baseScore * multiplier;
}

class RackTile {
  const RackTile({required this.letter, required this.points, this.isBlank = false});

  final String letter;
  final int points;
  final bool isBlank;
}

class HintResult {
  const HintResult({
    required this.word,
    required this.placements,
  });

  final String word;
  final List<PlacedTile> placements;
}

class TopMoveResult {
  const TopMoveResult({
    required this.word,
    required this.score,
    required this.placement,
  });

  final String word;
  final int score;
  final PlacedTile placement;
}

class GameController extends ChangeNotifier {
  GameController({Random? random}) : _random = random ?? Random();

  final Random _random;

  // Board: null means empty cell.
  final List<List<PlacedTile?>> _board = List<List<PlacedTile?>>.generate(
    boardSize,
    (_) => List<PlacedTile?>.filled(boardSize, null),
  );

  late WordDictionary _dictionary;
  SharedPreferences? _preferences;

  List<RackTile> _rack = <RackTile>[];
  int? _selectedRackIndex;
  List<PlacedTile> _pendingPlacements = <PlacedTile>[];
  bool _isReady = false;
  bool _isRunning = false;
  bool _isGameOver = false;
  int _score = 0;
  int _highScore = 0;
  int _hintsRemaining = hintLimit;
  int _hintShards = 0;
  String _statusMessage = 'Loading dictionary...';
  List<ScoredWord> _lastScoredWords = const <ScoredWord>[];
  HintResult? _activeHint;
  TopMoveResult? _lastTopMissedMove;
  String? _lastRejectedWord;

  // Consumable sound event.
  GameEvent? _pendingEvent;

  // Timer state.
  Timer? _moveTimer;
  int _countdownRemaining = 0;
  bool _countdownActive = false;

  // Flash cells for word clear animation.
  List<(int, int)> _flashCells = const <(int, int)>[];

  bool get isReady => _isReady;
  bool get isRunning => _isRunning;
  bool get isGameOver => _isGameOver;
  int get score => _score;
  int get highScore => _highScore;
  int get hintsRemaining => _hintsRemaining;
  int get hintShards => _hintShards;
  String get statusMessage => _statusMessage;
  List<RackTile> get rack => _rack;
  int? get selectedRackIndex => _selectedRackIndex;
  List<PlacedTile> get pendingPlacements => _pendingPlacements;
  List<List<PlacedTile?>> get board => _board;
  List<ScoredWord> get lastScoredWords => _lastScoredWords;
  HintResult? get activeHint => _activeHint;
  TopMoveResult? get lastTopMissedMove => _lastTopMissedMove;
  int get countdownRemaining => _countdownRemaining;
  bool get countdownActive => _countdownActive;
  List<(int, int)> get flashCells => _flashCells;
  bool get hasPendingPlacements => _pendingPlacements.isNotEmpty;
  GameEvent? get pendingEvent => _pendingEvent;

  void consumeEvent() {
    _pendingEvent = null;
  }

  bool get isBoardEmpty {
    for (final List<PlacedTile?> row in _board) {
      for (final PlacedTile? tile in row) {
        if (tile != null) return false;
      }
    }
    return true;
  }

  void consumeFlashCells() {
    _flashCells = const <(int, int)>[];
  }

  Future<void> initialize() async {
    _dictionary = await WordDictionary.load();
    _preferences = await SharedPreferences.getInstance();
    _highScore = _preferences?.getInt(highScoreKey) ?? 0;
    _isReady = true;
    _statusMessage = 'Ready';
    notifyListeners();
  }

  void startNewGame() {
    for (final List<PlacedTile?> row in _board) {
      row.fillRange(0, row.length, null);
    }
    _score = 0;
    _hintsRemaining = hintLimit;
    _hintShards = 0;
    _pendingPlacements = <PlacedTile>[];
    _selectedRackIndex = null;
    _lastScoredWords = const <ScoredWord>[];
    _activeHint = null;
    _lastTopMissedMove = null;
    _flashCells = const <(int, int)>[];
    _isGameOver = false;
    _isRunning = true;
    _countdownActive = false;
    _countdownRemaining = 0;
    _cancelTimers();
    _statusMessage = 'Place a tile crossing the center star.';
    _fillRack();
    _startMoveTimer();
    notifyListeners();
  }

  void selectRackTile(int index) {
    if (!_isRunning || _isGameOver) return;
    if (index < 0 || index >= _rack.length) return;
    _selectedRackIndex = (_selectedRackIndex == index) ? null : index;
    _pendingEvent = GameEvent.select;
    notifyListeners();
  }

  void tapCell(int row, int col) {
    if (!_isRunning || _isGameOver) return;

    // If tapping a pending placement, recall it to rack.
    final int pendingIndex = _pendingPlacements.indexWhere(
      (PlacedTile p) => p.row == row && p.column == col,
    );
    if (pendingIndex >= 0) {
      final PlacedTile recalled = _pendingPlacements.removeAt(pendingIndex);
      _rack.add(RackTile(
        letter: recalled.isBlank ? '★' : recalled.letter,
        points: recalled.points,
        isBlank: recalled.isBlank,
      ));
      _selectedRackIndex = null;
      notifyListeners();
      return;
    }

    // Otherwise, try placing the selected rack tile.
    if (_selectedRackIndex == null) return;
    if (_board[row][col] != null) return; // Occupied by permanent tile.
    if (_pendingPlacements.any(
      (PlacedTile p) => p.row == row && p.column == col,
    )) {
      return;
    }

    final RackTile rackTile = _rack[_selectedRackIndex!];
    _rack.removeAt(_selectedRackIndex!);

    _pendingPlacements.add(PlacedTile(
      letter: rackTile.isBlank ? '?' : rackTile.letter,
      points: rackTile.points,
      row: row,
      column: col,
      isBlank: rackTile.isBlank,
    ));

    _selectedRackIndex = null;
    _activeHint = null;
    notifyListeners();
  }

  /// Confirm the current placements: check words, score, lock tiles.
  void confirmMove() {
    if (!_isRunning || _pendingPlacements.isEmpty) return;

    // Temporarily place pending tiles on board for word checking.
    for (final PlacedTile p in _pendingPlacements) {
      _board[p.row][p.column] = p;
    }

    // Connectivity check: on the first move, at least one pending tile must
    // cover the center cell. On subsequent moves, at least one pending tile
    // must be adjacent to an existing permanent tile.
    if (!_arePendingTilesConnected()) {
      for (final PlacedTile p in _pendingPlacements) {
        _board[p.row][p.column] = null;
      }
      for (final PlacedTile p in _pendingPlacements) {
        _rack.add(RackTile(
          letter: p.isBlank ? '★' : p.letter,
          points: p.points,
          isBlank: p.isBlank,
        ));
      }
      _pendingPlacements = <PlacedTile>[];
      _statusMessage = isBoardEmpty
          ? 'First word must cross the center star.'
          : 'Tiles must connect to existing letters.';
      _pendingEvent = GameEvent.reject;
      notifyListeners();
      return;
    }

    // Resolve blank tiles.
    _resolveBlankTiles();

    // Find all new words formed.
    final List<ScoredWord> words = _findNewWords();

    if (words.isEmpty) {
      // Invalid move: remove pending tiles from board, return to rack.
      for (final PlacedTile p in _pendingPlacements) {
        _board[p.row][p.column] = null;
      }
      for (final PlacedTile p in _pendingPlacements) {
        _rack.add(RackTile(
          letter: p.isBlank ? '★' : p.letter,
          points: p.points,
          isBlank: p.isBlank,
        ));
      }
      _pendingPlacements = <PlacedTile>[];
      if (_lastRejectedWord != null) {
        _statusMessage = '"${_lastRejectedWord!.toUpperCase()}" is not a word.';
        _lastRejectedWord = null;
      } else {
        _statusMessage = 'No valid word formed. Try again.';
      }
      _pendingEvent = GameEvent.reject;
      notifyListeners();
      return;
    }

    // Valid move! Score it.
    _lastScoredWords = words;
    int earned = 0;
    for (final ScoredWord w in words) {
      earned += w.totalScore;
    }
    _score += earned;
    if (_score > _highScore) {
      _highScore = _score;
      unawaited(_preferences?.setInt(highScoreKey, _highScore));
    }

    // Collect flash cells from ALL cells in scored words.
    final Set<String> flashSet = <String>{};
    _flashCells = <(int, int)>[];
    for (final ScoredWord w in words) {
      for (final (int r, int c) in w.cells) {
        if (flashSet.add('$r:$c')) {
          _flashCells.add((r, c));
        }
      }
    }

    _statusMessage = words
        .map((ScoredWord w) =>
            '${w.word.toUpperCase()} +${w.totalScore}')
        .join('  •  ');

    if (earned >= 15) {
      _hintShards++;
      if (_hintShards >= hintShardThreshold) {
        _hintShards -= hintShardThreshold;
        _hintsRemaining++;
        _statusMessage = '$_statusMessage  •  Skill bonus: +1 Hint';
      } else {
        _statusMessage =
            '$_statusMessage  •  +1 Hint Shard ($_hintShards/$hintShardThreshold)';
      }
    }

    _pendingPlacements = <PlacedTile>[];
    _activeHint = null;
    _fillRack();
    _resetMoveTimer();

    _pendingEvent = GameEvent.points;

    // Check end conditions.
    _endGameIfNoMovesPossible();

    notifyListeners();
  }

  /// Recall all pending tiles back to rack.
  void recallPlacements() {
    if (!_isRunning) return;
    for (final PlacedTile p in _pendingPlacements) {
      _board[p.row][p.column] = null;
      _rack.add(RackTile(
        letter: p.isBlank ? '★' : p.letter,
        points: p.points,
        isBlank: p.isBlank,
      ));
    }
    _pendingPlacements = <PlacedTile>[];
    _selectedRackIndex = null;
    notifyListeners();
  }

  /// Use a hint. Shows a possible word placement.
  void useHint() {
    if (!_isRunning || _hintsRemaining <= 0) return;
    _hintsRemaining--;
    _activeHint = _findHint();
    if (_activeHint != null) {
      _statusMessage =
          'Hint: try "${_activeHint!.word.toUpperCase()}"';
    } else {
      if (_endGameIfNoMovesPossible()) {
        return;
      }
      _statusMessage = 'No hint available.';
    }
    notifyListeners();
  }

  /// Player gives up.
  void giveUp() {
    if (!_isRunning) return;
    _endGame('You gave up.');
  }

  void disposeController() {
    _cancelTimers();
  }

  // ─── Private helpers ───────────────────────────────────────

  /// Check connectivity: first move must cross center; later moves must have
  /// at least one pending tile adjacent to a permanent (non-pending) tile.
  bool _arePendingTilesConnected() {
    final Set<String> pendingKeys = <String>{};
    for (final PlacedTile p in _pendingPlacements) {
      pendingKeys.add('${p.row}:${p.column}');
    }

    // Check if board has any permanent (non-pending) tiles.
    bool hasPermanent = false;
    for (int r = 0; r < boardSize && !hasPermanent; r++) {
      for (int c = 0; c < boardSize && !hasPermanent; c++) {
        if (_board[r][c] != null && !pendingKeys.contains('$r:$c')) {
          hasPermanent = true;
        }
      }
    }

    // First move: at least one pending tile on the center cell.
    if (!hasPermanent) {
      return _pendingPlacements.any(
        (PlacedTile p) => p.row == centerCell && p.column == centerCell,
      );
    }

    // Subsequent moves: at least one pending tile must be adjacent to a
    // permanent (non-pending) tile already on the board.
    const List<(int, int)> deltas = <(int, int)>[
      (-1, 0), (1, 0), (0, -1), (0, 1),
    ];
    for (final PlacedTile p in _pendingPlacements) {
      for (final (int dr, int dc) in deltas) {
        final int nr = p.row + dr;
        final int nc = p.column + dc;
        if (nr < 0 || nr >= boardSize || nc < 0 || nc >= boardSize) continue;
        if (_board[nr][nc] != null && !pendingKeys.contains('$nr:$nc')) {
          return true;
        }
      }
    }
    return false;
  }

  void _resolveBlankTiles() {
    for (int i = 0; i < _pendingPlacements.length; i++) {
      final PlacedTile p = _pendingPlacements[i];
      if (!p.isBlank) continue;

      String bestLetter = 'E';
      int bestScore = -1;

      for (final String letter in letterPoints.keys) {
        _board[p.row][p.column] = PlacedTile(
          letter: letter,
          points: 0,
          row: p.row,
          column: p.column,
          isBlank: true,
        );
        final List<ScoredWord> candidates = _findNewWords();
        int total = 0;
        for (final ScoredWord w in candidates) {
          total += w.totalScore;
        }
        if (total > bestScore) {
          bestScore = total;
          bestLetter = letter;
        }
      }

      final PlacedTile resolved = PlacedTile(
        letter: bestLetter,
        points: 0,
        row: p.row,
        column: p.column,
        isBlank: true,
      );
      _pendingPlacements[i] = resolved;
      _board[p.row][p.column] = resolved;
    }
  }

  /// Find all new words formed by placing the pending tiles.
  /// Returns an empty list if ANY 2+-letter sequence through a pending tile
  /// is not a valid dictionary word (i.e. invalid cross-words reject the move).
  List<ScoredWord> _findNewWords() {
    final Set<String> pendingKeys = <String>{};
    for (final PlacedTile p in _pendingPlacements) {
      pendingKeys.add('${p.row}:${p.column}');
    }

    final List<ScoredWord> words = <ScoredWord>[];
    final Set<String> seenWords = <String>{}; // "axis:startRow:startCol"

    for (final PlacedTile p in _pendingPlacements) {
      // Horizontal word through this cell.
      final _ExtractedWord? hRaw = _extractRawWord(p.row, p.column, true, pendingKeys, seenWords);
      if (hRaw != null) {
        if (!_dictionary.contains(hRaw.word)) {
          _lastRejectedWord = hRaw.word;
          return const <ScoredWord>[];
        }
        words.add(hRaw.toScoredWord());
      }

      // Vertical word through this cell.
      final _ExtractedWord? vRaw = _extractRawWord(p.row, p.column, false, pendingKeys, seenWords);
      if (vRaw != null) {
        if (!_dictionary.contains(vRaw.word)) {
          _lastRejectedWord = vRaw.word;
          return const <ScoredWord>[];
        }
        words.add(vRaw.toScoredWord());
      }
    }

    return words;
  }

  /// Extract a raw word (not yet dictionary-validated) through the given cell.
  /// Returns null if the sequence is only 1 letter, already seen, or has no
  /// pending tile in it.
  _ExtractedWord? _extractRawWord(
    int row,
    int col,
    bool horizontal,
    Set<String> pendingKeys,
    Set<String> seenWords,
  ) {
    int start = horizontal ? col : row;
    int end = start;

    // Extend backward.
    while (start > 0) {
      final PlacedTile? prev = horizontal
          ? _board[row][start - 1]
          : _board[start - 1][col];
      if (prev == null) break;
      start--;
    }

    // Extend forward.
    while (end < boardSize - 1) {
      final PlacedTile? next = horizontal
          ? _board[row][end + 1]
          : _board[end + 1][col];
      if (next == null) break;
      end++;
    }

    if (end - start < 1) return null; // Single letter, no word.

    final String wordKey = '${horizontal ? "h" : "v"}:$start:${horizontal ? row : col}';
    if (seenWords.contains(wordKey)) return null;

    // Build the word and compute score.
    final StringBuffer word = StringBuffer();
    int baseScore = 0;
    int maxMultiplier = 1;
    bool containsPending = false;

    for (int i = start; i <= end; i++) {
      final PlacedTile tile =
          horizontal ? _board[row][i]! : _board[i][col]!;
      word.write(tile.letter.toLowerCase());
      baseScore += tile.points;

      final String cellKey = horizontal ? '$row:$i' : '$i:$col';
      if (pendingKeys.contains(cellKey)) {
        containsPending = true;
        // Check multiplier for newly placed tiles only.
        final CellMultiplier mult = horizontal
            ? boardMultipliers[row][i]
            : boardMultipliers[i][col];
        if (mult == CellMultiplier.triple3x && maxMultiplier < 3) {
          maxMultiplier = 3;
        } else if (mult == CellMultiplier.double2x && maxMultiplier < 2) {
          maxMultiplier = 2;
        }
      }
    }

    if (!containsPending) return null;

    seenWords.add(wordKey);

    // Collect all cells in this word.
    final List<(int, int)> wordCells = <(int, int)>[];
    for (int i = start; i <= end; i++) {
      wordCells.add(horizontal ? (row, i) : (i, col));
    }

    return _ExtractedWord(
      word: word.toString(),
      baseScore: baseScore,
      multiplier: maxMultiplier,
      cells: wordCells,
    );
  }

  void _fillRack() {
    while (_rack.length < rackSize) {
      _rack.add(_drawRackTile());
    }
    _ensureRackCanFormWord();
  }

  void _ensureRackCanFormWord() {
    // Build a simple board letter map for the dictionary check.
    final List<List<String?>> boardLetters = List<List<String?>>.generate(
      boardSize,
      (int r) => List<String?>.generate(
        boardSize,
        (int c) => _board[r][c]?.letter.toLowerCase(),
      ),
    );

    final List<String> rackLetters =
        _rack.map((RackTile t) => t.isBlank ? 'e' : t.letter.toLowerCase()).toList();

    if (!_dictionary.canFormAnyWord(
      board: boardLetters,
      rackLetters: rackLetters,
      boardSize: boardSize,
    )) {
      // Re-draw the entire rack (up to 10 attempts).
      for (int attempt = 0; attempt < 10; attempt++) {
        _rack = <RackTile>[];
        while (_rack.length < rackSize) {
          _rack.add(_drawRackTile());
        }
        final List<String> newLetters =
            _rack.map((RackTile t) => t.isBlank ? 'e' : t.letter.toLowerCase()).toList();
        if (_dictionary.canFormAnyWord(
          board: boardLetters,
          rackLetters: newLetters,
          boardSize: boardSize,
        )) {
          return;
        }
      }
    }
  }

  RackTile _drawRackTile() {
    // 3% chance of blank tile.
    if (_random.nextDouble() < 0.03) {
      return const RackTile(letter: '★', points: 0, isBlank: true);
    }

    int totalWeight = _baseBagSize;
    final int roll = _random.nextInt(totalWeight);
    int running = 0;
    for (final MapEntry<String, int> entry in _letterFrequencies.entries) {
      running += entry.value;
      if (roll < running) {
        return RackTile(
          letter: entry.key,
          points: letterPoints[entry.key]!,
        );
      }
    }
    return const RackTile(letter: 'E', points: 1);
  }

  bool _isBoardFull() {
    for (int r = 0; r < boardSize; r++) {
      for (int c = 0; c < boardSize; c++) {
        if (_board[r][c] == null) return false;
      }
    }
    return true;
  }

  bool _endGameIfNoMovesPossible() {
    if (!_isRunning || _isGameOver) return false;
    if (_isBoardFull()) {
      _endGame('Board full!');
      return true;
    }
    if (isBoardEmpty) {
      return false;
    }
    if (!_canPlayerMove()) {
      _endGame('No more words possible.');
      return true;
    }
    return false;
  }

  TopMoveResult? _findTopPossibleMove() {
    final List<List<String?>> boardLetters = List<List<String?>>.generate(
      boardSize,
      (int r) => List<String?>.generate(
        boardSize,
        (int c) => _board[r][c]?.letter.toLowerCase(),
      ),
    );

    final List<(int, int)> candidates = <(int, int)>[];
    for (int r = 0; r < boardSize; r++) {
      for (int c = 0; c < boardSize; c++) {
        if (boardLetters[r][c] != null) continue;
        if (_hasAdjacentFilled(boardLetters, r, c)) {
          candidates.add((r, c));
        }
      }
    }
    if (candidates.isEmpty && boardLetters[centerCell][centerCell] == null) {
      candidates.add((centerCell, centerCell));
    }

    TopMoveResult? best;
    final List<PlacedTile> previousPending = List<PlacedTile>.from(_pendingPlacements);
    final String? previousRejected = _lastRejectedWord;

    for (final (int row, int col) in candidates) {
      for (int i = 0; i < _rack.length; i++) {
        final RackTile tile = _rack[i];
        final List<String> lettersToTry =
            tile.isBlank ? letterPoints.keys.toList() : <String>[tile.letter];

        for (final String letter in lettersToTry) {
          _board[row][col] = PlacedTile(
            letter: letter,
            points: tile.isBlank ? 0 : tile.points,
            row: row,
            column: col,
            isBlank: tile.isBlank,
          );
          _pendingPlacements = <PlacedTile>[_board[row][col]!];

          final List<ScoredWord> words = _findNewWords();
          if (words.isNotEmpty) {
            int moveScore = 0;
            for (final ScoredWord w in words) {
              moveScore += w.totalScore;
            }

            if (best == null || moveScore > best.score) {
              best = TopMoveResult(
                word: words.first.word,
                score: moveScore,
                placement: PlacedTile(
                  letter: letter,
                  points: tile.isBlank ? 0 : tile.points,
                  row: row,
                  column: col,
                  isBlank: tile.isBlank,
                ),
              );
            }
          }

          _board[row][col] = null;
          _pendingPlacements = <PlacedTile>[];
        }
      }
    }

    _pendingPlacements = previousPending;
    _lastRejectedWord = previousRejected;
    return best;
  }

  bool _canPlayerMove() {
    final List<List<String?>> boardLetters = List<List<String?>>.generate(
      boardSize,
      (int r) => List<String?>.generate(
        boardSize,
        (int c) => _board[r][c]?.letter.toLowerCase(),
      ),
    );
    final List<String> rackLetters =
        _rack.map((RackTile t) => t.isBlank ? 'e' : t.letter.toLowerCase()).toList();
    return _dictionary.canFormAnyWord(
      board: boardLetters,
      rackLetters: rackLetters,
      boardSize: boardSize,
    );
  }

  HintResult? _findHint() {
    // Recall pending placements first.
    recallPlacements();

    final List<List<String?>> boardLetters = List<List<String?>>.generate(
      boardSize,
      (int r) => List<String?>.generate(
        boardSize,
        (int c) => _board[r][c]?.letter.toLowerCase(),
      ),
    );

    // Find empty cells adjacent to filled cells (or center if empty board).
    final List<(int, int)> candidates = <(int, int)>[];
    for (int r = 0; r < boardSize; r++) {
      for (int c = 0; c < boardSize; c++) {
        if (boardLetters[r][c] != null) continue;
        if (_hasAdjacentFilled(boardLetters, r, c)) {
          candidates.add((r, c));
        }
      }
    }
    if (candidates.isEmpty && boardLetters[centerCell][centerCell] == null) {
      candidates.add((centerCell, centerCell));
    }

    // Try placing each rack letter at each candidate, check for words.
    for (final (int row, int col) in candidates) {
      for (int i = 0; i < _rack.length; i++) {
        final RackTile tile = _rack[i];
        final List<String> lettersToTry =
            tile.isBlank ? letterPoints.keys.toList() : <String>[tile.letter];

        for (final String letter in lettersToTry) {
          _board[row][col] = PlacedTile(
            letter: letter,
            points: tile.isBlank ? 0 : tile.points,
            row: row,
            column: col,
            isBlank: tile.isBlank,
          );
          _pendingPlacements = <PlacedTile>[_board[row][col]!];

          final List<ScoredWord> words = _findNewWords();
          if (words.isNotEmpty) {
            _board[row][col] = null;
            _pendingPlacements = <PlacedTile>[];
            return HintResult(
              word: words.first.word,
              placements: <PlacedTile>[
                PlacedTile(
                  letter: letter,
                  points: tile.isBlank ? 0 : tile.points,
                  row: row,
                  column: col,
                  isBlank: tile.isBlank,
                ),
              ],
            );
          }
          _board[row][col] = null;
          _pendingPlacements = <PlacedTile>[];
        }
      }
    }

    return null;
  }

  bool _hasAdjacentFilled(List<List<String?>> board, int row, int col) {
    const List<(int, int)> deltas = <(int, int)>[
      (-1, 0), (1, 0), (0, -1), (0, 1),
    ];
    for (final (int dr, int dc) in deltas) {
      final int nr = row + dr;
      final int nc = col + dc;
      if (nr >= 0 && nr < boardSize && nc >= 0 && nc < boardSize) {
        if (board[nr][nc] != null) return true;
      }
    }
    return false;
  }

  void _startMoveTimer() {
    _cancelTimers();
    _countdownRemaining = gameMoveTimerSeconds;
    _countdownActive = true;
    _moveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _countdownRemaining--;
      if (_countdownRemaining <= 0) {
        _endGame('Time ran out!');
      } else {
        _pendingEvent = GameEvent.tick;
      }
      notifyListeners();
    });
  }

  void _resetMoveTimer() {
    _startMoveTimer();
  }

  void _cancelTimers() {
    _moveTimer?.cancel();
    _moveTimer = null;
  }

  void _endGame(String reason) {
    _lastTopMissedMove = _findTopPossibleMove();
    _isGameOver = true;
    _isRunning = false;
    _cancelTimers();
    _statusMessage = '$reason Final score: $_score';
    if (_lastTopMissedMove != null) {
      _statusMessage =
          '$_statusMessage\nTop possible move you missed: '
          '${_lastTopMissedMove!.word.toUpperCase()} (+${_lastTopMissedMove!.score})';
    }
    if (_score > _highScore) {
      _highScore = _score;
      unawaited(_preferences?.setInt(highScoreKey, _highScore));
    }
    _pendingEvent = GameEvent.gameOver;
    notifyListeners();
  }
}

/// Internal helper: a word extracted from the board before dictionary check.
class _ExtractedWord {
  const _ExtractedWord({
    required this.word,
    required this.baseScore,
    required this.multiplier,
    required this.cells,
  });

  final String word;
  final int baseScore;
  final int multiplier;
  final List<(int, int)> cells;

  ScoredWord toScoredWord() => ScoredWord(
        word: word,
        baseScore: baseScore,
        multiplier: multiplier,
        cells: cells,
      );
}

const Map<String, int> letterPoints = <String, int>{
  'A': 1, 'B': 3, 'C': 3, 'D': 2, 'E': 1, 'F': 4, 'G': 2, 'H': 4,
  'I': 1, 'J': 8, 'K': 5, 'L': 1, 'M': 3, 'N': 1, 'O': 1, 'P': 3,
  'Q': 10, 'R': 1, 'S': 1, 'T': 1, 'U': 1, 'V': 4, 'W': 4, 'X': 8,
  'Y': 4, 'Z': 10,
};

const Map<String, int> _letterFrequencies = <String, int>{
  'A': 9, 'B': 2, 'C': 2, 'D': 4, 'E': 12, 'F': 2, 'G': 3, 'H': 2,
  'I': 9, 'J': 1, 'K': 1, 'L': 4, 'M': 2, 'N': 6, 'O': 8, 'P': 2,
  'Q': 1, 'R': 6, 'S': 4, 'T': 6, 'U': 4, 'V': 2, 'W': 2, 'X': 1,
  'Y': 2, 'Z': 1,
};

const int _baseBagSize = 98;
