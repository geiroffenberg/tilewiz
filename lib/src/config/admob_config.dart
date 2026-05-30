import 'package:flutter/foundation.dart';

class AdMobConfig {
  // Test ads in debug/profile. In release, ads stay disabled until real IDs are set.
  static const bool useTestAds = !kReleaseMode;

  static const String _androidProdBanner =
      'ca-app-pub-9327215418607539/4643671795';
  static const String _iosProdBanner =
      'ca-app-pub-xxxxxxxxxxxxxxxx/yyyyyyyyyy';
  static const String _androidProdInterstitial =
      'ca-app-pub-9327215418607539/4258704589';
  static const String _iosProdInterstitial =
      'ca-app-pub-xxxxxxxxxxxxxxxx/yyyyyyyyyy';

  static const String _androidTestBanner =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _iosTestBanner =
      'ca-app-pub-3940256099942544/2934735716';
  static const String _androidTestInterstitial =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _iosTestInterstitial =
      'ca-app-pub-3940256099942544/4411468910';

  // Show one interstitial every N completed games.
  static const int interstitialEveryCompletedGames = 2;

  static bool get adsEnabled {
    if (kIsWeb) return false;
    if (useTestAds) return true;
    return !_isPlaceholder(_productionBannerAdUnitId) &&
        !_isPlaceholder(_productionInterstitialAdUnitId);
  }

  static String get _productionBannerAdUnitId {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _androidProdBanner;
      case TargetPlatform.iOS:
        return _iosProdBanner;
      default:
        return '';
    }
  }

  static String get _productionInterstitialAdUnitId {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _androidProdInterstitial;
      case TargetPlatform.iOS:
        return _iosProdInterstitial;
      default:
        return '';
    }
  }

  static bool _isPlaceholder(String value) {
    return value.isEmpty ||
        value.contains('xxxxxxxx') ||
        value.contains('yyyyyyyy');
  }

  static String get bannerAdUnitId {
    if (!adsEnabled || kIsWeb) return '';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return useTestAds ? _androidTestBanner : _androidProdBanner;
      case TargetPlatform.iOS:
        return useTestAds ? _iosTestBanner : _iosProdBanner;
      default:
        return '';
    }
  }

  static String get interstitialAdUnitId {
    if (!adsEnabled || kIsWeb) return '';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return useTestAds ? _androidTestInterstitial : _androidProdInterstitial;
      case TargetPlatform.iOS:
        return useTestAds ? _iosTestInterstitial : _iosProdInterstitial;
      default:
        return '';
    }
  }
}