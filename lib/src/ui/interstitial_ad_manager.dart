import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/admob_config.dart';

class InterstitialAdManager {
  InterstitialAd? _interstitial;
  bool _isLoading = false;
  int _completedGames = 0;

  void initialize() {
    _loadIfNeeded();
  }

  void markGameCompleted() {
    _completedGames += 1;
    _loadIfNeeded();
  }

  Future<void> showIfEligible() async {
    if (!AdMobConfig.adsEnabled || kIsWeb) return;
    if (AdMobConfig.interstitialEveryCompletedGames <= 0) return;
    if (_completedGames == 0) return;
    if (_completedGames % AdMobConfig.interstitialEveryCompletedGames != 0) {
      return;
    }
    final InterstitialAd? ad = _interstitial;
    if (ad == null) {
      _loadIfNeeded();
      return;
    }

    _interstitial = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        ad.dispose();
        _loadIfNeeded();
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
        ad.dispose();
        _loadIfNeeded();
      },
    );
    ad.show();
  }

  void _loadIfNeeded() {
    if (_interstitial != null || _isLoading) return;
    final String adUnitId = AdMobConfig.interstitialAdUnitId;
    if (adUnitId.isEmpty) return;

    _isLoading = true;
    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _isLoading = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isLoading = false;
          debugPrint('InterstitialAd failed to load: $error');
        },
      ),
    );
  }

  void dispose() {
    _interstitial?.dispose();
    _interstitial = null;
  }
}