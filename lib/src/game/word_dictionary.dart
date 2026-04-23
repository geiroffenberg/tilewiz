import 'dart:convert';

import 'package:flutter/services.dart';

class WordDictionary {
  WordDictionary._(this._wordsByLength);

  static const String assetPath = 'assets/enable1_2_to_7_by_length.json';

  final Map<int, Set<String>> _wordsByLength;

  static Future<WordDictionary> load() async {
    final String rawJson = await rootBundle.loadString(assetPath);
    final Map<String, dynamic> parsedJson =
        jsonDecode(rawJson) as Map<String, dynamic>;
    final Map<int, Set<String>> wordsByLength = <int, Set<String>>{};

    for (final MapEntry<String, dynamic> entry in parsedJson.entries) {
      wordsByLength[int.parse(entry.key)] = (entry.value as List<dynamic>)
          .cast<String>()
          .map((String word) => word.toLowerCase())
          .toSet();
    }

    return WordDictionary._(wordsByLength);
  }

  bool contains(String word) {
    final String normalized = word.toLowerCase();
    return _wordsByLength[normalized.length]?.contains(normalized) ?? false;
  }

  /// Returns all words that can be formed using the given letters on
  /// a line (row or column) of the board. Used by the hint system.
  Set<String> allWords() {
    final Set<String> all = <String>{};
    for (final Set<String> words in _wordsByLength.values) {
      all.addAll(words);
    }
    return all;
  }

  /// Returns words of a specific length.
  Set<String> wordsOfLength(int length) {
    return _wordsByLength[length] ?? const <String>{};
  }

  /// Checks if any word in the dictionary can be formed using the given
  /// available letters combined with the existing board letters along any
  /// line through any empty cell adjacent to a filled cell.
  bool canFormAnyWord({
    required List<List<String?>> board,
    required List<String> rackLetters,
    required int boardSize,
  }) {
    final Set<String> rackSet = <String>{};
    final Map<String, int> rackCounts = <String, int>{};
    for (final String letter in rackLetters) {
      final String lower = letter.toLowerCase();
      rackSet.add(lower);
      rackCounts[lower] = (rackCounts[lower] ?? 0) + 1;
    }

    // Find all empty cells adjacent to at least one filled cell.
    final List<(int, int)> candidates = <(int, int)>[];
    for (int row = 0; row < boardSize; row++) {
      for (int col = 0; col < boardSize; col++) {
        if (board[row][col] != null) continue;
        if (_hasFilledNeighbor(board, row, col, boardSize)) {
          candidates.add((row, col));
        }
      }
    }

    // Special case: empty board — center cell is the only candidate.
    if (candidates.isEmpty) {
      final int center = boardSize ~/ 2;
      if (board[center][center] == null) {
        candidates.add((center, center));
      }
    }

    // For each candidate cell, check horizontal and vertical lines.
    for (final (int row, int col) in candidates) {
      if (_canFormWordAt(board, row, col, rackCounts, boardSize)) {
        return true;
      }
    }
    return false;
  }

  bool _hasFilledNeighbor(
    List<List<String?>> board,
    int row,
    int col,
    int boardSize,
  ) {
    const List<(int, int)> deltas = <(int, int)>[
      (-1, 0),
      (1, 0),
      (0, -1),
      (0, 1),
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

  bool _canFormWordAt(
    List<List<String?>> board,
    int row,
    int col,
    Map<String, int> rackCounts,
    int boardSize,
  ) {
    // Check horizontal line through (row, col).
    // Collect existing letters and gaps in this row.
    // For simplicity, check if placing one rack letter at (row, col) creates
    // a valid word along the horizontal or vertical axis.
    for (final String rackLetter in rackCounts.keys) {
      // Try horizontal.
      if (_checkLineWithPlacement(
        board,
        row,
        col,
        rackLetter,
        true,
        boardSize,
      )) {
        return true;
      }
      // Try vertical.
      if (_checkLineWithPlacement(
        board,
        row,
        col,
        rackLetter,
        false,
        boardSize,
      )) {
        return true;
      }
    }
    return false;
  }

  bool _checkLineWithPlacement(
    List<List<String?>> board,
    int row,
    int col,
    String letter,
    bool horizontal,
    int boardSize,
  ) {
    // Find the contiguous run of letters including (row, col) with
    // the candidate letter placed there.
    final StringBuffer word = StringBuffer();
    int start = horizontal ? col : row;
    int end = start;

    // Extend backward.
    while (start > 0) {
      final String? prev = horizontal
          ? board[row][start - 1]
          : board[start - 1][col];
      if (prev == null) break;
      start--;
    }

    // Extend forward.
    while (end < boardSize - 1) {
      final String? next = horizontal
          ? board[row][end + 1]
          : board[end + 1][col];
      if (next == null) break;
      end++;
    }

    // Build the word.
    for (int i = start; i <= end; i++) {
      if ((horizontal && i == col) || (!horizontal && i == row)) {
        word.write(letter);
      } else {
        final String? existing =
            horizontal ? board[row][i] : board[i][col];
        if (existing == null) return false;
        word.write(existing.toLowerCase());
      }
    }

    final String candidate = word.toString();
    if (candidate.length < 2) return false;
    return contains(candidate);
  }
}
