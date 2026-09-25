// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Kuron';

  @override
  String sourceAuthProfileTitle(String sourceId) {
    return 'Profile $sourceId';
  }

  @override
  String sourceAuthLoginTitle(String sourceId) {
    return 'Login $sourceId';
  }

  @override
  String get sourceAuthConnectedAccount => 'Connected Account';

  @override
  String get sourceAuthSecureLogin => 'Secure Login';

  @override
  String get sourceAuthConnectedDescription =>
      'Your account is connected and ready.';

  @override
  String get sourceAuthLoginDescription =>
      'Sign in to sync your personalized favorites.';

  @override
  String get sourceAuthUser => 'User';

  @override
  String get sourceAuthSlug => 'Slug';

  @override
  String get sourceAuthAuthenticated => 'Authenticated';

  @override
  String get sourceAuthRefreshProfile => 'Refresh Profile';

  @override
  String get sourceAuthLogout => 'Logout';

  @override
  String get sourceAuthUsername => 'Username';

  @override
  String get sourceAuthPassword => 'Password';

  @override
  String get sourceAuthCaptchaVerified =>
      'CAPTCHA verified and stored securely';

  @override
  String get sourceAuthCaptchaRequired => 'Solve CAPTCHA to continue';

  @override
  String get sourceAuthCaptchaSolved => 'CAPTCHA Solved';

  @override
  String get sourceAuthSolveCaptcha => 'Solve CAPTCHA';

  @override
  String get sourceAuthLoginButton => 'Login';

  @override
  String get sourceAuthLoginSuccess => 'Login successful';

  @override
  String get sourceAuthSigningInSecurely => 'Signing in securely';

  @override
  String get sourceAuthStepValidateRequest => 'Validate request';

  @override
  String get sourceAuthStepSecureAuth => 'Secure authentication';

  @override
  String get sourceAuthStepFetchProfile => 'Fetch profile';

  @override
  String get sourceAuthFlowPreparingSession => 'Preparing secure session...';

  @override
  String get sourceAuthFlowSolvingChallenge => 'Solving security challenge...';

  @override
  String get sourceAuthFlowFetchingProfile =>
      'Session verified. Fetching profile...';

  @override
  String get sourceAuthFlowLoginSuccess => 'Login successful';

  @override
  String get sourceAuthCaptchaCaptured => 'CAPTCHA captured successfully';

  @override
  String get home => 'Home';

  @override
  String get search => 'Search';

  @override
  String get favorites => 'Favorites';

  @override
  String get downloads => 'Downloads';

  @override
  String get history => 'Reading History';

  @override
  String get randomGallery => 'Random Gallery';

  @override
  String get randomGalleryLoadingTitle => 'Random Gallery';

  @override
  String get randomGalleryLoadingMessage => 'Fetching a random gallery...';

  @override
  String get randomGalleryFoundTitle => 'Found';

  @override
  String get randomGalleryFoundMessage => 'Opening gallery details...';

  @override
  String get randomGalleryNoResult => 'No random gallery found. Try again.';

  @override
  String get randomGalleryError =>
      'Error loading random gallery. Please try again.';

  @override
  String get randomGalleryUnavailableTitle => 'Feature Unavailable';

  @override
  String get randomGalleryUnavailableMessage =>
      'Random Gallery is not available for this source.';

  @override
  String get offlineContent => 'Offline Content';

  @override
  String get settings => 'Settings';

  @override
  String get appDisguise => 'APP DISGUISE';

  @override
  String get disguiseMode => 'Disguise Mode';

  @override
  String get offline => 'Offline';

  @override
  String get about => 'About';

  @override
  String get supportDeveloper => 'Support Developer';

  @override
  String get supportDeveloperSubtitle => 'Buy me a coffee';

  @override
  String get donateMessage =>
      'Support development via QRIS donation. Thank you! ☕';

  @override
  String get thankYouMessage => 'Thank you for your support!';

  @override
  String get searchHint => 'Search...';

  @override
  String get searchPlaceholder => 'Enter search keywords';

  @override
  String get noResults => 'No Results Found';

  @override
  String get searchSuggestions => 'Search Suggestions';

  @override
  String get suggestions => 'Suggestions:';

  @override
  String get facebookPage => 'Doujin Stash 3';

  @override
  String get facebookPageSubtitle => 'Support us by liking our page';

  @override
  String get tapToLoadContent => 'Tap to load content';

  @override
  String get trySwitchingNetwork =>
      'Try switching between Wi-Fi and mobile data';

  @override
  String get restartRouter => 'Restart your router if using Wi-Fi';

  @override
  String get checkWebsiteStatus => 'Check if the website is down';

  @override
  String get cloudflareBypassMessage =>
      'The website is protected by Cloudflare. We\'re trying to bypass the protection.';

  @override
  String get forceBypass => 'Force Bypass';

  @override
  String get unableToProcessData =>
      'Unable to process the received data. The website structure might have changed.';

  @override
  String get reportIssue => 'Report Issue';

  @override
  String serverReturnedError(int statusCode) {
    return 'Server returned error $statusCode. The service might be temporarily unavailable.';
  }

  @override
  String get failedToOpenBrowser => 'Failed to open browser.';

  @override
  String get viewDownloads => 'View Downloads';

  @override
  String get clearSearch => 'Clear Search';

  @override
  String get clearFilters => 'Clear Filters';

  @override
  String get anyLanguage => 'Any language';

  @override
  String get anyCategory => 'Any category';

  @override
  String get errorOpeningFilter => 'Error opening filter selection';

  @override
  String get errorBrowsingTag => 'Error browsing tag';

  @override
  String get shuffleToNextGallery => 'Shuffle to next gallery';

  @override
  String get contentHidden => 'Content Hidden';

  @override
  String get tapToViewAnyway => 'Tap to view anyway';

  @override
  String get checkOutThisGallery => 'Check out this gallery!';

  @override
  String galleriesPreloaded(int count) {
    return '$count galleries preloaded';
  }

  @override
  String get oopsSomethingWentWrong => 'Oops! Something went wrong';

  @override
  String get cleanupInfo => 'Cleanup Info';

  @override
  String get clearingHistory => 'Clearing history...';

  @override
  String get areYouSureClearHistory =>
      'Are you sure you want to clear all reading history? This action cannot be undone.';

  @override
  String get artistCg => 'artist cg';

  @override
  String get gameCg => 'game cg';

  @override
  String get manga => 'manga';

  @override
  String get doujinshi => 'doujinshi';

  @override
  String get imageSet => 'image set';

  @override
  String get cosplay => 'cosplay';

  @override
  String get artistcg => 'artistcg';

  @override
  String get gamecg => 'gamecg';

  @override
  String get bigBreasts => 'big breasts';

  @override
  String get soleFemale => 'sole female';

  @override
  String get soleMale => 'sole male';

  @override
  String get pleaseSetStorageLocation =>
      'Set download storage location in settings first.';

  @override
  String get schoolgirlUniform => 'schoolgirl uniform';

  @override
  String get tryADifferentSearchTerm => 'Try a different search term';

  @override
  String get unknownError => 'Unknown error';

  @override
  String get loadingOfflineContent => 'Loading offline content...';

  @override
  String get excludeTags => 'Exclude Tags';

  @override
  String get excludeGroups => 'Exclude Groups';

  @override
  String get excludeCharacters => 'Exclude Characters';

  @override
  String get excludeParodies => 'Exclude Parodies';

  @override
  String get excludeArtists => 'Exclude Artists';

  @override
  String get noResultsFound => 'No Results Found';

  @override
  String get tryAdjustingFilters =>
      'Try adjusting your search filters or search terms.';

  @override
  String get networkError =>
      'Network error. Check your connection and try again.';

  @override
  String get accessBlocked => 'Access blocked. Trying to bypass protection...';

  @override
  String get tooManyRequests =>
      'Too many requests. Please wait a moment and try again.';

  @override
  String get errorProcessingResults =>
      'Error processing search results. Please try again.';

  @override
  String get invalidSearchParameters =>
      'Invalid search parameters. Please check your input.';

  @override
  String get unexpectedError =>
      'An unexpected error occurred. Please try again.';

  @override
  String get retryBypass => 'Retry Bypass';

  @override
  String get retryConnection => 'Retry Connection';

  @override
  String get retrySearch => 'Retry Search';

  @override
  String get errorNetwork =>
      'Network error. Check your connection and try again.';

  @override
  String get errorServer => 'Server error. Please try again later.';

  @override
  String get errorCloudflare =>
      'Content is temporarily blocked (Cloudflare). Please try again in a moment.';

  @override
  String get errorParsing =>
      'Failed to load content data. The content may be unavailable.';

  @override
  String get errorUnknown => 'Something went wrong. Please try again.';

  @override
  String get errorConnectionTimeout =>
      'Connection timed out. Please try again.';

  @override
  String get errorConnectionRefused =>
      'Connection refused. Server might be down.';

  @override
  String get networkErrorTitle => 'Network Error';

  @override
  String get serverErrorTitle => 'Server Error';

  @override
  String get unknownErrorTitle => 'Unknown Error';

  @override
  String get refreshingContent => 'Refreshing content...';

  @override
  String get loadingMoreContent => 'Loading more content...';

  @override
  String get searchResults => 'Search Results';

  @override
  String get latestContent => 'Latest Content';

  @override
  String get serverTemporarilyUnavailable =>
      'Server is temporarily unavailable. Please try again later.';

  @override
  String get cloudflareProtectionDetected =>
      'Cloudflare protection detected. Please wait and try again.';

  @override
  String get tooManyRequestsWait =>
      'Too many requests. Please wait a moment before trying again.';

  @override
  String get noContentFoundMatching =>
      'No content found matching your search criteria. Try adjusting your filters.';

  @override
  String noContentFoundForTag(String tagName) {
    return 'No content found for tag \"$tagName\".';
  }

  @override
  String get useGeneralTerms => 'Use more general search terms';

  @override
  String get tryBrowsingOtherTags => 'Try browsing other tags';

  @override
  String get checkPopularContent => 'Check popular content';

  @override
  String get useSearchFunction => 'Use the search function';

  @override
  String get checkInternetConnectionSuggestion =>
      'Check your internet connection';

  @override
  String get browsePopularContentSuggestion => 'Browse popular content';

  @override
  String get failedToInitializeSearch => 'Failed to initialize search';

  @override
  String noResultsFoundFor(String query) {
    return 'No results found for \"$query\"';
  }

  @override
  String get searchingWithFilters => 'Searching with filters...';

  @override
  String get noResultsFoundWithCurrentFilters =>
      'No results found with current filters';

  @override
  String invalidFilter(String errors) {
    return 'Invalid filter: $errors';
  }

  @override
  String invalidSearchFilter(String errors) {
    return 'Invalid search filter: $errors';
  }

  @override
  String get tags => 'Tags';

  @override
  String get language => 'Language';

  @override
  String get uploadedOn => 'Uploaded on';

  @override
  String get readNow => 'Read Now';

  @override
  String get featured => 'Featured';

  @override
  String get confirmDownload => 'Confirm Download';

  @override
  String get downloadConfirmation => 'Are you sure you want to download?';

  @override
  String get confirmButton => 'Confirm';

  @override
  String get download => 'Download';

  @override
  String get downloading => 'Downloading';

  @override
  String get downloadCompleted => 'Download Completed';

  @override
  String get initializing => 'Initializing...';

  @override
  String get noContentToBrowse => 'No content loaded to open in browser';

  @override
  String get addToFavorites => 'Add to Favorites';

  @override
  String get removeFromFavorites => 'Remove from Favorites';

  @override
  String get content => 'Content';

  @override
  String get clearAll => 'Clear All';

  @override
  String get exportList => 'Export List';

  @override
  String get unableToCheck => 'Unable to check connection.';

  @override
  String get noContentAvailable => 'No content available.';

  @override
  String get noContentToDownload => 'No content available to download.';

  @override
  String get noGalleriesFound => 'No galleries found on this page.';

  @override
  String get noContentLoadedToBrowse => 'No content loaded to open in browser';

  @override
  String get showCachedContent => 'Show Cached Content';

  @override
  String get openedInBrowser => 'Opened in browser';

  @override
  String get foundGalleries => 'Found Galleries';

  @override
  String get checkingDownloadStatus => 'Checking Download Status...';

  @override
  String get allGalleriesDownloaded => 'All Galleries Downloaded';

  @override
  String get downloadNewGalleries => 'Download New Galleries';

  @override
  String get downloadProgress => 'Download Progress';

  @override
  String get verifyingFiles => 'Verifying Files';

  @override
  String verifyingFilesWithTitle(String title) {
    return 'Verifying $title...';
  }

  @override
  String verifyingProgress(int progress) {
    return 'Verifying ($progress%)';
  }

  @override
  String get initializingDownloads => 'Initializing downloads...';

  @override
  String get loadingDownloads => 'Loading downloads...';

  @override
  String get pauseAll => 'Pause All';

  @override
  String get resumeAll => 'Resume All';

  @override
  String get cancelAll => 'Cancel All';

  @override
  String get clearCompleted => 'Clear Completed';

  @override
  String get cleanupStorage => 'Cleanup Storage';

  @override
  String get all => 'All';

  @override
  String get completed => 'Completed';

  @override
  String get noDownloadsYet => 'No downloads yet';

  @override
  String get noActiveDownloads => 'No active downloads.';

  @override
  String get noQueuedDownloads => 'No queued downloads.';

  @override
  String get noCompletedDownloads => 'No completed downloads.';

  @override
  String get noFailedDownloads => 'No failed downloads.';

  @override
  String get cancelAllDownloads => 'Cancel All Downloads';

  @override
  String get cancelAllConfirmation =>
      'Are you sure you want to cancel all active downloads? This action cannot be undone.';

  @override
  String get cancelDownload => 'Cancel Download';

  @override
  String get cancelDownloadConfirmation =>
      'Are you sure you want to cancel this download? Progress will be lost.';

  @override
  String get removeDownload => 'Remove Download';

  @override
  String get removeDownloadConfirmation =>
      'Are you sure you want to remove this download from the list? Downloaded files will be deleted.';

  @override
  String get cleanupConfirmation =>
      'This will remove orphaned files and clean up failed downloads. Continue?';

  @override
  String get downloadDetails => 'Download Details';

  @override
  String get status => 'Status';

  @override
  String get progressPercent => 'Progress %';

  @override
  String get started => 'Started';

  @override
  String get ended => 'Ended';

  @override
  String get eta => 'ETA';

  @override
  String get failed => 'Failed';

  @override
  String get downloadListExported => 'Download list exported';

  @override
  String get downloadAll => 'Download All';

  @override
  String get downloadRange => 'Download Range';

  @override
  String get selectDownloadRange => 'Download Range';

  @override
  String get useSliderToSelectRange => 'Use slider to select range:';

  @override
  String get orEnterManually => 'Or enter manually:';

  @override
  String get quickSelections => 'Quick selections:';

  @override
  String get allPages => 'All Pages';

  @override
  String get firstHalf => 'First Half';

  @override
  String get secondHalf => 'Second Half';

  @override
  String get first10 => 'First 10';

  @override
  String get last10 => 'Last 10';

  @override
  String countAlreadyDownloaded(int count) {
    return 'Skipped $count already downloaded';
  }

  @override
  String newGalleriesToDownload(int count) {
    return '• $count new galleries to download';
  }

  @override
  String alreadyDownloaded(int count) {
    return '• $count already downloaded (will be skipped)';
  }

  @override
  String downloadNew(int count) {
    return 'Download $count New';
  }

  @override
  String queuedDownloads(int count) {
    return 'Queued $count new downloads';
  }

  @override
  String downloadInfo(int count) {
    return 'Download $count new galleries?\\n\\nThis may take significant time and storage space.';
  }

  @override
  String get failedToDownload => 'Failed to download galleries';

  @override
  String selectedPagesTo(int start, int end) {
    return 'Selected: Pages $start to $end';
  }

  @override
  String pagesPercentage(int count, String percentage) {
    return '$count pages ($percentage%)';
  }

  @override
  String rangeDownloadStarted(String title, String pageText) {
    return 'Range download started: $title ($pageText)';
  }

  @override
  String opening(String title) {
    return 'Opening: $title';
  }

  @override
  String get lastUpdatedLabel => 'Updated:';

  @override
  String get releasedLabel => 'Released:';

  @override
  String get updatedLabel => 'Updated:';

  @override
  String get rangeLabel => 'Range:';

  @override
  String get ofWord => 'of';

  @override
  String waitAndTry(int minutes) {
    return 'Wait $minutes minutes and try again';
  }

  @override
  String get serviceUnderMaintenance =>
      'The service might be under maintenance';

  @override
  String get tryRefreshingPage => 'Try refreshing the page';

  @override
  String get waitForBypass => 'Wait for automatic bypass to complete';

  @override
  String get tryUsingVpn => 'Try using a VPN if available';

  @override
  String get checkBackLater => 'Check back in a few minutes';

  @override
  String get tryRefreshingContent => 'Try refreshing the content';

  @override
  String get checkForAppUpdate => 'Check if the app needs an update';

  @override
  String get reportIfPersists => 'Report the issue if it persists';

  @override
  String get maintenanceTakesHours => 'Maintenance usually takes a few hours';

  @override
  String get checkSocialMedia => 'Check social media for updates';

  @override
  String get tryAgainLater => 'Try again later';

  @override
  String get tryDifferentKeywords => 'Try different keywords';

  @override
  String get serverUnavailable =>
      'The server is currently unavailable. Please try again later.';

  @override
  String get removeSomeFilters => 'Remove some filters';

  @override
  String get checkSpelling => 'Check spelling';

  @override
  String get useBroaderSearchTerms => 'Use broader search terms';

  @override
  String get welcomeTitle => 'Welcome to Kuron!';

  @override
  String get welcomeMessage => 'Before you start:';

  @override
  String get ispBlockingInfo => '🚨 ISP Blocking Notice';

  @override
  String get ispBlockingMessage =>
      'Blocked by ISP? Use a VPN like Cloudflare WARP 1.1.1.1.';

  @override
  String get downloadWarp => 'Download 1.1.1.1 VPN';

  @override
  String get permissionsRequired => 'Required Permissions';

  @override
  String get storagePermissionInfo =>
      '📁 Storage: Required to download and save content offline';

  @override
  String get notificationPermissionInfo =>
      '🔔 Notifications: Required to show download progress and completion';

  @override
  String get grantStoragePermission => 'Grant Storage Permission';

  @override
  String get grantNotificationPermission => 'Grant Notification Permission';

  @override
  String get storageGranted => '✅ Storage permission granted';

  @override
  String get notificationGranted => '✅ Notification permission granted';

  @override
  String get getStarted => 'Get Started';

  @override
  String get pleaseGrantAllPermissions =>
      'Grant all required permissions to continue';

  @override
  String get permissionDenied =>
      'Permission denied. Some features may not work properly.';

  @override
  String get loadingFavorites => 'Loading favorites...';

  @override
  String get errorLoadingFavorites => 'Error Loading Favorites';

  @override
  String get removeFavoriteConfirmation =>
      'Are you sure you want to remove this content from favorites?';

  @override
  String get removeAction => 'Remove';

  @override
  String get deleteFavorites => 'Delete Favorites';

  @override
  String deleteFavoritesConfirmation(int count, String s) {
    return 'Are you sure you want to remove $count favorite$s?';
  }

  @override
  String get exportFavorites => 'Export Favorites';

  @override
  String get noFavoritesYet =>
      'No favorites yet. Start adding content to your favorites!';

  @override
  String get exportingFavorites => 'Exporting favorites...';

  @override
  String get exportComplete => 'Export Complete';

  @override
  String exportedFavoritesCount(int count) {
    return 'Exported $count favorites successfully.';
  }

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get selectFavorites => 'Favorites';

  @override
  String get deleteSelected => 'Delete selected';

  @override
  String get searchFavorites => 'Search favorites...';

  @override
  String get selectAll => 'Select All';

  @override
  String get removingFromFavorites => 'Removing from favorites...';

  @override
  String get removedFromFavorites => 'Removed from favorites';

  @override
  String failedToRemoveFavorite(String error) {
    return 'Failed to remove favorite: $error';
  }

  @override
  String removedFavoritesCount(int count) {
    return 'Removed $count favorites';
  }

  @override
  String failedToRemoveFavorites(String error) {
    return 'Failed to remove favorites: $error';
  }

  @override
  String get appearance => 'Appearance';

  @override
  String get theme => 'Theme';

  @override
  String get imageQuality => 'Image Quality';

  @override
  String get blurThumbnails => 'Blur Thumbnails';

  @override
  String get blurThumbnailsDescription =>
      'Apply blur effect on card images for privacy';

  @override
  String get gridColumns => 'Grid Columns (Portrait)';

  @override
  String get reader => 'Reader';

  @override
  String get showSystemUIInReader => 'Show System UI in Reader';

  @override
  String get historyCleanup => 'History Cleanup';

  @override
  String get autoCleanupHistory => 'Auto Cleanup History';

  @override
  String get automaticallyCleanOldReadingHistory =>
      'Automatically clean old reading history';

  @override
  String get cleanupInterval => 'Cleanup Interval';

  @override
  String get howOftenToCleanupHistory => 'How often to cleanup history';

  @override
  String get maxHistoryDays => 'Max History Days';

  @override
  String get maximumDaysToKeepHistory =>
      'Maximum days to keep history (0 = unlimited)';

  @override
  String get cleanupOnInactivity => 'Cleanup on Inactivity';

  @override
  String get cleanHistoryWhenAppUnused =>
      'Clean history when app is unused for several days';

  @override
  String get inactivityThreshold => 'Inactivity Threshold';

  @override
  String get daysOfInactivityBeforeCleanup =>
      'Days of inactivity before cleanup';

  @override
  String get resetToDefault => 'Reset to Default';

  @override
  String get generalSettings => 'General Settings';

  @override
  String get displaySettings => 'Display';

  @override
  String get darkMode => 'Dark Mode';

  @override
  String get lightMode => 'Light Mode';

  @override
  String get systemMode => 'Follow System';

  @override
  String get appLanguage => 'App Language';

  @override
  String get allowAnalytics => 'Allow Analytics';

  @override
  String get privacyAnalytics => 'Privacy Analytics';

  @override
  String get termsAndConditions => 'Terms and Conditions';

  @override
  String get termsAndConditionsSubtitle => 'User agreement and disclaimers';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get privacyPolicySubtitle => 'How we handle your data';

  @override
  String get faq => 'FAQ';

  @override
  String get faqSubtitle => 'Frequently asked questions';

  @override
  String get resetSettings => 'Reset Settings';

  @override
  String get resetReaderSettings => 'Reset Reader Settings';

  @override
  String get resetReaderSettingsConfirmation =>
      'This will reset all reader settings to their default values:\n\n';

  @override
  String get readingModeLabel => 'Reading Mode: Horizontal Pages';

  @override
  String get areYouSure => 'Are you sure you want to proceed?';

  @override
  String get readerSettingsResetSuccess =>
      'Reader settings have been reset to defaults.';

  @override
  String get readingHistory => 'Reading History';

  @override
  String get clearAllHistory => 'Clear All History';

  @override
  String get manualCleanup => 'Manual Cleanup';

  @override
  String get cleanupSettings => 'Cleanup Settings';

  @override
  String get removeFromHistoryQuestion =>
      'Remove this item from reading history?';

  @override
  String get cleanup => 'Cleanup';

  @override
  String get failedToLoadCleanupStatus => 'Failed to load cleanup status';

  @override
  String get manualCleanupConfirmation =>
      'This will perform cleanup based on your current settings. Continue?';

  @override
  String get nextPage => 'Next Page';

  @override
  String get previousPage => 'Previous Page';

  @override
  String get pageOf => 'of';

  @override
  String get fullscreen => 'Fullscreen';

  @override
  String get exitFullscreen => 'Exit Fullscreen';

  @override
  String get checkingConnection => 'Checking connection...';

  @override
  String get backOnline => 'Back online! All features available.';

  @override
  String get stillNoInternet => 'Still no internet connection.';

  @override
  String get unableToCheckConnection => 'Unable to check connection.';

  @override
  String get noInternetConnection => 'No internet connection';

  @override
  String get connectionError => 'Connection error';

  @override
  String get serverError => 'Server error';

  @override
  String get low => 'Low';

  @override
  String get medium => 'Medium';

  @override
  String get high => 'High';

  @override
  String get original => 'Original';

  @override
  String get lowFaster => 'Low (Faster)';

  @override
  String get highBetterQuality => 'High (Better Quality)';

  @override
  String get originalLargest => 'Original (Largest)';

  @override
  String get lowQuality => 'Low (Faster)';

  @override
  String get mediumQuality => 'Medium';

  @override
  String get highQuality => 'High (Better Quality)';

  @override
  String get originalQuality => 'Original (Largest)';

  @override
  String get dark => 'Dark';

  @override
  String get light => 'Light';

  @override
  String get amoled => 'AMOLED';

  @override
  String get english => 'English';

  @override
  String get japanese => 'Japanese';

  @override
  String get indonesian => 'Indonesian';

  @override
  String get chinese => 'Chinese (Simplified)';

  @override
  String get comfortReading => 'Comfortable Reading';

  @override
  String get filterBy => 'Filter by';

  @override
  String get recent => 'Recent';

  @override
  String get popular => 'Popular';

  @override
  String get oldest => 'Oldest';

  @override
  String get ok => 'OK';

  @override
  String get exitApp => 'Exit App';

  @override
  String get areYouSureExit => 'Are you sure you want to exit the app?';

  @override
  String get exit => 'Exit';

  @override
  String get delete => 'Delete';

  @override
  String get confirm => 'Confirm';

  @override
  String get tryAgain => 'Try Again';

  @override
  String get save => 'Save';

  @override
  String get edit => 'Edit';

  @override
  String get close => 'Close';

  @override
  String get clear => 'Clear';

  @override
  String get share => 'Share';

  @override
  String get goBack => 'Go Back';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String get goToDownloads => 'Go to Downloads';

  @override
  String get retryAction => 'Retry';

  @override
  String get unknown => 'Unknown';

  @override
  String get noData => 'No Data';

  @override
  String get downloadError => 'Download Error';

  @override
  String get other => 'Other';

  @override
  String get confirmResetSettings =>
      'Are you sure you want to restore all settings to default?';

  @override
  String get reset => 'Reset';

  @override
  String get manageAutoCleanupDescription =>
      'Manage automatic cleanup of reading history to free up storage space.';

  @override
  String get nextCleanup => 'Next cleanup';

  @override
  String get historyStatistics => 'History Statistics';

  @override
  String get totalItems => 'Total items';

  @override
  String get lastCleanup => 'Last cleanup';

  @override
  String get lastAppAccess => 'Last app access';

  @override
  String get oneDay => '1 day';

  @override
  String get twoDays => '2 days';

  @override
  String get oneWeek => '1 week';

  @override
  String get privacyInfoText =>
      '• Data is stored on your device\n• Not sent to external servers\n• Only to improve app performance\n• Can be disabled anytime';

  @override
  String get unlimited => 'Unlimited';

  @override
  String daysValue(int days) {
    return '$days days';
  }

  @override
  String days(int count) {
    return '$count days';
  }

  @override
  String get analyticsSubtitle =>
      'Helps app development with local data (not shared)';

  @override
  String get loadingContent => 'Loading content...';

  @override
  String get loadingError => 'Loading Error';

  @override
  String get jumpToPage => 'Jump to Page';

  @override
  String pageInputLabel(int maxPages) {
    return 'Page (1-$maxPages)';
  }

  @override
  String pageOfPages(int current, int total) {
    return 'Page $current of $total';
  }

  @override
  String get jump => 'Jump';

  @override
  String get readerSettings => 'Reader Settings';

  @override
  String get readingMode => 'Reading Mode';

  @override
  String get horizontalPages => 'Horizontal Pages';

  @override
  String get verticalPages => 'Vertical Pages';

  @override
  String get continuousScroll => 'Continuous Scroll';

  @override
  String get keepScreenOnLabel => 'Keep Screen On: Off';

  @override
  String get showUILabel => 'Show UI: On';

  @override
  String get keepScreenOn => 'Keep Screen On';

  @override
  String get keepScreenOnDescription =>
      'Prevent screen from turning off while reading';

  @override
  String get platformNotSupported => 'Platform Not Supported';

  @override
  String get platformNotSupportedBody =>
      'Kuron is designed exclusively for Android devices.';

  @override
  String get platformNotSupportedInstall =>
      'Install and run this app on an Android device.';

  @override
  String get storagePermissionExplanation =>
      'Storage permission is needed to download files. Files saved to Downloads/nhasix folder.';

  @override
  String get grantPermission => 'Grant Permission';

  @override
  String get permissionRequired => 'Permission Required';

  @override
  String get storagePermissionSettingsPrompt =>
      'Storage permission is required to download files. Please grant storage permission in app settings.';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get noReadingHistory => 'No Reading History';

  @override
  String get readingHistoryMessage =>
      'Your reading history will appear here as you read content.';

  @override
  String get startReading => 'Start Reading';

  @override
  String get browsePopularContent => 'Browse popular content';

  @override
  String get searchSomethingInteresting => 'Search for something interesting';

  @override
  String get checkOutFeaturedItems => 'Check out featured items';

  @override
  String get appSubtitleDescription => 'Nhentai unofficial client';

  @override
  String get downloadedGalleries => 'Downloaded galleries';

  @override
  String get favoriteGalleries => 'Favorite galleries';

  @override
  String get viewHistory => 'View history';

  @override
  String get openInBrowser => 'Open in browser';

  @override
  String get downloadAllGalleries => 'Download all galleries in this page';

  @override
  String get featureDisabledTitle => 'Feature Not Available';

  @override
  String get downloadFeatureDisabled =>
      'Download feature is not available for this source';

  @override
  String get favoriteFeatureDisabled =>
      'Favorite feature is not available for this source';

  @override
  String get featureNotAvailable => 'This feature is currently unavailable';

  @override
  String get chaptersTitle => 'Chapters';

  @override
  String chapterCount(int count) {
    return '$count chapters';
  }

  @override
  String loadMoreChapters(String label) {
    return 'Load more $label';
  }

  @override
  String get readChapter => 'Read';

  @override
  String get downloadChapter => 'Download Chapter';

  @override
  String enterPageNumber(int totalPages) {
    return 'Enter page number (1 - $totalPages)';
  }

  @override
  String get go => 'Go';

  @override
  String validPageNumberError(int totalPages) {
    return 'Enter a page number between 1 and $totalPages';
  }

  @override
  String get tapToJump => 'Tap to jump';

  @override
  String get goToPage => 'Go to Page';

  @override
  String get previousPageTooltip => 'Previous page';

  @override
  String get nextPageTooltip => 'Next page';

  @override
  String get tapToJumpToPage => 'Tap to jump to page';

  @override
  String get loadingContentTitle => 'Loading Content';

  @override
  String get loadingContentDetails => 'Loading Content Details';

  @override
  String get fetchingMetadata => 'Fetching metadata and images...';

  @override
  String get thisMayTakeMoments => 'This may take a few moments...';

  @override
  String get youAreOffline => 'You are offline';

  @override
  String get goOnline => 'Go Online';

  @override
  String get youAreOfflineTapToGoOnline => 'You are offline. Tap to go online.';

  @override
  String get contentInformation => 'Content Information';

  @override
  String get copyLink => 'Copy Link';

  @override
  String get moreOptions => 'More Options';

  @override
  String get moreLikeThis => 'More Like This';

  @override
  String get statistics => 'Statistics';

  @override
  String get failedToLoadContent => 'Failed to load content';

  @override
  String get shareContent => 'Share Content';

  @override
  String get sharePanelOpened => 'Share panel opened successfully!';

  @override
  String get shareFailed => 'Share failed, but link copied to clipboard';

  @override
  String downloadStartedFor(String title) {
    return 'Download started for \"$title\"';
  }

  @override
  String get viewDownloadsAction => 'View';

  @override
  String get linkCopiedToClipboard => 'Link copied to clipboard';

  @override
  String get failedToCopyLink => 'Failed to copy link. Please try again.';

  @override
  String get copiedLink => 'Copied Link';

  @override
  String get linkCopiedToClipboardDescription =>
      'The following link has been copied to your clipboard:';

  @override
  String get closeDialog => 'Close';

  @override
  String get goOnlineDialogTitle => 'Go Online';

  @override
  String get goOnlineDialogContent =>
      'You are currently in offline mode. Would you like to go online to access the latest content?';

  @override
  String get goingOnline => 'Going online...';

  @override
  String get idLabel => 'ID';

  @override
  String get pagesLabel => 'Pages';

  @override
  String artistLabel(String name) {
    return 'Artist: $name';
  }

  @override
  String get uploadedLabel => 'Uploaded';

  @override
  String get viewAllChapters => 'View All Chapters';

  @override
  String get searchChapters => 'Search chapters...';

  @override
  String get noChaptersFound => 'No chapters found.';

  @override
  String get favoritesLabel => 'Favorites';

  @override
  String get relatedLabel => 'Related';

  @override
  String yearAgo(int count, String plural) {
    return '$count year$plural ago';
  }

  @override
  String monthAgo(int count, String plural) {
    return '$count month$plural ago';
  }

  @override
  String dayAgo(int count, String plural) {
    return '$count day$plural ago';
  }

  @override
  String hourAgo(int count, String plural) {
    return '$count hour$plural ago';
  }

  @override
  String get selectFavoritesTooltip => 'Select favorites';

  @override
  String get deleteSelectedTooltip => 'Delete selected';

  @override
  String get exportAction => 'Export';

  @override
  String get refreshAction => 'Refresh';

  @override
  String get selectAllAction => 'Select All';

  @override
  String get clearAction => 'Clear';

  @override
  String selectedCountFormat(int selected, int total) {
    return '$selected / $total';
  }

  @override
  String get loadingFavoritesMessage => 'Loading favorites...';

  @override
  String get deletingFavoritesMessage => 'Deleting favorites...';

  @override
  String get removingFromFavoritesMessage => 'Removing from favorites...';

  @override
  String get favoritesDeletedMessage => 'Favorites deleted successfully';

  @override
  String get failedToDeleteFavoritesMessage => 'Failed to delete favorites.';

  @override
  String get confirmDeleteFavoritesTitle => 'Delete Favorites';

  @override
  String confirmDeleteFavoritesMessage(int count, String plural) {
    return 'Are you sure you want to delete $count favorite$plural?';
  }

  @override
  String get exportFavoritesTitle => 'Export Favorites';

  @override
  String get exportingFavoritesMessage => 'Exporting favorites...';

  @override
  String get favoritesExportedMessage => 'Favorites exported successfully';

  @override
  String get failedToExportFavoritesMessage => 'Failed to export favorites';

  @override
  String get searchFavoritesHint => 'Search favorites...';

  @override
  String get searchOfflineContentHint => 'Search offline content...';

  @override
  String failedToLoadPage(int pageNumber) {
    return 'Failed to load page $pageNumber';
  }

  @override
  String get failedToLoad => 'Failed to load';

  @override
  String get loginRequiredForAction => 'Login required for this action';

  @override
  String get login => 'Login';

  @override
  String get offlineContentTitle => 'Offline Content';

  @override
  String get offlineContentError => 'Offline Content Error';

  @override
  String get favorited => 'Favorited';

  @override
  String get favorite => 'Favorite';

  @override
  String get errorLoadingHistory => 'Error Loading History';

  @override
  String get errorLoadingFavoritesTitle => 'Error Loading Favorites';

  @override
  String get filterDataTitle => 'Filter Data';

  @override
  String searchFilterHint(String filterType) {
    return 'Search $filterType...';
  }

  @override
  String selectedCountFormat2(int count) {
    return 'Selected ($count)';
  }

  @override
  String get errorLoadingFilterDataTitle => 'Error Loading Filter Data';

  @override
  String noFilterTypeAvailable(String filterType) {
    return 'No $filterType available';
  }

  @override
  String noResultsFoundForQuery(String query) {
    return 'No results found for \"$query\"';
  }

  @override
  String get contentNotFoundTitle => 'Content Not Found';

  @override
  String contentNotFoundMessage(String contentId) {
    return 'Content with ID \"$contentId\" was not found.';
  }

  @override
  String get filterCategoriesTitle => 'Filter Categories';

  @override
  String get searchTitle => 'Search';

  @override
  String get advancedSearchTitle => 'Advanced Search';

  @override
  String get enterSearchQueryHint => 'Search (e.g. \"big breasts english\")';

  @override
  String get popularSearchesTitle => 'Popular Searches';

  @override
  String get clearAllAction => 'Clear All';

  @override
  String get pressSearchButtonMessage => 'Search with your current filters';

  @override
  String get searchingMessage => 'Searching...';

  @override
  String resultsCountFormat(String count) {
    return '$count results';
  }

  @override
  String get viewInMainAction => 'View in Main';

  @override
  String get searchErrorTitle => 'Search Error';

  @override
  String get noResultsFoundTitle => 'No Results Found';

  @override
  String pageText(int pageNumber) {
    return 'page $pageNumber';
  }

  @override
  String pagesText(int startPage, int endPage) {
    return 'pages $startPage-$endPage';
  }

  @override
  String get offlineStatus => 'OFFLINE';

  @override
  String get onlineStatus => 'ONLINE';

  @override
  String get sortBy => 'Sort by';

  @override
  String get errorOccurred => 'An error occurred';

  @override
  String get tapToRetry => 'Tap to retry';

  @override
  String get helpTitle => 'Help';

  @override
  String get helpNoResults => 'No results found for your search';

  @override
  String get helpTryDifferent =>
      'Try using different keywords or check your spelling';

  @override
  String get helpUseFilters => 'Use filters to narrow down your search';

  @override
  String get helpCheckConnection => 'Check your internet connection';

  @override
  String get sendReportText => 'Send Report';

  @override
  String get technicalDetailsTitle => 'Technical Details';

  @override
  String get reportSentText => 'Report sent!';

  @override
  String get suggestionCheckConnection => 'Check your internet connection';

  @override
  String get suggestionTryWifiMobile =>
      'Try switching between Wi-Fi and mobile data';

  @override
  String get suggestionRestartRouter => 'Restart your router if using Wi-Fi';

  @override
  String get suggestionCheckWebsite => 'Check if the website is down';

  @override
  String noContentFoundWithQuery(String query) {
    return 'No content found for \"$query\". Try adjusting your search terms or filters.';
  }

  @override
  String get noContentFound =>
      'No content found. Try adjusting your search terms or filters.';

  @override
  String get suggestionTryDifferentKeywords => 'Try different keywords';

  @override
  String get suggestionRemoveFilters => 'Remove some filters';

  @override
  String get suggestionCheckSpelling => 'Check spelling';

  @override
  String get suggestionUseBroaderTerms => 'Use broader search terms';

  @override
  String get underMaintenanceTitle => 'Under Maintenance';

  @override
  String get underMaintenanceMessage =>
      'The service is currently under maintenance. Please check back later.';

  @override
  String get suggestionMaintenanceHours =>
      'Maintenance usually takes a few hours';

  @override
  String get suggestionCheckSocial => 'Check social media for updates';

  @override
  String get suggestionTryLater => 'Try again later';

  @override
  String get includeFilter => 'Include';

  @override
  String get excludeFilter => 'Exclude';

  @override
  String get overallProgress => 'Overall Progress';

  @override
  String get active => 'Active';

  @override
  String get queued => 'Queued';

  @override
  String get speed => 'Speed';

  @override
  String downloadsFailed(int count, String plural) {
    return '$count download$plural failed';
  }

  @override
  String get view => 'View';

  @override
  String get processing => 'Processing...';

  @override
  String get loading => 'Loading...';

  @override
  String get unknownTitle => 'Unknown Title';

  @override
  String get readingCompleted => 'Completed';

  @override
  String get readAgain => 'Read Again';

  @override
  String get continueReading => 'Continue';

  @override
  String get removeFromHistory => 'Remove from History';

  @override
  String get lessThanOneMinute => 'Less than 1 minute';

  @override
  String get readingTime => 'reading time';

  @override
  String get downloadActions => 'Download Actions';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get cancel => 'Cancel';

  @override
  String get retry => 'Retry';

  @override
  String get details => 'Details';

  @override
  String get remove => 'Remove';

  @override
  String get downloadActionPause => 'Pause';

  @override
  String get downloadActionResume => 'Resume';

  @override
  String get downloadActionCancel => 'Cancel';

  @override
  String get downloadActionRetry => 'Retry';

  @override
  String get downloadActionConvertToPdf => 'Convert to PDF';

  @override
  String get downloadActionDetails => 'Details';

  @override
  String get downloadActionRemove => 'Remove';

  @override
  String downloadPagesRangeFormat(
      int downloaded, int total, int start, int end, int totalPages) {
    return '$downloaded/$total (Pages $start-$end of $totalPages)';
  }

  @override
  String downloadPagesFormat(int downloaded, int total) {
    return '$downloaded/$total';
  }

  @override
  String downloadContentTitle(String contentId) {
    return 'Content $contentId';
  }

  @override
  String downloadEtaLabel(String duration) {
    return 'ETA: $duration';
  }

  @override
  String get duration => 'Duration';

  @override
  String get downloadSettingsTitle => 'Download Settings';

  @override
  String get performanceSection => 'Performance';

  @override
  String get maxConcurrentDownloads => 'Max Concurrent Downloads';

  @override
  String get concurrentDownloadsWarning =>
      'Higher values may consume more bandwidth and device resources';

  @override
  String get imageQualityLabel => 'Image Quality';

  @override
  String get autoRetrySection => 'Auto Retry';

  @override
  String get autoRetryFailedDownloads => 'Auto Retry Failed Downloads';

  @override
  String get autoRetryDescription => 'Automatically retry failed downloads';

  @override
  String get maxRetryAttempts => 'Max Retry Attempts';

  @override
  String get networkSection => 'Network';

  @override
  String get wifiOnlyLabel => 'Wi-Fi Only';

  @override
  String get wifiOnlyDescription => 'Only download when connected to Wi-Fi';

  @override
  String get downloadTimeoutLabel => 'Download Timeout';

  @override
  String get notificationsSection => 'Notifications';

  @override
  String get enableNotificationsLabel => 'Enable Notifications';

  @override
  String get enableNotificationsDescription =>
      'Show notifications for download progress';

  @override
  String get minutesUnit => 'min';

  @override
  String get searchContentHint => 'Search content...';

  @override
  String get hideFiltersTooltip => 'Hide filters';

  @override
  String get showMoreFiltersTooltip => 'Show more filters';

  @override
  String get advancedFiltersTitle => 'Advanced Filters';

  @override
  String get sortByLabel => 'Sort by';

  @override
  String get recentSearchesTitle => 'Recent Searches';

  @override
  String get includeTagsLabel => 'Include tags (comma separated)';

  @override
  String get includeTagsHint => 'e.g., romance, comedy, school';

  @override
  String get excludeTagsHint => 'e.g., horror, violence';

  @override
  String get artistsHint => 'e.g., artist1, artist2';

  @override
  String get pageCountRangeTitle => 'Page Count Range';

  @override
  String get minPagesLabel => 'Min pages';

  @override
  String get maxPagesLabel => 'Max pages';

  @override
  String get rangeToSeparator => 'to';

  @override
  String get popularTagsTitle => 'Popular Tags';

  @override
  String get filtersActiveLabel => 'active';

  @override
  String get clearAllFilters => 'Clear All';

  @override
  String get appSubtitle => 'Enhanced Reading Experience';

  @override
  String get initializingApp => 'Initializing Application...';

  @override
  String get settingUpComponents =>
      'Setting up components and checking connection...';

  @override
  String get bypassingProtection =>
      'Bypassing protection and establishing connection...';

  @override
  String get connectionFailed => 'Connection Failed';

  @override
  String get readyToGo => 'Ready to Go!';

  @override
  String get launchingApp => 'Launching main application...';

  @override
  String downloaded(String size) {
    return '$size downloaded';
  }

  @override
  String get imageNotAvailable => 'Image not available';

  @override
  String loadingPage(int pageNumber) {
    return 'Loading page $pageNumber...';
  }

  @override
  String pageNumber(int pageNumber) {
    return 'Page $pageNumber';
  }

  @override
  String get checkInternetConnection => 'Check your internet connection';

  @override
  String selectedItemsCount(int count) {
    return '$count selected';
  }

  @override
  String get removeFavorite => 'Remove Favorite';

  @override
  String get noImage => 'No image';

  @override
  String get youAreOfflineShort => 'You are offline';

  @override
  String get someFeaturesLimited =>
      'Some features are limited. Connect to internet for full access.';

  @override
  String get wifi => 'WI-FI';

  @override
  String get ethernet => 'ETHERNET';

  @override
  String get mobile => 'MOBILE';

  @override
  String get online => 'ONLINE';

  @override
  String get offlineMode => 'Offline Mode';

  @override
  String get applySearch => 'Apply Search';

  @override
  String get addFiltersToSearch => 'Add filters to enable search';

  @override
  String get startSearching => 'Start searching';

  @override
  String get enterKeywordsAdvancedHint =>
      'Enter keywords, tags, or use advanced filters to find content';

  @override
  String get filtersReady => 'Filters Ready';

  @override
  String get clearAllFiltersTooltip => 'Clear all filters';

  @override
  String get offlineSomeFeaturesUnavailable =>
      'You are offline. Some features may not be available.';

  @override
  String get usingDownloadedContentOnly => 'Using downloaded content only';

  @override
  String get onlineModeWithNetworkAccess => 'Online mode with network access';

  @override
  String get tagsScreenPlaceholder => 'Tags Screen - To be implemented';

  @override
  String get artistsScreenPlaceholder => 'Artists Screen - To be implemented';

  @override
  String get statusScreenPlaceholder => 'Status Screen - To be implemented';

  @override
  String get pageNotFound => 'Page Not Found';

  @override
  String pageNotFoundWithUri(String uri) {
    return 'Page not found: $uri';
  }

  @override
  String get goHome => 'Go Home';

  @override
  String get debugThemeInfo => 'DEBUG: Theme Info';

  @override
  String get lightTheme => 'Light';

  @override
  String get darkTheme => 'Dark';

  @override
  String get amoledTheme => 'AMOLED';

  @override
  String get systemMessages => 'System Messages and Background Services';

  @override
  String get notificationMessages => 'Notification Messages';

  @override
  String convertingToPdfWithTitle(String title) {
    return 'Converting $title to PDF...';
  }

  @override
  String convertingToPdfProgress(Object progress) {
    return 'Converting to PDF ($progress%)';
  }

  @override
  String convertingToPdfProgressWithTitle(String title, int progress) {
    return 'Converting $title to PDF ($progress%)';
  }

  @override
  String get progress => 'Progress';

  @override
  String get pdfCreatedSuccessfully => 'PDF Created Successfully';

  @override
  String pdfCreatedWithParts(String title, int partsCount) {
    return '$title converted to $partsCount PDF files';
  }

  @override
  String downloadStarted(String title) {
    return 'Download Started';
  }

  @override
  String downloadingWithTitle(String title) {
    return 'Downloading: $title';
  }

  @override
  String downloadingProgress(Object progress) {
    return 'Downloading ($progress%)';
  }

  @override
  String get downloadComplete => 'Download Complete';

  @override
  String downloadedWithTitle(String title) {
    return 'Downloaded: $title';
  }

  @override
  String get downloadFailed => 'Download Failed';

  @override
  String downloadFailedWithTitle(String title) {
    return 'Failed: $title';
  }

  @override
  String get downloadPaused => 'Paused';

  @override
  String get downloadResumed => 'Resumed';

  @override
  String get downloadCancelled => 'Cancelled';

  @override
  String get downloadRetry => 'Retry';

  @override
  String get downloadOpen => 'Open';

  @override
  String get pdfOpen => 'Open PDF';

  @override
  String get pdfShare => 'Share';

  @override
  String get pdfRetry => 'Retry PDF';

  @override
  String get downloadServiceMessages => 'Download Service Messages';

  @override
  String downloadRangeInfo(int startPage, int endPage) {
    return ' (Pages $startPage-$endPage)';
  }

  @override
  String downloadRangeComplete(int startPage, int endPage) {
    return ' (Pages $startPage-$endPage)';
  }

  @override
  String get startPage => 'Start Page';

  @override
  String get endPage => 'End Page';

  @override
  String invalidPageRange(int start, int end, int total) {
    return 'Invalid page range: $start-$end (total: $total)';
  }

  @override
  String get storagePermissionRequired =>
      'Storage permission is required for downloads. Please grant storage permission in app settings.';

  @override
  String noDataReceived(String url) {
    return 'No data received for image: $url';
  }

  @override
  String createdNoMediaFile(String path) {
    return 'Created .nomedia file for privacy: $path';
  }

  @override
  String get privacyProtectionEnsured =>
      'Privacy protection ensured for existing downloads';

  @override
  String get pdfConversionMessages => 'PDF Conversion Service Messages';

  @override
  String pdfConversionStarted(String contentId) {
    return 'PDF conversion started for $contentId';
  }

  @override
  String pdfConversionCompleted(String contentId) {
    return 'PDF conversion completed successfully for $contentId';
  }

  @override
  String pdfConversionFailed(String contentId, String error) {
    return 'PDF conversion failed for $contentId: $error';
  }

  @override
  String pdfPartProcessing(int part) {
    return 'Processing part $part in isolate...';
  }

  @override
  String get pdfSingleProcessing => 'Processing single PDF in isolate...';

  @override
  String pdfSplitRequired(int totalParts, int totalPages) {
    return 'Splitting into $totalParts parts ($totalPages pages)';
  }

  @override
  String get totalPages => 'Total Pages';

  @override
  String pdfCreatedFiles(int partsCount, int pageCount) {
    return 'Created $partsCount PDF file(s) with $pageCount total pages';
  }

  @override
  String get pdfNoImagesProvided => 'No images provided for PDF conversion';

  @override
  String pdfFailedToCreatePart(int part, String error) {
    return 'Failed to create PDF part $part: $error';
  }

  @override
  String pdfFailedToCreate(String error) {
    return 'Failed to create PDF: $error';
  }

  @override
  String pdfOutputDirectoryCreated(String path) {
    return 'Created PDF output directory: $path';
  }

  @override
  String pdfUsingFallbackDirectory(String path) {
    return 'Using fallback directory: $path';
  }

  @override
  String pdfInfoSaved(String contentId, int partsCount, int pageCount) {
    return 'PDF info saved for $contentId ($partsCount parts, $pageCount pages)';
  }

  @override
  String pdfExistsForContent(String contentId, String exists) {
    return 'PDF exists for $contentId: $exists';
  }

  @override
  String pdfFoundFiles(String contentId, int count) {
    return 'Found $count PDF file(s) for $contentId';
  }

  @override
  String pdfDeletedFiles(String contentId, int count) {
    return 'Successfully deleted $count PDF file(s) for $contentId';
  }

  @override
  String pdfTotalSize(String contentId, int sizeBytes) {
    return 'Total PDF size for $contentId: $sizeBytes bytes';
  }

  @override
  String pdfCleanupStarted(int maxAge) {
    return 'Starting PDF cleanup, deleting files older than $maxAge days';
  }

  @override
  String pdfCleanupCompleted(int deletedCount) {
    return 'Cleanup completed, deleted $deletedCount old PDF files';
  }

  @override
  String pdfStatistics(Object averageFilesPerContent, Object totalFiles,
      Object totalSizeFormatted, Object uniqueContents) {
    return 'PDF statistics - $totalFiles files, $totalSizeFormatted total size, $uniqueContents unique contents, $averageFilesPerContent avg files per content';
  }

  @override
  String get historyCleanupMessages => 'History Cleanup Service Messages';

  @override
  String get historyCleanupServiceInitialized =>
      'History Cleanup Service initialized';

  @override
  String get historyCleanupServiceDisposed =>
      'History Cleanup Service disposed';

  @override
  String get autoCleanupDisabled => 'Auto cleanup history is disabled';

  @override
  String cleanupServiceStarted(int intervalHours) {
    return 'Cleanup service started with ${intervalHours}h interval';
  }

  @override
  String performingHistoryCleanup(String reason) {
    return 'Performing history cleanup: $reason';
  }

  @override
  String historyCleanupCompleted(int clearedCount, String reason) {
    return 'History cleanup completed: cleared $clearedCount entries ($reason)';
  }

  @override
  String get manualHistoryCleanup => 'Performing manual history cleanup';

  @override
  String get updatedLastAppAccess => 'Updated last app access time';

  @override
  String get updatedLastCleanupTime => 'Updated last cleanup time';

  @override
  String intervalCleanup(int intervalHours) {
    return 'Interval cleanup (${intervalHours}h)';
  }

  @override
  String inactivityCleanup(int inactivityDays) {
    return 'Inactivity cleanup ($inactivityDays days)';
  }

  @override
  String maxAgeCleanup(int maxDays) {
    return 'Max age cleanup ($maxDays days)';
  }

  @override
  String get initialCleanupSetup => 'Initial cleanup setup';

  @override
  String shouldCleanupOldHistory(String shouldCleanup) {
    return 'Should cleanup old history: $shouldCleanup';
  }

  @override
  String get analyticsMessages => 'Analytics Service Messages';

  @override
  String analyticsServiceInitialized(String enabled) {
    return 'Analytics service initialized - tracking $enabled';
  }

  @override
  String get analyticsTrackingEnabled => 'Analytics tracking enabled by user';

  @override
  String get analyticsTrackingDisabled =>
      'Analytics tracking disabled by user - data cleared';

  @override
  String get analyticsDataCleared => 'Analytics data cleared by user request';

  @override
  String get analyticsServiceDisposed => 'Analytics service disposed';

  @override
  String analyticsEventTracked(String eventType, String eventName) {
    return '📊 Analytics: $eventType - $eventName';
  }

  @override
  String get appStartedEvent => 'App started event tracked';

  @override
  String sessionEndEvent(int minutes) {
    return 'Session end event tracked ($minutes minutes)';
  }

  @override
  String get analyticsEnabledEvent => 'Analytics enabled event tracked';

  @override
  String get analyticsDisabledEvent => 'Analytics disabled event tracked';

  @override
  String screenViewEvent(String screenName) {
    return 'Screen view tracked: $screenName';
  }

  @override
  String userActionEvent(String action) {
    return 'User action tracked: $action';
  }

  @override
  String performanceEvent(String operation, int durationMs) {
    return 'Performance tracked: $operation (${durationMs}ms)';
  }

  @override
  String errorEvent(String errorType, String errorMessage) {
    return 'Error tracked: $errorType - $errorMessage';
  }

  @override
  String featureUsageEvent(String feature) {
    return 'Feature usage tracked: $feature';
  }

  @override
  String readingSessionEvent(String contentId, int minutes, int pages) {
    return 'Reading session tracked: $contentId (${minutes}min, $pages pages)';
  }

  @override
  String get pages => 'Pages';

  @override
  String get offlineManagerMessages => 'Offline Content Manager Messages';

  @override
  String offlineContentAvailable(String contentId, String available) {
    return 'Offline Content Available';
  }

  @override
  String offlineContentPath(String contentId, String path) {
    return 'Offline content path for $contentId: $path';
  }

  @override
  String foundExistingFiles(int count) {
    return 'Found $count existing downloaded files';
  }

  @override
  String offlineImageUrlsFound(String contentId, int count) {
    return 'Found $count offline image URLs for $contentId';
  }

  @override
  String offlineContentIdsFound(int count) {
    return 'Found $count offline content IDs';
  }

  @override
  String searchingOfflineContent(String query) {
    return 'Searching offline content for: $query';
  }

  @override
  String offlineContentMetadata(String contentId, String source) {
    return 'Offline content metadata for $contentId: $source';
  }

  @override
  String offlineContentCreated(String contentId) {
    return 'Offline content created for $contentId';
  }

  @override
  String offlineStorageUsage(int sizeBytes) {
    return 'Offline storage usage: $sizeBytes bytes';
  }

  @override
  String get cleanupOrphanedFilesStarted =>
      'Starting cleanup of orphaned offline files';

  @override
  String get cleanupOrphanedFilesCompleted =>
      'Cleanup of orphaned offline files completed';

  @override
  String removedOrphanedDirectory(String path) {
    return 'Removed orphaned directory: $path';
  }

  @override
  String daysAgo(int count, String suffix) {
    return '$count$suffix ago';
  }

  @override
  String hoursAgo(int count, String suffix) {
    return '$count$suffix ago';
  }

  @override
  String minutesAgo(int count, String suffix) {
    return '$count$suffix ago';
  }

  @override
  String get justNow => 'Just now';

  @override
  String get queryLabel => 'Query';

  @override
  String get tagsLabel => 'Tags';

  @override
  String get excludeTagsLabel => 'Exclude Tags';

  @override
  String get groupsLabel => 'Groups';

  @override
  String get excludeGroupsLabel => 'Exclude Groups';

  @override
  String get charactersLabel => 'Characters';

  @override
  String get excludeCharactersLabel => 'Exclude Characters';

  @override
  String get parodiesLabel => 'Parodies';

  @override
  String get excludeParodiesLabel => 'Exclude Parodies';

  @override
  String get artistsLabel => 'Artists';

  @override
  String get excludeArtistsLabel => 'Exclude Artists';

  @override
  String get languageLabel => 'Language';

  @override
  String get categoryLabel => 'Category';

  @override
  String hours(int count) {
    return '${count}h';
  }

  @override
  String minutes(int count) {
    return '${count}m';
  }

  @override
  String seconds(int count) {
    return '${count}s';
  }

  @override
  String get loadingUserPreferences => 'Loading user preferences';

  @override
  String get successfullyLoadedUserPreferences =>
      'Successfully loaded user preferences';

  @override
  String invalidColumnsPortraitValue(int value) {
    return 'Invalid columns portrait value: $value';
  }

  @override
  String invalidColumnsLandscapeValue(int value) {
    return 'Invalid columns landscape value: $value';
  }

  @override
  String get updatingSettingsViaPreferencesService =>
      'Updating settings via PreferencesService';

  @override
  String get successfullyUpdatedSettings => 'Successfully updated settings';

  @override
  String failedToUpdateSetting(String error) {
    return 'Failed to update setting: $error';
  }

  @override
  String get resettingAllSettingsToDefaults =>
      'Resetting all settings to defaults';

  @override
  String get successfullyResetAllSettingsToDefaults =>
      'Successfully reset all settings to defaults';

  @override
  String failedToResetSettings(String error) {
    return 'Failed to reset settings: $error';
  }

  @override
  String get settingsNotLoaded => 'Settings not loaded';

  @override
  String get exportingSettings => 'Exporting settings';

  @override
  String get successfullyExportedSettings => 'Successfully exported settings';

  @override
  String failedToExportSettings(String error) {
    return 'Failed to export settings: $error';
  }

  @override
  String get importingSettings => 'Importing settings';

  @override
  String get successfullyImportedSettings => 'Successfully imported settings';

  @override
  String failedToImportSettings(String error) {
    return 'Failed to import settings: $error';
  }

  @override
  String get unableToSyncSettings =>
      'Unable to sync settings. Changes will be saved locally.';

  @override
  String get unableToSaveSettings =>
      'Unable to save settings. Please check device storage.';

  @override
  String get failedToUpdateSettings =>
      'Failed to update settings. Please try again.';

  @override
  String get loadingHistory => 'Loading history';

  @override
  String get noHistoryFound => 'No history found';

  @override
  String loadedHistoryEntries(int count) {
    return 'Loaded $count history entries';
  }

  @override
  String failedToLoadHistory(String error) {
    return 'Failed to load history: $error';
  }

  @override
  String loadingMoreHistory(int page) {
    return 'Loading more history (page $page)';
  }

  @override
  String loadedMoreHistoryEntries(int count, int total) {
    return 'Loaded $count more entries, total: $total';
  }

  @override
  String get refreshingHistory => 'Refreshing history';

  @override
  String refreshedHistoryWithEntries(int count) {
    return 'Refreshed history with $count entries';
  }

  @override
  String failedToRefreshHistory(String error) {
    return 'Failed to refresh history: $error';
  }

  @override
  String get clearingAllHistory => 'Clearing all history';

  @override
  String get allHistoryCleared => 'All history cleared';

  @override
  String failedToClearHistory(String error) {
    return 'Failed to clear history: $error';
  }

  @override
  String removingHistoryItem(String contentId) {
    return 'Removing history item: $contentId';
  }

  @override
  String removedHistoryItem(String contentId) {
    return 'Removed history item: $contentId';
  }

  @override
  String failedToRemoveHistoryItem(String error) {
    return 'Failed to remove history item: $error';
  }

  @override
  String get performingManualHistoryCleanup =>
      'Performing manual history cleanup';

  @override
  String get manualCleanupCompleted => 'Manual cleanup completed';

  @override
  String failedToPerformCleanup(String error) {
    return 'Failed to perform cleanup: $error';
  }

  @override
  String get updatingCleanupSettings => 'Updating cleanup settings';

  @override
  String get cleanupSettingsUpdated => 'Cleanup settings updated';

  @override
  String addingContentToFavorites(String title) {
    return 'Adding content to favorites: $title';
  }

  @override
  String successfullyAddedToFavorites(String title) {
    return 'Successfully added to favorites: $title';
  }

  @override
  String contentNotInFavorites(String contentId) {
    return 'Content $contentId is not in favorites, skipping removal';
  }

  @override
  String callingRemoveFromFavoritesUseCase(String params) {
    return 'Calling removeFromFavoritesUseCase with params: $params';
  }

  @override
  String get successfullyCalledRemoveFromFavoritesUseCase =>
      'Successfully called removeFromFavoritesUseCase';

  @override
  String updatingFavoritesListInState(String contentId) {
    return 'Updating favorites list in state, removing contentId: $contentId';
  }

  @override
  String favoritesCountBeforeAfter(int before, int after) {
    return 'Favorites count: before=$before, after=$after';
  }

  @override
  String get stateUpdatedSuccessfully => 'State updated successfully';

  @override
  String successfullyRemovedFromFavorites(String contentId) {
    return 'Successfully removed from favorites: $contentId';
  }

  @override
  String errorRemovingContentFromFavorites(String contentId, String error) {
    return 'Error removing content $contentId from favorites: $error';
  }

  @override
  String removingFavoritesInBatch(int count) {
    return 'Removing $count favorites in batch';
  }

  @override
  String successfullyRemovedFavoritesInBatch(int count) {
    return 'Successfully removed $count favorites in batch';
  }

  @override
  String searchingFavoritesWithQuery(String query) {
    return 'Searching favorites with query: $query';
  }

  @override
  String foundFavoritesMatchingQuery(int count) {
    return 'Found $count favorites matching query';
  }

  @override
  String get clearingFavoritesSearch => 'Clearing favorites search';

  @override
  String get exportingFavoritesData => 'Exporting favorites data';

  @override
  String successfullyExportedFavorites(int count) {
    return 'Successfully exported $count favorites';
  }

  @override
  String get importingFavoritesData => 'Importing favorites data';

  @override
  String successfullyImportedFavorites(int count) {
    return 'Successfully imported $count favorites';
  }

  @override
  String failedToImportFavorite(String error) {
    return 'Failed to import favorite: $error';
  }

  @override
  String get retryingFavoritesLoading => 'Retrying favorites loading';

  @override
  String get refreshingFavorites => 'Refreshing favorites';

  @override
  String failedToLoadFavorites(String error) {
    return 'Failed to load favorites: $error';
  }

  @override
  String failedToInitializeDownloadManager(String error) {
    return 'Failed to initialize download manager: $error';
  }

  @override
  String get waitingForWifiConnection => 'Waiting for Wi-Fi connection';

  @override
  String failedToQueueDownload(String error) {
    return 'Failed to queue download: $error';
  }

  @override
  String retryingDownload(int current, int total) {
    return 'Retrying... ($current/$total)';
  }

  @override
  String get downloadCancelledByUser => 'Download cancelled by user';

  @override
  String get pausingAllDownloads => 'Pausing all downloads';

  @override
  String get resumingAllDownloads => 'Resuming all downloads';

  @override
  String get cancellingAllDownloads => 'Cancelling all downloads';

  @override
  String get clearingCompletedDownloads => 'Clearing completed downloads';

  @override
  String failedToQueueRangeDownload(String error) {
    return 'Failed to queue range download: $error';
  }

  @override
  String failedToPauseDownload(String error) {
    return 'Failed to pause download: $error';
  }

  @override
  String failedToCancelDownload(String error) {
    return 'Failed to cancel download: $error';
  }

  @override
  String failedToRetryDownload(String error) {
    return 'Failed to retry download: $error';
  }

  @override
  String failedToResumeDownload(String error) {
    return 'Failed to resume download: $error';
  }

  @override
  String failedToRemoveDownload(String error) {
    return 'Failed to remove download: $error';
  }

  @override
  String failedToRefreshDownloads(String error) {
    return 'Failed to refresh downloads: $error';
  }

  @override
  String failedToUpdateDownloadSettings(String error) {
    return 'Failed to update download settings: $error';
  }

  @override
  String failedToPauseAllDownloads(String error) {
    return 'Failed to pause all downloads: $error';
  }

  @override
  String failedToResumeAllDownloads(String error) {
    return 'Failed to resume all downloads: $error';
  }

  @override
  String failedToCancelAllDownloads(String error) {
    return 'Failed to cancel all downloads: $error';
  }

  @override
  String failedToClearCompletedDownloads(String error) {
    return 'Failed to clear completed downloads: $error';
  }

  @override
  String get downloadNotCompletedYet => 'Download is not completed yet';

  @override
  String get noImagesFoundForConversion => 'No images found for conversion';

  @override
  String storageCleanupCompleted(int cleanedFiles, String freedSpace) {
    return 'Storage cleanup completed. Cleaned $cleanedFiles directories, freed $freedSpace MB';
  }

  @override
  String storageCleanupComplete(int cleanedFiles, String freedSpace) {
    return 'Storage Cleanup Complete: Cleaned $cleanedFiles items, freed $freedSpace MB';
  }

  @override
  String storageCleanupFailed(String error) {
    return 'Storage Cleanup Failed: $error';
  }

  @override
  String exportDownloadsComplete(String fileName) {
    return 'Export Complete: Downloads exported to $fileName';
  }

  @override
  String exportFailed(String error) {
    return 'Export Failed: $error';
  }

  @override
  String failedToDeleteDirectory(String path, String error) {
    return 'Failed to delete directory: $path, error: $error';
  }

  @override
  String failedToDeleteTempFile(String path, String error) {
    return 'Failed to delete temp file: $path, error: $error';
  }

  @override
  String downloadDirectoryNotFound(String path) {
    return 'Download directory not found: $path';
  }

  @override
  String cannotOpenIncompleteDownload(String contentId) {
    return 'Cannot open - download not completed or path missing for $contentId';
  }

  @override
  String allStrategiesFailedToOpenDownload(String contentId) {
    return 'All strategies failed to open downloaded content for $contentId';
  }

  @override
  String failedToSaveProgressToDatabase(String error) {
    return 'Failed to save progress to database: $error';
  }

  @override
  String failedToUpdatePauseNotification(String error) {
    return 'Failed to update pause notification: $error';
  }

  @override
  String failedToUpdateResumeNotification(String error) {
    return 'Failed to update resume notification: $error';
  }

  @override
  String failedToUpdateNotificationProgress(String error) {
    return 'Failed to update notification progress: $error';
  }

  @override
  String errorCalculatingDirectorySize(String error) {
    return 'Error calculating directory size: $error';
  }

  @override
  String errorCleaningTempFiles(String path, String error) {
    return 'Error cleaning temp files in: $path, error: $error';
  }

  @override
  String errorDetectingDownloadsDirectory(String error) {
    return 'Error detecting Downloads directory: $error';
  }

  @override
  String usingEmergencyFallbackDirectory(String path) {
    return 'Using emergency fallback directory: $path';
  }

  @override
  String get errorDuringStorageCleanup => 'Error during storage cleanup';

  @override
  String get errorDuringExport => 'Error during export';

  @override
  String errorDuringPdfConversion(String contentId) {
    return 'Error during PDF conversion for $contentId';
  }

  @override
  String errorRetryingPdfConversion(String error) {
    return 'Error retrying PDF conversion: $error';
  }

  @override
  String errorOpeningDownloadedContent(String error) {
    return 'Error opening downloaded content: $error';
  }

  @override
  String get importBackupFolder => 'Import Backup Folder';

  @override
  String get importBackupFolderDescription =>
      'Enter the path to your backup folder containing nhasix content folders:';

  @override
  String get scanningBackupFolder => 'Scanning backup folder...';

  @override
  String backupContentFound(int count) {
    return 'Found $count backup items';
  }

  @override
  String get noBackupContentFound => 'No valid content found in backup folder';

  @override
  String errorScanningBackup(String error) {
    return 'Error scanning backup: $error';
  }

  @override
  String get themeDescription => 'Color theme for the app interface.';

  @override
  String get imageQualityDescription =>
      'Image quality for downloads. Higher quality uses more storage.';

  @override
  String get gridColumnsDescription => 'Grid columns in portrait mode.';

  @override
  String get gridPreview => 'Grid Preview';

  @override
  String get autoCleanupDescription =>
      'Manage automatic cleanup of reading history to free up storage space.';

  @override
  String get testCacheClearing => 'Test App Update Cache Clearing';

  @override
  String get testCacheClearingDescription =>
      'Simulate app update and test cache clearing behavior.';

  @override
  String get forceClearCache => 'Force Clear All Caches';

  @override
  String get forceClearCacheDescription => 'Manually clear all image caches.';

  @override
  String get runTest => 'Run Test';

  @override
  String get clearCacheButton => 'Clear Cache';

  @override
  String get disguiseModeDescription => 'App launcher appearance for privacy.';

  @override
  String get applyingDisguiseMode => 'Applying disguise mode changes...';

  @override
  String get disguiseDefault => 'Default';

  @override
  String get disguiseCalculator => 'Calculator';

  @override
  String get disguiseNotes => 'Notes';

  @override
  String get disguiseWeather => 'Weather';

  @override
  String get storagePermissionScan =>
      'Storage permission required to scan backup folders';

  @override
  String get exportingLibrary => 'Exporting Library';

  @override
  String get libraryExportSuccess => 'Library exported successfully!';

  @override
  String get browseDownloads => 'Browse Downloads';

  @override
  String deletingContent(String title) {
    return 'Deleting $title...';
  }

  @override
  String contentDeletedFreed(String title, String size) {
    return '$title deleted. Freed $size MB';
  }

  @override
  String get size => 'Size';

  @override
  String failedToDeleteContent(String title) {
    return 'Failed to delete $title';
  }

  @override
  String errorGeneric(String error) {
    return 'Error: $error';
  }

  @override
  String get contentDeleted => 'Content deleted';

  @override
  String get cacheManagementDebug => '🚀 Cache Management (Debug)';

  @override
  String get convertToPdf => 'Convert to PDF';

  @override
  String get convertingToPdf => 'Converting to PDF...';

  @override
  String pdfConversionFailedWithError(String title, String error) {
    return 'PDF conversion failed for $title: $error';
  }

  @override
  String get syncStarted => 'Syncing Backup...';

  @override
  String get syncStartedMessage => 'Scanning and importing offline content';

  @override
  String syncInProgress(int percent) {
    return 'Syncing Backup ($percent%)';
  }

  @override
  String syncProgressMessage(int processed, int total) {
    return 'Processed $processed of $total items';
  }

  @override
  String get total => 'Total';

  @override
  String get syncCompleted => 'Sync Completed';

  @override
  String syncCompletedMessage(int synced, int updated) {
    return 'Imported: $synced, Updated: $updated';
  }

  @override
  String syncResult(int synced, int updated) {
    return 'Sync Result: $synced imported, $updated updated';
  }

  @override
  String get storageSection => 'Storage Location';

  @override
  String get storageLocation => 'Custom Download Folder';

  @override
  String get defaultStorage => 'Default (Internal)';

  @override
  String get storageDescription => 'Choose a folder to save downloads';

  @override
  String get downloadDirectory => 'Download Directory';

  @override
  String get changeDirectory => 'Change Directory';

  @override
  String get downloadDirectoryUpdated => 'Download directory updated';

  @override
  String get useDefaultInternalStorage =>
      'Use default internal storage location';

  @override
  String get confirmResetStorageDirectory =>
      'Reset download directory to default internal storage?';

  @override
  String get downloadDirectoryReset => 'Download directory reset to default';

  @override
  String get backupNotFound => 'Backup Not Found';

  @override
  String get backupNotFoundMessage =>
      'No \'nhasix\' backup folder was found in the default location. Would you like to select a custom folder containing your backup?';

  @override
  String get selectFolder => 'Folder';

  @override
  String get premiumFeature => 'Premium Feature';

  @override
  String get commentsMaintenance => 'Comments Under Maintenance';

  @override
  String get estimatedRecovery => 'Estimated Recovery';

  @override
  String get fullColor => 'full color';

  @override
  String downloadBlocInitializedWithDownloads(int count) {
    return 'DownloadBloc: Initialized with $count downloads';
  }

  @override
  String get downloadBlocProgressStreamSubscriptionInitialized =>
      'DownloadBloc: Progress stream subscription initialized';

  @override
  String get downloadBlocNotificationCallbacksConfigured =>
      'DownloadBloc: Notification callbacks configured';

  @override
  String downloadBlocReceivedProgressUpdate(String update) {
    return 'DownloadBloc: Received progress update: $update';
  }

  @override
  String downloadBlocReceivedCompletionEvent(String contentId) {
    return 'DownloadBloc: Received completion event for $contentId';
  }

  @override
  String downloadBlocProgressStreamError(String error) {
    return 'DownloadBloc: Progress stream error: $error';
  }

  @override
  String notificationActionPauseRequested(String contentId) {
    return 'NotificationAction: Pause requested for $contentId';
  }

  @override
  String notificationActionResumeRequested(String contentId) {
    return 'NotificationAction: Resume requested for $contentId';
  }

  @override
  String notificationActionCancelRequested(String contentId) {
    return 'NotificationAction: Cancel requested for $contentId';
  }

  @override
  String notificationActionRetryRequested(String contentId) {
    return 'NotificationAction: Retry requested for $contentId';
  }

  @override
  String notificationActionPdfRetryRequested(String contentId) {
    return 'NotificationAction: PDF retry requested for $contentId';
  }

  @override
  String notificationActionOpenDownloadRequested(String contentId) {
    return 'NotificationAction: Open download requested for $contentId';
  }

  @override
  String notificationActionNavigateToDownloadsRequested(String contentId) {
    return 'NotificationAction: Navigate to downloads requested for $contentId';
  }

  @override
  String get downloadBlocErrorInitializing =>
      'DownloadBloc: Error initializing';

  @override
  String downloadBlocFailedToReadDownloadBlocState(String error) {
    return 'Failed to read DownloadBloc state, falling back to filesystem check: $error';
  }

  @override
  String get sourceSelectorSelectSource => 'Source';

  @override
  String get sourceSelectorDescription =>
      'Switch provider for feed, detail, search, and reader data.';

  @override
  String get sourceSelectorNoSourceSelected => 'No source selected';

  @override
  String get sourceSelectorActiveSource => 'Active source';

  @override
  String get sourceSelectorUnderMaintenance => 'Under maintenance';

  @override
  String get sourceSelectorCurrentlySelected => 'Currently selected';

  @override
  String get sourceSelectorTapToSwitch => 'Tap to switch';

  @override
  String get sourceSelectorSearchHint => 'Search source';

  @override
  String get sourceSelectorNoResults => 'No source matches your search';

  @override
  String get settingsCustomSourceTitle => 'Add Custom Source';

  @override
  String get settingsCustomSourceSubtitle =>
      'Install source package from signed manifest URL or ZIP package.';

  @override
  String get settingsAddViaLink => 'Add via Link';

  @override
  String get settingsImportZip => 'Import ZIP';

  @override
  String get sourceImportLinkDialogTitle => 'Install Source via Link';

  @override
  String get sourceImportConfigUrlLabel => 'Manifest URL';

  @override
  String get sourceImportConfigUrlHint =>
      'https://example.com/source-manifest.json';

  @override
  String get sourceImportInstallingFromLink => 'Installing source from link...';

  @override
  String get sourceImportInstallingFromZip => 'Importing source from ZIP...';

  @override
  String get sourceImportPreviewTitle => 'Install Source Preview';

  @override
  String get sourceImportPreviewSourceId => 'Source ID';

  @override
  String get sourceImportPreviewVersion => 'Version';

  @override
  String get sourceImportPreviewDisplayName => 'Display name';

  @override
  String get sourceImportPreviewVerified => 'Integrity';

  @override
  String get sourceImportPreviewVerifiedYes => 'Verified';

  @override
  String get sourceImportPreviewVerifiedNo => 'Unverified';

  @override
  String get sourceImportConfirmInstall => 'Install';

  @override
  String get sourceImportManifestInvalid => 'Invalid source manifest format.';

  @override
  String get sourceImportConfigEmpty => 'Downloaded source config is empty.';

  @override
  String get sourceImportZipManifestRequired =>
      'ZIP must contain manifest.json.';

  @override
  String get sourceImportChecksumMismatch =>
      'Source checksum verification failed.';

  @override
  String get sourceImportSourceMismatch =>
      'Source ID mismatch between manifest and config.';

  @override
  String sourceImportInstalledFromLink(String sourceId) {
    return '$sourceId installed from link';
  }

  @override
  String sourceImportInstalledFromZip(String sourceId) {
    return '$sourceId installed from ZIP';
  }

  @override
  String sourceImportFailedFromLink(String error) {
    return 'Failed to install source from link: $error';
  }

  @override
  String sourceImportFailedFromZip(String error) {
    return 'Failed to import ZIP source: $error';
  }

  @override
  String get aboutTitle => 'About';

  @override
  String get appIsUpToDate => 'App is up to date!';

  @override
  String checkFailedMessage(String message) {
    return 'Check failed: $message';
  }

  @override
  String get updatesSection => 'Updates';

  @override
  String get communityAndInfo => 'Community & Info';

  @override
  String get githubRepository => 'GitHub Repository';

  @override
  String get viewSourceCodeContribute => 'View source code & contribute';

  @override
  String get openSourceLicenses => 'Open Source Licenses';

  @override
  String get librariesUsedInApp => 'Libraries used in this app';

  @override
  String get builtWith => 'Built With';

  @override
  String get madeWithLoveBy => 'Made with ❤️ by Shirokun20';

  @override
  String get allRightsReserved => '© 2025 All Rights Reserved';

  @override
  String get appUpdates => 'App Updates';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String get checking => 'Checking...';

  @override
  String get updateAvailable => 'Update Available!';

  @override
  String get upToDate => 'Up to date';

  @override
  String get checkFailed => 'Check failed';

  @override
  String couldNotLaunchUrl(String url) {
    return 'Could not launch $url';
  }

  @override
  String get solveCaptchaTitle => 'Solve CAPTCHA';

  @override
  String get reloadChallenge => 'Reload challenge';

  @override
  String get loginToCrotpedia => 'Login to Crotpedia';

  @override
  String syncedAsUser(String username) {
    return 'Synced as $username';
  }

  @override
  String loggedInAsUser(String username) {
    return 'Logged in as $username';
  }

  @override
  String get logout => 'Logout';

  @override
  String get loginViaSecureBrowser => 'Login via Secure Browser';

  @override
  String get loginIncomplete => 'Login incomplete. Please try again.';

  @override
  String loginFailedError(String error) {
    return 'Login failed: $error';
  }

  @override
  String get doujinListTitle => 'Doujin List (A-Z)';

  @override
  String get errorLoadingDoujinList => 'Error Loading Doujin List';

  @override
  String get noDoujinsFound => 'No Doujins Found';

  @override
  String get doujinListEmpty => 'The doujin list is empty.';

  @override
  String get searchDoujinsHint => 'Search doujins...';

  @override
  String cannotParseSlug(String url) {
    return 'Cannot parse slug from URL: $url';
  }

  @override
  String errorParsingUrl(String url) {
    return 'Error parsing URL: $url';
  }

  @override
  String get checkAll => 'Check All';

  @override
  String get copyPath => 'Copy path';

  @override
  String get createCollection => 'Create collection';

  @override
  String daysAgoShort(Object days) {
    return '${days}d ago';
  }

  @override
  String get deleteCollection => 'Delete collection';

  @override
  String deleteCollectionConfirm(Object name) {
    return 'Delete \"$name\"? Item favorites stay saved, only the collection grouping is removed.';
  }

  @override
  String deleteItems(Object count) {
    return 'Delete $count items?';
  }

  @override
  String deletingItems(Object count) {
    return 'Deleting $count items...';
  }

  @override
  String get doujinList => 'Doujin List';

  @override
  String get downloadGalleryRange => 'Choose gallery range';

  @override
  String get downloadGalleryRangeDesc => 'Uses original gallery page numbers.';

  @override
  String get downloadGalleryWide => 'Gallery-wide range';

  @override
  String get downloadGalleryWideDesc =>
      'Uses original E-Hentai gallery page numbers.';

  @override
  String get downloadThisPart => 'Download this part';

  @override
  String get downloadThisPartDesc => 'Downloads only the selected part.';

  @override
  String get downloadWholeGallery => 'Download whole gallery';

  @override
  String get downloadWholeGalleryDesc => 'Queues every part in gallery order.';

  @override
  String get ehentaiOnly => 'Only available for E-Hentai galleries.';

  @override
  String get ehentaiOnlyDesc =>
      'Gallery download options for whole-series and range are only available on E-Hentai.';

  @override
  String get ehentaiOnlyTitle => 'E-Hentai Only';

  @override
  String get genres => 'Genres';

  @override
  String get genreOptionsFailed => 'Genre options failed';

  @override
  String get gitHubRaw => 'GitHub raw';

  @override
  String get hide => 'Hide';

  @override
  String get liveTags => 'Live tags';

  @override
  String get loadingGenreOptions => 'Loading genre options';

  @override
  String monthsAgo(int months) {
    return '${months}mo ago';
  }

  @override
  String get openInExplorer => 'Open in explorer';

  @override
  String pageFailedDownload(Object page) {
    return 'Page $page failed to download';
  }

  @override
  String pageInputPage(Object page) {
    return 'Page $page';
  }

  @override
  String get pathCopied => 'Path copied to clipboard';

  @override
  String get pathsCopied => 'Paths copied';

  @override
  String get reloadSearchUI => 'Reload search UI';

  @override
  String get reloadingSearchFilters => 'Reloading search filters';

  @override
  String get remoteSource => 'Remote source';

  @override
  String removeOfflineChapters(Object count) {
    return 'Remove $count offline chapters?';
  }

  @override
  String get requestList => 'Request List';

  @override
  String get retryFetch => 'Retry fetch';

  @override
  String get selectMode => 'Select Mode';

  @override
  String get showAvailability => 'Show availability';

  @override
  String showingFirstChapters(Object count) {
    return 'Showing first $count chapters. Go to detail page and use \"View All\" to see more.';
  }

  @override
  String get sortAZ => 'A - Z';

  @override
  String get sortDirectionAZ => 'A - Z';

  @override
  String get sortDirectionZA => 'Z - A';

  @override
  String get sortNewToOld => 'New to Old';

  @override
  String get sortNewest => 'Newest';

  @override
  String get sortOldToNew => 'Old to New';

  @override
  String get sortOldest => 'Oldest';

  @override
  String get sortOptions => 'Sort Options';

  @override
  String get sortPagesAsc => 'Pages (Ascending)';

  @override
  String get sortPagesDesc => 'Pages (Descending)';

  @override
  String get sortZA => 'Z - A';

  @override
  String get specialSeriesDownload => 'Special Series Download';

  @override
  String get starOnGitHub => 'Star on GitHub';

  @override
  String get statusError => 'Error';

  @override
  String get statusIdle => 'Idle';

  @override
  String get statusLoading => 'Loading';

  @override
  String get statusLocal => 'Local';

  @override
  String get today => 'Today';

  @override
  String weeksAgo(int weeks) {
    return '${weeks}w ago';
  }

  @override
  String get yesterday => 'Yesterday';

  @override
  String get noGenreListLoaded =>
      'No remote genre list loaded. Reload to sync from source.';

  @override
  String get genreListTitle => 'Genre List';

  @override
  String get errorLoadingGenres => 'Error Loading Genres';

  @override
  String get noGenresFound => 'No Genres Found';

  @override
  String get noGenresAvailable =>
      'There are no genres available at the moment.';

  @override
  String get projectRequests => 'Project Requests';

  @override
  String get errorLoadingRequests => 'Error Loading Requests';

  @override
  String get noRequestsFound => 'No Requests Found';

  @override
  String get noProjectRequests =>
      'There are no project requests at the moment.';

  @override
  String get manageCollections => 'Manage Collections';

  @override
  String get addToFavoritesFirst => 'Add to favorites first';

  @override
  String get favoriteOffline => 'Favorite Offline';

  @override
  String get favoriteOnline => 'Favorite Online';

  @override
  String get favoriteBoth => 'Favorite Both';

  @override
  String get unsupportedGalleryId =>
      'Unsupported gallery ID for online favorite.';

  @override
  String get addToFavoritesManageCollections =>
      'Add to favorites first to manage collections';

  @override
  String get loginRequiredAction => 'Login required for this action';

  @override
  String get newCollection => 'New collection';

  @override
  String get collectionName => 'Collection name';

  @override
  String failedToCreateCollection(String error) {
    return 'Failed to create collection: $error';
  }

  @override
  String get clearSelection => 'Clear Selection';

  @override
  String get refreshingDownloads => 'Refreshing downloads...';

  @override
  String get refresh => 'Refresh';

  @override
  String failedToSaveCollection(String error) {
    return 'Failed to save collection: $error';
  }

  @override
  String get renameCollection => 'Rename collection';

  @override
  String get pressBackToExit => 'Press back again to exit';

  @override
  String get backToDetail => 'Back to Detail';

  @override
  String get backToPreviousPage => 'Back to previous page';

  @override
  String failedToOpenPdf(String error) {
    return 'Failed to open PDF: $error';
  }

  @override
  String get noChaptersAvailable => 'No chapters available';

  @override
  String failedToApplySearch(String error) {
    return 'Failed to apply search: $error';
  }

  @override
  String get addTag => 'Add tag';

  @override
  String includeCountLabel(int count) {
    return 'Include $count';
  }

  @override
  String excludeCountLabel(int count) {
    return 'Exclude $count';
  }

  @override
  String get searchTagsHint => 'Search tags...';

  @override
  String applyWithCounts(int include, int exclude) {
    return 'Apply ($include / $exclude)';
  }

  @override
  String applyWithCount(int count) {
    return 'Apply ($count)';
  }

  @override
  String get searchByTitleHint => 'Search by title, ID, or keyword...';

  @override
  String get pagesLabel2 => 'Pages';

  @override
  String get favoritesGte => 'Favorites ≥';

  @override
  String get manage => 'Manage';

  @override
  String get local => 'Local';

  @override
  String get rules => 'Rules';

  @override
  String failedToSave(String error) {
    return 'Failed to save: $error';
  }

  @override
  String failedToDelete(String error) {
    return 'Failed to delete: $error';
  }

  @override
  String get searchExampleHint => 'romance, artist:example, 12345';

  @override
  String get refreshOnline => 'Refresh online';

  @override
  String get addRules => 'Add rules';

  @override
  String get pickFromTags => 'From tags';

  @override
  String get done => 'Done';

  @override
  String get uninstallSource => 'Uninstall source';

  @override
  String get uninstallSourceTitle => 'Uninstall Source';

  @override
  String get uninstall => 'Uninstall';

  @override
  String failedToUninstall(String sourceId, String error) {
    return 'Failed to uninstall \"$sourceId\": $error';
  }

  @override
  String get chooseOneSource => 'Install source';

  @override
  String get chooseMultipleSources => 'Install sources';

  @override
  String installSelectedCount(int count) {
    return 'Install Selected ($count)';
  }

  @override
  String get installSelected => 'Install Selected';

  @override
  String get offlineModeLabel => 'Offline Mode';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get aliasesLabel => 'Aliases';

  @override
  String get searchContentWithTag => 'Search Content With This Tag';

  @override
  String get backToFilters => 'Back to Filters';

  @override
  String get dnsSettings => 'DNS Settings';

  @override
  String get resetToDefaults => 'Reset to defaults';

  @override
  String get enableDnsOverHttps => 'Enable DNS-over-HTTPS';

  @override
  String get dnsServerIp => 'DNS Server IP';

  @override
  String get primaryDnsAddress => 'Primary DNS server address';

  @override
  String get dnsOverHttpsUrl => 'DNS-over-HTTPS endpoint URL';

  @override
  String get resetDnsSettings => 'Reset DNS Settings';

  @override
  String get syncRefresh => 'Sync/Refresh';

  @override
  String get importFromBackup => 'Import from Backup';

  @override
  String get importZipFile => 'Import ZIP File';

  @override
  String get exportLibrary => 'Export Library';

  @override
  String get loginRequired => 'Login Required';

  @override
  String get openPdf => 'Open PDF';

  @override
  String get maybeLater => 'Maybe Later';

  @override
  String get noContentAtMoment => 'No content available at the moment.';

  @override
  String get refreshingContentMsg => 'Refreshing content...';

  @override
  String get retryingMsg => 'Retrying...';

  @override
  String get clearingSearchMsg => 'Clearing search...';

  @override
  String failedToClearSearch(String error) {
    return 'Failed to clear search results: $error';
  }

  @override
  String get searchingContentMsg => 'Searching content...';

  @override
  String get noContentMatchingSearch =>
      'No content found matching your search criteria.';

  @override
  String get loadingPopularContent => 'Loading popular content...';

  @override
  String get noPopularContent => 'No popular content available at the moment.';

  @override
  String get loadingContentByTag => 'Loading content by tag...';

  @override
  String get noContentForTag => 'No content found for this tag.';

  @override
  String loadingPageNum(int page) {
    return 'Loading page $page...';
  }

  @override
  String get noContentOnPage => 'No content found on this page.';

  @override
  String get noDownloadableImages => 'This content has no downloadable images.';

  @override
  String failedToStartDownload(String error) {
    return 'Failed to start download: $error';
  }

  @override
  String get bulkDeleteCompleted => 'Bulk Delete Completed';

  @override
  String get bulkDeletePartial => 'Bulk Delete Partial';

  @override
  String get failedToInitSearch => 'Failed to initialize search';

  @override
  String get searchingMsg => 'Searching...';

  @override
  String noResultsForQuery(String query) {
    return 'No results for \"$query\"';
  }

  @override
  String get searchingWithFiltersMsg => 'Searching with filters...';

  @override
  String get noResultsWithFilters => 'No results found with current filters';

  @override
  String invalidFilterErrors(String errors) {
    return 'Invalid filter: $errors';
  }

  @override
  String get noResultsGeneric => 'No Results Found';

  @override
  String get loadingConfigMsg => 'Loading configuration...';

  @override
  String get initTagsDbMsg => 'Initializing tags database...';

  @override
  String downloadingTagsMsg(String source) {
    return 'Downloading tags for $source...';
  }

  @override
  String initFailedMsg(String error) {
    return 'Initialization failed: $error';
  }

  @override
  String get initBypassMsg => 'Initializing bypass system...';

  @override
  String get connectingToSite => 'Connecting to nhentai.net...';

  @override
  String get connectedSuccess => 'Successfully connected to nhentai.net';

  @override
  String get failedToConnect =>
      'Failed to connect to nhentai.net. Please try again.';

  @override
  String failedInitBypass(String error) {
    return 'Failed to initialize bypass system: $error';
  }

  @override
  String get bypassFailed => 'Bypass verification failed. Please try again.';

  @override
  String get offlineBypassFailed => 'Offline Mode (Bypass Failed)';

  @override
  String errorBypassResult(String error) {
    return 'Error processing bypass result: $error';
  }

  @override
  String get readyOfflineLimited => 'Ready (Offline Mode - Limited)';

  @override
  String get downloadingInitConfig => 'Downloading initial configuration...';

  @override
  String get readyOffline => 'Ready (Offline Mode)';

  @override
  String get connectingMsg => 'Connecting...';

  @override
  String failedLoadOffline(String error) {
    return 'Failed to load offline content: $error';
  }

  @override
  String get noInternetCheckOffline =>
      'No internet connection. Checking offline content...';

  @override
  String foundOfflineItems(int count) {
    return 'Found $count offline items. Continuing...';
  }

  @override
  String get noInternetNoOffline =>
      'No internet connection and no offline content available.';

  @override
  String unableCheckOffline(String error) {
    return 'Unable to check offline content. $error';
  }

  @override
  String get offlineLimitedFeatures => 'Offline Mode (Limited Features)';

  @override
  String get readyOfflineLimitedFeatures =>
      'Ready (Offline Mode - Limited Features)';

  @override
  String failedEnableOffline(String error) {
    return 'Failed to enable offline mode: $error';
  }

  @override
  String failedCheckOffline(String error) {
    return 'Failed to check offline content: $error';
  }

  @override
  String failedOpenChapter(String message) {
    return 'Failed to open chapter: $message';
  }

  @override
  String externalChapterBadge(String host) {
    return 'External • $host';
  }

  @override
  String get externalChapterHint =>
      'All chapters are available on the official site';

  @override
  String get externalChapterOpenFailed => 'Cannot open external link';

  @override
  String get externalChapterDownloadBlocked =>
      'External chapters cannot be downloaded, open in browser';

  @override
  String failedInitFilterData(String error) {
    return 'Failed to initialize filter data: $error';
  }

  @override
  String failedSwitchFilterType(String error) {
    return 'Failed to switch filter type: $error';
  }

  @override
  String get failedMonitorNetwork => 'Failed to monitor network connectivity';

  @override
  String failedInitNetwork(String error) {
    return 'Failed to initialize network monitoring: $error';
  }

  @override
  String failedUpdateConnection(String error) {
    return 'Failed to update connection status: $error';
  }

  @override
  String failedCheckConnectivity(String error) {
    return 'Failed to check connectivity: $error';
  }

  @override
  String failedSearchOffline(String error) {
    return 'Failed to search offline content: $error';
  }

  @override
  String get failedLoadOfflineContent => 'Failed to load offline content';

  @override
  String failedScanBackup(String error) {
    return 'Failed to scan backup folder: $error';
  }

  @override
  String failedLoadContentError(String error) {
    return 'Failed to load content: $error';
  }

  @override
  String get chapterNavNotAvailable => 'Chapter navigation not available';

  @override
  String get unknownChapter => 'Unknown Chapter';

  @override
  String get failedLoadChapterImages => 'Failed to load chapter images';

  @override
  String failedLoadChapter(String error) {
    return 'Failed to load chapter: $error';
  }

  @override
  String importFailedError(String error) {
    return 'Import failed: $error';
  }

  @override
  String errorImportingZip(String error) {
    return 'Error importing ZIP: $error';
  }

  @override
  String get error => 'Error';

  @override
  String get lightThemeDesc => 'Light theme with bright colors';

  @override
  String get darkThemeDesc => 'Dark theme with muted colors';

  @override
  String get amoledThemeDesc => 'Pure black theme for AMOLED displays';

  @override
  String get systemThemeDesc => 'Follow system theme settings';

  @override
  String nItems(int count) {
    return '$count items';
  }

  @override
  String nPages(int count) {
    return '$count pages';
  }

  @override
  String nGalleries(int count) {
    return '$count galleries';
  }

  @override
  String sourceUninstalled(String sourceId) {
    return 'Source \"$sourceId\" uninstalled.';
  }

  @override
  String selectedSourcesCount(int count) {
    return 'Selected sources: $count';
  }

  @override
  String timeoutMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get dohUrlOptional => 'DoH URL (Optional)';

  @override
  String get dnsEncryptedDescription =>
      'Use encrypted DNS for enhanced privacy and bypass censorship';

  @override
  String get usingSystemDns => 'Using system default DNS resolver';

  @override
  String get dnsProvider => 'DNS Provider';

  @override
  String get customConfiguration => 'Custom Configuration';

  @override
  String get aboutDoh => 'About DNS-over-HTTPS';

  @override
  String get dohDescription =>
      'DNS-over-HTTPS encrypts DNS queries to prevent monitoring and bypass censorship.';

  @override
  String get dnsQueriesEncrypted => 'All DNS queries encrypted via HTTPS';

  @override
  String get enhancedPrivacy => 'Enhanced privacy and security';

  @override
  String get resetDnsConfirmation =>
      'This will reset DNS settings to system defaults. Continue?';

  @override
  String get appDns => 'App DNS';

  @override
  String get devicePrivateDns => 'Private DNS';

  @override
  String get dnsModeOn => 'ON';

  @override
  String get dnsModeOff => 'OFF';

  @override
  String get dnsSystemDns => 'System DNS';

  @override
  String dnsPrivateDnsStrict(Object hostname) {
    return 'Strict ($hostname)';
  }

  @override
  String get dnsPrivateDnsOpportunistic => 'Opportunistic';

  @override
  String get dnsPrivateDnsRequirements => 'Requires Android 10+';

  @override
  String get dnsPrivateDnsOff => 'Off';

  @override
  String get dnsPrivateDnsGuidance =>
      'Enable Private DNS in Android settings to encrypt all DNS queries on your device.';

  @override
  String get dnsPrivateDnsRequiresAndroid10 =>
      'Device Private DNS status requires Android 10+.';

  @override
  String get dnsPrivateDnsCannotAutoSet =>
      'Kuron cannot set device-wide Private DNS automatically on standard installs.';

  @override
  String get openDnsSettings => 'Open DNS Settings';

  @override
  String get collections => 'Collections';

  @override
  String get collectionsUpdatedSuccessfully =>
      'Collections updated successfully';

  @override
  String get blacklistMatchWarning =>
      'This gallery matches blacklist rules. Cover/cards can be blurred in list views.';

  @override
  String get chapterCompleted => 'Chapter completed';

  @override
  String continueFromPage(int page) {
    return 'Continue from page $page';
  }

  @override
  String get loginRequiredForContent =>
      'You need to log in to Crotpedia to view this content.';

  @override
  String commentsCount(int count) {
    return 'Comments ($count)';
  }

  @override
  String get postComment => 'Post Comment';

  @override
  String get commentInputHint =>
      'Write a comment. Markdown supported. 10-1000 characters.';

  @override
  String get commentPosted => 'Comment posted';

  @override
  String get commentLengthRequirement => 'Comment must be 10-1000 characters.';

  @override
  String get noCommentsYet => 'No comments yet';

  @override
  String get failedToLoadComments => 'Failed to load comments';

  @override
  String nSelected(int count) {
    return '$count selected';
  }

  @override
  String get bulkDelete => 'Bulk Delete';

  @override
  String bulkDeleteConfirmation(int count) {
    return 'Are you sure you want to delete $count downloads?';
  }

  @override
  String exportedFavoritesTo(int count, String path) {
    return 'Exported favorites only ($count items) to:\n$path';
  }

  @override
  String get failedToSaveExportFile => 'Failed to save export file';

  @override
  String get importFavorites => 'Import Favorites';

  @override
  String importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get noOnlineFavoritesSource => 'No online favorites source available.';

  @override
  String collectionWithCount(String name, int count) {
    return '$name ($count)';
  }

  @override
  String get newLabel => 'New';

  @override
  String get tryDifferentSearchTerm => 'Try a different search term';

  @override
  String get apply => 'Apply';

  @override
  String nItemsInHistory(int count) {
    return '$count items in history';
  }

  @override
  String pageProgress(int lastPage, int totalPages) {
    return '$lastPage/$totalPages pages';
  }

  @override
  String get chapterComplete => 'Chapter Complete!';

  @override
  String get finishedReading => 'Finished Reading';

  @override
  String get chapterLabel => 'Chapter';

  @override
  String get noChapterSelected => 'No chapter selected';

  @override
  String get preventScreenOff =>
      'Prevent screen from turning off while reading';

  @override
  String get chapters => 'Chapters';

  @override
  String get readerSettingsReset =>
      'Reader settings have been reset to defaults.';

  @override
  String get tagInputTip =>
      'Tip: press Enter or the + button to add a tag. You can type multiple tags using commas or new lines.';

  @override
  String get loadingOptions => 'Loading options...';

  @override
  String get filterTags => 'Filter Tags';

  @override
  String get noOptionsAvailable => 'No options available for this field';

  @override
  String get failedLoadingOptions =>
      'Failed loading options. Check connection and try again.';

  @override
  String get noTagsFound => 'No tags found';

  @override
  String get previewQuery => 'Preview Query (q)';

  @override
  String get showLess => 'Show Less';

  @override
  String showAllCount(int count) {
    return 'Show All ($count)';
  }

  @override
  String get advancedFilters => 'Advanced Filters';

  @override
  String get min => 'Min';

  @override
  String get max => 'Max';

  @override
  String searchConfigUnavailable(String sourceId) {
    return 'Search configuration unavailable for $sourceId';
  }

  @override
  String get checkInternetOrReload =>
      'Please check your internet connection or try reloading the application.';

  @override
  String get tagBlacklist => 'Tag blacklist';

  @override
  String get blacklistDescription =>
      'Nhentai-only feature. Local entries work offline for nhentai, and logged-in nhentai accounts also pull online blacklist IDs. Other sources are not affected.';

  @override
  String onlineRuleDetailsCount(int count) {
    return 'Online rule details ($count)';
  }

  @override
  String get noBlacklistRulesYet =>
      'No blacklist rules yet. Add tag names like romance, artist:foo, or numeric tag IDs.';

  @override
  String activeCoverageDescription(int count) {
    return 'Active coverage is enabled for $count tokens (local + online IDs). Hidden here to keep this view human-readable.';
  }

  @override
  String get manageTagBlacklist => 'Manage tag blacklist';

  @override
  String get addTagRulesDescription =>
      'Add tag names, typed rules like artist:foo, or numeric tag IDs. Separate multiple values with commas or new lines.';

  @override
  String localRulesCount(int count) {
    return 'Local rules ($count)';
  }

  @override
  String onlineRulesMetadataCount(int count) {
    return 'Online rules metadata ($count)';
  }

  @override
  String get onlineRulesMetadata => 'Online rules metadata';

  @override
  String activeCoverageCount(int count) {
    return 'Active coverage ($count)';
  }

  @override
  String nSourcesInstalled(int count) {
    return '$count source(s) installed';
  }

  @override
  String removeSourceConfirmation(String sourceId) {
    return 'Remove \"$sourceId\" from local installed sources?';
  }

  @override
  String installedSourcesFromZip(int count) {
    return 'Installed $count sources from ZIP';
  }

  @override
  String get enhancedReadingExperience => 'Enhanced Reading Experience';

  @override
  String get initializingApplication => 'Initializing Application...';

  @override
  String get offlineContentAvailableLabel => 'Offline Content Available';

  @override
  String get offlineModeEnabled => 'Offline Mode Enabled';

  @override
  String get confirmExit => 'Are you sure you want to exit?';

  @override
  String get resize => 'Resize';

  @override
  String get offlineFeaturesLimited =>
      'Some features are limited. Connect to internet for full access.';

  @override
  String get downloadSettings => 'Download Settings';

  @override
  String get higherValuesBandwidth =>
      'Higher values may consume more bandwidth and device resources';

  @override
  String get autoRetryFailed => 'Auto Retry Failed Downloads';

  @override
  String get wifiOnlyDownload => 'Only download when connected to WiFi';

  @override
  String get downloadTimeout => 'Download Timeout';

  @override
  String get enableNotifications => 'Enable Notifications';

  @override
  String get showNotificationsProgress =>
      'Show notifications for download progress';

  @override
  String get failedToLoadImage => 'Failed to load image';

  @override
  String get retrying => 'Retrying...';

  @override
  String get readerRedownloadImage => 'Redownload page';

  @override
  String get readerRepairingImage => 'Repairing image...';

  @override
  String readerPageNotDownloaded(int pageNumber) {
    return 'Page $pageNumber not downloaded';
  }

  @override
  String get readerPageSkippedDuringDownload =>
      'This page was skipped during download (timeout or error). Tap below to download it now.';

  @override
  String get readerPageDownloadSuccess => 'Downloaded successfully';

  @override
  String get readerOpenSourcePage => 'Open source page';

  @override
  String get readerOpeningSourcePage => 'Opening source page...';

  @override
  String readerImageRepairSuccess(int pageNumber) {
    return 'Page $pageNumber was redownloaded successfully.';
  }

  @override
  String readerImageRepairHttpStatus(int pageNumber, int statusCode) {
    return 'Could not redownload page $pageNumber. Server returned HTTP $statusCode.';
  }

  @override
  String readerImageRepairInvalidImage(int pageNumber) {
    return 'Could not redownload page $pageNumber because the response was not a valid image.';
  }

  @override
  String readerImageRepairUnavailable(int pageNumber) {
    return 'Page $pageNumber could not be redownloaded from the source.';
  }

  @override
  String readerImageRepairFailed(int pageNumber) {
    return 'Failed to redownload page $pageNumber.';
  }

  @override
  String pageAttempt(int pageNumber, int current, int max) {
    return 'Page $pageNumber • Attempt $current/$max';
  }

  @override
  String downloadingNItems(int count) {
    return 'Downloading $count items';
  }

  @override
  String get noOfflineContent => 'No offline content';

  @override
  String get howToGetStarted => 'How to get started';

  @override
  String get loadingMore => 'Loading more...';

  @override
  String get noImagesFound => 'No images found';

  @override
  String get dontAskAgain => 'Don\'t ask again';

  @override
  String pageOfTotal(int current, int total) {
    return 'Page $current of $total';
  }

  @override
  String loadingPageNumber(int pageNumber) {
    return 'Loading page $pageNumber...';
  }

  @override
  String get recentSearches => 'Recent Searches';

  @override
  String get pageCountRange => 'Page Count Range';

  @override
  String nMoreFilters(int count) {
    return '+$count more';
  }

  @override
  String get newUpdateAvailable => 'New Update Available!';

  @override
  String get newVersion => 'New Version: ';

  @override
  String get whatsNew => 'What\'s New';

  @override
  String get downloadUpdate => 'Download Update';

  @override
  String exportPath(String path) {
    return 'Path: $path';
  }

  @override
  String importedContentWithImages(String contentId, int count) {
    return 'Imported \"$contentId\" with $count images to local folder';
  }

  @override
  String failedToLoadCaptcha(String error) {
    return 'Failed to load CAPTCHA: $error';
  }

  @override
  String get turnstileRejected =>
      'Cloudflare Turnstile rejected the challenge (110200). Please retry or use manual token input.';

  @override
  String get openingNativeCaptcha => 'Opening native CAPTCHA solver...';

  @override
  String get tapRefreshToRetry =>
      'Tap refresh to retry native CAPTCHA challenge.';

  @override
  String get loginToCrotpediaDescription =>
      'Login to Crotpedia using the native secure browser to access bookmarks and more.';

  @override
  String get crotpediaBookmarkLoginPrompt =>
      'This feature (Bookmarking) requires you to be logged in to Crotpedia.\n\nWould you like to login now?';

  @override
  String get browseByGenre => 'Browse by Genre';

  @override
  String nMoreGenres(int count) {
    return '+$count more';
  }

  @override
  String get selectSourceFromManifest => 'From Manifest';

  @override
  String pagesWithSize(int pageCount, String size) {
    return '$pageCount pages • $size';
  }

  @override
  String get browseComics => '1. Browse comics you like';

  @override
  String get tapDownloadButton => '2. Tap the download button';

  @override
  String get accessOffline => '3. Access them here anytime, even offline!';

  @override
  String get source => 'Source';

  @override
  String nPagesText(int count) {
    return '$count pages';
  }

  @override
  String checkItOut(String url) {
    return 'Check it out: $url';
  }

  @override
  String get filteredResults => 'Filtered Results';

  @override
  String get filter => 'Filter';

  @override
  String crotpediaMaintenance(String reason) {
    return 'Crotpedia maintenance: $reason';
  }

  @override
  String get tapToChangeFilters => 'Tap to change search filters';

  @override
  String get prevChapter => 'Prev Chapter';

  @override
  String get nextChapter => 'Next Chapter';

  @override
  String pageOfContent(int current, int total) {
    return 'Page $current of $total';
  }

  @override
  String nChapters(int count) {
    return '$count chapters';
  }

  @override
  String get failedToLoadOptionsTap => 'Failed to load options. Tap to retry.';

  @override
  String chooseField(String field) {
    return '$field';
  }

  @override
  String get tapToLoadOptions => 'Tap to load options';

  @override
  String nSelectedItems(int count) {
    return '$count selected';
  }

  @override
  String get tapToChooseTags => 'Tap to choose included/excluded tags';

  @override
  String includeExcludeCount(int include, int exclude) {
    return 'Include $include • Exclude $exclude';
  }

  @override
  String get searchLabel => 'Search';

  @override
  String get genreLabel => 'Genre';

  @override
  String get statusLabel => 'Status';

  @override
  String get orderBy => 'Order by';

  @override
  String get authorLabel => 'Author';

  @override
  String get artistFilterLabel => 'Artist';

  @override
  String get artists => 'Artists';

  @override
  String get characters => 'Characters';

  @override
  String get parodies => 'Parodies';

  @override
  String get groups => 'Groups';

  @override
  String get filterCategories => 'FILTER CATEGORIES';

  @override
  String get dateUploaded => 'DATE UPLOADED';

  @override
  String get numericFilters => 'NUMERIC FILTERS';

  @override
  String get older => 'Older';

  @override
  String get contentFilters => 'CONTENT FILTERS';

  @override
  String get blurCoversDescription =>
      'Blur covers that match your local tag rules, even when browsing offline. If you are logged into nhentai, online blacklist IDs are merged automatically.';

  @override
  String get developerTools => 'DEVELOPER TOOLS';

  @override
  String get noOnlineRulesYet =>
      'No online detailed rules returned yet. Pull refresh to fetch /blacklist data.';

  @override
  String get nothingSavedLocally =>
      'Nothing saved locally yet. Local rules are always applied, including offline results.';

  @override
  String get loginRequiredForRules =>
      'Login required to fetch detailed rule metadata from /blacklist.';

  @override
  String get syncingOnlineRules => 'Syncing online rule details...';

  @override
  String get noOnlineRuleDetails =>
      'No online rule details returned yet. Tap refresh to fetch /blacklist.';

  @override
  String get blacklistGalleriesInfo =>
      'Blacklisted galleries will be blurred here once you add local rules or sync online IDs.';

  @override
  String coverageActiveDescription(int count) {
    return 'Coverage is active for $count tokens. ID tokens are hidden here by request; only named online rules are shown above.';
  }

  @override
  String get availableSources => 'AVAILABLE SOURCES';

  @override
  String get settingUpConnection =>
      'Setting up components and checking connection...';

  @override
  String get tagId => 'Tag ID';

  @override
  String get slug => 'Slug';

  @override
  String get path => 'Path';

  @override
  String get tag => 'Tag';

  @override
  String profileWithName(String name) {
    return 'Profile ($name)';
  }

  @override
  String get profile => 'Profile';

  @override
  String get loginAccount => 'Login / Account';

  @override
  String accountWithName(String name) {
    return 'Account ($name)';
  }

  @override
  String get performance => 'Performance';

  @override
  String get autoRetry => 'Auto Retry';

  @override
  String get network => 'Network';

  @override
  String get notifications => 'Notifications';

  @override
  String get estimatingProgress => 'Estimating progress...';

  @override
  String get processingBadAvifToWebp =>
      'Processing conversion from bad AVIF to WebP...';

  @override
  String get downloadingImageData => 'Downloading image data...';

  @override
  String get hideFilters => 'Hide filters';

  @override
  String get showMoreFilters => 'Show more filters';

  @override
  String get preparingExport => 'Preparing export...';

  @override
  String get readingFavorites => 'Reading favorites from database...';

  @override
  String get encodingFavorites => 'Encoding favorites data...';

  @override
  String get writingExportFile => 'Writing export file...';

  @override
  String get finalizingExport => 'Finalizing export...';

  @override
  String get readerContinuousDisabledHeavyImage =>
      'Continuous Scroll disabled: heavy animated image detected. Use Horizontal/Vertical mode.';

  @override
  String get readerContinuousOffHeavyImage => 'Continuous off (heavy image)';

  @override
  String get chapterCurrentBadge => 'NOW';

  @override
  String readerDaysAgoShort(int count) {
    return '${count}d ago';
  }

  @override
  String readerWeeksAgoShort(int count) {
    return '${count}w ago';
  }

  @override
  String readerMonthsAgoShort(int count) {
    return '${count}mo ago';
  }

  @override
  String get readerTapDirectionLabel => 'Tap Direction';

  @override
  String get readerTapDirectionNormal => 'Normal';

  @override
  String get readerTapDirectionInverted => 'Reverse';

  @override
  String get readerTapDirectionNormalDescription =>
      'Tap right to go to the next page';

  @override
  String get readerTapDirectionInvertedDescription =>
      'Tap left to go to the next page';

  @override
  String get readerClearImageCache => 'Clear Image Cache';

  @override
  String get readerImageCacheCleared =>
      'Image cache cleared. Scroll to reload pages.';

  @override
  String get readerOpenInGallery => 'Open in gallery';

  @override
  String get readerPinchToZoom => 'Pinch to zoom';

  @override
  String get captchaCancelled => 'CAPTCHA challenge was cancelled or failed.';

  @override
  String failedToOpenCaptcha(String error) {
    return 'Failed to open native CAPTCHA solver: $error';
  }

  @override
  String get readFirstChapter => 'Read First Chapter';

  @override
  String get convertAllToPdf => 'Convert All to PDF';

  @override
  String deleteSeriesConfirmation(int count, String title) {
    return 'Are you sure you want to delete $count chapters of \"$title\"?';
  }

  @override
  String deleteSeriesWithCount(int count) {
    return 'Delete Series ($count)';
  }

  @override
  String get readerScreenSupporter => 'Support Developer';

  @override
  String get readerScreenSupporterDesc =>
      'If you like this app, consider supporting its development.';

  @override
  String get readerScreenThanks => 'Thank You for Reading!';

  @override
  String get readerScreenThanksDesc =>
      'Hope you enjoyed this chapter. See you in the next one!';

  @override
  String get readerScreenGoToFirstPage => 'Go to First Page';

  @override
  String get appLockSectionTitle => 'APP LOCK';

  @override
  String get pinLock => 'PIN Lock';

  @override
  String get pinLockActive => 'PIN is set and active';

  @override
  String get pinLockSet => 'Set a PIN to lock the app';

  @override
  String get changePin => 'Change PIN';

  @override
  String get changePinDescription => 'Set a new PIN';

  @override
  String get biometricUnlock => 'Biometric Unlock';

  @override
  String get biometricAvailable => 'Use fingerprint or face to unlock';

  @override
  String get biometricUnavailable => 'Biometric not available on this device';

  @override
  String get enterPin => 'Enter PIN';

  @override
  String get enterCurrentPin => 'Enter Current PIN';

  @override
  String get enterCurrentPinSubtitle => 'Verify your identity first';

  @override
  String get enterNewPin => 'Enter New PIN';

  @override
  String enterNewPinSubtitle(int maxDigits) {
    return 'Choose a $maxDigits-digit PIN';
  }

  @override
  String get confirmNewPin => 'Confirm New PIN';

  @override
  String get confirmNewPinSubtitle => 'Enter the PIN again';

  @override
  String get setupPin => 'Set Up PIN';

  @override
  String setupPinSubtitle(int maxDigits) {
    return 'Choose a $maxDigits-digit PIN';
  }

  @override
  String get confirmPin => 'Confirm PIN';

  @override
  String get confirmPinSubtitle => 'Enter the PIN again to confirm';

  @override
  String get wrongPin => 'Wrong PIN';

  @override
  String get pinsDoNotMatch => 'PINs do not match';

  @override
  String get pinChangedSuccess => 'PIN changed successfully';

  @override
  String get failedToSavePin => 'Failed to save PIN. Try again.';

  @override
  String get failedToChangePin => 'Failed to change PIN. Try again.';

  @override
  String get disablePinLock => 'Disable PIN Lock?';

  @override
  String get disablePinLockDescription =>
      'To disable PIN lock, please enter your current PIN.';

  @override
  String get enterPinToDisable => 'Enter PIN to Disable';

  @override
  String get enterPinToDisableSubtitle =>
      'This will remove PIN and disable lock';

  @override
  String get unlockKuron => 'Unlock Kuron to continue';

  @override
  String get continue_ => 'Continue';

  @override
  String get aiTranslate => 'AI Translate';

  @override
  String get aiTutorialHint => 'Tap anywhere to close';

  @override
  String get aiTutorialTranslateTitle => '✨ Translate page';

  @override
  String get aiTutorialTranslateDesc =>
      'Auto bubble detection -> translation overlaid on original text. Tap again to toggle.';

  @override
  String get aiTutorialDrawTitle => '✏️ Draw bubbles';

  @override
  String get aiTutorialDrawDesc =>
      'Manual correction. Drag to add bubble (red), 🛰 Detect to see ONNX one (blue). Done locks but bubbles stay visible.';

  @override
  String get aiTutorialClearTitle => '🗑 Clear';

  @override
  String get aiTutorialClearDesc =>
      'Remove translation result + all reference bubbles.';

  @override
  String get aiTutorialGotIt => 'Got it!';

  @override
  String get aiNotAvailableCS =>
      'AI translate tidak tersedia di continue scroll.';

  @override
  String get aiHideTranslation => 'Hide translation';

  @override
  String get aiTranslating => 'Translating...';

  @override
  String get aiDetecting => 'Detecting bubbles...';

  @override
  String get aiTranslatePage => 'Translate page';

  @override
  String get aiClearTranslateBubbles => 'Clear translate + bubbles';

  @override
  String get aiExitDrawMode => 'Exit draw mode';

  @override
  String get aiDrawBubbles => 'Draw bubbles';

  @override
  String get aiDrawRect => 'Rectangle';

  @override
  String get aiDrawEllipse => 'Ellipse';

  @override
  String get aiDrawFreeform => 'Freeform';

  @override
  String get aiExpandDraw => 'Show actions';

  @override
  String get aiCollapseDraw => 'Hide actions';

  @override
  String get aiDrawDetect => 'Detect bubbles';

  @override
  String get aiDrawUndo => 'Undo';

  @override
  String get aiDrawClear => 'Clear';

  @override
  String get aiSkipSfxOn => 'Skip SFX: ON';

  @override
  String get aiSkipSfxOff => 'Skip SFX: OFF';

  @override
  String get moreActions => 'More actions';

  @override
  String get aiEditTranslation => 'Edit Translation';

  @override
  String get aiTranslation => 'Translation';

  @override
  String get aiSave => 'Save';

  @override
  String get aiSaveToGlossaryHint => 'Save to learning glossary';

  @override
  String get aiSaveToGlossary => 'Save to Glossary';

  @override
  String get aiSavedToGlossary => 'Saved to Glossary';

  @override
  String aiTranslateFailed(Object error) {
    return 'Translate gagal: $error';
  }

  @override
  String get aiNeedVisionProvider =>
      'AI translate needs a vision provider. Set it up in Settings → AI Translation.';

  @override
  String aiRateLimited(Object fallback) {
    return 'Rate limited. $fallback';
  }

  @override
  String aiUsingFallback(Object name) {
    return 'Using $name as fallback.';
  }

  @override
  String aiWaitCooldown(Object seconds) {
    return 'Wait ${seconds}s.';
  }

  @override
  String get aiGagalFetch =>
      'Failed to load the page image. Try again or check your connection.';

  @override
  String get aiCapturingViewport => 'Capturing the screen... please wait.';

  @override
  String get aiGagalCapture => 'Failed to capture the screen. Try again.';

  @override
  String get aiCapturedViewport => 'Screen captured.';

  @override
  String get aiSettings => 'AI Settings';

  @override
  String get aiProvidersSubtitle =>
      'Providers, language, style, translation cache';

  @override
  String get aiManageProviders => 'AI Providers';

  @override
  String get aiOpen => 'Open';

  @override
  String get aiTargetLanguage => 'Target Language';

  @override
  String get aiTargetLangSubtitle => 'Language AI translates into';

  @override
  String get aiTranslationStyle => 'Translation Style';

  @override
  String get aiSkipSfx => 'Skip SFX bubbles';

  @override
  String get aiSkipSfxSubtitle => 'Skip sound-effect-only bubbles (default on)';

  @override
  String get aiMosaicQuality => 'Mosaic quality';

  @override
  String get aiMosaicQualitySubtitle =>
      'Low saves tokens (JPEG 75, 1 MB); High preserves detail (JPEG 85, 2 MB)';

  @override
  String get aiSwitchModel => 'Switch model';

  @override
  String aiModelSwitched(Object name) {
    return 'Model switched to $name';
  }

  @override
  String get aiPrivacyDisclosure => 'Privacy Disclosure';

  @override
  String get aiPrivacyDesc =>
      'Images are sent to your chosen provider. Kuron does not relay your data.';

  @override
  String get aiClearCache => 'Clear Translation Cache';

  @override
  String get aiClearCacheSubtitle => 'Delete all cached page translations';

  @override
  String get aiGlossary => 'Learning Glossary';

  @override
  String get aiGlossarySubtitle => 'Review saved vocabulary';

  @override
  String get aiAddProvider => 'Add Provider';

  @override
  String get aiEditProvider => 'Edit Provider';

  @override
  String get aiProviderType => 'Type';

  @override
  String get aiDisplayName => 'Display Name';

  @override
  String get aiApiKey => 'API Key';

  @override
  String get aiApiKeyHint => 'Leave empty for no-key free models';

  @override
  String get aiModel => 'Model';

  @override
  String get aiBaseUrl => 'Base URL';

  @override
  String get aiTestKey => 'Test Key';

  @override
  String get aiTesting => 'Testing...';

  @override
  String get aiDelete => 'Delete';

  @override
  String get aiValidKey => '✓ Valid key';

  @override
  String aiCheckIconD(Object model) {
    return '✓ Valid key — model $model OK';
  }

  @override
  String get aiCustomTypeDefault => 'user must supply';

  @override
  String get aiModeKasarTitle => 'Kasar Mode (18+)';

  @override
  String get aiModeKasarConfirm => 'Kasar mode uses strong language. Continue?';

  @override
  String get aiEnable => 'Enable';

  @override
  String get aiCancel => 'Cancel';

  @override
  String aiModelNotVision(Object model) {
    return 'Model \"$model\" does not support image translation (text-only/free). Choose a vision model (e.g. kimi-k2.6, gemini-2.5-flash, gpt-4o-mini) in Settings → AI Translation.';
  }

  @override
  String aiNoVisionProvider(Object model) {
    return 'Model \"$model\" is text-only/free — choose a vision model in Settings → AI Translation (e.g. kimi-k2.6).';
  }

  @override
  String get aiGlossaryEmpty =>
      'No glossary entries yet.\\nLong-press a translated bubble to save one.';

  @override
  String aiDefaultModel(Object model) {
    return 'Default: $model';
  }

  @override
  String get aiLoadModels => 'Load models';

  @override
  String get aiReload => 'Reload';

  @override
  String get aiManualEntry => 'Manual entry';

  @override
  String get aiUseLov => 'Use list';

  @override
  String get aiEnterApiKeyFirst => 'Enter API key first';

  @override
  String get aiAll => 'All';

  @override
  String get aiVision => 'Vision';

  @override
  String get aiTextOnly => 'Text only';

  @override
  String get aiSearchModels => 'Search models';

  @override
  String get aiSelectModel => 'Select model';

  @override
  String aiStaleModel(Object model) {
    return 'Saved model \"$model\" not in current list';
  }

  @override
  String get aiModelHint =>
      'Pick a model from the live list, or use manual entry';

  @override
  String get aiClearCacheCleared => 'Translation cache cleared';

  @override
  String get aiPrivacyDialogDesc =>
      'Page images you translate are sent to the provider you choose using your own key. No data passes through Kuron\'s servers.';

  @override
  String get aiPrivacyAgree => 'Agree & Translate';

  @override
  String get aiNoKeyNeeded => 'No key needed';

  @override
  String get glossaryPage => 'page';

  @override
  String get nclientImport => 'Import from NClient';

  @override
  String get nclientImportSubtitle =>
      'Favorites, collections, history and reading positions from an NClient V2/V3 backup';

  @override
  String get nclientImportAction => 'Import';

  @override
  String get nclientPreview => 'Import preview';

  @override
  String get nclientResult => 'Import result';

  @override
  String get nclientPositions => 'Reading positions';

  @override
  String get nclientMemberships => 'Collection items';

  @override
  String get nclientMalformedRows => 'Unreadable rows';

  @override
  String get kuronBackupNow => 'Back up library & settings';

  @override
  String get kuronBackupNowSubtitle =>
      'Creates a KuronBackup ZIP with favorites, collections, history, reading positions and settings (no images)';

  @override
  String get kuronBackupNowAction => 'Back up';

  @override
  String kuronBackupReady(String path) {
    return 'Backup saved: $path';
  }

  @override
  String kuronBackupFailed(String error) {
    return 'Backup failed: $error';
  }

  @override
  String get kuronRestore => 'Restore backup';

  @override
  String get kuronRestoreSubtitle =>
      'Restore a KuronBackup ZIP. Existing data is never overwritten';

  @override
  String get kuronRestoreAction => 'Restore';

  @override
  String get kuronRestorePreview => 'Restore preview';

  @override
  String get kuronRestoreResult => 'Restore result';

  @override
  String kuronBackupIncompatible(String version) {
    return 'This backup was made by a newer Kuron version (format $version) and cannot be restored here';
  }

  @override
  String nclientSummaryRow(String label, int success, int skipped, int failed) {
    return '$label: $success added, $skipped skipped, $failed failed';
  }
}
