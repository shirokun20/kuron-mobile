// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Kuron';

  @override
  String sourceAuthProfileTitle(String sourceId) {
    return '个人资料 $sourceId';
  }

  @override
  String sourceAuthLoginTitle(String sourceId) {
    return '登录 $sourceId';
  }

  @override
  String get sourceAuthConnectedAccount => '已连接账号';

  @override
  String get sourceAuthSecureLogin => '安全登录';

  @override
  String get sourceAuthConnectedDescription => '您的账号已连接并可使用。';

  @override
  String get sourceAuthLoginDescription => '登录以同步您的个性化收藏。';

  @override
  String get sourceAuthUser => '用户';

  @override
  String get sourceAuthSlug => '标识';

  @override
  String get sourceAuthAuthenticated => '已认证';

  @override
  String get sourceAuthRefreshProfile => '刷新资料';

  @override
  String get sourceAuthLogout => '退出登录';

  @override
  String get sourceAuthUsername => '用户名';

  @override
  String get sourceAuthPassword => '密码';

  @override
  String get sourceAuthCaptchaVerified => 'CAPTCHA 已验证并安全保存';

  @override
  String get sourceAuthCaptchaRequired => '完成 CAPTCHA 以继续';

  @override
  String get sourceAuthCaptchaSolved => 'CAPTCHA 已完成';

  @override
  String get sourceAuthSolveCaptcha => '完成 CAPTCHA';

  @override
  String get sourceAuthLoginButton => '登录';

  @override
  String get sourceAuthLoginSuccess => '登录成功';

  @override
  String get sourceAuthSigningInSecurely => '正在安全登录';

  @override
  String get sourceAuthStepValidateRequest => '校验请求';

  @override
  String get sourceAuthStepSecureAuth => '安全认证';

  @override
  String get sourceAuthStepFetchProfile => '获取资料';

  @override
  String get sourceAuthFlowPreparingSession => '正在准备安全会话...';

  @override
  String get sourceAuthFlowSolvingChallenge => '正在完成安全挑战...';

  @override
  String get sourceAuthFlowFetchingProfile => '会话已验证。正在获取资料...';

  @override
  String get sourceAuthFlowLoginSuccess => '登录成功';

  @override
  String get sourceAuthCaptchaCaptured => 'CAPTCHA 已成功保存';

  @override
  String get home => '首页';

  @override
  String get search => '搜索';

  @override
  String get favorites => '收藏';

  @override
  String get downloads => '下载';

  @override
  String get history => '阅读历史';

  @override
  String get randomGallery => '随机画廊';

  @override
  String get randomGalleryLoadingTitle => '随机画廊';

  @override
  String get randomGalleryLoadingMessage => '正在获取随机画廊...';

  @override
  String get randomGalleryFoundTitle => '已找到';

  @override
  String get randomGalleryFoundMessage => '正在打开画廊详情...';

  @override
  String get randomGalleryNoResult => '未找到随机画廊，请重试。';

  @override
  String get randomGalleryError => '随机画廊加载失败，请重试。';

  @override
  String get randomGalleryUnavailableTitle => '功能不可用';

  @override
  String get randomGalleryUnavailableMessage => '当前来源暂不支持随机画廊。';

  @override
  String get offlineContent => '离线内容';

  @override
  String get settings => '设置';

  @override
  String get appDisguise => '应用伪装';

  @override
  String get disguiseMode => '伪装模式';

  @override
  String get offline => '离线';

  @override
  String get about => '关于';

  @override
  String get supportDeveloper => '支持开发者';

  @override
  String get supportDeveloperSubtitle => '请我喝杯咖啡';

  @override
  String get donateMessage => '支持开发 via QRIS 捐赠。谢谢！☕';

  @override
  String get thankYouMessage => '感谢您的支持！';

  @override
  String get searchHint => '搜索...';

  @override
  String get searchPlaceholder => '输入搜索关键词';

  @override
  String get noResults => '未找到结果';

  @override
  String get searchSuggestions => '搜索建议';

  @override
  String get suggestions => '建议：';

  @override
  String get facebookPage => 'Doujin Stash 3';

  @override
  String get facebookPageSubtitle => '点赞关注以支持我们';

  @override
  String get tapToLoadContent => '点击加载内容';

  @override
  String get trySwitchingNetwork => '尝试切换 Wi-Fi 或移动数据';

  @override
  String get restartRouter => '如果使用 Wi-Fi，请尝试重启路由器';

  @override
  String get checkWebsiteStatus => '检查目标网站是否正常运行';

  @override
  String get cloudflareBypassMessage => '网站受 Cloudflare 保护，正在尝试绕过验证。';

  @override
  String get forceBypass => '强制绕过';

  @override
  String get unableToProcessData => '无法处理返回数据，网站结构可能已变更。';

  @override
  String get reportIssue => '反馈问题';

  @override
  String serverReturnedError(int statusCode) {
    return '服务器返回错误代码 $statusCode，服务暂时不可用。';
  }

  @override
  String get failedToOpenBrowser => '无法打开浏览器';

  @override
  String get viewDownloads => '查看下载';

  @override
  String get clearSearch => '清除搜索';

  @override
  String get clearFilters => '清除筛选';

  @override
  String get anyLanguage => '任何语言';

  @override
  String get anyCategory => '任何类别';

  @override
  String get errorOpeningFilter => '打开筛选器选择时出错';

  @override
  String get errorBrowsingTag => '浏览标签时出错';

  @override
  String get shuffleToNextGallery => '随机切换到下一个画廊';

  @override
  String get contentHidden => '内容已隐藏';

  @override
  String get tapToViewAnyway => '点击仍然查看';

  @override
  String get checkOutThisGallery => '查看这个画廊！';

  @override
  String galleriesPreloaded(int count) {
    return '已预加载 $count 个画廊';
  }

  @override
  String get oopsSomethingWentWrong => '哎呀！出了点问题';

  @override
  String get cleanupInfo => '清理信息';

  @override
  String get clearingHistory => '正在清除历史...';

  @override
  String get areYouSureClearHistory => '您确定要清除所有阅读历史记录吗？此操作无法撤销。';

  @override
  String get artistCg => '画师 cg';

  @override
  String get gameCg => '游戏CG';

  @override
  String get manga => '漫画';

  @override
  String get doujinshi => '同人志';

  @override
  String get imageSet => '图集';

  @override
  String get cosplay => 'Cosplay';

  @override
  String get artistcg => '画师CG';

  @override
  String get gamecg => '游戏CG';

  @override
  String get bigBreasts => '巨乳';

  @override
  String get soleFemale => '单女主';

  @override
  String get soleMale => '单男主';

  @override
  String get pleaseSetStorageLocation => '先在设置中设置下载存储位置。';

  @override
  String get schoolgirlUniform => '女学生制服';

  @override
  String get tryADifferentSearchTerm => '尝试不同的搜索词';

  @override
  String get unknownError => '未知错误';

  @override
  String get loadingOfflineContent => '加载离线内容...';

  @override
  String get excludeTags => '排除标签';

  @override
  String get excludeGroups => '排除团体';

  @override
  String get excludeCharacters => '排除角色';

  @override
  String get excludeParodies => '排除原作';

  @override
  String get excludeArtists => '排除画师';

  @override
  String get noResultsFound => '未找到结果';

  @override
  String get tryAdjustingFilters => '尝试调整筛选条件或使用其他关键词。';

  @override
  String get networkError => '网络连接错误，检查网络设置。';

  @override
  String get accessBlocked => '访问被阻止。正在尝试绕过保护...';

  @override
  String get tooManyRequests => '请求过多。请稍等片刻后重试。';

  @override
  String get errorProcessingResults => '处理搜索结果时出错。请重试。';

  @override
  String get invalidSearchParameters => '无效的搜索参数。请检查您的输入。';

  @override
  String get unexpectedError => '发生意外错误。请重试。';

  @override
  String get retryBypass => '重试绕过';

  @override
  String get retryConnection => '重试连接';

  @override
  String get retrySearch => '重试搜索';

  @override
  String get errorNetwork => '网络连接错误，检查网络设置。';

  @override
  String get errorServer => '服务器暂时无法响应，请稍后再试。';

  @override
  String get errorCloudflare => '检测到 Cloudflare 验证，请稍后重试。';

  @override
  String get errorParsing => '数据解析失败，内容可能已失效。';

  @override
  String get errorUnknown => '发生未知错误，请重试。';

  @override
  String get errorConnectionTimeout => '连接请求超时，请重试。';

  @override
  String get errorConnectionRefused => '连接被拒绝，服务器可能已停止服务。';

  @override
  String get networkErrorTitle => '网络错误';

  @override
  String get serverErrorTitle => '服务器错误';

  @override
  String get unknownErrorTitle => '未知错误';

  @override
  String get refreshingContent => '正在刷新内容...';

  @override
  String get loadingMoreContent => '正在加载更多内容...';

  @override
  String get searchResults => '搜索结果';

  @override
  String get latestContent => '最新内容';

  @override
  String get serverTemporarilyUnavailable => '服务器暂时不可用，请稍后再试。';

  @override
  String get cloudflareProtectionDetected => '检测到 Cloudflare 保护，请稍等后重试。';

  @override
  String get tooManyRequestsWait => '请求过多，请稍等片刻后重试。';

  @override
  String get noContentFoundMatching => '未找到符合搜索条件的内容。请尝试调整筛选器。';

  @override
  String noContentFoundForTag(String tagName) {
    return '未找到标签 \"$tagName\" 的内容。';
  }

  @override
  String get useGeneralTerms => '使用更宽泛的搜索词';

  @override
  String get tryBrowsingOtherTags => '尝试浏览其他标签';

  @override
  String get checkPopularContent => '查看热门内容';

  @override
  String get useSearchFunction => '使用搜索功能';

  @override
  String get checkInternetConnectionSuggestion => '检查您的网络连接';

  @override
  String get browsePopularContentSuggestion => '浏览热门内容';

  @override
  String get failedToInitializeSearch => '搜索初始化失败';

  @override
  String noResultsFoundFor(String query) {
    return '未找到 \"$query\" 的相关结果';
  }

  @override
  String get searchingWithFilters => '正在根据筛选条件搜索...';

  @override
  String get noResultsFoundWithCurrentFilters => '当前筛选条件下未找到结果';

  @override
  String invalidFilter(String errors) {
    return '无效的筛选器：$errors';
  }

  @override
  String invalidSearchFilter(String errors) {
    return '无效的搜索筛选：$errors';
  }

  @override
  String get tags => '标签';

  @override
  String get language => '语言';

  @override
  String get uploadedOn => '上传于';

  @override
  String get readNow => '立即阅读';

  @override
  String get featured => '精选';

  @override
  String get confirmDownload => '确认下载';

  @override
  String get downloadConfirmation => '确定要下载吗？';

  @override
  String get confirmButton => '确认';

  @override
  String get download => '下载';

  @override
  String get downloading => '下载中';

  @override
  String get downloadCompleted => '下载完成';

  @override
  String get initializing => '初始化中...';

  @override
  String get noContentToBrowse => '没有可加载到浏览器的内容';

  @override
  String get addToFavorites => '加入收藏';

  @override
  String get removeFromFavorites => '取消收藏';

  @override
  String get content => '内容';

  @override
  String get clearAll => '清空全部';

  @override
  String get exportList => '导出列表';

  @override
  String get unableToCheck => '无法检查连接状况';

  @override
  String get noContentAvailable => '暂无内容';

  @override
  String get noContentToDownload => '无可下载内容';

  @override
  String get noGalleriesFound => '此页面未找到画廊';

  @override
  String get noContentLoadedToBrowse => '没有可加载到浏览器的内容';

  @override
  String get showCachedContent => '显示缓存内容';

  @override
  String get openedInBrowser => '已在浏览器中打开';

  @override
  String get foundGalleries => '发现画廊';

  @override
  String get checkingDownloadStatus => '正在检查下载状态...';

  @override
  String get allGalleriesDownloaded => '所有画廊已下载';

  @override
  String get downloadNewGalleries => '下载新画廊';

  @override
  String get downloadProgress => '下载进度';

  @override
  String get verifyingFiles => '校验文件';

  @override
  String verifyingFilesWithTitle(String title) {
    return '正在校验 $title...';
  }

  @override
  String verifyingProgress(int progress) {
    return '校验中 ($progress%)';
  }

  @override
  String get initializingDownloads => '正在初始化下载...';

  @override
  String get loadingDownloads => '正在加载下载...';

  @override
  String get pauseAll => '全部暂停';

  @override
  String get resumeAll => '全部继续';

  @override
  String get cancelAll => '全部取消';

  @override
  String get clearCompleted => '清除已完成';

  @override
  String get cleanupStorage => '清理存储';

  @override
  String get all => '全部';

  @override
  String get completed => '已完成';

  @override
  String get noDownloadsYet => '暂无下载记录';

  @override
  String get noActiveDownloads => '没有进行中的下载';

  @override
  String get noQueuedDownloads => '没有排队中的下载';

  @override
  String get noCompletedDownloads => '没有已完成的下载';

  @override
  String get noFailedDownloads => '没有失败的下载';

  @override
  String get cancelAllDownloads => '取消所有下载';

  @override
  String get cancelAllConfirmation => '确定要取消所有进行中的下载吗？此操作无法撤销。';

  @override
  String get cancelDownload => '取消下载';

  @override
  String get cancelDownloadConfirmation => '确定要取消此下载任务吗？当前进度将丢失。';

  @override
  String get removeDownload => '移除下载';

  @override
  String get removeDownloadConfirmation => '确定要从列表移除此下载吗？已下载的文件也将被删除。';

  @override
  String get cleanupConfirmation => '此操作将清理无用的文件和失败的下载记录，是否继续？';

  @override
  String get downloadDetails => '下载详情';

  @override
  String get status => '状态';

  @override
  String get progressPercent => '进度 %';

  @override
  String get started => '开始时间';

  @override
  String get ended => '结束时间';

  @override
  String get eta => '预计剩余时间';

  @override
  String get failed => '失败';

  @override
  String get downloadListExported => '下载列表已导出';

  @override
  String get downloadAll => '全部下载';

  @override
  String get downloadRange => '范围下载';

  @override
  String get selectDownloadRange => '选择下载范围';

  @override
  String get useSliderToSelectRange => '使用滑块选择范围：';

  @override
  String get orEnterManually => '或手动输入：';

  @override
  String get quickSelections => '快速选择：';

  @override
  String get allPages => '所有页面';

  @override
  String get firstHalf => '前半部分';

  @override
  String get secondHalf => '后半部分';

  @override
  String get first10 => '前 10 页';

  @override
  String get last10 => '后 10 页';

  @override
  String countAlreadyDownloaded(int count) {
    return '已跳过 $count 个已下载项';
  }

  @override
  String newGalleriesToDownload(int count) {
    return '• $count 个新画廊待下载';
  }

  @override
  String alreadyDownloaded(int count) {
    return '• $count 个已存在 (将被跳过)';
  }

  @override
  String downloadNew(int count) {
    return '下载 $count 个新项目';
  }

  @override
  String queuedDownloads(int count) {
    return '已添加 $count 个新下载到队列';
  }

  @override
  String downloadInfo(int count) {
    return '确定下载 $count 个新画廊吗？\n\n这可能需要较长时间并占用大量存储空间。';
  }

  @override
  String get failedToDownload => '下载画廊失败';

  @override
  String selectedPagesTo(int start, int end) {
    return '已选：第 $start 页 至 第 $end 页';
  }

  @override
  String pagesPercentage(int count, String percentage) {
    return '$count 页 ($percentage%)';
  }

  @override
  String rangeDownloadStarted(String title, String pageText) {
    return '范围下载已开始：$title ($pageText)';
  }

  @override
  String opening(String title) {
    return '正在打开：$title';
  }

  @override
  String get lastUpdatedLabel => '更新于:';

  @override
  String get releasedLabel => '发布于:';

  @override
  String get updatedLabel => '更新于:';

  @override
  String get rangeLabel => '范围:';

  @override
  String get ofWord => '/';

  @override
  String waitAndTry(int minutes) {
    return '请等待 $minutes 分钟后再试';
  }

  @override
  String get serviceUnderMaintenance => '服务可能正在维护中';

  @override
  String get tryRefreshingPage => '尝试刷新页面';

  @override
  String get waitForBypass => '等待自动绕过完成';

  @override
  String get tryUsingVpn => '尝试使用 VPN';

  @override
  String get checkBackLater => '请过几分钟再来看看';

  @override
  String get tryRefreshingContent => '尝试刷新内容';

  @override
  String get checkForAppUpdate => '检查应用更新';

  @override
  String get reportIfPersists => '如果问题持续存在，请反馈';

  @override
  String get maintenanceTakesHours => '维护通常需要几个小时';

  @override
  String get checkSocialMedia => '查看社交媒体获取最新消息';

  @override
  String get tryAgainLater => '请稍后重试';

  @override
  String get tryDifferentKeywords => '尝试使用不同的关键词。';

  @override
  String get serverUnavailable => '服务器当前不可用，请稍后再试。';

  @override
  String get removeSomeFilters => '移除部分筛选器';

  @override
  String get checkSpelling => '检查拼写';

  @override
  String get useBroaderSearchTerms => '使用更宽泛的搜索词';

  @override
  String get welcomeTitle => '欢迎使用 Kuron！';

  @override
  String get welcomeMessage => '在开始之前：';

  @override
  String get ispBlockingInfo => '🚨 ISP 封锁通知';

  @override
  String get ispBlockingMessage => '被 ISP 屏蔽？使用 VPN 如 Cloudflare WARP 1.1.1.1。';

  @override
  String get downloadWarp => '下载 1.1.1.1 VPN';

  @override
  String get permissionsRequired => '所需权限';

  @override
  String get storagePermissionInfo => '📁 存储：下载和离线保存内容所需';

  @override
  String get notificationPermissionInfo => '🔔 通知：显示下载进度和完成通知所需';

  @override
  String get grantStoragePermission => '授予存储权限';

  @override
  String get grantNotificationPermission => '授予通知权限';

  @override
  String get storageGranted => '✅ 存储权限已授予';

  @override
  String get notificationGranted => '✅ 通知权限已授予';

  @override
  String get getStarted => '开始使用';

  @override
  String get pleaseGrantAllPermissions => '授予必需的权限以继续';

  @override
  String get permissionDenied => '权限被拒绝。某些功能可能无法正常工作。';

  @override
  String get loadingFavorites => '正在加载收藏...';

  @override
  String get errorLoadingFavorites => '加载收藏失败';

  @override
  String get removeFavoriteConfirmation => '确定要将此内容移出收藏夹吗？';

  @override
  String get removeAction => '移除';

  @override
  String get deleteFavorites => '删除收藏';

  @override
  String deleteFavoritesConfirmation(int count, String s) {
    return '确定要删除 $count 个收藏项吗？';
  }

  @override
  String get exportFavorites => '导出收藏';

  @override
  String get noFavoritesYet => '暂无收藏。快去添加一些喜欢的内容吧！';

  @override
  String get exportingFavorites => '正在导出收藏...';

  @override
  String get exportComplete => '导出完成';

  @override
  String exportedFavoritesCount(int count) {
    return '成功导出 $count 个收藏项。';
  }

  @override
  String selectedCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String get selectFavorites => '选择收藏';

  @override
  String get deleteSelected => '删除所选';

  @override
  String get searchFavorites => '搜索收藏...';

  @override
  String get selectAll => '全选';

  @override
  String get removingFromFavorites => '正在移除收藏...';

  @override
  String get removedFromFavorites => '已移除收藏';

  @override
  String failedToRemoveFavorite(String error) {
    return '移除收藏失败：$error';
  }

  @override
  String removedFavoritesCount(int count) {
    return '已移除 $count 个收藏';
  }

  @override
  String failedToRemoveFavorites(String error) {
    return '批量移除失败: $error';
  }

  @override
  String get appearance => '外观';

  @override
  String get theme => '主题';

  @override
  String get imageQuality => '图片质量';

  @override
  String get blurThumbnails => '模糊缩略图';

  @override
  String get blurThumbnailsDescription => '对卡片图片应用模糊效果以保护隐私';

  @override
  String get gridColumns => '网格列数 (竖屏)';

  @override
  String get reader => '阅读器';

  @override
  String get showSystemUIInReader => '阅读时显示系统界面';

  @override
  String get historyCleanup => '历史清理';

  @override
  String get autoCleanupHistory => '自动清理历史';

  @override
  String get automaticallyCleanOldReadingHistory => '自动清理旧的阅读历史记录';

  @override
  String get cleanupInterval => '清理间隔';

  @override
  String get howOftenToCleanupHistory => '执行清理的频率';

  @override
  String get maxHistoryDays => '保留历史天数';

  @override
  String get maximumDaysToKeepHistory => '保留历史记录的最大天数 (0 = 无限)';

  @override
  String get cleanupOnInactivity => '闲置清理';

  @override
  String get cleanHistoryWhenAppUnused => '应用未使用多天后自动清理';

  @override
  String get inactivityThreshold => '闲置阈值';

  @override
  String get daysOfInactivityBeforeCleanup => '触发清理的闲置天数';

  @override
  String get resetToDefault => '恢复默认';

  @override
  String get generalSettings => '通用设置';

  @override
  String get displaySettings => '显示设置';

  @override
  String get darkMode => '深色模式';

  @override
  String get lightMode => '浅色模式';

  @override
  String get systemMode => '跟随系统';

  @override
  String get appLanguage => '应用语言';

  @override
  String get allowAnalytics => '允许分析统计';

  @override
  String get privacyAnalytics => '隐私分析';

  @override
  String get termsAndConditions => '条款与条件';

  @override
  String get termsAndConditionsSubtitle => '用户协议和免责声明';

  @override
  String get privacyPolicy => '隐私政策';

  @override
  String get privacyPolicySubtitle => '数据处理方式说明';

  @override
  String get faq => '常见问题';

  @override
  String get faqSubtitle => '常见问题解答';

  @override
  String get resetSettings => '重置设置';

  @override
  String get resetReaderSettings => '重置阅读器设置';

  @override
  String get resetReaderSettingsConfirmation => '这将重置阅读器的所有设置到默认值：\n\n';

  @override
  String get readingModeLabel => '阅读模式：水平翻页';

  @override
  String get areYouSure => '确定要继续吗？';

  @override
  String get readerSettingsResetSuccess => '阅读器设置已恢复默认。';

  @override
  String get readingHistory => '阅读历史';

  @override
  String get clearAllHistory => '清空历史';

  @override
  String get manualCleanup => '手动清理';

  @override
  String get cleanupSettings => '清理设置';

  @override
  String get removeFromHistoryQuestion => '确定移除此历史记录？';

  @override
  String get cleanup => '清理';

  @override
  String get failedToLoadCleanupStatus => '无法加载清理状态';

  @override
  String get manualCleanupConfirmation => '将根据当前设置执行清理，是否继续？';

  @override
  String get nextPage => '下一页';

  @override
  String get previousPage => '上一页';

  @override
  String get pageOf => ' / ';

  @override
  String get fullscreen => '全屏';

  @override
  String get exitFullscreen => '退出全屏';

  @override
  String get checkingConnection => '正在检查连接...';

  @override
  String get backOnline => '网络已恢复！所有功能可用。';

  @override
  String get stillNoInternet => '网络连接仍不可用。';

  @override
  String get unableToCheckConnection => '无法检查连接。';

  @override
  String get noInternetConnection => '无网络连接';

  @override
  String get connectionError => '连接错误';

  @override
  String get serverError => '服务器错误';

  @override
  String get low => '低';

  @override
  String get medium => '中';

  @override
  String get high => '高';

  @override
  String get original => '原图';

  @override
  String get lowFaster => '低 (较快)';

  @override
  String get highBetterQuality => '高 (较清晰)';

  @override
  String get originalLargest => '原图 (最大)';

  @override
  String get lowQuality => '低 (较快)';

  @override
  String get mediumQuality => '中';

  @override
  String get highQuality => '高 (较清晰)';

  @override
  String get originalQuality => '原图 (最大)';

  @override
  String get dark => '深色';

  @override
  String get light => '浅色';

  @override
  String get amoled => 'AMOLED';

  @override
  String get english => '英语';

  @override
  String get japanese => '日语';

  @override
  String get indonesian => '印尼语';

  @override
  String get chinese => '简体中文';

  @override
  String get comfortReading => '舒适阅读';

  @override
  String get filterBy => '筛选';

  @override
  String get recent => '最近';

  @override
  String get popular => '热门';

  @override
  String get oldest => '最早';

  @override
  String get ok => '确定';

  @override
  String get exitApp => '退出应用';

  @override
  String get areYouSureExit => '您确定要退出应用吗？';

  @override
  String get exit => '退出';

  @override
  String get delete => '删除';

  @override
  String get confirm => '确认';

  @override
  String get tryAgain => '重试';

  @override
  String get save => '保存';

  @override
  String get edit => '编辑';

  @override
  String get close => '关闭';

  @override
  String get clear => '清除';

  @override
  String get share => '分享';

  @override
  String get goBack => '返回';

  @override
  String get yes => '是';

  @override
  String get no => '否';

  @override
  String get previous => '上一页';

  @override
  String get next => '下一页';

  @override
  String get goToDownloads => '转到下载';

  @override
  String get retryAction => '重试';

  @override
  String get unknown => '未知';

  @override
  String get noData => '无数据';

  @override
  String get downloadError => '下载错误';

  @override
  String get other => '其他';

  @override
  String get confirmResetSettings => '确定要恢复所有默认设置吗？';

  @override
  String get reset => '重置';

  @override
  String get manageAutoCleanupDescription => '管理阅读历史的自动清理策略以节省空间。';

  @override
  String get nextCleanup => '下次清理';

  @override
  String get historyStatistics => '历史记录统计';

  @override
  String get totalItems => '总数';

  @override
  String get lastCleanup => '上次清理';

  @override
  String get lastAppAccess => '上次使用';

  @override
  String get oneDay => '1 天';

  @override
  String get twoDays => '2 天';

  @override
  String get oneWeek => '1 周';

  @override
  String get privacyInfoText =>
      '• 数据仅存储在本地设备\n• 不会上传至任何外部服务器\n• 仅用于优化应用性能\n• 可随时关闭';

  @override
  String get unlimited => '无限制';

  @override
  String daysValue(int days) {
    return '$days 天';
  }

  @override
  String days(int count) {
    return '$count 天';
  }

  @override
  String get analyticsSubtitle => '利用本地数据辅助开发优化（不共享）';

  @override
  String get loadingContent => '加载内容中...';

  @override
  String get loadingError => '加载错误';

  @override
  String get jumpToPage => '跳转到页';

  @override
  String pageInputLabel(int maxPages) {
    return '页码 (1-$maxPages)';
  }

  @override
  String pageOfPages(int current, int total) {
    return '第 $current 页，共 $total 页';
  }

  @override
  String get jump => '跳转';

  @override
  String get readerSettings => '阅读器设置';

  @override
  String get readingMode => '阅读模式';

  @override
  String get horizontalPages => '水平翻页';

  @override
  String get verticalPages => '垂直翻页';

  @override
  String get continuousScroll => '连续滚动';

  @override
  String get keepScreenOnLabel => '保持屏幕常亮：关';

  @override
  String get showUILabel => '显示界面：开';

  @override
  String get keepScreenOn => '保持屏幕常亮';

  @override
  String get keepScreenOnDescription => '阅读时防止屏幕自动关闭';

  @override
  String get platformNotSupported => '平台不支持';

  @override
  String get platformNotSupportedBody => 'Kuron 专为 Android 设备设计。';

  @override
  String get platformNotSupportedInstall => '请在 Android 设备上安装并运行此应用。';

  @override
  String get storagePermissionExplanation =>
      '需要存储权限以下载文件。文件保存在 Downloads/nhasix 文件夹。';

  @override
  String get grantPermission => '授予权限';

  @override
  String get permissionRequired => '权限受限';

  @override
  String get storagePermissionSettingsPrompt => '文件下载需要存储权限。请在应用设置中开启存储权限。';

  @override
  String get openSettings => '打开设置';

  @override
  String get noReadingHistory => '暂无阅读历史';

  @override
  String get readingHistoryMessage => '您的阅读历史将在这里显示。';

  @override
  String get startReading => '开始阅读';

  @override
  String get browsePopularContent => '浏览热门内容';

  @override
  String get searchSomethingInteresting => '搜索些有趣的内容吧';

  @override
  String get checkOutFeaturedItems => '查看精选内容';

  @override
  String get appSubtitleDescription => '非官方 Nhentai 客户端';

  @override
  String get downloadedGalleries => '已下载图集';

  @override
  String get favoriteGalleries => '收藏图集';

  @override
  String get viewHistory => '查看历史';

  @override
  String get openInBrowser => '在浏览器中打开';

  @override
  String get downloadAllGalleries => '下载此页面中的所有画廊';

  @override
  String get featureDisabledTitle => '功能不可用';

  @override
  String get downloadFeatureDisabled => '此来源不支持下载功能';

  @override
  String get favoriteFeatureDisabled => '此来源不支持收藏功能';

  @override
  String get featureNotAvailable => '此功能当前不可用';

  @override
  String get chaptersTitle => '章节';

  @override
  String chapterCount(int count) {
    return '$count 个章节';
  }

  @override
  String loadMoreChapters(String label) {
    return '加载更多$label';
  }

  @override
  String get readChapter => '阅读';

  @override
  String get downloadChapter => '下载章节';

  @override
  String enterPageNumber(int totalPages) {
    return '输入页码 (1 - $totalPages)';
  }

  @override
  String get go => '前往';

  @override
  String validPageNumberError(int totalPages) {
    return '输入页码 (1 - $totalPages)';
  }

  @override
  String get tapToJump => '点击跳转';

  @override
  String get goToPage => '跳转到页';

  @override
  String get previousPageTooltip => '上一页';

  @override
  String get nextPageTooltip => '下一页';

  @override
  String get tapToJumpToPage => '点击跳转到其他页';

  @override
  String get loadingContentTitle => '加载内容中';

  @override
  String get loadingContentDetails => '加载内容详情中';

  @override
  String get fetchingMetadata => '正在获取元数据和图片...';

  @override
  String get thisMayTakeMoments => '这可能需要一会儿...';

  @override
  String get youAreOffline => '您已离线';

  @override
  String get goOnline => '切换至在线';

  @override
  String get youAreOfflineTapToGoOnline => '当前离线，点击切换至在线模式。';

  @override
  String get contentInformation => '内容信息';

  @override
  String get copyLink => '复制链接';

  @override
  String get moreOptions => '更多选项';

  @override
  String get moreLikeThis => '类似推荐';

  @override
  String get statistics => '统计信息';

  @override
  String get failedToLoadContent => '加载内容失败';

  @override
  String get shareContent => '分享内容';

  @override
  String get sharePanelOpened => '分享面板已打开！';

  @override
  String get shareFailed => '分享失败，链接已复制到剪贴板';

  @override
  String downloadStartedFor(String title) {
    return '已开始下载 \"$title\"';
  }

  @override
  String get viewDownloadsAction => '查看';

  @override
  String get linkCopiedToClipboard => '链接已复制';

  @override
  String get failedToCopyLink => '复制链接失败，请重试。';

  @override
  String get copiedLink => '已复制链接';

  @override
  String get linkCopiedToClipboardDescription => '以下链接已复制到您的剪贴板：';

  @override
  String get closeDialog => '关闭';

  @override
  String get goOnlineDialogTitle => '切换至在线';

  @override
  String get goOnlineDialogContent => '您当前处于离线模式。是否切换到在线模式以获取最新内容？';

  @override
  String get goingOnline => '正在上线...';

  @override
  String get idLabel => 'ID';

  @override
  String get pagesLabel => '页数';

  @override
  String artistLabel(String name) {
    return '画师：$name';
  }

  @override
  String get uploadedLabel => '上传时间';

  @override
  String get viewAllChapters => '查看所有章节';

  @override
  String get searchChapters => '搜索章节...';

  @override
  String get noChaptersFound => '未找到章节';

  @override
  String get favoritesLabel => '收藏';

  @override
  String get relatedLabel => '相关';

  @override
  String yearAgo(int count, String plural) {
    return '$count 年前';
  }

  @override
  String monthAgo(int count, String plural) {
    return '$count 个月前';
  }

  @override
  String dayAgo(int count, String plural) {
    return '$count 天前';
  }

  @override
  String hourAgo(int count, String plural) {
    return '$count 小时前';
  }

  @override
  String get selectFavoritesTooltip => '选择收藏';

  @override
  String get deleteSelectedTooltip => '已选择删除项';

  @override
  String get exportAction => '导出';

  @override
  String get refreshAction => '刷新';

  @override
  String get selectAllAction => '全选';

  @override
  String get clearAction => '清除';

  @override
  String selectedCountFormat(int selected, int total) {
    return '$selected / $total';
  }

  @override
  String get loadingFavoritesMessage => '正在加载收藏...';

  @override
  String get deletingFavoritesMessage => '正在删除收藏...';

  @override
  String get removingFromFavoritesMessage => '正在从收藏中移除...';

  @override
  String get favoritesDeletedMessage => '收藏删除成功';

  @override
  String get failedToDeleteFavoritesMessage => '删除收藏失败';

  @override
  String get confirmDeleteFavoritesTitle => '删除收藏';

  @override
  String confirmDeleteFavoritesMessage(int count, String plural) {
    return '确定要删除 $count 个收藏吗？';
  }

  @override
  String get exportFavoritesTitle => '导出收藏';

  @override
  String get exportingFavoritesMessage => '正在导出收藏...';

  @override
  String get favoritesExportedMessage => '收藏导出成功';

  @override
  String get failedToExportFavoritesMessage => '导出收藏失败';

  @override
  String get searchFavoritesHint => '搜索收藏...';

  @override
  String get searchOfflineContentHint => '搜索离线内容...';

  @override
  String failedToLoadPage(int pageNumber) {
    return '无法加载第 $pageNumber 页';
  }

  @override
  String get failedToLoad => '加载失败';

  @override
  String get loginRequiredForAction => '此操作需要登录';

  @override
  String get login => '登录';

  @override
  String get offlineContentTitle => '离线内容';

  @override
  String get offlineContentError => '离线内容错误';

  @override
  String get favorited => '已收藏';

  @override
  String get favorite => '收藏';

  @override
  String get errorLoadingHistory => '加载历史记录出错';

  @override
  String get errorLoadingFavoritesTitle => '加载收藏出错';

  @override
  String get filterDataTitle => '筛选数据';

  @override
  String searchFilterHint(String filterType) {
    return '搜索 $filterType...';
  }

  @override
  String selectedCountFormat2(int count) {
    return '已选 ($count)';
  }

  @override
  String get errorLoadingFilterDataTitle => '加载筛选数据出错';

  @override
  String noFilterTypeAvailable(String filterType) {
    return '无可用 $filterType';
  }

  @override
  String noResultsFoundForQuery(String query) {
    return '未找到 \"$query\" 的结果';
  }

  @override
  String get contentNotFoundTitle => '内容未找到';

  @override
  String contentNotFoundMessage(String contentId) {
    return '未找到 ID 为 \"$contentId\" 的内容。';
  }

  @override
  String get filterCategoriesTitle => '筛选分类';

  @override
  String get searchTitle => '搜索';

  @override
  String get advancedSearchTitle => '高级搜索';

  @override
  String get enterSearchQueryHint => '搜索 (例如 \"big breasts english\")';

  @override
  String get popularSearchesTitle => '热门搜索';

  @override
  String get clearAllAction => '清除全部';

  @override
  String get pressSearchButtonMessage => '按当前筛选条件搜索';

  @override
  String get searchingMessage => '搜索中...';

  @override
  String resultsCountFormat(String count) {
    return '$count 个结果';
  }

  @override
  String get viewInMainAction => '在主页查看';

  @override
  String get searchErrorTitle => '搜索错误';

  @override
  String get noResultsFoundTitle => '未找到结果';

  @override
  String pageText(int pageNumber) {
    return '第 $pageNumber 页';
  }

  @override
  String pagesText(int startPage, int endPage) {
    return '页数 $startPage-$endPage';
  }

  @override
  String get offlineStatus => '离线';

  @override
  String get onlineStatus => '在线';

  @override
  String get sortBy => '排序';

  @override
  String get errorOccurred => '发生错误';

  @override
  String get tapToRetry => '点击重试';

  @override
  String get helpTitle => '帮助';

  @override
  String get helpNoResults => '未找到相关搜索结果';

  @override
  String get helpTryDifferent => '尝试使用不同的关键词或检查拼写';

  @override
  String get helpUseFilters => '使用筛选器缩小搜索范围';

  @override
  String get helpCheckConnection => '检查您的网络连接';

  @override
  String get sendReportText => '发送报告';

  @override
  String get technicalDetailsTitle => '技术详情';

  @override
  String get reportSentText => '报告已发送！';

  @override
  String get suggestionCheckConnection => '检查网络连接';

  @override
  String get suggestionTryWifiMobile => '尝试切换 Wi-Fi 或移动数据';

  @override
  String get suggestionRestartRouter => '如果使用 Wi-Fi，请尝试重启路由器';

  @override
  String get suggestionCheckWebsite => '检查网站是否宕机';

  @override
  String noContentFoundWithQuery(String query) {
    return '未找到 \"$query\" 的内容。尝试调整关键词或筛选器。';
  }

  @override
  String get noContentFound => '未找到内容。尝试调整关键词或筛选器。';

  @override
  String get suggestionTryDifferentKeywords => '尝试不同的关键词';

  @override
  String get suggestionRemoveFilters => '移除部分筛选器';

  @override
  String get suggestionCheckSpelling => '检查拼写';

  @override
  String get suggestionUseBroaderTerms => '使用更宽泛的搜索词';

  @override
  String get underMaintenanceTitle => '维护中';

  @override
  String get underMaintenanceMessage => '服务正在维护中，请稍后再试。';

  @override
  String get suggestionMaintenanceHours => '维护通常需要几个小时';

  @override
  String get suggestionCheckSocial => '查看社交媒体获取更新';

  @override
  String get suggestionTryLater => '请稍后重试';

  @override
  String get includeFilter => '包含';

  @override
  String get excludeFilter => '排除';

  @override
  String get overallProgress => '总进度';

  @override
  String get active => '进行中';

  @override
  String get queued => '排队中';

  @override
  String get speed => '速度';

  @override
  String downloadsFailed(int count, String plural) {
    return '$count 个下载失败';
  }

  @override
  String get view => '查看';

  @override
  String get processing => '处理中...';

  @override
  String get loading => '加载中...';

  @override
  String get unknownTitle => '未知标题';

  @override
  String get readingCompleted => '已完成';

  @override
  String get readAgain => '重新阅读';

  @override
  String get continueReading => '继续';

  @override
  String get removeFromHistory => '从历史中移除';

  @override
  String get lessThanOneMinute => '少于 1 分钟';

  @override
  String get readingTime => '阅读时长';

  @override
  String get downloadActions => '下载操作';

  @override
  String get pause => '暂停';

  @override
  String get resume => '恢复';

  @override
  String get cancel => '取消';

  @override
  String get retry => '重试';

  @override
  String get details => '详情';

  @override
  String get remove => '移除';

  @override
  String get downloadActionPause => '暂停';

  @override
  String get downloadActionResume => '继续';

  @override
  String get downloadActionCancel => '取消';

  @override
  String get downloadActionRetry => '重试';

  @override
  String get downloadActionConvertToPdf => '转换为 PDF';

  @override
  String get downloadActionDetails => '详情';

  @override
  String get downloadActionRemove => '移除';

  @override
  String downloadPagesRangeFormat(
      int downloaded, int total, int start, int end, int totalPages) {
    return '$downloaded/$total (第 $start-$end 页，共 $totalPages 页)';
  }

  @override
  String downloadPagesFormat(int downloaded, int total) {
    return '$downloaded/$total';
  }

  @override
  String downloadContentTitle(String contentId) {
    return '内容 $contentId';
  }

  @override
  String downloadEtaLabel(String duration) {
    return '预计剩余: $duration';
  }

  @override
  String get duration => '耗时';

  @override
  String get downloadSettingsTitle => '下载设置';

  @override
  String get performanceSection => '性能';

  @override
  String get maxConcurrentDownloads => '最大并发下载数';

  @override
  String get concurrentDownloadsWarning => '较高的值可能会消耗更多带宽和设备资源';

  @override
  String get imageQualityLabel => '图片质量';

  @override
  String get autoRetrySection => '自动重试';

  @override
  String get autoRetryFailedDownloads => '自动重试失败的下载';

  @override
  String get autoRetryDescription => '自动重试下载失败的任务';

  @override
  String get maxRetryAttempts => '最大重试次数';

  @override
  String get networkSection => '网络';

  @override
  String get wifiOnlyLabel => '仅 Wi-Fi';

  @override
  String get wifiOnlyDescription => '仅在连接 Wi-Fi 时下载';

  @override
  String get downloadTimeoutLabel => '下载超时';

  @override
  String get notificationsSection => '通知';

  @override
  String get enableNotificationsLabel => '启用通知';

  @override
  String get enableNotificationsDescription => '显示下载进度通知';

  @override
  String get minutesUnit => '分钟';

  @override
  String get searchContentHint => '搜索内容...';

  @override
  String get hideFiltersTooltip => '隐藏筛选';

  @override
  String get showMoreFiltersTooltip => '显示更多筛选';

  @override
  String get advancedFiltersTitle => '高级筛选';

  @override
  String get sortByLabel => '排序方式';

  @override
  String get recentSearchesTitle => '最近搜索';

  @override
  String get includeTagsLabel => '包含标签 (逗号分隔)';

  @override
  String get includeTagsHint => '例如: romance, comedy, school';

  @override
  String get excludeTagsHint => '例如: horror, violence';

  @override
  String get artistsHint => '例如: artist1, artist2';

  @override
  String get pageCountRangeTitle => '页数范围';

  @override
  String get minPagesLabel => '最少页数';

  @override
  String get maxPagesLabel => '最多页数';

  @override
  String get rangeToSeparator => '至';

  @override
  String get popularTagsTitle => '热门标签';

  @override
  String get filtersActiveLabel => '生效中';

  @override
  String get clearAllFilters => '清除全部';

  @override
  String get appSubtitle => 'Enhanced Reading Experience';

  @override
  String get initializingApp => '正在初始化应用...';

  @override
  String get settingUpComponents => '正在设置组件并检查连接...';

  @override
  String get bypassingProtection => '正在绕过保护并建立连接...';

  @override
  String get connectionFailed => '连接失败';

  @override
  String get readyToGo => '准备就绪！';

  @override
  String get launchingApp => '正在启动主应用...';

  @override
  String downloaded(String size) {
    return '已下载 $size';
  }

  @override
  String get imageNotAvailable => '图片不可用';

  @override
  String loadingPage(int pageNumber) {
    return '正在加载第 $pageNumber 页...';
  }

  @override
  String pageNumber(int pageNumber) {
    return '第 $pageNumber 页';
  }

  @override
  String get checkInternetConnection => '请检查您的网络连接';

  @override
  String selectedItemsCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String get removeFavorite => '取消收藏';

  @override
  String get noImage => '无图';

  @override
  String get youAreOfflineShort => '当前处于离线状态';

  @override
  String get someFeaturesLimited => '部分功能受限。请连接网络以获取完整体验。';

  @override
  String get wifi => 'WI-FI';

  @override
  String get ethernet => '以太网';

  @override
  String get mobile => '移动网络';

  @override
  String get online => '在线';

  @override
  String get offlineMode => '离线模式';

  @override
  String get applySearch => '应用搜索';

  @override
  String get addFiltersToSearch => '添加上方筛选器以启用搜索';

  @override
  String get startSearching => '开始搜索';

  @override
  String get enterKeywordsAdvancedHint => '输入关键词、标签或使用高级筛选来查找内容';

  @override
  String get filtersReady => '筛选器已就绪';

  @override
  String get clearAllFiltersTooltip => '清除所有筛选';

  @override
  String get offlineSomeFeaturesUnavailable => '当前处于离线状态，部分功能可能不可用。';

  @override
  String get usingDownloadedContentOnly => '仅显示已下载内容';

  @override
  String get onlineModeWithNetworkAccess => '在线模式 (已联网)';

  @override
  String get tagsScreenPlaceholder => '标签页面 - 待实现';

  @override
  String get artistsScreenPlaceholder => '画师页面 - 待实现';

  @override
  String get statusScreenPlaceholder => '状态页面 - 待实现';

  @override
  String get pageNotFound => '页面未找到';

  @override
  String pageNotFoundWithUri(String uri) {
    return '页面未找到: $uri';
  }

  @override
  String get goHome => '前往首页';

  @override
  String get debugThemeInfo => 'DEBUG: 主题信息';

  @override
  String get lightTheme => '浅色';

  @override
  String get darkTheme => '深色';

  @override
  String get amoledTheme => 'AMOLED';

  @override
  String get systemMessages => '系统消息与后台服务';

  @override
  String get notificationMessages => '通知消息';

  @override
  String convertingToPdfWithTitle(String title) {
    return '正在将 $title 转换为 PDF...';
  }

  @override
  String convertingToPdfProgress(Object progress) {
    return '转换 PDF 中 ($progress%)';
  }

  @override
  String convertingToPdfProgressWithTitle(String title, int progress) {
    return '正在转换 $title 为 PDF ($progress%)';
  }

  @override
  String get progress => '进度';

  @override
  String get pdfCreatedSuccessfully => 'PDF 创建成功';

  @override
  String pdfCreatedWithParts(String title, int partsCount) {
    return '$title 已转换为 $partsCount 个 PDF 文件';
  }

  @override
  String downloadStarted(String title) {
    return '下载已开始';
  }

  @override
  String downloadingWithTitle(String title) {
    return '正在下载: $title';
  }

  @override
  String downloadingProgress(Object progress) {
    return '下载中 ($progress%)';
  }

  @override
  String get downloadComplete => '下载完成';

  @override
  String downloadedWithTitle(String title) {
    return '已下载: $title';
  }

  @override
  String get downloadFailed => '下载失败';

  @override
  String downloadFailedWithTitle(String title) {
    return '失败: $title';
  }

  @override
  String get downloadPaused => '已暂停';

  @override
  String get downloadResumed => '已继续';

  @override
  String get downloadCancelled => '已取消';

  @override
  String get downloadRetry => '重试';

  @override
  String get downloadOpen => '打开';

  @override
  String get pdfOpen => '打开 PDF';

  @override
  String get pdfShare => '分享';

  @override
  String get pdfRetry => '重试 PDF';

  @override
  String get downloadServiceMessages => '下载服务消息';

  @override
  String downloadRangeInfo(int startPage, int endPage) {
    return ' (第 $startPage-$endPage 页)';
  }

  @override
  String downloadRangeComplete(int startPage, int endPage) {
    return ' (第 $startPage-$endPage 页)';
  }

  @override
  String get startPage => '起始页';

  @override
  String get endPage => '结束页';

  @override
  String invalidPageRange(int start, int end, int total) {
    return '无效的页码范围: $start-$end (共 $total 页)';
  }

  @override
  String get storagePermissionRequired => '下载功能需要存储权限，请在设置中授予权限。';

  @override
  String noDataReceived(String url) {
    return '未接收到图片数据: $url';
  }

  @override
  String createdNoMediaFile(String path) {
    return '为保护隐私已创建 .nomedia 文件: $path';
  }

  @override
  String get privacyProtectionEnsured => '已确保存有下载内容的隐私保护';

  @override
  String get pdfConversionMessages => 'PDF 转换服务消息';

  @override
  String pdfConversionStarted(String contentId) {
    return '已开始转换 PDF: $contentId';
  }

  @override
  String pdfConversionCompleted(String contentId) {
    return '$contentId PDF 转换成功';
  }

  @override
  String pdfConversionFailed(String contentId, String error) {
    return '$contentId PDF 转换失败: $error';
  }

  @override
  String pdfPartProcessing(int part) {
    return '正在处理第 $part 部分 (Isolate)...';
  }

  @override
  String get pdfSingleProcessing => '正在处理单体 PDF (Isolate)...';

  @override
  String pdfSplitRequired(int totalParts, int totalPages) {
    return '正在分割为 $totalParts 个部分 (共 $totalPages 页)';
  }

  @override
  String get totalPages => '总页数';

  @override
  String pdfCreatedFiles(int partsCount, int pageCount) {
    return '已创建 $partsCount 个 PDF 文件，共 $pageCount 页';
  }

  @override
  String get pdfNoImagesProvided => '未提供用于 PDF 转换的图片';

  @override
  String pdfFailedToCreatePart(int part, String error) {
    return '无法创建 PDF 第 $part 部分: $error';
  }

  @override
  String pdfFailedToCreate(String error) {
    return '无法创建 PDF: $error';
  }

  @override
  String pdfOutputDirectoryCreated(String path) {
    return '已创建 PDF 输出目录: $path';
  }

  @override
  String pdfUsingFallbackDirectory(String path) {
    return '使用备用目录: $path';
  }

  @override
  String pdfInfoSaved(String contentId, int partsCount, int pageCount) {
    return '$contentId PDF 信息已保存 ($partsCount 部分, $pageCount 页)';
  }

  @override
  String pdfExistsForContent(String contentId, String exists) {
    return '$contentId PDF 是否存在: $exists';
  }

  @override
  String pdfFoundFiles(String contentId, int count) {
    return '找到 $contentId 的 $count 个 PDF 文件';
  }

  @override
  String pdfDeletedFiles(String contentId, int count) {
    return '成功删除 $contentId 的 $count 个 PDF 文件';
  }

  @override
  String pdfTotalSize(String contentId, int sizeBytes) {
    return '$contentId PDF 总大小: $sizeBytes 字节';
  }

  @override
  String pdfCleanupStarted(int maxAge) {
    return '开始 PDF 清理，删除 $maxAge 天前的文件';
  }

  @override
  String pdfCleanupCompleted(int deletedCount) {
    return '清理完成，已删除 $deletedCount 个旧 PDF 文件';
  }

  @override
  String pdfStatistics(Object averageFilesPerContent, Object totalFiles,
      Object totalSizeFormatted, Object uniqueContents) {
    return 'PDF 统计 - $totalFiles 文件, 总大小 $totalSizeFormatted, $uniqueContents 个内容, 平均每个内容 $averageFilesPerContent 个文件';
  }

  @override
  String get historyCleanupMessages => '历史清理服务消息';

  @override
  String get historyCleanupServiceInitialized => '历史清理服务已初始化';

  @override
  String get historyCleanupServiceDisposed => '历史清理服务已销毁';

  @override
  String get autoCleanupDisabled => '自动清理历史已禁用';

  @override
  String cleanupServiceStarted(int intervalHours) {
    return '清理服务已启动，间隔 $intervalHours 小时';
  }

  @override
  String performingHistoryCleanup(String reason) {
    return '正在执行历史清理: $reason';
  }

  @override
  String historyCleanupCompleted(int clearedCount, String reason) {
    return '历史清理完成: 清除了 $clearedCount 条记录 ($reason)';
  }

  @override
  String get manualHistoryCleanup => '正在执行手动历史清理';

  @override
  String get updatedLastAppAccess => '已更新上次应用访问时间';

  @override
  String get updatedLastCleanupTime => '已更新上次清理时间';

  @override
  String intervalCleanup(int intervalHours) {
    return '定时清理 (${intervalHours}h)';
  }

  @override
  String inactivityCleanup(int inactivityDays) {
    return '闲置清理 ($inactivityDays 天)';
  }

  @override
  String maxAgeCleanup(int maxDays) {
    return '过期清理 ($maxDays 天)';
  }

  @override
  String get initialCleanupSetup => '初始清理设置';

  @override
  String shouldCleanupOldHistory(String shouldCleanup) {
    return '是否应清理旧历史: $shouldCleanup';
  }

  @override
  String get analyticsMessages => '统计服务消息';

  @override
  String analyticsServiceInitialized(String enabled) {
    return '统计服务已初始化 - 追踪 $enabled';
  }

  @override
  String get analyticsTrackingEnabled => '用户已启用统计追踪';

  @override
  String get analyticsTrackingDisabled => '用户已禁用统计追踪 - 数据已清除';

  @override
  String get analyticsDataCleared => '应用户请求已清除统计数据';

  @override
  String get analyticsServiceDisposed => '统计服务已销毁';

  @override
  String analyticsEventTracked(String eventType, String eventName) {
    return '📊 统计: $eventType - $eventName';
  }

  @override
  String get appStartedEvent => '应用启动事件已追踪';

  @override
  String sessionEndEvent(int minutes) {
    return '会话结束事件已追踪 ($minutes 分钟)';
  }

  @override
  String get analyticsEnabledEvent => '统计启用事件已追踪';

  @override
  String get analyticsDisabledEvent => '统计禁用事件已追踪';

  @override
  String screenViewEvent(String screenName) {
    return '屏幕浏览已追踪: $screenName';
  }

  @override
  String userActionEvent(String action) {
    return '用户操作已追踪: $action';
  }

  @override
  String performanceEvent(String operation, int durationMs) {
    return '性能已追踪: $operation (${durationMs}ms)';
  }

  @override
  String errorEvent(String errorType, String errorMessage) {
    return '错误已追踪: $errorType - $errorMessage';
  }

  @override
  String featureUsageEvent(String feature) {
    return '功能使用已追踪: $feature';
  }

  @override
  String readingSessionEvent(String contentId, int minutes, int pages) {
    return '阅读会话已追踪: $contentId ($minutes分, $pages 页)';
  }

  @override
  String get pages => '页数';

  @override
  String get offlineManagerMessages => '离线内容管理器消息';

  @override
  String offlineContentAvailable(String contentId, String available) {
    return '离线内容可用';
  }

  @override
  String offlineContentPath(String contentId, String path) {
    return '$contentId 离线内容路径: $path';
  }

  @override
  String foundExistingFiles(int count) {
    return '发现 $count 个已下载文件';
  }

  @override
  String offlineImageUrlsFound(String contentId, int count) {
    return '发现 $contentId 的 $count 个离线图片链接';
  }

  @override
  String offlineContentIdsFound(int count) {
    return '发现 $count 个离线内容 ID';
  }

  @override
  String searchingOfflineContent(String query) {
    return '正在搜索离线内容: $query';
  }

  @override
  String offlineContentMetadata(String contentId, String source) {
    return '$contentId 离线内容元数据: $source';
  }

  @override
  String offlineContentCreated(String contentId) {
    return '已为 $contentId 创建离线内容';
  }

  @override
  String offlineStorageUsage(int sizeBytes) {
    return '离线存储使用量: $sizeBytes 字节';
  }

  @override
  String get cleanupOrphanedFilesStarted => '开始清理孤立离线文件';

  @override
  String get cleanupOrphanedFilesCompleted => '孤立离线文件清理完成';

  @override
  String removedOrphanedDirectory(String path) {
    return '已移除孤立目录: $path';
  }

  @override
  String daysAgo(int count, String suffix) {
    return '$count$suffix前';
  }

  @override
  String hoursAgo(int count, String suffix) {
    return '$count$suffix前';
  }

  @override
  String minutesAgo(int count, String suffix) {
    return '$count$suffix前';
  }

  @override
  String get justNow => '刚刚';

  @override
  String get queryLabel => '查询';

  @override
  String get tagsLabel => '标签';

  @override
  String get excludeTagsLabel => '排除标签';

  @override
  String get groupsLabel => '社团';

  @override
  String get excludeGroupsLabel => '排除社团';

  @override
  String get charactersLabel => '角色';

  @override
  String get excludeCharactersLabel => '排除角色';

  @override
  String get parodiesLabel => '原作';

  @override
  String get excludeParodiesLabel => '排除原作';

  @override
  String get artistsLabel => '画师';

  @override
  String get excludeArtistsLabel => '排除画师';

  @override
  String get languageLabel => '语言';

  @override
  String get categoryLabel => '分类';

  @override
  String hours(int count) {
    return '$count 小时';
  }

  @override
  String minutes(int count) {
    return '$count分';
  }

  @override
  String seconds(int count) {
    return '$count秒';
  }

  @override
  String get loadingUserPreferences => '正在加载用户偏好设置';

  @override
  String get successfullyLoadedUserPreferences => '成功加载用户偏好设置';

  @override
  String invalidColumnsPortraitValue(int value) {
    return '无效的竖屏列数: $value';
  }

  @override
  String invalidColumnsLandscapeValue(int value) {
    return '无效的横屏列数: $value';
  }

  @override
  String get updatingSettingsViaPreferencesService =>
      '通过 PreferencesService 更新设置';

  @override
  String get successfullyUpdatedSettings => '设置更新成功';

  @override
  String failedToUpdateSetting(String error) {
    return '设置更新失败: $error';
  }

  @override
  String get resettingAllSettingsToDefaults => '正在恢复所有默认设置';

  @override
  String get successfullyResetAllSettingsToDefaults => '已恢复所有默认设置';

  @override
  String failedToResetSettings(String error) {
    return '重置设置失败：$error';
  }

  @override
  String get settingsNotLoaded => '设置未加载';

  @override
  String get exportingSettings => '正在导出设置';

  @override
  String get successfullyExportedSettings => '设置导出成功';

  @override
  String failedToExportSettings(String error) {
    return '设置导出失败: $error';
  }

  @override
  String get importingSettings => '正在导入设置';

  @override
  String get successfullyImportedSettings => '设置导入成功';

  @override
  String failedToImportSettings(String error) {
    return '设置导入失败: $error';
  }

  @override
  String get unableToSyncSettings => '无法同步设置，更改仅保存在本地。';

  @override
  String get unableToSaveSettings => '无法保存设置，请检查设备存储。';

  @override
  String get failedToUpdateSettings => '设置更新失败，请重试。';

  @override
  String get loadingHistory => '正在加载历史...';

  @override
  String get noHistoryFound => '未找到历史记录';

  @override
  String loadedHistoryEntries(int count) {
    return '已加载 $count 条历史记录';
  }

  @override
  String failedToLoadHistory(String error) {
    return '历史记录加载失败: $error';
  }

  @override
  String loadingMoreHistory(int page) {
    return '正在加载更多历史 (第 $page 页)';
  }

  @override
  String loadedMoreHistoryEntries(int count, int total) {
    return '已加载另外 $count 条，共 $total 条';
  }

  @override
  String get refreshingHistory => '正在刷新历史';

  @override
  String refreshedHistoryWithEntries(int count) {
    return '历史已刷新，共 $count 条';
  }

  @override
  String failedToRefreshHistory(String error) {
    return '历史刷新失败: $error';
  }

  @override
  String get clearingAllHistory => '正在清空所有历史';

  @override
  String get allHistoryCleared => '所有历史已清空';

  @override
  String failedToClearHistory(String error) {
    return '清空历史失败: $error';
  }

  @override
  String removingHistoryItem(String contentId) {
    return '正在移除历史项: $contentId';
  }

  @override
  String removedHistoryItem(String contentId) {
    return '已移除历史项: $contentId';
  }

  @override
  String failedToRemoveHistoryItem(String error) {
    return '移除历史项失败: $error';
  }

  @override
  String get performingManualHistoryCleanup => '正在执行手动历史清理';

  @override
  String get manualCleanupCompleted => '手动清理完成';

  @override
  String failedToPerformCleanup(String error) {
    return '执行清理失败: $error';
  }

  @override
  String get updatingCleanupSettings => '正在更新清理设置';

  @override
  String get cleanupSettingsUpdated => '清理设置已更新';

  @override
  String addingContentToFavorites(String title) {
    return '正在添加到收藏: $title';
  }

  @override
  String successfullyAddedToFavorites(String title) {
    return '已成功添加到收藏: $title';
  }

  @override
  String contentNotInFavorites(String contentId) {
    return '内容 $contentId 不在收藏中，跳过移除';
  }

  @override
  String callingRemoveFromFavoritesUseCase(String params) {
    return '调用 removeFromFavoritesUseCase，参数: $params';
  }

  @override
  String get successfullyCalledRemoveFromFavoritesUseCase =>
      '成功调用 removeFromFavoritesUseCase';

  @override
  String updatingFavoritesListInState(String contentId) {
    return '更新状态中的收藏列表，移除内容 ID: $contentId';
  }

  @override
  String favoritesCountBeforeAfter(int before, int after) {
    return '收藏数量: 之前=$before, 之后=$after';
  }

  @override
  String get stateUpdatedSuccessfully => '状态更新成功';

  @override
  String successfullyRemovedFromFavorites(String contentId) {
    return '成功从收藏移除: $contentId';
  }

  @override
  String errorRemovingContentFromFavorites(String contentId, String error) {
    return '从收藏中移除内容 $contentId 失败: $error';
  }

  @override
  String removingFavoritesInBatch(int count) {
    return '批量移除 $count 个收藏';
  }

  @override
  String successfullyRemovedFavoritesInBatch(int count) {
    return '成功批量移除 $count 个收藏';
  }

  @override
  String searchingFavoritesWithQuery(String query) {
    return '正在搜索收藏: $query';
  }

  @override
  String foundFavoritesMatchingQuery(int count) {
    return '找到 $count 个匹配的收藏';
  }

  @override
  String get clearingFavoritesSearch => '正在清除收藏搜索';

  @override
  String get exportingFavoritesData => '正在导出收藏数据';

  @override
  String successfullyExportedFavorites(int count) {
    return '成功导出 $count 个收藏';
  }

  @override
  String get importingFavoritesData => '正在导入收藏数据';

  @override
  String successfullyImportedFavorites(int count) {
    return '成功导入 $count 个收藏';
  }

  @override
  String failedToImportFavorite(String error) {
    return '导入收藏失败: $error';
  }

  @override
  String get retryingFavoritesLoading => '正在重新加载收藏';

  @override
  String get refreshingFavorites => '正在刷新收藏';

  @override
  String failedToLoadFavorites(String error) {
    return '加载收藏失败: $error';
  }

  @override
  String failedToInitializeDownloadManager(String error) {
    return '初始化下载管理器失败: $error';
  }

  @override
  String get waitingForWifiConnection => '等待 Wi-Fi 连接';

  @override
  String failedToQueueDownload(String error) {
    return '下载入队失败: $error';
  }

  @override
  String retryingDownload(int current, int total) {
    return '正在重试... ($current/$total)';
  }

  @override
  String get downloadCancelledByUser => '用户已取消下载';

  @override
  String get pausingAllDownloads => '正在暂停所有下载';

  @override
  String get resumingAllDownloads => '正在继续所有下载';

  @override
  String get cancellingAllDownloads => '正在取消所有下载';

  @override
  String get clearingCompletedDownloads => '正在清除已完成的下载';

  @override
  String failedToQueueRangeDownload(String error) {
    return '范围下载入队失败: $error';
  }

  @override
  String failedToPauseDownload(String error) {
    return '暂停下载失败: $error';
  }

  @override
  String failedToCancelDownload(String error) {
    return '取消下载失败: $error';
  }

  @override
  String failedToRetryDownload(String error) {
    return '重试下载失败: $error';
  }

  @override
  String failedToResumeDownload(String error) {
    return '继续下载失败: $error';
  }

  @override
  String failedToRemoveDownload(String error) {
    return '移除下载失败: $error';
  }

  @override
  String failedToRefreshDownloads(String error) {
    return '刷新下载失败: $error';
  }

  @override
  String failedToUpdateDownloadSettings(String error) {
    return '更新下载设置失败: $error';
  }

  @override
  String failedToPauseAllDownloads(String error) {
    return '暂停所有下载失败: $error';
  }

  @override
  String failedToResumeAllDownloads(String error) {
    return '继续所有下载失败: $error';
  }

  @override
  String failedToCancelAllDownloads(String error) {
    return '取消所有下载失败: $error';
  }

  @override
  String failedToClearCompletedDownloads(String error) {
    return '清除已完成下载失败: $error';
  }

  @override
  String get downloadNotCompletedYet => '下载尚未完成';

  @override
  String get noImagesFoundForConversion => '未找到可转换的图片';

  @override
  String storageCleanupCompleted(int cleanedFiles, String freedSpace) {
    return '存储清理完成。清理了 $cleanedFiles 个目录，释放了 $freedSpace MB';
  }

  @override
  String storageCleanupComplete(int cleanedFiles, String freedSpace) {
    return '存储清理完成: 清理了 $cleanedFiles 个项目，释放了 $freedSpace MB';
  }

  @override
  String storageCleanupFailed(String error) {
    return '存储清理失败: $error';
  }

  @override
  String exportDownloadsComplete(String fileName) {
    return '导出完成: 下载已导出到 $fileName';
  }

  @override
  String exportFailed(String error) {
    return '导出失败: $error';
  }

  @override
  String failedToDeleteDirectory(String path, String error) {
    return '删除目录失败: $path，错误: $error';
  }

  @override
  String failedToDeleteTempFile(String path, String error) {
    return '删除临时文件失败: $path，错误: $error';
  }

  @override
  String downloadDirectoryNotFound(String path) {
    return '未找到下载目录: $path';
  }

  @override
  String cannotOpenIncompleteDownload(String contentId) {
    return '无法打开 - 下载未完成或 $contentId 路径丢失';
  }

  @override
  String allStrategiesFailedToOpenDownload(String contentId) {
    return '所有策略均无法打开 $contentId 的已下载内容';
  }

  @override
  String failedToSaveProgressToDatabase(String error) {
    return '保存进度到数据库失败: $error';
  }

  @override
  String failedToUpdatePauseNotification(String error) {
    return '更新暂停通知失败: $error';
  }

  @override
  String failedToUpdateResumeNotification(String error) {
    return '更新继续通知失败: $error';
  }

  @override
  String failedToUpdateNotificationProgress(String error) {
    return '更新通知进度失败: $error';
  }

  @override
  String errorCalculatingDirectorySize(String error) {
    return '计算目录大小出错: $error';
  }

  @override
  String errorCleaningTempFiles(String path, String error) {
    return '清理临时文件出错: $path，错误: $error';
  }

  @override
  String errorDetectingDownloadsDirectory(String error) {
    return '检测下载目录出错: $error';
  }

  @override
  String usingEmergencyFallbackDirectory(String path) {
    return '使用紧急备用目录: $path';
  }

  @override
  String get errorDuringStorageCleanup => '存储清理过程中出错';

  @override
  String get errorDuringExport => '导出过程中出错';

  @override
  String errorDuringPdfConversion(String contentId) {
    return '$contentId PDF 转换过程中出错';
  }

  @override
  String errorRetryingPdfConversion(String error) {
    return '重试 PDF 转换出错: $error';
  }

  @override
  String errorOpeningDownloadedContent(String error) {
    return '打开已下载内容出错: $error';
  }

  @override
  String get importBackupFolder => '导入备份文件夹';

  @override
  String get importBackupFolderDescription => '请输入包含 nhasix 内容文件夹的备份路径:';

  @override
  String get scanningBackupFolder => '正在扫描备份文件夹...';

  @override
  String backupContentFound(int count) {
    return '发现 $count 个备份项目';
  }

  @override
  String get noBackupContentFound => '备份文件夹中未找到有效内容';

  @override
  String errorScanningBackup(String error) {
    return '扫描备份出错: $error';
  }

  @override
  String get themeDescription => '应用界面颜色主题。';

  @override
  String get imageQualityDescription => '下载图片质量。';

  @override
  String get gridColumnsDescription => '竖屏网格列数。';

  @override
  String get gridPreview => '网格预览';

  @override
  String get autoCleanupDescription => '管理阅读历史的自动清理以释放存储空间。';

  @override
  String get testCacheClearing => '测试应用更新缓存清理';

  @override
  String get testCacheClearingDescription => '模拟应用更新并测试缓存清理行为。';

  @override
  String get forceClearCache => '强制清除所有缓存';

  @override
  String get forceClearCacheDescription => '手动清除所有图片缓存。';

  @override
  String get runTest => '运行测试';

  @override
  String get clearCacheButton => '清除缓存';

  @override
  String get disguiseModeDescription => '启动器显示方式以保护隐私。';

  @override
  String get applyingDisguiseMode => '正在应用伪装模式更改...';

  @override
  String get disguiseDefault => '默认';

  @override
  String get disguiseCalculator => '计算器';

  @override
  String get disguiseNotes => '笔记';

  @override
  String get disguiseWeather => '天气';

  @override
  String get storagePermissionScan => '扫描备份文件夹需要存储权限';

  @override
  String get exportingLibrary => '正在导出资料库';

  @override
  String get libraryExportSuccess => '资料库导出成功！';

  @override
  String get browseDownloads => '浏览下载';

  @override
  String deletingContent(String title) {
    return '正在删除 $title...';
  }

  @override
  String contentDeletedFreed(String title, String size) {
    return '$title 已删除，释放了 $size MB';
  }

  @override
  String get size => '大小';

  @override
  String failedToDeleteContent(String title) {
    return '删除 $title 失败';
  }

  @override
  String errorGeneric(String error) {
    return '错误: $error';
  }

  @override
  String get contentDeleted => '内容已删除';

  @override
  String get cacheManagementDebug => '🚀 缓存管理（调试）';

  @override
  String get convertToPdf => '转换为 PDF';

  @override
  String get convertingToPdf => '正在转换为 PDF...';

  @override
  String pdfConversionFailedWithError(String title, String error) {
    return '$title PDF 转换失败: $error';
  }

  @override
  String get syncStarted => '正在同步备份...';

  @override
  String get syncStartedMessage => '正在扫描并导入离线内容';

  @override
  String syncInProgress(int percent) {
    return '正在同步备份 ($percent%)';
  }

  @override
  String syncProgressMessage(int processed, int total) {
    return '已处理 $processed/$total 项';
  }

  @override
  String get total => '总计';

  @override
  String get syncCompleted => '同步完成';

  @override
  String syncCompletedMessage(int synced, int updated) {
    return '已导入: $synced，已更新: $updated';
  }

  @override
  String syncResult(int synced, int updated) {
    return '同步结果: 导入 $synced 个，更新 $updated 个';
  }

  @override
  String get storageSection => '存储位置';

  @override
  String get storageLocation => '自定义下载文件夹';

  @override
  String get defaultStorage => '默认（内部存储）';

  @override
  String get storageDescription => '选择保存下载的文件夹';

  @override
  String get downloadDirectory => '下载目录';

  @override
  String get changeDirectory => '更改目录';

  @override
  String get downloadDirectoryUpdated => '下载目录已更新';

  @override
  String get useDefaultInternalStorage => '使用默认内部存储位置';

  @override
  String get confirmResetStorageDirectory => '将下载目录重置为默认内部存储？';

  @override
  String get downloadDirectoryReset => '下载目录已重置为默认';

  @override
  String get backupNotFound => '未找到备份';

  @override
  String get backupNotFoundMessage =>
      '在默认位置未找到\'nhasix\'备份文件夹。您想选择包含备份的自定义文件夹吗？';

  @override
  String get selectFolder => '文件夹';

  @override
  String get premiumFeature => '高级功能';

  @override
  String get commentsMaintenance => '评论正在维护中';

  @override
  String get estimatedRecovery => '预计恢复时间';

  @override
  String get fullColor => '全彩';

  @override
  String downloadBlocInitializedWithDownloads(int count) {
    return 'DownloadBloc：已初始化，共 $count 个下载';
  }

  @override
  String get downloadBlocProgressStreamSubscriptionInitialized =>
      'DownloadBloc：进度流订阅已初始化';

  @override
  String get downloadBlocNotificationCallbacksConfigured =>
      'DownloadBloc：通知回调已配置';

  @override
  String downloadBlocReceivedProgressUpdate(String update) {
    return 'DownloadBloc：收到进度更新：$update';
  }

  @override
  String downloadBlocReceivedCompletionEvent(String contentId) {
    return 'DownloadBloc：收到 $contentId 的完成事件';
  }

  @override
  String downloadBlocProgressStreamError(String error) {
    return 'DownloadBloc：进度流错误：$error';
  }

  @override
  String notificationActionPauseRequested(String contentId) {
    return 'NotificationAction：请求暂停 $contentId';
  }

  @override
  String notificationActionResumeRequested(String contentId) {
    return 'NotificationAction：请求继续 $contentId';
  }

  @override
  String notificationActionCancelRequested(String contentId) {
    return 'NotificationAction：请求取消 $contentId';
  }

  @override
  String notificationActionRetryRequested(String contentId) {
    return 'NotificationAction：请求重试 $contentId';
  }

  @override
  String notificationActionPdfRetryRequested(String contentId) {
    return 'NotificationAction：请求重试 PDF $contentId';
  }

  @override
  String notificationActionOpenDownloadRequested(String contentId) {
    return 'NotificationAction：请求打开下载 $contentId';
  }

  @override
  String notificationActionNavigateToDownloadsRequested(String contentId) {
    return 'NotificationAction：请求跳转到下载页面 $contentId';
  }

  @override
  String get downloadBlocErrorInitializing => 'DownloadBloc：初始化时发生错误';

  @override
  String downloadBlocFailedToReadDownloadBlocState(String error) {
    return '读取 DownloadBloc 状态失败，回退到文件系统检查：$error';
  }

  @override
  String get sourceSelectorSelectSource => '来源';

  @override
  String get sourceSelectorDescription => '切换提供方以更改首页、详情、搜索和阅读数据来源。';

  @override
  String get sourceSelectorNoSourceSelected => '未选择来源';

  @override
  String get sourceSelectorActiveSource => '当前来源';

  @override
  String get sourceSelectorUnderMaintenance => '维护中';

  @override
  String get sourceSelectorCurrentlySelected => '当前已选择';

  @override
  String get sourceSelectorTapToSwitch => '点击切换';

  @override
  String get sourceSelectorSearchHint => '搜索来源';

  @override
  String get sourceSelectorNoResults => '没有匹配的来源';

  @override
  String get settingsCustomSourceTitle => '添加自定义来源';

  @override
  String get settingsCustomSourceSubtitle => '通过已签名清单 URL 或 ZIP 包安装来源。';

  @override
  String get settingsAddViaLink => '通过链接添加';

  @override
  String get settingsImportZip => '导入 ZIP';

  @override
  String get sourceImportLinkDialogTitle => '通过链接安装来源';

  @override
  String get sourceImportConfigUrlLabel => '清单 URL';

  @override
  String get sourceImportConfigUrlHint =>
      'https://example.com/source-manifest.json';

  @override
  String get sourceImportInstallingFromLink => '正在从链接安装来源...';

  @override
  String get sourceImportInstallingFromZip => '正在从 ZIP 导入来源...';

  @override
  String get sourceImportPreviewTitle => '来源安装预览';

  @override
  String get sourceImportPreviewSourceId => '来源 ID';

  @override
  String get sourceImportPreviewVersion => '版本';

  @override
  String get sourceImportPreviewDisplayName => '显示名称';

  @override
  String get sourceImportPreviewVerified => '完整性';

  @override
  String get sourceImportPreviewVerifiedYes => '已验证';

  @override
  String get sourceImportPreviewVerifiedNo => '未验证';

  @override
  String get sourceImportConfirmInstall => '安装';

  @override
  String get sourceImportManifestInvalid => '来源清单格式无效。';

  @override
  String get sourceImportConfigEmpty => '下载的来源配置为空。';

  @override
  String get sourceImportZipManifestRequired => 'ZIP 必须包含 manifest.json。';

  @override
  String get sourceImportChecksumMismatch => '来源校验和验证失败。';

  @override
  String get sourceImportSourceMismatch => '清单与配置中的来源 ID 不匹配。';

  @override
  String sourceImportInstalledFromLink(String sourceId) {
    return '已通过链接安装 $sourceId';
  }

  @override
  String sourceImportInstalledFromZip(String sourceId) {
    return '已通过 ZIP 安装 $sourceId';
  }

  @override
  String sourceImportFailedFromLink(String error) {
    return '通过链接安装来源失败：$error';
  }

  @override
  String sourceImportFailedFromZip(String error) {
    return '导入 ZIP 来源失败：$error';
  }

  @override
  String get aboutTitle => '关于';

  @override
  String get appIsUpToDate => '应用已是最新版本！';

  @override
  String checkFailedMessage(String message) {
    return '检查失败：$message';
  }

  @override
  String get updatesSection => '更新';

  @override
  String get communityAndInfo => '社区 & 信息';

  @override
  String get githubRepository => 'GitHub 仓库';

  @override
  String get viewSourceCodeContribute => '查看源代码和贡献';

  @override
  String get openSourceLicenses => '开源许可证';

  @override
  String get librariesUsedInApp => '本应用使用的库';

  @override
  String get builtWith => '技术栈';

  @override
  String get madeWithLoveBy => '由 Shirokun20 用 ❤️ 制作';

  @override
  String get allRightsReserved => '© 2025 保留所有权利';

  @override
  String get appUpdates => '应用更新';

  @override
  String get checkForUpdates => '检查更新';

  @override
  String get checking => '检查中...';

  @override
  String get updateAvailable => '有更新可用！';

  @override
  String get upToDate => '已是最新';

  @override
  String get checkFailed => '检查失败';

  @override
  String couldNotLaunchUrl(String url) {
    return '无法打开 $url';
  }

  @override
  String get solveCaptchaTitle => '完成 CAPTCHA';

  @override
  String get reloadChallenge => '重新加载验证';

  @override
  String get loginToCrotpedia => '登录到 Crotpedia';

  @override
  String syncedAsUser(String username) {
    return '已同步为 $username';
  }

  @override
  String loggedInAsUser(String username) {
    return '已登录为 $username';
  }

  @override
  String get logout => '退出登录';

  @override
  String get loginViaSecureBrowser => '通过安全浏览器登录';

  @override
  String get loginIncomplete => '登录未完成，请重试。';

  @override
  String loginFailedError(String error) {
    return '登录失败：$error';
  }

  @override
  String get doujinListTitle => '同人列表 (A-Z)';

  @override
  String get errorLoadingDoujinList => '加载同人列表出错';

  @override
  String get noDoujinsFound => '未找到同人作品';

  @override
  String get doujinListEmpty => '同人列表为空。';

  @override
  String get searchDoujinsHint => '搜索同人...';

  @override
  String cannotParseSlug(String url) {
    return '无法解析 URL 中的 slug：$url';
  }

  @override
  String errorParsingUrl(String url) {
    return '解析 URL 出错：$url';
  }

  @override
  String get checkAll => '检查全部';

  @override
  String get copyPath => '复制路径';

  @override
  String get createCollection => '创建合集';

  @override
  String daysAgoShort(Object days) {
    return '$days天前';
  }

  @override
  String get deleteCollection => '删除合集';

  @override
  String deleteCollectionConfirm(Object name) {
    return '删除\"$name\"？项目收藏仍保留，仅移除收藏集分组。';
  }

  @override
  String deleteItems(Object count) {
    return '删除$count项？';
  }

  @override
  String deletingItems(Object count) {
    return '正在删除$count项...';
  }

  @override
  String get doujinList => '同人列表';

  @override
  String get downloadGalleryRange => '选择画廊范围';

  @override
  String get downloadGalleryRangeDesc => '使用原始画廊页码。';

  @override
  String get downloadGalleryWide => '全画廊范围';

  @override
  String get downloadGalleryWideDesc => '使用原始 E-Hentai 画廊页码。';

  @override
  String get downloadThisPart => '下载此部分';

  @override
  String get downloadThisPartDesc => '仅下载所选部分。';

  @override
  String get downloadWholeGallery => '下载整个画廊';

  @override
  String get downloadWholeGalleryDesc => '按画廊顺序排队所有部分。';

  @override
  String get ehentaiOnly => '仅适用于 E-Hentai 画廊。';

  @override
  String get ehentaiOnlyDesc => '画廊下载选项（全系列和范围）仅在 E-Hentai 上可用。';

  @override
  String get ehentaiOnlyTitle => '仅限 E-Hentai';

  @override
  String get genres => '类型';

  @override
  String get genreOptionsFailed => '类型选项失败';

  @override
  String get gitHubRaw => 'GitHub raw';

  @override
  String get hide => '隐藏';

  @override
  String get liveTags => '实时标签';

  @override
  String get loadingGenreOptions => '加载类型选项';

  @override
  String monthsAgo(int months) {
    return '$months个月前';
  }

  @override
  String get openInExplorer => '在文件管理器中打开';

  @override
  String pageFailedDownload(Object page) {
    return '第$page页下载失败';
  }

  @override
  String pageInputPage(Object page) {
    return '第$page页';
  }

  @override
  String get pathCopied => '路径已复制到剪贴板';

  @override
  String get pathsCopied => '路径已复制';

  @override
  String get reloadSearchUI => '重新加载搜索界面';

  @override
  String get reloadingSearchFilters => '重新加载搜索筛选器';

  @override
  String get remoteSource => '远程源';

  @override
  String removeOfflineChapters(Object count) {
    return '移除$count个离线章节？';
  }

  @override
  String get requestList => '请求列表';

  @override
  String get retryFetch => '重试获取';

  @override
  String get selectMode => '选择模式';

  @override
  String get showAvailability => '查看可用性';

  @override
  String showingFirstChapters(Object count) {
    return '显示前$count章。前往详情页并使用\"查看全部\"以查看更多。';
  }

  @override
  String get sortAZ => 'A - Z';

  @override
  String get sortDirectionAZ => 'A - Z';

  @override
  String get sortDirectionZA => 'Z - A';

  @override
  String get sortNewToOld => '从新到旧';

  @override
  String get sortNewest => '最新';

  @override
  String get sortOldToNew => '从旧到新';

  @override
  String get sortOldest => '最旧';

  @override
  String get sortOptions => '排序选项';

  @override
  String get sortPagesAsc => '页数 (升序)';

  @override
  String get sortPagesDesc => '页数 (降序)';

  @override
  String get sortZA => 'Z - A';

  @override
  String get specialSeriesDownload => '特殊系列下载';

  @override
  String get starOnGitHub => '在 GitHub 上标星';

  @override
  String get statusError => '错误';

  @override
  String get statusIdle => '空闲';

  @override
  String get statusLoading => '加载中';

  @override
  String get statusLocal => '本地';

  @override
  String get today => '今天';

  @override
  String weeksAgo(int weeks) {
    return '$weeks周前';
  }

  @override
  String get yesterday => '昨天';

  @override
  String get noGenreListLoaded => '远程类型列表尚未加载。重新加载以从源同步。';

  @override
  String get genreListTitle => '分类列表';

  @override
  String get errorLoadingGenres => '加载分类出错';

  @override
  String get noGenresFound => '未找到分类';

  @override
  String get noGenresAvailable => '暂无可用分类。';

  @override
  String get projectRequests => '项目请求';

  @override
  String get errorLoadingRequests => '加载请求出错';

  @override
  String get noRequestsFound => '未找到请求';

  @override
  String get noProjectRequests => '暂无项目请求。';

  @override
  String get manageCollections => '管理收藏夹';

  @override
  String get addToFavoritesFirst => '请先添加到收藏';

  @override
  String get favoriteOffline => '离线收藏';

  @override
  String get favoriteOnline => '在线收藏';

  @override
  String get favoriteBoth => '同时收藏';

  @override
  String get unsupportedGalleryId => '不支持的在线收藏画廊 ID。';

  @override
  String get addToFavoritesManageCollections => '请先添加到收藏以管理收藏夹';

  @override
  String get loginRequiredAction => '此操作需要先登录';

  @override
  String get newCollection => '新建收藏夹';

  @override
  String get collectionName => '收藏夹名称';

  @override
  String failedToCreateCollection(String error) {
    return '创建收藏夹失败：$error';
  }

  @override
  String get clearSelection => '清除选择';

  @override
  String get refreshingDownloads => '正在刷新下载...';

  @override
  String get refresh => '刷新';

  @override
  String failedToSaveCollection(String error) {
    return '保存收藏夹失败：$error';
  }

  @override
  String get renameCollection => '重命名合集';

  @override
  String get pressBackToExit => '再按一次返回退出';

  @override
  String get backToDetail => '返回详情';

  @override
  String get backToPreviousPage => '返回上一页';

  @override
  String failedToOpenPdf(String error) {
    return '打开 PDF 失败：$error';
  }

  @override
  String get noChaptersAvailable => '没有可用章节';

  @override
  String failedToApplySearch(String error) {
    return '应用搜索失败：$error';
  }

  @override
  String get addTag => '添加标签';

  @override
  String includeCountLabel(int count) {
    return '包含 $count';
  }

  @override
  String excludeCountLabel(int count) {
    return '排除 $count';
  }

  @override
  String get searchTagsHint => '搜索标签...';

  @override
  String applyWithCounts(int include, int exclude) {
    return '应用 ($include / $exclude)';
  }

  @override
  String applyWithCount(int count) {
    return '应用 ($count)';
  }

  @override
  String get searchByTitleHint => '按标题、ID 或关键词搜索...';

  @override
  String get pagesLabel2 => '页数';

  @override
  String get favoritesGte => '收藏 ≥';

  @override
  String get manage => '管理';

  @override
  String get local => '本地';

  @override
  String get rules => '规则';

  @override
  String failedToSave(String error) {
    return '保存失败：$error';
  }

  @override
  String failedToDelete(String error) {
    return '删除失败：$error';
  }

  @override
  String get searchExampleHint => '浪漫, 画师:示例, 12345';

  @override
  String get refreshOnline => '在线刷新';

  @override
  String get addRules => '添加规则';

  @override
  String get pickFromTags => '从标签';

  @override
  String get done => '完成';

  @override
  String get uninstallSource => '卸载来源';

  @override
  String get uninstallSourceTitle => '卸载来源';

  @override
  String get uninstall => '卸载';

  @override
  String failedToUninstall(String sourceId, String error) {
    return '卸载 \"$sourceId\" 失败：$error';
  }

  @override
  String get chooseOneSource => '安装来源';

  @override
  String get chooseMultipleSources => '安装来源';

  @override
  String installSelectedCount(int count) {
    return '安装所选 ($count)';
  }

  @override
  String get installSelected => '安装所选';

  @override
  String get offlineModeLabel => '离线模式';

  @override
  String get descriptionLabel => '描述';

  @override
  String get aliasesLabel => '别名';

  @override
  String get searchContentWithTag => '搜索带有此标签的内容';

  @override
  String get backToFilters => '返回筛选';

  @override
  String get dnsSettings => 'DNS 设置';

  @override
  String get resetToDefaults => '恢复默认';

  @override
  String get enableDnsOverHttps => '启用 DNS-over-HTTPS';

  @override
  String get dnsServerIp => 'DNS 服务器 IP';

  @override
  String get primaryDnsAddress => '主 DNS 服务器地址';

  @override
  String get dnsOverHttpsUrl => 'DNS-over-HTTPS 端点 URL';

  @override
  String get resetDnsSettings => '重置 DNS 设置';

  @override
  String get syncRefresh => '同步/刷新';

  @override
  String get importFromBackup => '从备份导入';

  @override
  String get importZipFile => '导入 ZIP 文件';

  @override
  String get exportLibrary => '导出资料库';

  @override
  String get loginRequired => '需要登录';

  @override
  String get openPdf => '打开 PDF';

  @override
  String get maybeLater => '以后再说';

  @override
  String get noContentAtMoment => '暂无可用内容。';

  @override
  String get refreshingContentMsg => '正在刷新内容...';

  @override
  String get retryingMsg => '正在重试...';

  @override
  String get clearingSearchMsg => '正在清除搜索...';

  @override
  String failedToClearSearch(String error) {
    return '清除搜索结果失败：$error';
  }

  @override
  String get searchingContentMsg => '正在搜索内容...';

  @override
  String get noContentMatchingSearch => '未找到符合搜索条件的内容。';

  @override
  String get loadingPopularContent => '正在加载热门内容...';

  @override
  String get noPopularContent => '暂无热门内容。';

  @override
  String get loadingContentByTag => '正在按标签加载内容...';

  @override
  String get noContentForTag => '未找到此标签的内容。';

  @override
  String loadingPageNum(int page) {
    return '正在加载第 $page 页...';
  }

  @override
  String get noContentOnPage => '此页面未找到内容。';

  @override
  String get noDownloadableImages => '此内容没有可下载的图片。';

  @override
  String failedToStartDownload(String error) {
    return '启动下载失败：$error';
  }

  @override
  String get bulkDeleteCompleted => '批量删除完成';

  @override
  String get bulkDeletePartial => '批量删除部分完成';

  @override
  String get failedToInitSearch => '搜索初始化失败';

  @override
  String get searchingMsg => '搜索中...';

  @override
  String noResultsForQuery(String query) {
    return '没有找到 \"$query\" 的结果';
  }

  @override
  String get searchingWithFiltersMsg => '正在使用筛选条件搜索...';

  @override
  String get noResultsWithFilters => '当前筛选条件下未找到结果';

  @override
  String invalidFilterErrors(String errors) {
    return '无效的筛选器：$errors';
  }

  @override
  String get noResultsGeneric => '未找到结果';

  @override
  String get loadingConfigMsg => '正在加载配置...';

  @override
  String get initTagsDbMsg => '正在初始化标签数据库...';

  @override
  String downloadingTagsMsg(String source) {
    return '正在下载 $source 的标签...';
  }

  @override
  String initFailedMsg(String error) {
    return '初始化失败：$error';
  }

  @override
  String get initBypassMsg => '正在初始化绕过系统...';

  @override
  String get connectingToSite => '正在连接 nhentai.net...';

  @override
  String get connectedSuccess => '成功连接到 nhentai.net';

  @override
  String get failedToConnect => '连接 nhentai.net 失败，请重试。';

  @override
  String failedInitBypass(String error) {
    return '初始化绕过系统失败：$error';
  }

  @override
  String get bypassFailed => '绕过验证失败，请重试。';

  @override
  String get offlineBypassFailed => '离线模式（绕过失败）';

  @override
  String errorBypassResult(String error) {
    return '处理绕过结果出错：$error';
  }

  @override
  String get readyOfflineLimited => '就绪（离线模式 - 受限）';

  @override
  String get downloadingInitConfig => '正在下载初始配置...';

  @override
  String get readyOffline => '就绪（离线模式）';

  @override
  String get connectingMsg => '连接中...';

  @override
  String failedLoadOffline(String error) {
    return '加载离线内容失败：$error';
  }

  @override
  String get noInternetCheckOffline => '无网络连接，正在检查离线内容...';

  @override
  String foundOfflineItems(int count) {
    return '找到 $count 个离线项目，继续中...';
  }

  @override
  String get noInternetNoOffline => '无网络连接且没有可用的离线内容。';

  @override
  String unableCheckOffline(String error) {
    return '无法检查离线内容。$error';
  }

  @override
  String get offlineLimitedFeatures => '离线模式（功能受限）';

  @override
  String get readyOfflineLimitedFeatures => '就绪（离线模式 - 功能受限）';

  @override
  String failedEnableOffline(String error) {
    return '启用离线模式失败：$error';
  }

  @override
  String failedCheckOffline(String error) {
    return '检查离线内容失败：$error';
  }

  @override
  String failedOpenChapter(String message) {
    return '打开章节失败：$message';
  }

  @override
  String externalChapterBadge(String host) {
    return '外部 • $host';
  }

  @override
  String get externalChapterHint => '所有章节均可在官方网站上查看';

  @override
  String get externalChapterOpenFailed => '无法打开外部链接';

  @override
  String get externalChapterDownloadBlocked => '外部章节无法下载，请在浏览器中打开';

  @override
  String failedInitFilterData(String error) {
    return '初始化筛选数据失败：$error';
  }

  @override
  String failedSwitchFilterType(String error) {
    return '切换筛选类型失败：$error';
  }

  @override
  String get failedMonitorNetwork => '监控网络连接失败';

  @override
  String failedInitNetwork(String error) {
    return '初始化网络监控失败：$error';
  }

  @override
  String failedUpdateConnection(String error) {
    return '更新连接状态失败：$error';
  }

  @override
  String failedCheckConnectivity(String error) {
    return '检查连接性失败：$error';
  }

  @override
  String failedSearchOffline(String error) {
    return '搜索离线内容失败：$error';
  }

  @override
  String get failedLoadOfflineContent => '加载离线内容失败';

  @override
  String failedScanBackup(String error) {
    return '扫描备份文件夹失败：$error';
  }

  @override
  String failedLoadContentError(String error) {
    return '加载内容失败：$error';
  }

  @override
  String get chapterNavNotAvailable => '章节导航不可用';

  @override
  String get unknownChapter => '未知章节';

  @override
  String get failedLoadChapterImages => '加载章节图片失败';

  @override
  String failedLoadChapter(String error) {
    return '加载章节失败：$error';
  }

  @override
  String importFailedError(String error) {
    return '导入失败：$error';
  }

  @override
  String errorImportingZip(String error) {
    return '导入 ZIP 出错：$error';
  }

  @override
  String get error => '错误';

  @override
  String get lightThemeDesc => '明亮色彩的浅色主题';

  @override
  String get darkThemeDesc => '柔和色彩的深色主题';

  @override
  String get amoledThemeDesc => '适用于 AMOLED 屏幕的纯黑主题';

  @override
  String get systemThemeDesc => '跟随系统主题设置';

  @override
  String nItems(int count) {
    return '$count 项';
  }

  @override
  String nPages(int count) {
    return '$count 页';
  }

  @override
  String nGalleries(int count) {
    return '$count 个画廊';
  }

  @override
  String sourceUninstalled(String sourceId) {
    return '源 \"$sourceId\" 已卸载。';
  }

  @override
  String selectedSourcesCount(int count) {
    return '已选择源：$count';
  }

  @override
  String timeoutMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get dohUrlOptional => 'DoH URL（可选）';

  @override
  String get dnsEncryptedDescription => '使用加密 DNS 提升隐私并绕过审查';

  @override
  String get usingSystemDns => '使用系统默认 DNS 解析器';

  @override
  String get dnsProvider => 'DNS 提供商';

  @override
  String get customConfiguration => '自定义配置';

  @override
  String get aboutDoh => '关于 DNS-over-HTTPS';

  @override
  String get dohDescription => 'DNS-over-HTTPS 加密 DNS 查询以防止监控和绕过审查。';

  @override
  String get dnsQueriesEncrypted => '所有 DNS 查询通过 HTTPS 加密';

  @override
  String get enhancedPrivacy => '增强的隐私和安全性';

  @override
  String get resetDnsConfirmation => '这将把 DNS 设置重置为系统默认值。是否继续？';

  @override
  String get appDns => '应用 DNS';

  @override
  String get devicePrivateDns => '设备私有 DNS';

  @override
  String get dnsModeOn => '开';

  @override
  String get dnsModeOff => '关';

  @override
  String get dnsSystemDns => '系统 DNS';

  @override
  String dnsPrivateDnsStrict(Object hostname) {
    return '严格模式 ($hostname)';
  }

  @override
  String get dnsPrivateDnsOpportunistic => '机会模式';

  @override
  String get dnsPrivateDnsRequirements => '需要 Android 10+';

  @override
  String get dnsPrivateDnsOff => '关闭';

  @override
  String get dnsPrivateDnsGuidance =>
      '在 Android 设置中启用私有 DNS 以加密您设备上的所有 DNS 查询。';

  @override
  String get dnsPrivateDnsRequiresAndroid10 => '设备私有 DNS 状态需要 Android 10+。';

  @override
  String get dnsPrivateDnsCannotAutoSet => 'Kuron 无法在标准安装中自动设置设备范围的私有 DNS。';

  @override
  String get openDnsSettings => '打开 DNS 设置';

  @override
  String get collections => '合集';

  @override
  String get collectionsUpdatedSuccessfully => '合集更新成功';

  @override
  String get blacklistMatchWarning => '此画廊匹配黑名单规则。封面/卡片可在列表视图中模糊显示。';

  @override
  String get chapterCompleted => '章节已完成';

  @override
  String continueFromPage(int page) {
    return '从第 $page 页继续';
  }

  @override
  String get loginRequiredForContent => '您需要登录 Crotpedia 才能查看此内容。';

  @override
  String commentsCount(int count) {
    return '评论 ($count)';
  }

  @override
  String get postComment => '发布评论';

  @override
  String get commentInputHint => '写下评论，支持 Markdown。10-1000 个字符。';

  @override
  String get commentPosted => '评论已发布';

  @override
  String get commentLengthRequirement => '评论必须为 10-1000 个字符。';

  @override
  String get noCommentsYet => '暂无评论';

  @override
  String get failedToLoadComments => '加载评论失败';

  @override
  String nSelected(int count) {
    return '已选择 $count 项';
  }

  @override
  String get bulkDelete => '批量删除';

  @override
  String bulkDeleteConfirmation(int count) {
    return '确定要删除 $count 个下载吗？';
  }

  @override
  String exportedFavoritesTo(int count, String path) {
    return '仅导出收藏（$count 项）到：\n$path';
  }

  @override
  String get failedToSaveExportFile => '保存导出文件失败';

  @override
  String get importFavorites => '导入收藏';

  @override
  String importFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String get noOnlineFavoritesSource => '没有可用的在线收藏源。';

  @override
  String collectionWithCount(String name, int count) {
    return '$name ($count)';
  }

  @override
  String get newLabel => '新建';

  @override
  String get tryDifferentSearchTerm => '尝试不同的搜索词';

  @override
  String get apply => '应用';

  @override
  String nItemsInHistory(int count) {
    return '历史记录中有 $count 项';
  }

  @override
  String pageProgress(int lastPage, int totalPages) {
    return '$lastPage/$totalPages 页';
  }

  @override
  String get chapterComplete => '章节完成！';

  @override
  String get finishedReading => '阅读完成';

  @override
  String get chapterLabel => '章节';

  @override
  String get noChapterSelected => '未选择章节';

  @override
  String get preventScreenOff => '阅读时防止屏幕关闭';

  @override
  String get chapters => '章节列表';

  @override
  String get readerSettingsReset => '阅读器设置已重置为默认值。';

  @override
  String get tagInputTip => '提示：按 Enter 或 + 按钮添加标签。可以用逗号或换行输入多个标签。';

  @override
  String get loadingOptions => '加载选项中...';

  @override
  String get filterTags => '筛选标签';

  @override
  String get noOptionsAvailable => '此字段没有可用选项';

  @override
  String get failedLoadingOptions => '加载选项失败。请检查连接后重试。';

  @override
  String get noTagsFound => '未找到标签';

  @override
  String get previewQuery => '预览查询 (q)';

  @override
  String get showLess => '收起';

  @override
  String showAllCount(int count) {
    return '显示全部 ($count)';
  }

  @override
  String get advancedFilters => '高级筛选';

  @override
  String get min => '最小';

  @override
  String get max => '最大';

  @override
  String searchConfigUnavailable(String sourceId) {
    return '$sourceId 的搜索配置不可用';
  }

  @override
  String get checkInternetOrReload => '请检查您的网络连接或尝试重新加载应用。';

  @override
  String get tagBlacklist => '标签黑名单';

  @override
  String get blacklistDescription =>
      '这是仅限 nhentai 的功能。本地条目仅对 nhentai 离线生效，已登录的 nhentai 帐户还会拉取在线黑名单 ID。其他来源不受影响。';

  @override
  String onlineRuleDetailsCount(int count) {
    return '在线规则详情 ($count)';
  }

  @override
  String get noBlacklistRulesYet =>
      '暂无黑名单规则。添加标签名称如 romance、artist:foo 或数字标签 ID。';

  @override
  String activeCoverageDescription(int count) {
    return '已为 $count 个令牌启用活跃覆盖（本地 + 在线 ID）。此处隐藏以保持视图可读性。';
  }

  @override
  String get manageTagBlacklist => '管理标签黑名单';

  @override
  String get addTagRulesDescription =>
      '添加标签名称、类型规则如 artist:foo 或数字标签 ID。用逗号或换行分隔多个值。';

  @override
  String localRulesCount(int count) {
    return '本地规则 ($count)';
  }

  @override
  String onlineRulesMetadataCount(int count) {
    return '在线规则元数据 ($count)';
  }

  @override
  String get onlineRulesMetadata => '在线规则元数据';

  @override
  String activeCoverageCount(int count) {
    return '活跃覆盖 ($count)';
  }

  @override
  String nSourcesInstalled(int count) {
    return '已安装 $count 个源';
  }

  @override
  String removeSourceConfirmation(String sourceId) {
    return '从本地已安装源中移除 \"$sourceId\"？';
  }

  @override
  String installedSourcesFromZip(int count) {
    return '从 ZIP 安装了 $count 个源';
  }

  @override
  String get enhancedReadingExperience => '增强阅读体验';

  @override
  String get initializingApplication => '正在初始化应用...';

  @override
  String get offlineContentAvailableLabel => '离线内容可用';

  @override
  String get offlineModeEnabled => '已启用离线模式';

  @override
  String get confirmExit => '确定要退出吗？';

  @override
  String get resize => '调整大小';

  @override
  String get offlineFeaturesLimited => '部分功能受限。连接网络以获得完整访问权限。';

  @override
  String get downloadSettings => '下载设置';

  @override
  String get higherValuesBandwidth => '较高的值可能消耗更多带宽和设备资源';

  @override
  String get autoRetryFailed => '自动重试失败的下载';

  @override
  String get wifiOnlyDownload => '仅在连接 Wi-Fi 时下载';

  @override
  String get downloadTimeout => '下载超时';

  @override
  String get enableNotifications => '启用通知';

  @override
  String get showNotificationsProgress => '显示下载进度通知';

  @override
  String get failedToLoadImage => '加载图片失败';

  @override
  String get retrying => '正在重试...';

  @override
  String get readerRedownloadImage => '重新下载此页';

  @override
  String get readerRepairingImage => '正在修复图片...';

  @override
  String readerPageNotDownloaded(int pageNumber) {
    return '第 $pageNumber 页未下载';
  }

  @override
  String get readerPageSkippedDuringDownload => '此页在下载时被跳过（超时或错误）。点击下方立即下载。';

  @override
  String get readerPageDownloadSuccess => '下载成功';

  @override
  String get readerOpenSourcePage => '打开源页面';

  @override
  String get readerOpeningSourcePage => '正在打开源页面...';

  @override
  String readerImageRepairSuccess(int pageNumber) {
    return '第 $pageNumber 页已成功重新下载。';
  }

  @override
  String readerImageRepairHttpStatus(int pageNumber, int statusCode) {
    return '无法重新下载第 $pageNumber 页。服务器返回了 HTTP $statusCode。';
  }

  @override
  String readerImageRepairInvalidImage(int pageNumber) {
    return '无法重新下载第 $pageNumber 页，因为返回内容不是有效图片。';
  }

  @override
  String readerImageRepairUnavailable(int pageNumber) {
    return '无法从源站重新下载第 $pageNumber 页。';
  }

  @override
  String readerImageRepairFailed(int pageNumber) {
    return '重新下载第 $pageNumber 页失败。';
  }

  @override
  String pageAttempt(int pageNumber, int current, int max) {
    return '第 $pageNumber 页 • 第 $current/$max 次尝试';
  }

  @override
  String downloadingNItems(int count) {
    return '正在下载 $count 项';
  }

  @override
  String get noOfflineContent => '没有离线内容';

  @override
  String get howToGetStarted => '如何开始';

  @override
  String get loadingMore => '加载更多...';

  @override
  String get noImagesFound => '未找到图片';

  @override
  String get dontAskAgain => '不再询问';

  @override
  String pageOfTotal(int current, int total) {
    return '第 $current 页，共 $total 页';
  }

  @override
  String loadingPageNumber(int pageNumber) {
    return '正在加载第 $pageNumber 页...';
  }

  @override
  String get recentSearches => '最近搜索';

  @override
  String get pageCountRange => '页数范围';

  @override
  String nMoreFilters(int count) {
    return '+$count 更多';
  }

  @override
  String get newUpdateAvailable => '有新更新可用！';

  @override
  String get newVersion => '新版本：';

  @override
  String get whatsNew => '更新内容';

  @override
  String get downloadUpdate => '下载更新';

  @override
  String exportPath(String path) {
    return '路径：$path';
  }

  @override
  String importedContentWithImages(String contentId, int count) {
    return '已导入 \"$contentId\"，含 $count 张图片到本地文件夹';
  }

  @override
  String failedToLoadCaptcha(String error) {
    return '加载验证码失败：$error';
  }

  @override
  String get turnstileRejected =>
      'Cloudflare Turnstile 拒绝了挑战（110200）。请重试或使用手动令牌输入。';

  @override
  String get openingNativeCaptcha => '正在打开原生验证码求解器...';

  @override
  String get tapRefreshToRetry => '点击刷新以重试原生验证码挑战。';

  @override
  String get loginToCrotpediaDescription => '使用原生安全浏览器登录 Crotpedia 以访问书签和更多功能。';

  @override
  String get crotpediaBookmarkLoginPrompt =>
      '此功能（书签）需要您登录 Crotpedia。\n\n是否现在登录？';

  @override
  String get browseByGenre => '按类型浏览';

  @override
  String nMoreGenres(int count) {
    return '+$count 更多';
  }

  @override
  String get selectSourceFromManifest => '从清单选择源';

  @override
  String pagesWithSize(int pageCount, String size) {
    return '$pageCount 页 • $size';
  }

  @override
  String get browseComics => '1. 浏览您喜欢的漫画';

  @override
  String get tapDownloadButton => '2. 点击下载按钮';

  @override
  String get accessOffline => '3. 随时随地访问，即使离线！';

  @override
  String get source => '来源';

  @override
  String nPagesText(int count) {
    return '$count 页';
  }

  @override
  String checkItOut(String url) {
    return '在这里查看：$url';
  }

  @override
  String get filteredResults => '筛选结果';

  @override
  String get filter => '筛选';

  @override
  String crotpediaMaintenance(String reason) {
    return 'Crotpedia 维护中：$reason';
  }

  @override
  String get tapToChangeFilters => '点击更改搜索筛选器';

  @override
  String get prevChapter => '上一章';

  @override
  String get nextChapter => '下一章';

  @override
  String pageOfContent(int current, int total) {
    return '第 $current 页，共 $total 页';
  }

  @override
  String nChapters(int count) {
    return '$count 章';
  }

  @override
  String get failedToLoadOptionsTap => '加载选项失败。点击重试。';

  @override
  String chooseField(String field) {
    return '$field';
  }

  @override
  String get tapToLoadOptions => '点击加载选项';

  @override
  String nSelectedItems(int count) {
    return '已选 $count 项';
  }

  @override
  String get tapToChooseTags => '点击选择包含/排除标签';

  @override
  String includeExcludeCount(int include, int exclude) {
    return '包含 $include • 排除 $exclude';
  }

  @override
  String get searchLabel => '搜索';

  @override
  String get genreLabel => '类型';

  @override
  String get statusLabel => '状态';

  @override
  String get orderBy => '排序';

  @override
  String get authorLabel => '作者';

  @override
  String get artistFilterLabel => '画师';

  @override
  String get artists => '画师';

  @override
  String get characters => '角色';

  @override
  String get parodies => '同人';

  @override
  String get groups => '团体';

  @override
  String get filterCategories => '筛选分类';

  @override
  String get dateUploaded => '上传日期';

  @override
  String get numericFilters => '数值筛选';

  @override
  String get older => '更早';

  @override
  String get contentFilters => '内容筛选';

  @override
  String get blurCoversDescription =>
      '模糊匹配本地标签规则的封面，即使离线浏览也有效。如果您登录了 nhentai，在线黑名单 ID 会自动合并。';

  @override
  String get developerTools => '开发者工具';

  @override
  String get noOnlineRulesYet => '尚未获取在线详细规则。下拉刷新以获取 /blacklist 数据。';

  @override
  String get nothingSavedLocally => '本地尚未保存任何内容。本地规则始终生效，包括离线结果。';

  @override
  String get loginRequiredForRules => '需要登录才能从 /blacklist 获取详细规则元数据。';

  @override
  String get syncingOnlineRules => '正在同步在线规则详情...';

  @override
  String get noOnlineRuleDetails => '尚未获取在线规则详情。点击刷新以获取 /blacklist。';

  @override
  String get blacklistGalleriesInfo => '添加本地规则或同步在线 ID 后，黑名单画廊将在此模糊显示。';

  @override
  String coverageActiveDescription(int count) {
    return '已为 $count 个令牌启用覆盖。ID 令牌按请求在此隐藏；上方仅显示已命名的在线规则。';
  }

  @override
  String get availableSources => '可用来源';

  @override
  String get settingUpConnection => '正在设置组件并检查连接...';

  @override
  String get tagId => '标签 ID';

  @override
  String get slug => 'Slug';

  @override
  String get path => '路径';

  @override
  String get tag => '标签';

  @override
  String profileWithName(String name) {
    return '个人资料 ($name)';
  }

  @override
  String get profile => '个人资料';

  @override
  String get loginAccount => '登录 / 账户';

  @override
  String accountWithName(String name) {
    return '账户 ($name)';
  }

  @override
  String get performance => '性能';

  @override
  String get autoRetry => '自动重试';

  @override
  String get network => '网络';

  @override
  String get notifications => '通知';

  @override
  String get estimatingProgress => '正在估算进度...';

  @override
  String get processingBadAvifToWebp => '正在将损坏的 AVIF 转换为 WebP...';

  @override
  String get downloadingImageData => '正在下载图片数据...';

  @override
  String get hideFilters => '隐藏筛选器';

  @override
  String get showMoreFilters => '显示更多筛选器';

  @override
  String get preparingExport => '正在准备导出...';

  @override
  String get readingFavorites => '正在从数据库读取收藏...';

  @override
  String get encodingFavorites => '正在编码收藏数据...';

  @override
  String get writingExportFile => '正在写入导出文件...';

  @override
  String get finalizingExport => '正在完成导出...';

  @override
  String get readerContinuousDisabledHeavyImage =>
      '已禁用连续滚动：检测到高负载动画图片。请使用水平/垂直模式。';

  @override
  String get readerContinuousOffHeavyImage => '连续滚动已关闭（重型图片）';

  @override
  String get chapterCurrentBadge => '当前';

  @override
  String readerDaysAgoShort(int count) {
    return '$count天前';
  }

  @override
  String readerWeeksAgoShort(int count) {
    return '$count周前';
  }

  @override
  String readerMonthsAgoShort(int count) {
    return '$count个月前';
  }

  @override
  String get readerTapDirectionLabel => '点击方向';

  @override
  String get readerTapDirectionNormal => '正常';

  @override
  String get readerTapDirectionInverted => '反向';

  @override
  String get readerTapDirectionNormalDescription => '点击右侧前往下一页';

  @override
  String get readerTapDirectionInvertedDescription => '点击左侧前往下一页';

  @override
  String get readerClearImageCache => '清除图片缓存';

  @override
  String get readerImageCacheCleared => '图片缓存已清除。滚动以重新加载页面。';

  @override
  String get readerOpenInGallery => '在图库中打开';

  @override
  String get readerPinchToZoom => '双指缩放';

  @override
  String get captchaCancelled => '验证码挑战已取消或失败。';

  @override
  String failedToOpenCaptcha(String error) {
    return '无法打开原生验证码求解器：$error';
  }

  @override
  String get readFirstChapter => '阅读第一章';

  @override
  String get convertAllToPdf => '全部转换为 PDF';

  @override
  String deleteSeriesConfirmation(int count, String title) {
    return '您确定要删除 \"$title\" 的 $count 个章节吗？';
  }

  @override
  String deleteSeriesWithCount(int count) {
    return '删除系列 ($count)';
  }

  @override
  String get readerScreenSupporter => '支持开发者';

  @override
  String get readerScreenSupporterDesc => '如果你喜欢这个应用，请考虑支持其开发。';

  @override
  String get readerScreenThanks => '感谢阅读！';

  @override
  String get readerScreenThanksDesc => '希望你享受这一章节。下一章再见！';

  @override
  String get readerScreenGoToFirstPage => '回到第一页';

  @override
  String get appLockSectionTitle => '应用锁';

  @override
  String get pinLock => 'PIN锁';

  @override
  String get pinLockActive => 'PIN已设置并激活';

  @override
  String get pinLockSet => '设置PIN以锁定应用';

  @override
  String get changePin => '更改PIN';

  @override
  String get changePinDescription => '设置新PIN';

  @override
  String get biometricUnlock => '生物识别解锁';

  @override
  String get biometricAvailable => '使用指纹或面部解锁';

  @override
  String get biometricUnavailable => '此设备不支持生物识别';

  @override
  String get enterPin => '输入PIN';

  @override
  String get enterCurrentPin => '输入当前PIN';

  @override
  String get enterCurrentPinSubtitle => '请先验证身份';

  @override
  String get enterNewPin => '输入新PIN';

  @override
  String enterNewPinSubtitle(int maxDigits) {
    return '选择$maxDigits位PIN';
  }

  @override
  String get confirmNewPin => '确认新PIN';

  @override
  String get confirmNewPinSubtitle => '再次输入PIN';

  @override
  String get setupPin => '设置PIN';

  @override
  String setupPinSubtitle(int maxDigits) {
    return '选择$maxDigits位PIN';
  }

  @override
  String get confirmPin => '确认PIN';

  @override
  String get confirmPinSubtitle => '再次输入PIN以确认';

  @override
  String get wrongPin => 'PIN错误';

  @override
  String get pinsDoNotMatch => 'PIN不匹配';

  @override
  String get pinChangedSuccess => 'PIN更改成功';

  @override
  String get failedToSavePin => '保存PIN失败。请重试。';

  @override
  String get failedToChangePin => '更改PIN失败。请重试。';

  @override
  String get disablePinLock => '禁用PIN锁？';

  @override
  String get disablePinLockDescription => '要禁用PIN锁，请输入当前PIN。';

  @override
  String get enterPinToDisable => '输入PIN以禁用';

  @override
  String get enterPinToDisableSubtitle => '这将删除PIN并禁用锁定';

  @override
  String get unlockKuron => '解锁Kuron以继续';

  @override
  String get continue_ => '继续';

  @override
  String get aiTranslate => 'AI 翻译';

  @override
  String get aiTutorialHint => '点击任意位置关闭';

  @override
  String get aiTutorialTranslateTitle => '✨ 翻译页面';

  @override
  String get aiTutorialTranslateDesc => '自动检测气泡 → 翻译叠加在原文上。再次点击切换显示。';

  @override
  String get aiTutorialDrawTitle => '✏️ 绘制气泡';

  @override
  String get aiTutorialDrawDesc =>
      '手动修正。拖动添加气泡（红），🛰 Detect 查看 ONNX 检测（蓝）。Done 锁定但气泡保持显示。';

  @override
  String get aiTutorialClearTitle => '🗑 清除';

  @override
  String get aiTutorialClearDesc => '移除翻译结果 + 所有参考气泡。';

  @override
  String get aiTutorialGotIt => '明白了！';

  @override
  String get aiNotAvailableCS => '连续滚动模式下不可用 AI 翻译。';

  @override
  String get aiHideTranslation => '隐藏翻译';

  @override
  String get aiTranslating => '翻译中...';

  @override
  String get aiDetecting => '检测气泡中...';

  @override
  String get aiTranslatePage => '翻译页面';

  @override
  String get aiClearTranslateBubbles => '清除翻译 + 气泡';

  @override
  String get aiExitDrawMode => '退出绘制模式';

  @override
  String get aiDrawBubbles => '绘制气泡';

  @override
  String get aiDrawRect => '矩形';

  @override
  String get aiDrawEllipse => '椭圆';

  @override
  String get aiDrawFreeform => '自由形状';

  @override
  String get aiExpandDraw => '显示操作';

  @override
  String get aiCollapseDraw => '隐藏操作';

  @override
  String get aiDrawDetect => '检测气泡';

  @override
  String get aiDrawUndo => '撤消';

  @override
  String get aiDrawClear => '清除';

  @override
  String get aiSkipSfxOn => '跳过音效：开';

  @override
  String get aiSkipSfxOff => '跳过音效：关';

  @override
  String get moreActions => '更多操作';

  @override
  String get aiEditTranslation => '编辑翻译';

  @override
  String get aiTranslation => '翻译';

  @override
  String get aiSave => '保存';

  @override
  String get aiSaveToGlossaryHint => '保存到学习词汇表';

  @override
  String get aiSaveToGlossary => '保存到词汇表';

  @override
  String get aiSavedToGlossary => '已保存到词汇表';

  @override
  String aiTranslateFailed(Object error) {
    return '翻译失败：$error';
  }

  @override
  String get aiNeedVisionProvider => 'AI 翻译需要视觉模型。请在设置 → AI 翻译中配置。';

  @override
  String aiRateLimited(Object fallback) {
    return '速率受限。$fallback';
  }

  @override
  String aiUsingFallback(Object name) {
    return '使用 $name 作为备用。';
  }

  @override
  String aiWaitCooldown(Object seconds) {
    return '等待 $seconds 秒。';
  }

  @override
  String get aiGagalFetch => '获取页面图片失败。请重试或检查网络。';

  @override
  String get aiCapturingViewport => '正在截取屏幕...请稍候。';

  @override
  String get aiGagalCapture => '截取屏幕失败。请重试。';

  @override
  String get aiCapturedViewport => '屏幕截取成功。';

  @override
  String get aiSettings => 'AI 设置';

  @override
  String get aiProvidersSubtitle => '提供商、语言、风格、翻译缓存';

  @override
  String get aiManageProviders => 'AI 提供商';

  @override
  String get aiOpen => '打开';

  @override
  String get aiTargetLanguage => '目标语言';

  @override
  String get aiTargetLangSubtitle => 'AI 翻译成的语言';

  @override
  String get aiTranslationStyle => '翻译风格';

  @override
  String get aiSkipSfx => '跳过音效气泡';

  @override
  String get aiSkipSfxSubtitle => '跳过仅含音效的气泡（默认开）';

  @override
  String get aiMosaicQuality => '马赛克质量';

  @override
  String get aiMosaicQualitySubtitle =>
      '低画质省 token（JPEG 75，1 MB）；高画质保留细节（JPEG 85，2 MB）';

  @override
  String get aiSwitchModel => '切换模型';

  @override
  String aiModelSwitched(Object name) {
    return '模型已切换为 $name';
  }

  @override
  String get aiPrivacyDisclosure => '隐私声明';

  @override
  String get aiPrivacyDesc => '图片发送到您选择的提供商。Kuron 不转发您的数据。';

  @override
  String get aiClearCache => '清除翻译缓存';

  @override
  String get aiClearCacheSubtitle => '删除所有缓存的页面翻译';

  @override
  String get aiGlossary => '学习词汇表';

  @override
  String get aiGlossarySubtitle => '查看已保存的词汇';

  @override
  String get aiAddProvider => '添加提供商';

  @override
  String get aiEditProvider => '编辑提供商';

  @override
  String get aiProviderType => '类型';

  @override
  String get aiDisplayName => '显示名称';

  @override
  String get aiApiKey => 'API 密钥';

  @override
  String get aiApiKeyHint => '免密钥免费模型留空';

  @override
  String get aiModel => '模型';

  @override
  String get aiBaseUrl => '基础 URL';

  @override
  String get aiTestKey => '测试密钥';

  @override
  String get aiTesting => '测试中...';

  @override
  String get aiDelete => '删除';

  @override
  String get aiValidKey => '✓ 密钥有效';

  @override
  String aiCheckIconD(Object model) {
    return '✓ 密钥有效 — 模型 $model 正常';
  }

  @override
  String get aiCustomTypeDefault => '用户必须填写';

  @override
  String get aiModeKasarTitle => '粗俗模式（18+）';

  @override
  String get aiModeKasarConfirm => '粗俗模式使用强硬语言。继续？';

  @override
  String get aiEnable => '启用';

  @override
  String get aiCancel => '取消';

  @override
  String aiModelNotVision(Object model) {
    return '模型 \"$model\" 不支持图片翻译（仅文本/免费）。请在设置 → AI 翻译中选择视觉模型（如 kimi-k2.6、gemini-2.5-flash、gpt-4o-mini）。';
  }

  @override
  String aiNoVisionProvider(Object model) {
    return '模型 \"$model\" 仅文本/免费 — 请在设置 → AI 翻译中选择视觉模型（如 kimi-k2.6）。';
  }

  @override
  String get aiGlossaryEmpty => '尚无词汇表条目。\\n长按翻译气泡可保存。';

  @override
  String aiDefaultModel(Object model) {
    return '默认：$model';
  }

  @override
  String get aiLoadModels => '加载模型';

  @override
  String get aiReload => '重新加载';

  @override
  String get aiManualEntry => '手动输入';

  @override
  String get aiUseLov => '使用列表';

  @override
  String get aiEnterApiKeyFirst => '请先输入 API 密钥';

  @override
  String get aiAll => '全部';

  @override
  String get aiVision => '视觉';

  @override
  String get aiTextOnly => '仅文本';

  @override
  String get aiSearchModels => '搜索模型';

  @override
  String get aiSelectModel => '选择模型';

  @override
  String aiStaleModel(Object model) {
    return '已保存的模型“$model”不在当前列表中';
  }

  @override
  String get aiModelHint => '从实时列表中选择模型，或使用手动输入';

  @override
  String get aiClearCacheCleared => '翻译缓存已清除';

  @override
  String get aiPrivacyDialogDesc =>
      '您翻译的页面图片将使用您自己的密钥发送到您选择的提供商。没有数据经过 Kuron 的服务器。';

  @override
  String get aiPrivacyAgree => '同意并翻译';

  @override
  String get aiNoKeyNeeded => '无需密钥';

  @override
  String get glossaryPage => '页';

  @override
  String get nclientImport => '从 NClient 导入';

  @override
  String get nclientImportSubtitle => '从 NClient V2/V3 备份导入收藏、合集、历史和阅读进度';

  @override
  String get nclientImportAction => '导入';

  @override
  String get nclientPreview => '导入预览';

  @override
  String get nclientResult => '导入结果';

  @override
  String get nclientPositions => '阅读进度';

  @override
  String get nclientMemberships => '合集内容';

  @override
  String get nclientMalformedRows => '无法读取的行';

  @override
  String nclientSummaryRow(String label, int success, int skipped, int failed) {
    return '$label：新增 $success，跳过 $skipped，失败 $failed';
  }
}
