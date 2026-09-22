// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get appTitle => 'Kuron';

  @override
  String sourceAuthProfileTitle(String sourceId) {
    return 'Profil $sourceId';
  }

  @override
  String sourceAuthLoginTitle(String sourceId) {
    return 'Masuk $sourceId';
  }

  @override
  String get sourceAuthConnectedAccount => 'Akun Terhubung';

  @override
  String get sourceAuthSecureLogin => 'Masuk Aman';

  @override
  String get sourceAuthConnectedDescription =>
      'Akun Anda sudah terhubung dan siap digunakan.';

  @override
  String get sourceAuthLoginDescription =>
      'Masuk untuk sinkronisasi favorit personal Anda.';

  @override
  String get sourceAuthUser => 'Pengguna';

  @override
  String get sourceAuthSlug => 'Slug';

  @override
  String get sourceAuthAuthenticated => 'Terautentikasi';

  @override
  String get sourceAuthRefreshProfile => 'Segarkan Profil';

  @override
  String get sourceAuthLogout => 'Keluar';

  @override
  String get sourceAuthUsername => 'Username';

  @override
  String get sourceAuthPassword => 'Kata sandi';

  @override
  String get sourceAuthCaptchaVerified =>
      'CAPTCHA terverifikasi dan tersimpan aman';

  @override
  String get sourceAuthCaptchaRequired => 'Selesaikan CAPTCHA untuk lanjut';

  @override
  String get sourceAuthCaptchaSolved => 'CAPTCHA Selesai';

  @override
  String get sourceAuthSolveCaptcha => 'Selesaikan CAPTCHA';

  @override
  String get sourceAuthLoginButton => 'Masuk';

  @override
  String get sourceAuthLoginSuccess => 'Masuk berhasil';

  @override
  String get sourceAuthSigningInSecurely => 'Sedang masuk dengan aman';

  @override
  String get sourceAuthStepValidateRequest => 'Validasi permintaan';

  @override
  String get sourceAuthStepSecureAuth => 'Autentikasi aman';

  @override
  String get sourceAuthStepFetchProfile => 'Ambil profil';

  @override
  String get sourceAuthFlowPreparingSession => 'Menyiapkan sesi aman...';

  @override
  String get sourceAuthFlowSolvingChallenge =>
      'Menyelesaikan tantangan keamanan...';

  @override
  String get sourceAuthFlowFetchingProfile =>
      'Sesi terverifikasi. Mengambil profil...';

  @override
  String get sourceAuthFlowLoginSuccess => 'Masuk berhasil';

  @override
  String get sourceAuthCaptchaCaptured => 'CAPTCHA berhasil disimpan';

  @override
  String get home => 'Beranda';

  @override
  String get search => 'Cari';

  @override
  String get favorites => 'Favorit';

  @override
  String get downloads => 'Unduhan';

  @override
  String get history => 'Riwayat Baca';

  @override
  String get randomGallery => 'Galeri Acak';

  @override
  String get randomGalleryLoadingTitle => 'Galeri Acak';

  @override
  String get randomGalleryLoadingMessage => 'Mengambil galeri acak...';

  @override
  String get randomGalleryFoundTitle => 'Ditemukan';

  @override
  String get randomGalleryFoundMessage => 'Membuka detail galeri...';

  @override
  String get randomGalleryNoResult =>
      'Tidak ada galeri acak ditemukan. Coba lagi.';

  @override
  String get randomGalleryError =>
      'Gagal memuat galeri acak. Silakan coba lagi.';

  @override
  String get randomGalleryUnavailableTitle => 'Fitur tidak tersedia';

  @override
  String get randomGalleryUnavailableMessage =>
      'Galeri Acak belum tersedia untuk sumber ini.';

  @override
  String get offlineContent => 'Konten Offline';

  @override
  String get settings => 'Pengaturan';

  @override
  String get appDisguise => 'PENYAMARAN APLIKASI';

  @override
  String get disguiseMode => 'Mode Penyamaran';

  @override
  String get offline => 'Offline';

  @override
  String get about => 'Tentang';

  @override
  String get supportDeveloper => 'Dukung Pengembang';

  @override
  String get supportDeveloperSubtitle => 'Traktir saya kopi';

  @override
  String get donateMessage => 'Dukung pengembangan via QRIS. Terima kasih! ☕';

  @override
  String get thankYouMessage => 'Terima kasih atas dukunganmu!';

  @override
  String get searchHint => 'Cari...';

  @override
  String get searchPlaceholder => 'Masukkan kata kunci pencarian';

  @override
  String get noResults => 'Tidak ada hasil ditemukan';

  @override
  String get searchSuggestions => 'Saran Pencarian';

  @override
  String get suggestions => 'Saran:';

  @override
  String get facebookPage => 'Doujin Stash 3';

  @override
  String get facebookPageSubtitle => 'Bantu support dengan like halaman';

  @override
  String get tapToLoadContent => 'Ketuk untuk memuat konten';

  @override
  String get trySwitchingNetwork =>
      'Coba beralih antara Wi-Fi dan data seluler';

  @override
  String get restartRouter => 'Restart router jika menggunakan Wi-Fi';

  @override
  String get checkWebsiteStatus => 'Periksa apakah situs web sedang down';

  @override
  String get cloudflareBypassMessage =>
      'Situs web dilindungi oleh Cloudflare. Kami sedang mencoba untuk melewati proteksi.';

  @override
  String get forceBypass => 'Paksa Bypass';

  @override
  String get unableToProcessData =>
      'Tidak dapat memproses data yang diterima. Struktur situs mungkin telah berubah.';

  @override
  String get reportIssue => 'Laporkan Masalah';

  @override
  String serverReturnedError(int statusCode) {
    return 'Server mengembalikan kesalahan $statusCode. Layanan mungkin sedang tidak tersedia.';
  }

  @override
  String get failedToOpenBrowser => 'Gagal membuka browser';

  @override
  String get viewDownloads => 'Lihat Unduhan';

  @override
  String get clearSearch => 'Bersihkan Pencarian';

  @override
  String get clearFilters => 'Bersihkan Filter';

  @override
  String get anyLanguage => 'Bahasa Apa Saja';

  @override
  String get anyCategory => 'Kategori Apa Saja';

  @override
  String get errorOpeningFilter => 'Kesalahan membuka pilihan filter';

  @override
  String get errorBrowsingTag => 'Kesalahan menjelajahi tag';

  @override
  String get shuffleToNextGallery => 'Acak ke galeri berikutnya';

  @override
  String get contentHidden => 'Konten Disembunyikan';

  @override
  String get tapToViewAnyway => 'Ketuk untuk tetap melihat';

  @override
  String get checkOutThisGallery => 'Lihat galeri ini!';

  @override
  String galleriesPreloaded(int count) {
    return '$count galeri dimuat sebelumnya';
  }

  @override
  String get oopsSomethingWentWrong => 'Ups! Ada yang salah';

  @override
  String get cleanupInfo => 'Info Pembersihan';

  @override
  String get clearingHistory => 'Menghapus riwayat...';

  @override
  String get areYouSureClearHistory =>
      'Apakah Anda yakin ingin menghapus semua riwayat bacaan? Tindakan ini tidak dapat dibatalkan.';

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
      'Atur lokasi penyimpanan unduhan di pengaturan.';

  @override
  String get schoolgirlUniform => 'schoolgirl uniform';

  @override
  String get tryADifferentSearchTerm => 'Coba istilah pencarian yang berbeda';

  @override
  String get unknownError => 'Kesalahan tidak diketahui';

  @override
  String get loadingOfflineContent => 'Memuat konten offline...';

  @override
  String get excludeTags => 'Kecualikan Tag';

  @override
  String get excludeGroups => 'Kecualikan Grup';

  @override
  String get excludeCharacters => 'Kecualikan Karakter';

  @override
  String get excludeParodies => 'Kecualikan Parodi';

  @override
  String get excludeArtists => 'Kecualikan Artis';

  @override
  String get noResultsFound => 'Tidak ada hasil ditemukan';

  @override
  String get tryAdjustingFilters =>
      'Coba sesuaikan filter pencarian atau istilah pencarian Anda.';

  @override
  String get networkError =>
      'Kesalahan jaringan. Periksa koneksi dan coba lagi.';

  @override
  String get accessBlocked => 'Akses diblokir. Mencoba melewati proteksi...';

  @override
  String get tooManyRequests =>
      'Terlalu banyak permintaan. Silakan tunggu sebentar dan coba lagi.';

  @override
  String get errorProcessingResults =>
      'Kesalahan memproses hasil pencarian. Silakan coba lagi.';

  @override
  String get invalidSearchParameters =>
      'Parameter pencarian tidak valid. Silakan periksa input Anda.';

  @override
  String get unexpectedError =>
      'Terjadi error yang tidak terduga. Silakan coba lagi.';

  @override
  String get retryBypass => 'Coba Bypass Lagi';

  @override
  String get retryConnection => 'Coba Koneksi Lagi';

  @override
  String get retrySearch => 'Coba Cari Lagi';

  @override
  String get errorNetwork =>
      'Kesalahan jaringan. Periksa koneksi dan coba lagi.';

  @override
  String get errorServer => 'Kesalahan server. Silakan coba lagi nanti.';

  @override
  String get errorCloudflare =>
      'Konten diblokir sementara (Cloudflare). Silakan coba lagi sebentar lagi.';

  @override
  String get errorParsing =>
      'Gagal memuat data konten. Konten mungkin tidak tersedia.';

  @override
  String get errorUnknown => 'Terjadi kesalahan. Silakan coba lagi.';

  @override
  String get errorConnectionTimeout =>
      'Koneksi habis waktu. Silakan coba lagi.';

  @override
  String get errorConnectionRefused =>
      'Koneksi ditolak. Server mungkin sedang down.';

  @override
  String get networkErrorTitle => 'Kesalahan Jaringan';

  @override
  String get serverErrorTitle => 'Kesalahan Server';

  @override
  String get unknownErrorTitle => 'Kesalahan Tidak Diketahui';

  @override
  String get refreshingContent => 'Menyegarkan konten...';

  @override
  String get loadingMoreContent => 'Memuat konten lainnya...';

  @override
  String get searchResults => 'Hasil Pencarian';

  @override
  String get latestContent => 'Konten Terbaru';

  @override
  String get serverTemporarilyUnavailable =>
      'Server sementara tidak tersedia. Silakan coba lagi nanti.';

  @override
  String get cloudflareProtectionDetected =>
      'Proteksi Cloudflare terdeteksi. Silakan tunggu dan coba lagi.';

  @override
  String get tooManyRequestsWait =>
      'Terlalu banyak permintaan. Silakan tunggu sebentar sebelum mencoba lagi.';

  @override
  String get noContentFoundMatching =>
      'Tidak ada konten yang ditemukan sesuai kriteria pencarian Anda. Coba sesuaikan filter Anda.';

  @override
  String noContentFoundForTag(String tagName) {
    return 'Tidak ada konten ditemukan untuk tag \"$tagName\".';
  }

  @override
  String get useGeneralTerms => 'Gunakan istilah pencarian yang lebih umum';

  @override
  String get tryBrowsingOtherTags => 'Coba jelajahi tag lain';

  @override
  String get checkPopularContent => 'Periksa konten populer';

  @override
  String get useSearchFunction => 'Gunakan fungsi pencarian';

  @override
  String get checkInternetConnectionSuggestion =>
      'Periksa koneksi internet Anda';

  @override
  String get browsePopularContentSuggestion => 'Jelajahi konten populer';

  @override
  String get failedToInitializeSearch => 'Gagal menginisialisasi pencarian';

  @override
  String noResultsFoundFor(String query) {
    return 'Tidak ada hasil ditemukan untuk \"$query\"';
  }

  @override
  String get searchingWithFilters => 'Mencari dengan filter...';

  @override
  String get noResultsFoundWithCurrentFilters =>
      'Tidak ada hasil ditemukan dengan filter saat ini';

  @override
  String invalidFilter(String errors) {
    return 'Filter tidak valid: $errors';
  }

  @override
  String invalidSearchFilter(String errors) {
    return 'Filter pencarian tidak valid: $errors';
  }

  @override
  String get tags => 'Tag';

  @override
  String get language => 'Bahasa';

  @override
  String get uploadedOn => 'Diunggah pada';

  @override
  String get readNow => 'Baca Sekarang';

  @override
  String get featured => 'Unggulan';

  @override
  String get confirmDownload => 'Konfirmasi Unduhan';

  @override
  String get downloadConfirmation => 'Apakah Anda yakin ingin mengunduh?';

  @override
  String get confirmButton => 'Konfirmasi';

  @override
  String get download => 'Unduh';

  @override
  String get downloading => 'Mengunduh';

  @override
  String get downloadCompleted => 'Unduhan Selesai';

  @override
  String get initializing => 'Memulai...';

  @override
  String get noContentToBrowse => 'Tidak ada konten untuk dibuka di browser';

  @override
  String get addToFavorites => 'Tambah ke Favorit';

  @override
  String get removeFromFavorites => 'Hapus dari Favorit';

  @override
  String get content => 'Konten';

  @override
  String get clearAll => 'Bersihkan Semua';

  @override
  String get exportList => 'Ekspor Daftar';

  @override
  String get unableToCheck => 'Tidak dapat memeriksa koneksi.';

  @override
  String get noContentAvailable => 'Tidak ada konten tersedia';

  @override
  String get noContentToDownload => 'Tidak ada konten untuk diunduh';

  @override
  String get noGalleriesFound => 'Tidak ada galeri ditemukan di halaman ini';

  @override
  String get noContentLoadedToBrowse =>
      'Tidak ada konten dimuat untuk dibuka di browser';

  @override
  String get showCachedContent => 'Tampilkan Konten Cache';

  @override
  String get openedInBrowser => 'Dibuka di browser';

  @override
  String get foundGalleries => 'Galeri Ditemukan';

  @override
  String get checkingDownloadStatus => 'Memeriksa Status Unduhan...';

  @override
  String get allGalleriesDownloaded => 'Semua Galeri Telah Diunduh';

  @override
  String get downloadNewGalleries => 'Unduh Galeri Baru';

  @override
  String get downloadProgress => 'Progres Unduhan';

  @override
  String get verifyingFiles => 'Memverifikasi File';

  @override
  String verifyingFilesWithTitle(String title) {
    return 'Memverifikasi $title...';
  }

  @override
  String verifyingProgress(int progress) {
    return 'Memverifikasi ($progress%)';
  }

  @override
  String get initializingDownloads => 'Memulai unduhan...';

  @override
  String get loadingDownloads => 'Memuat unduhan...';

  @override
  String get pauseAll => 'Jeda Semua';

  @override
  String get resumeAll => 'Lanjutkan Semua';

  @override
  String get cancelAll => 'Batalkan Semua';

  @override
  String get clearCompleted => 'Hapus yang Selesai';

  @override
  String get cleanupStorage => 'Bersihkan Penyimpanan';

  @override
  String get all => 'Semua';

  @override
  String get completed => 'Selesai';

  @override
  String get noDownloadsYet => 'Belum ada unduhan';

  @override
  String get noActiveDownloads => 'Tidak ada unduhan aktif';

  @override
  String get noQueuedDownloads => 'Tidak ada unduhan antrian';

  @override
  String get noCompletedDownloads => 'Tidak ada unduhan selesai';

  @override
  String get noFailedDownloads => 'Tidak ada unduhan gagal';

  @override
  String get cancelAllDownloads => 'Batalkan Semua Unduhan';

  @override
  String get cancelAllConfirmation =>
      'Yakin ingin membatalkan semua unduhan aktif? Tindakan ini tidak bisa dibatalkan.';

  @override
  String get cancelDownload => 'Batalkan Unduhan';

  @override
  String get cancelDownloadConfirmation =>
      'Yakin ingin membatalkan unduhan ini? Progress akan hilang.';

  @override
  String get removeDownload => 'Hapus Unduhan';

  @override
  String get removeDownloadConfirmation =>
      'Yakin ingin menghapus unduhan ini dari daftar? File yang telah diunduh akan dihapus.';

  @override
  String get cleanupConfirmation =>
      'Ini akan menghapus file yatim dan membersihkan unduhan yang gagal. Lanjutkan?';

  @override
  String get downloadDetails => 'Detail Unduhan';

  @override
  String get status => 'Status';

  @override
  String get progressPercent => 'Progres %';

  @override
  String get started => 'Dimulai';

  @override
  String get ended => 'Selesai';

  @override
  String get eta => 'ETA';

  @override
  String get failed => 'Gagal';

  @override
  String get downloadListExported => 'Daftar unduhan diekspor';

  @override
  String get downloadAll => 'Unduh Semua';

  @override
  String get downloadRange => 'Unduh Rentang';

  @override
  String get selectDownloadRange => 'Pilih Rentang Unduhan';

  @override
  String get useSliderToSelectRange => 'Gunakan slider untuk memilih rentang:';

  @override
  String get orEnterManually => 'Atau masukkan secara manual:';

  @override
  String get quickSelections => 'Pilihan cepat:';

  @override
  String get allPages => 'Semua Halaman';

  @override
  String get firstHalf => 'Setengah Pertama';

  @override
  String get secondHalf => 'Setengah Kedua';

  @override
  String get first10 => '10 Pertama';

  @override
  String get last10 => '10 Terakhir';

  @override
  String countAlreadyDownloaded(int count) {
    return 'Dilewati $count yang sudah diunduh';
  }

  @override
  String newGalleriesToDownload(int count) {
    return '• $count galeri baru untuk diunduh';
  }

  @override
  String alreadyDownloaded(int count) {
    return '• $count sudah diunduh (akan dilewati)';
  }

  @override
  String downloadNew(int count) {
    return 'Unduh $count Baru';
  }

  @override
  String queuedDownloads(int count) {
    return 'Mengantri $count unduhan baru';
  }

  @override
  String downloadInfo(int count) {
    return 'Unduh $count galeri baru?\\n\\nIni mungkin memerlukan waktu dan ruang penyimpanan yang signifikan.';
  }

  @override
  String get failedToDownload => 'Gagal mengunduh galeri';

  @override
  String selectedPagesTo(int start, int end) {
    return 'Dipilih: Halaman $start hingga $end';
  }

  @override
  String pagesPercentage(int count, String percentage) {
    return '$count halaman ($percentage%)';
  }

  @override
  String rangeDownloadStarted(String title, String pageText) {
    return 'Unduhan rentang dimulai: $title ($pageText)';
  }

  @override
  String opening(String title) {
    return 'Membuka: $title';
  }

  @override
  String get lastUpdatedLabel => 'Diperbarui:';

  @override
  String get releasedLabel => 'Rilis:';

  @override
  String get updatedLabel => 'Diperbarui:';

  @override
  String get rangeLabel => 'Rentang:';

  @override
  String get ofWord => 'dari';

  @override
  String waitAndTry(int minutes) {
    return 'Tunggu $minutes menit dan coba lagi';
  }

  @override
  String get serviceUnderMaintenance =>
      'Layanan mungkin sedang dalam pemeliharaan';

  @override
  String get tryRefreshingPage => 'Coba muat ulang halaman';

  @override
  String get waitForBypass => 'Tunggu bypass otomatis selesai';

  @override
  String get tryUsingVpn => 'Coba gunakan VPN jika tersedia';

  @override
  String get checkBackLater => 'Periksa kembali beberapa menit lagi';

  @override
  String get tryRefreshingContent => 'Coba muat ulang konten';

  @override
  String get checkForAppUpdate => 'Periksa apakah aplikasi perlu diperbarui';

  @override
  String get reportIfPersists => 'Laporkan masalah jika terus berlanjut';

  @override
  String get maintenanceTakesHours =>
      'Pemeliharaan biasanya memakan waktu beberapa jam';

  @override
  String get checkSocialMedia => 'Periksa media sosial untuk pembaruan';

  @override
  String get tryAgainLater => 'Coba lagi nanti';

  @override
  String get tryDifferentKeywords => 'Coba kata kunci berbeda';

  @override
  String get serverUnavailable =>
      'Server saat ini tidak tersedia. Silakan coba lagi nanti.';

  @override
  String get removeSomeFilters => 'Hapus beberapa filter';

  @override
  String get checkSpelling => 'Periksa ejaan';

  @override
  String get useBroaderSearchTerms =>
      'Gunakan istilah pencarian yang lebih luas';

  @override
  String get welcomeTitle => 'Selamat Datang di Kuron!';

  @override
  String get welcomeMessage => 'Sebelum memulai:';

  @override
  String get ispBlockingInfo => '🚨 Pemberitahuan Pemblokiran ISP';

  @override
  String get ispBlockingMessage =>
      'Diblokir ISP? Gunakan VPN seperti Cloudflare WARP 1.1.1.1.';

  @override
  String get downloadWarp => 'Unduh VPN 1.1.1.1';

  @override
  String get permissionsRequired => 'Izin yang Diperlukan';

  @override
  String get storagePermissionInfo =>
      '📁 Penyimpanan: Diperlukan untuk mengunduh dan menyimpan konten offline';

  @override
  String get notificationPermissionInfo =>
      '🔔 Notifikasi: Diperlukan untuk menampilkan progress dan penyelesaian unduhan';

  @override
  String get grantStoragePermission => 'Berikan Izin Penyimpanan';

  @override
  String get grantNotificationPermission => 'Berikan Izin Notifikasi';

  @override
  String get storageGranted => '✅ Izin penyimpanan diberikan';

  @override
  String get notificationGranted => '✅ Izin notifikasi diberikan';

  @override
  String get getStarted => 'Mulai';

  @override
  String get pleaseGrantAllPermissions =>
      'Berikan izin yang diperlukan untuk melanjutkan';

  @override
  String get permissionDenied =>
      'Izin ditolak. Beberapa fitur mungkin tidak berfungsi dengan baik.';

  @override
  String get loadingFavorites => 'Memuat favorit...';

  @override
  String get errorLoadingFavorites => 'Kesalahan Memuat Favorit';

  @override
  String get removeFavoriteConfirmation =>
      'Yakin ingin menghapus konten ini dari favorit?';

  @override
  String get removeAction => 'Hapus';

  @override
  String get deleteFavorites => 'Hapus Favorit';

  @override
  String deleteFavoritesConfirmation(int count, String s) {
    return 'Yakin ingin menghapus $count favorit$s?';
  }

  @override
  String get exportFavorites => 'Ekspor Favorit';

  @override
  String get noFavoritesYet =>
      'Belum ada favorit. Mulai tambahkan konten ke favorit Anda!';

  @override
  String get exportingFavorites => 'Mengekspor favorit...';

  @override
  String get exportComplete => 'Ekspor Selesai';

  @override
  String exportedFavoritesCount(int count) {
    return 'Berhasil mengekspor $count favorit.';
  }

  @override
  String selectedCount(int count) {
    return '$count dipilih';
  }

  @override
  String get selectFavorites => 'Favorit';

  @override
  String get deleteSelected => 'Hapus yang dipilih';

  @override
  String get searchFavorites => 'Cari favorit...';

  @override
  String get selectAll => 'Pilih Semua';

  @override
  String get removingFromFavorites => 'Menghapus dari favorit...';

  @override
  String get removedFromFavorites => 'Dihapus dari favorit';

  @override
  String failedToRemoveFavorite(String error) {
    return 'Gagal menghapus favorit: $error';
  }

  @override
  String removedFavoritesCount(int count) {
    return 'Menghapus $count favorit';
  }

  @override
  String failedToRemoveFavorites(String error) {
    return 'Gagal menghapus favorit: $error';
  }

  @override
  String get appearance => 'Tampilan';

  @override
  String get theme => 'Tema';

  @override
  String get imageQuality => 'Kualitas Gambar';

  @override
  String get blurThumbnails => 'Blur Gambar Mini';

  @override
  String get blurThumbnailsDescription =>
      'Terapkan efek blur pada gambar kartu untuk privasi';

  @override
  String get gridColumns => 'Kolom Grid (Portrait)';

  @override
  String get reader => 'Pembaca';

  @override
  String get showSystemUIInReader => 'Tampilkan UI Sistem di Pembaca';

  @override
  String get historyCleanup => 'Pembersihan Riwayat';

  @override
  String get autoCleanupHistory => 'Pembersihan Otomatis Riwayat';

  @override
  String get automaticallyCleanOldReadingHistory =>
      'Otomatis membersihkan riwayat baca lama';

  @override
  String get cleanupInterval => 'Interval Pembersihan';

  @override
  String get howOftenToCleanupHistory => 'Seberapa sering membersihkan riwayat';

  @override
  String get maxHistoryDays => 'Maksimal Hari Riwayat';

  @override
  String get maximumDaysToKeepHistory =>
      'Maksimal hari menyimpan riwayat (0 = tanpa batas)';

  @override
  String get cleanupOnInactivity => 'Bersihkan saat Tidak Aktif';

  @override
  String get cleanHistoryWhenAppUnused =>
      'Bersihkan riwayat ketika aplikasi tidak digunakan beberapa hari';

  @override
  String get inactivityThreshold => 'Batas Tidak Aktif';

  @override
  String get daysOfInactivityBeforeCleanup =>
      'Hari tidak aktif sebelum pembersihan';

  @override
  String get resetToDefault => 'Reset ke Default';

  @override
  String get generalSettings => 'Pengaturan Umum';

  @override
  String get displaySettings => 'Tampilan';

  @override
  String get darkMode => 'Mode Gelap';

  @override
  String get lightMode => 'Mode Terang';

  @override
  String get systemMode => 'Mengikuti Sistem';

  @override
  String get appLanguage => 'Bahasa Aplikasi';

  @override
  String get allowAnalytics => 'Izinkan Analytics';

  @override
  String get privacyAnalytics => 'Privasi Analytics';

  @override
  String get termsAndConditions => 'Syarat dan Ketentuan';

  @override
  String get termsAndConditionsSubtitle => 'Perjanjian pengguna dan disclaimer';

  @override
  String get privacyPolicy => 'Kebijakan Privasi';

  @override
  String get privacyPolicySubtitle => 'Bagaimana kami menangani data Anda';

  @override
  String get faq => 'FAQ';

  @override
  String get faqSubtitle => 'Pertanyaan yang sering diajukan';

  @override
  String get resetSettings => 'Reset Pengaturan';

  @override
  String get resetReaderSettings => 'Reset Pengaturan Reader';

  @override
  String get resetReaderSettingsConfirmation =>
      'Ini akan mengatur ulang semua pengaturan pembaca ke nilai default:\n\n';

  @override
  String get readingModeLabel => 'Mode Membaca: Halaman Horizontal';

  @override
  String get areYouSure => 'Apakah Anda yakin ingin melanjutkan?';

  @override
  String get readerSettingsResetSuccess =>
      'Pengaturan pembaca telah direset ke default.';

  @override
  String get readingHistory => 'Riwayat Baca';

  @override
  String get clearAllHistory => 'Bersihkan Semua Riwayat';

  @override
  String get manualCleanup => 'Pembersihan Manual';

  @override
  String get cleanupSettings => 'Pengaturan Pembersihan';

  @override
  String get removeFromHistoryQuestion => 'Hapus item ini dari riwayat baca?';

  @override
  String get cleanup => 'Bersihkan';

  @override
  String get failedToLoadCleanupStatus => 'Gagal memuat status pembersihan';

  @override
  String get manualCleanupConfirmation =>
      'Ini akan melakukan pembersihan berdasarkan pengaturan Anda saat ini. Lanjutkan?';

  @override
  String get nextPage => 'Halaman Berikutnya';

  @override
  String get previousPage => 'Halaman Sebelumnya';

  @override
  String get pageOf => 'dari';

  @override
  String get fullscreen => 'Layar Penuh';

  @override
  String get exitFullscreen => 'Keluar Layar Penuh';

  @override
  String get checkingConnection => 'Memeriksa koneksi...';

  @override
  String get backOnline => 'Kembali online! Semua fitur tersedia.';

  @override
  String get stillNoInternet => 'Masih tidak ada koneksi internet.';

  @override
  String get unableToCheckConnection => 'Tidak dapat memeriksa koneksi.';

  @override
  String get noInternetConnection => 'Tidak ada koneksi internet';

  @override
  String get connectionError => 'Kesalahan koneksi';

  @override
  String get serverError => 'Kesalahan server';

  @override
  String get low => 'Rendah';

  @override
  String get medium => 'Sedang';

  @override
  String get high => 'Tinggi';

  @override
  String get original => 'Asli';

  @override
  String get lowFaster => 'Rendah (Lebih Cepat)';

  @override
  String get highBetterQuality => 'Tinggi (Kualitas Lebih Baik)';

  @override
  String get originalLargest => 'Asli (Terbesar)';

  @override
  String get lowQuality => 'Rendah (Lebih Cepat)';

  @override
  String get mediumQuality => 'Sedang';

  @override
  String get highQuality => 'Tinggi (Kualitas Lebih Baik)';

  @override
  String get originalQuality => 'Asli (Terbesar)';

  @override
  String get dark => 'Gelap';

  @override
  String get light => 'Terang';

  @override
  String get amoled => 'AMOLED';

  @override
  String get english => 'Bahasa Inggris';

  @override
  String get japanese => 'Bahasa Jepang';

  @override
  String get indonesian => 'Bahasa Indonesia';

  @override
  String get chinese => 'Bahasa Tionghoa (Sederhana)';

  @override
  String get comfortReading => 'Pembacaan yang Nyaman';

  @override
  String get filterBy => 'Filter berdasarkan';

  @override
  String get recent => 'Terbaru';

  @override
  String get popular => 'Populer';

  @override
  String get oldest => 'Terlama';

  @override
  String get ok => 'OK';

  @override
  String get exitApp => 'Keluar Aplikasi';

  @override
  String get areYouSureExit => 'Apakah Anda yakin ingin keluar dari aplikasi?';

  @override
  String get exit => 'Keluar';

  @override
  String get delete => 'Hapus';

  @override
  String get confirm => 'Konfirmasi';

  @override
  String get tryAgain => 'Coba Lagi';

  @override
  String get save => 'Simpan';

  @override
  String get edit => 'Edit';

  @override
  String get close => 'Tutup';

  @override
  String get clear => 'Bersihkan';

  @override
  String get share => 'Bagikan';

  @override
  String get goBack => 'Kembali';

  @override
  String get yes => 'Ya';

  @override
  String get no => 'Tidak';

  @override
  String get previous => 'Sebelumnya';

  @override
  String get next => 'Selanjutnya';

  @override
  String get goToDownloads => 'Ke Unduhan';

  @override
  String get retryAction => 'Coba Lagi';

  @override
  String get unknown => 'Tidak diketahui';

  @override
  String get noData => 'Tidak Ada Data';

  @override
  String get downloadError => 'Kesalahan Unduhan';

  @override
  String get other => 'Lainnya';

  @override
  String get confirmResetSettings =>
      'Yakin ingin mengembalikan semua pengaturan ke default?';

  @override
  String get reset => 'Reset';

  @override
  String get manageAutoCleanupDescription =>
      'Kelola pembersihan otomatis riwayat baca untuk menghemat ruang penyimpanan.';

  @override
  String get nextCleanup => 'Pembersihan berikutnya';

  @override
  String get historyStatistics => 'Statistik Riwayat';

  @override
  String get totalItems => 'Total item';

  @override
  String get lastCleanup => 'Pembersihan terakhir';

  @override
  String get lastAppAccess => 'Akses aplikasi terakhir';

  @override
  String get oneDay => '1 hari';

  @override
  String get twoDays => '2 hari';

  @override
  String get oneWeek => '1 minggu';

  @override
  String get privacyInfoText =>
      '• Data disimpan di perangkat Anda\n• Tidak dikirim ke server eksternal\n• Hanya untuk meningkatkan performa aplikasi\n• Dapat dimatikan kapan saja';

  @override
  String get unlimited => 'Tanpa batas';

  @override
  String daysValue(int days) {
    return '$days hari';
  }

  @override
  String days(int count) {
    return '$count hari';
  }

  @override
  String get analyticsSubtitle =>
      'Membantu pengembangan aplikasi dengan data lokal (tidak dibagikan)';

  @override
  String get loadingContent => 'Memuat konten...';

  @override
  String get loadingError => 'Kesalahan Memuat';

  @override
  String get jumpToPage => 'Loncat ke Halaman';

  @override
  String pageInputLabel(int maxPages) {
    return 'Halaman (1-$maxPages)';
  }

  @override
  String pageOfPages(int current, int total) {
    return 'Halaman $current dari $total';
  }

  @override
  String get jump => 'Loncat';

  @override
  String get readerSettings => 'Pengaturan Pembaca';

  @override
  String get readingMode => 'Mode Baca';

  @override
  String get horizontalPages => 'Halaman Horizontal';

  @override
  String get verticalPages => 'Halaman Vertikal';

  @override
  String get continuousScroll => 'Gulir Berkelanjutan';

  @override
  String get keepScreenOnLabel => 'Jaga Layar Hidup: Mati';

  @override
  String get showUILabel => 'Tampilkan UI: Hidup';

  @override
  String get keepScreenOn => 'Jaga Layar Hidup';

  @override
  String get keepScreenOnDescription => 'Mencegah layar mati saat membaca';

  @override
  String get platformNotSupported => 'Platform Tidak Didukung';

  @override
  String get platformNotSupportedBody =>
      'Kuron dirancang khusus untuk perangkat Android.';

  @override
  String get platformNotSupportedInstall =>
      'Silakan pasang dan jalankan aplikasi ini di perangkat Android.';

  @override
  String get storagePermissionExplanation =>
      'Izin penyimpanan diperlukan untuk mengunduh file. File disimpan di folder Downloads/nhasix.';

  @override
  String get grantPermission => 'Berikan Izin';

  @override
  String get permissionRequired => 'Izin Diperlukan';

  @override
  String get storagePermissionSettingsPrompt =>
      'Izin penyimpanan diperlukan untuk mengunduh file. Silakan berikan izin penyimpanan di pengaturan aplikasi.';

  @override
  String get openSettings => 'Buka Pengaturan';

  @override
  String get noReadingHistory => 'Tidak Ada Riwayat Baca';

  @override
  String get readingHistoryMessage =>
      'Riwayat bacaan Anda akan muncul di sini saat Anda membaca konten.';

  @override
  String get startReading => 'Mulai Membaca';

  @override
  String get browsePopularContent => 'Jelajahi konten populer';

  @override
  String get searchSomethingInteresting => 'Cari sesuatu yang menarik';

  @override
  String get checkOutFeaturedItems => 'Lihat item unggulan';

  @override
  String get appSubtitleDescription => 'Klien tidak resmi Nhentai';

  @override
  String get downloadedGalleries => 'Galeri yang diunduh';

  @override
  String get favoriteGalleries => 'Galeri favorit';

  @override
  String get viewHistory => 'Lihat riwayat';

  @override
  String get openInBrowser => 'Buka di browser';

  @override
  String get downloadAllGalleries => 'Unduh semua galeri di halaman ini';

  @override
  String get featureDisabledTitle => 'Fitur Tidak Tersedia';

  @override
  String get downloadFeatureDisabled =>
      'Fitur unduhan tidak tersedia untuk sumber ini';

  @override
  String get favoriteFeatureDisabled =>
      'Fitur favorit tidak tersedia untuk sumber ini';

  @override
  String get featureNotAvailable => 'Fitur ini saat ini tidak tersedia';

  @override
  String get chaptersTitle => 'Chapter';

  @override
  String chapterCount(int count) {
    return '$count chapter';
  }

  @override
  String loadMoreChapters(String label) {
    return 'Muat lebih banyak $label';
  }

  @override
  String get readChapter => 'Baca';

  @override
  String get downloadChapter => 'Unduh Chapter';

  @override
  String enterPageNumber(int totalPages) {
    return 'Masukkan nomor halaman (1 - $totalPages)';
  }

  @override
  String get go => 'Pergi';

  @override
  String validPageNumberError(int totalPages) {
    return 'Masukkan nomor halaman antara 1 dan $totalPages';
  }

  @override
  String get tapToJump => 'Ketuk untuk loncat';

  @override
  String get goToPage => 'Pergi ke Halaman';

  @override
  String get previousPageTooltip => 'Halaman sebelumnya';

  @override
  String get nextPageTooltip => 'Halaman berikutnya';

  @override
  String get tapToJumpToPage => 'Ketuk untuk lompat ke halaman';

  @override
  String get loadingContentTitle => 'Memuat Konten';

  @override
  String get loadingContentDetails => 'Memuat Detail Konten';

  @override
  String get fetchingMetadata => 'Mengambil metadata dan gambar...';

  @override
  String get thisMayTakeMoments => 'Ini mungkin memerlukan beberapa saat...';

  @override
  String get youAreOffline => 'Anda sedang offline';

  @override
  String get goOnline => 'Buka Online';

  @override
  String get youAreOfflineTapToGoOnline =>
      'Anda sedang offline. Ketuk untuk online.';

  @override
  String get contentInformation => 'Informasi Konten';

  @override
  String get copyLink => 'Salin Link';

  @override
  String get moreOptions => 'Opsi Lainnya';

  @override
  String get moreLikeThis => 'Lebih Seperti Ini';

  @override
  String get statistics => 'Statistik';

  @override
  String get failedToLoadContent => 'Gagal memuat konten';

  @override
  String get shareContent => 'Bagikan Konten';

  @override
  String get sharePanelOpened => 'Panel berbagi berhasil dibuka!';

  @override
  String get shareFailed =>
      'Berbagi gagal, tetapi link telah disalin ke clipboard';

  @override
  String downloadStartedFor(String title) {
    return 'Unduhan dimulai untuk \"$title\"';
  }

  @override
  String get viewDownloadsAction => 'Lihat';

  @override
  String get linkCopiedToClipboard => 'Link telah disalin ke clipboard';

  @override
  String get failedToCopyLink => 'Gagal menyalin link. Silakan coba lagi.';

  @override
  String get copiedLink => 'Link Disalin';

  @override
  String get linkCopiedToClipboardDescription =>
      'Link berikut telah disalin ke clipboard Anda:';

  @override
  String get closeDialog => 'Tutup';

  @override
  String get goOnlineDialogTitle => 'Buka Online';

  @override
  String get goOnlineDialogContent =>
      'Anda saat ini dalam mode offline. Apakah Anda ingin online untuk mengakses konten terbaru?';

  @override
  String get goingOnline => 'Membuka online...';

  @override
  String get idLabel => 'ID';

  @override
  String get pagesLabel => 'Halaman';

  @override
  String artistLabel(String name) {
    return 'Seniman: $name';
  }

  @override
  String get uploadedLabel => 'Diunggah';

  @override
  String get viewAllChapters => 'Lihat Semua Chapter';

  @override
  String get searchChapters => 'Cari chapter...';

  @override
  String get noChaptersFound => 'Tidak ada chapter ditemukan';

  @override
  String get favoritesLabel => 'Favorit';

  @override
  String get relatedLabel => 'Terkait';

  @override
  String yearAgo(int count, String plural) {
    return '$count tahun$plural lalu';
  }

  @override
  String monthAgo(int count, String plural) {
    return '$count bulan$plural lalu';
  }

  @override
  String dayAgo(int count, String plural) {
    return '$count hari$plural lalu';
  }

  @override
  String hourAgo(int count, String plural) {
    return '$count jam$plural lalu';
  }

  @override
  String get selectFavoritesTooltip => 'Pilih favorit';

  @override
  String get deleteSelectedTooltip => 'Hapus yang dipilih';

  @override
  String get exportAction => 'Ekspor';

  @override
  String get refreshAction => 'Segarkan';

  @override
  String get selectAllAction => 'Pilih Semua';

  @override
  String get clearAction => 'Bersihkan';

  @override
  String selectedCountFormat(int selected, int total) {
    return '$selected / $total';
  }

  @override
  String get loadingFavoritesMessage => 'Memuat favorit...';

  @override
  String get deletingFavoritesMessage => 'Menghapus favorit...';

  @override
  String get removingFromFavoritesMessage => 'Menghapus dari favorit...';

  @override
  String get favoritesDeletedMessage => 'Favorit berhasil dihapus';

  @override
  String get failedToDeleteFavoritesMessage => 'Gagal menghapus favorit';

  @override
  String get confirmDeleteFavoritesTitle => 'Hapus Favorit';

  @override
  String confirmDeleteFavoritesMessage(int count, String plural) {
    return 'Apakah Anda yakin ingin menghapus $count favorit?';
  }

  @override
  String get exportFavoritesTitle => 'Ekspor Favorit';

  @override
  String get exportingFavoritesMessage => 'Mengekspor favorit...';

  @override
  String get favoritesExportedMessage => 'Favorit berhasil diekspor';

  @override
  String get failedToExportFavoritesMessage => 'Gagal mengekspor favorit';

  @override
  String get searchFavoritesHint => 'Cari favorit...';

  @override
  String get searchOfflineContentHint => 'Cari konten offline...';

  @override
  String failedToLoadPage(int pageNumber) {
    return 'Gagal memuat halaman $pageNumber';
  }

  @override
  String get failedToLoad => 'Gagal memuat';

  @override
  String get loginRequiredForAction => 'Masuk diperlukan untuk tindakan ini';

  @override
  String get login => 'Masuk';

  @override
  String get offlineContentTitle => 'Konten Offline';

  @override
  String get offlineContentError => 'Kesalahan Konten Offline';

  @override
  String get favorited => 'Difavoritkan';

  @override
  String get favorite => 'Favorit';

  @override
  String get errorLoadingHistory => 'Kesalahan Memuat Riwayat';

  @override
  String get errorLoadingFavoritesTitle => 'Kesalahan Memuat Favorit';

  @override
  String get filterDataTitle => 'Filter Data';

  @override
  String searchFilterHint(String filterType) {
    return 'Cari $filterType...';
  }

  @override
  String selectedCountFormat2(int count) {
    return 'Dipilih ($count)';
  }

  @override
  String get errorLoadingFilterDataTitle => 'Kesalahan memuat data filter';

  @override
  String noFilterTypeAvailable(String filterType) {
    return 'Tidak ada $filterType tersedia';
  }

  @override
  String noResultsFoundForQuery(String query) {
    return 'Tidak ada hasil untuk \"$query\"';
  }

  @override
  String get contentNotFoundTitle => 'Konten Tidak Ditemukan';

  @override
  String contentNotFoundMessage(String contentId) {
    return 'Konten dengan ID \"$contentId\" tidak ditemukan.';
  }

  @override
  String get filterCategoriesTitle => 'Kategori Filter';

  @override
  String get searchTitle => 'Cari';

  @override
  String get advancedSearchTitle => 'Pencarian Lanjutan';

  @override
  String get enterSearchQueryHint => 'Cari (contoh: \"gunung berapi\")';

  @override
  String get popularSearchesTitle => 'Pencarian Populer';

  @override
  String get clearAllAction => 'Bersihkan Semua';

  @override
  String get pressSearchButtonMessage => 'Cari dengan filter saat ini';

  @override
  String get searchingMessage => 'Mencari...';

  @override
  String resultsCountFormat(String count) {
    return '$count hasil';
  }

  @override
  String get viewInMainAction => 'Lihat di Utama';

  @override
  String get searchErrorTitle => 'Kesalahan Pencarian';

  @override
  String get noResultsFoundTitle => 'Tidak ada hasil';

  @override
  String pageText(int pageNumber) {
    return 'halaman $pageNumber';
  }

  @override
  String pagesText(int startPage, int endPage) {
    return 'halaman $startPage-$endPage';
  }

  @override
  String get offlineStatus => 'OFFLINE';

  @override
  String get onlineStatus => 'ONLINE';

  @override
  String get sortBy => 'Urutkan berdasarkan';

  @override
  String get errorOccurred => 'Terjadi kesalahan';

  @override
  String get tapToRetry => 'Ketuk untuk mencoba lagi';

  @override
  String get helpTitle => 'Bantuan';

  @override
  String get helpNoResults => 'Tidak ada hasil ditemukan untuk pencarian Anda';

  @override
  String get helpTryDifferent =>
      'Coba gunakan kata kunci yang berbeda atau periksa ejaan';

  @override
  String get helpUseFilters => 'Gunakan filter untuk mempersempit pencarian';

  @override
  String get helpCheckConnection => 'Periksa koneksi internet Anda';

  @override
  String get sendReportText => 'Kirim Laporan';

  @override
  String get technicalDetailsTitle => 'Detail Teknis';

  @override
  String get reportSentText => 'Laporan terkirim!';

  @override
  String get suggestionCheckConnection => 'Periksa koneksi internet Anda';

  @override
  String get suggestionTryWifiMobile =>
      'Coba beralih antara Wi-Fi dan data seluler';

  @override
  String get suggestionRestartRouter => 'Restart router jika menggunakan Wi-Fi';

  @override
  String get suggestionCheckWebsite => 'Periksa apakah situs web sedang down';

  @override
  String noContentFoundWithQuery(String query) {
    return 'Tidak ada konten ditemukan untuk \"$query\". Coba sesuaikan istilah pencarian atau filter.';
  }

  @override
  String get noContentFound =>
      'Tidak ada konten ditemukan. Coba sesuaikan istilah pencarian atau filter.';

  @override
  String get suggestionTryDifferentKeywords => 'Coba kata kunci yang berbeda';

  @override
  String get suggestionRemoveFilters => 'Hapus beberapa filter';

  @override
  String get suggestionCheckSpelling => 'Periksa ejaan';

  @override
  String get suggestionUseBroaderTerms =>
      'Gunakan istilah pencarian yang lebih luas';

  @override
  String get underMaintenanceTitle => 'Sedang Pemeliharaan';

  @override
  String get underMaintenanceMessage =>
      'Layanan sedang dalam pemeliharaan. Silakan coba lagi nanti.';

  @override
  String get suggestionMaintenanceHours =>
      'Pemeliharaan biasanya memakan waktu beberapa jam';

  @override
  String get suggestionCheckSocial => 'Periksa media sosial untuk pembaruan';

  @override
  String get suggestionTryLater => 'Coba lagi nanti';

  @override
  String get includeFilter => 'Sertakan';

  @override
  String get excludeFilter => 'Kecualikan';

  @override
  String get overallProgress => 'Progres Keseluruhan';

  @override
  String get active => 'Aktif';

  @override
  String get queued => 'Antri';

  @override
  String get speed => 'Kecepatan';

  @override
  String downloadsFailed(int count, String plural) {
    return '$count unduhan gagal';
  }

  @override
  String get view => 'Lihat';

  @override
  String get processing => 'Memproses...';

  @override
  String get loading => 'Memuat...';

  @override
  String get unknownTitle => 'Judul Tidak Diketahui';

  @override
  String get readingCompleted => 'Selesai';

  @override
  String get readAgain => 'Baca Lagi';

  @override
  String get continueReading => 'Lanjutkan';

  @override
  String get removeFromHistory => 'Hapus dari Riwayat';

  @override
  String get lessThanOneMinute => 'Kurang dari 1 menit';

  @override
  String get readingTime => 'waktu baca';

  @override
  String get downloadActions => 'Tindakan Unduhan';

  @override
  String get pause => 'Jeda';

  @override
  String get resume => 'Lanjutkan';

  @override
  String get cancel => 'Batal';

  @override
  String get retry => 'Coba Lagi';

  @override
  String get details => 'Detail';

  @override
  String get remove => 'Hapus';

  @override
  String get downloadActionPause => 'Jeda';

  @override
  String get downloadActionResume => 'Lanjutkan';

  @override
  String get downloadActionCancel => 'Batalkan';

  @override
  String get downloadActionRetry => 'Coba Lagi';

  @override
  String get downloadActionConvertToPdf => 'Ubah ke PDF';

  @override
  String get downloadActionDetails => 'Detail';

  @override
  String get downloadActionRemove => 'Hapus';

  @override
  String downloadPagesRangeFormat(
      int downloaded, int total, int start, int end, int totalPages) {
    return '$downloaded/$total (Halaman $start-$end dari $totalPages)';
  }

  @override
  String downloadPagesFormat(int downloaded, int total) {
    return '$downloaded/$total';
  }

  @override
  String downloadContentTitle(String contentId) {
    return 'Konten $contentId';
  }

  @override
  String downloadEtaLabel(String duration) {
    return 'Perkiraan: $duration';
  }

  @override
  String get duration => 'Durasi';

  @override
  String get downloadSettingsTitle => 'Pengaturan Unduhan';

  @override
  String get performanceSection => 'Performa';

  @override
  String get maxConcurrentDownloads => 'Unduhan Bersamaan Maksimal';

  @override
  String get concurrentDownloadsWarning =>
      'Nilai tinggi mungkin menggunakan lebih banyak bandwidth dan sumber daya perangkat';

  @override
  String get imageQualityLabel => 'Kualitas Gambar';

  @override
  String get autoRetrySection => 'Ulangi Otomatis';

  @override
  String get autoRetryFailedDownloads => 'Ulangi Unduhan Gagal Otomatis';

  @override
  String get autoRetryDescription =>
      'Secara otomatis mencoba ulang unduhan yang gagal';

  @override
  String get maxRetryAttempts => 'Percobaan Ulang Maksimal';

  @override
  String get networkSection => 'Jaringan';

  @override
  String get wifiOnlyLabel => 'Hanya Wi-Fi';

  @override
  String get wifiOnlyDescription => 'Hanya unduh saat terhubung ke Wi-Fi';

  @override
  String get downloadTimeoutLabel => 'Batas Waktu Unduhan';

  @override
  String get notificationsSection => 'Notifikasi';

  @override
  String get enableNotificationsLabel => 'Aktifkan Notifikasi';

  @override
  String get enableNotificationsDescription =>
      'Tampilkan notifikasi untuk progres unduhan';

  @override
  String get minutesUnit => 'mnt';

  @override
  String get searchContentHint => 'Cari konten...';

  @override
  String get hideFiltersTooltip => 'Sembunyikan filter';

  @override
  String get showMoreFiltersTooltip => 'Tampilkan lebih banyak filter';

  @override
  String get advancedFiltersTitle => 'Filter Lanjutan';

  @override
  String get sortByLabel => 'Urutkan berdasarkan';

  @override
  String get recentSearchesTitle => 'Pencarian Terbaru';

  @override
  String get includeTagsLabel => 'Sertakan tag (dipisahkan koma)';

  @override
  String get includeTagsHint => 'contoh: romansa, komedi, sekolah';

  @override
  String get excludeTagsHint => 'contoh: horor, kekerasan';

  @override
  String get artistsHint => 'contoh: artis1, artis2';

  @override
  String get pageCountRangeTitle => 'Rentang Jumlah Halaman';

  @override
  String get minPagesLabel => 'Halaman minimal';

  @override
  String get maxPagesLabel => 'Halaman maksimal';

  @override
  String get rangeToSeparator => 'hingga';

  @override
  String get popularTagsTitle => 'Tag Populer';

  @override
  String get filtersActiveLabel => 'aktif';

  @override
  String get clearAllFilters => 'Hapus Semua';

  @override
  String get appSubtitle => 'Pengalaman Membaca yang Ditingkatkan';

  @override
  String get initializingApp => 'Menginisialisasi Aplikasi...';

  @override
  String get settingUpComponents =>
      'Menyiapkan komponen dan memeriksa koneksi...';

  @override
  String get bypassingProtection =>
      'Melewati perlindungan dan membuat koneksi...';

  @override
  String get connectionFailed => 'Koneksi Gagal';

  @override
  String get readyToGo => 'Siap Digunakan!';

  @override
  String get launchingApp => 'Meluncurkan aplikasi utama...';

  @override
  String downloaded(String size) {
    return '$size diunduh';
  }

  @override
  String get imageNotAvailable => 'Gambar tidak tersedia';

  @override
  String loadingPage(int pageNumber) {
    return 'Memuat halaman $pageNumber...';
  }

  @override
  String pageNumber(int pageNumber) {
    return 'Halaman $pageNumber';
  }

  @override
  String get checkInternetConnection => 'Periksa koneksi internet Anda';

  @override
  String selectedItemsCount(int count) {
    return '$count terpilih';
  }

  @override
  String get removeFavorite => 'Hapus Favorit';

  @override
  String get noImage => 'Tidak ada gambar';

  @override
  String get youAreOfflineShort => 'Anda sedang offline';

  @override
  String get someFeaturesLimited =>
      'Beberapa fitur terbatas. Sambungkan ke internet untuk akses penuh.';

  @override
  String get wifi => 'WIFI';

  @override
  String get ethernet => 'ETHERNET';

  @override
  String get mobile => 'MOBILE';

  @override
  String get online => 'ONLINE';

  @override
  String get offlineMode => 'Mode Offline';

  @override
  String get applySearch => 'Terapkan Pencarian';

  @override
  String get addFiltersToSearch =>
      'Tambahkan filter di atas untuk mengaktifkan pencarian';

  @override
  String get startSearching => 'Mulai mencari';

  @override
  String get enterKeywordsAdvancedHint =>
      'Masukkan kata kunci, tag, atau gunakan filter lanjutan untuk menemukan konten';

  @override
  String get filtersReady => 'Filter Siap';

  @override
  String get clearAllFiltersTooltip => 'Bersihkan semua filter';

  @override
  String get offlineSomeFeaturesUnavailable =>
      'Anda sedang offline. Beberapa fitur mungkin tidak tersedia.';

  @override
  String get usingDownloadedContentOnly =>
      'Menggunakan konten yang diunduh saja';

  @override
  String get onlineModeWithNetworkAccess => 'Mode online dengan akses jaringan';

  @override
  String get tagsScreenPlaceholder => 'Layar Tag - Akan diimplementasikan';

  @override
  String get artistsScreenPlaceholder => 'Layar Artis - Akan diimplementasikan';

  @override
  String get statusScreenPlaceholder => 'Layar Status - Akan diimplementasikan';

  @override
  String get pageNotFound => 'Halaman Tidak Ditemukan';

  @override
  String pageNotFoundWithUri(String uri) {
    return 'Halaman tidak ditemukan: $uri';
  }

  @override
  String get goHome => 'Kembali ke Beranda';

  @override
  String get debugThemeInfo => 'DEBUG: Info Tema';

  @override
  String get lightTheme => 'Terang';

  @override
  String get darkTheme => 'Gelap';

  @override
  String get amoledTheme => 'AMOLED';

  @override
  String get systemMessages => 'Pesan Sistem dan Layanan Latar Belakang';

  @override
  String get notificationMessages => 'Pesan Notifikasi';

  @override
  String convertingToPdfWithTitle(String title) {
    return 'Mengonversi $title ke PDF...';
  }

  @override
  String convertingToPdfProgress(Object progress) {
    return 'Mengonversi ke PDF ($progress%)';
  }

  @override
  String convertingToPdfProgressWithTitle(String title, int progress) {
    return 'Mengonversi $title ke PDF ($progress%)';
  }

  @override
  String get progress => 'Progres';

  @override
  String get pdfCreatedSuccessfully => 'PDF Berhasil Dibuat';

  @override
  String pdfCreatedWithParts(String title, int partsCount) {
    return '$title dikonversi ke $partsCount file PDF';
  }

  @override
  String downloadStarted(String title) {
    return 'Unduhan Dimulai';
  }

  @override
  String downloadingWithTitle(String title) {
    return 'Mengunduh: $title';
  }

  @override
  String downloadingProgress(Object progress) {
    return 'Mengunduh ($progress%)';
  }

  @override
  String get downloadComplete => 'Unduhan Selesai';

  @override
  String downloadedWithTitle(String title) {
    return 'Diunduh: $title';
  }

  @override
  String get downloadFailed => 'Unduhan Gagal';

  @override
  String downloadFailedWithTitle(String title) {
    return 'Gagal: $title';
  }

  @override
  String get downloadPaused => 'Dijeda';

  @override
  String get downloadResumed => 'Dilanjutkan';

  @override
  String get downloadCancelled => 'Dibatalkan';

  @override
  String get downloadRetry => 'Coba Lagi';

  @override
  String get downloadOpen => 'Buka';

  @override
  String get pdfOpen => 'Buka PDF';

  @override
  String get pdfShare => 'Bagikan';

  @override
  String get pdfRetry => 'Coba Lagi PDF';

  @override
  String get downloadServiceMessages => 'Pesan Layanan Unduhan';

  @override
  String downloadRangeInfo(int startPage, int endPage) {
    return ' (Halaman $startPage-$endPage)';
  }

  @override
  String downloadRangeComplete(int startPage, int endPage) {
    return ' (Halaman $startPage-$endPage)';
  }

  @override
  String get startPage => 'Halaman Awal';

  @override
  String get endPage => 'Halaman Akhir';

  @override
  String invalidPageRange(int start, int end, int total) {
    return 'Rentang halaman tidak valid: $start-$end (total: $total)';
  }

  @override
  String get storagePermissionRequired =>
      'Izin penyimpanan diperlukan untuk unduhan. Harap berikan izin penyimpanan di pengaturan aplikasi.';

  @override
  String noDataReceived(String url) {
    return 'Tidak ada data yang diterima untuk gambar: $url';
  }

  @override
  String createdNoMediaFile(String path) {
    return 'File .nomedia dibuat untuk privasi: $path';
  }

  @override
  String get privacyProtectionEnsured =>
      'Perlindungan privasi dipastikan untuk unduhan yang ada';

  @override
  String get pdfConversionMessages => 'Pesan Layanan Konversi PDF';

  @override
  String pdfConversionStarted(String contentId) {
    return 'Konversi PDF dimulai untuk $contentId';
  }

  @override
  String pdfConversionCompleted(String contentId) {
    return 'Konversi PDF berhasil diselesaikan untuk $contentId';
  }

  @override
  String pdfConversionFailed(String contentId, String error) {
    return 'Konversi PDF gagal untuk $contentId: $error';
  }

  @override
  String pdfPartProcessing(int part) {
    return 'Memproses bagian $part dalam isolate...';
  }

  @override
  String get pdfSingleProcessing => 'Memproses PDF tunggal dalam isolate...';

  @override
  String pdfSplitRequired(int totalParts, int totalPages) {
    return 'Memisahkan menjadi $totalParts bagian ($totalPages halaman)';
  }

  @override
  String get totalPages => 'Total Halaman';

  @override
  String pdfCreatedFiles(int partsCount, int pageCount) {
    return 'Dibuat $partsCount file PDF dengan $pageCount total halaman';
  }

  @override
  String get pdfNoImagesProvided =>
      'Tidak ada gambar yang disediakan untuk konversi PDF';

  @override
  String pdfFailedToCreatePart(int part, String error) {
    return 'Gagal membuat bagian PDF $part: $error';
  }

  @override
  String pdfFailedToCreate(String error) {
    return 'Gagal membuat PDF: $error';
  }

  @override
  String pdfOutputDirectoryCreated(String path) {
    return 'Direktori output PDF dibuat: $path';
  }

  @override
  String pdfUsingFallbackDirectory(String path) {
    return 'Menggunakan direktori fallback: $path';
  }

  @override
  String pdfInfoSaved(String contentId, int partsCount, int pageCount) {
    return 'Info PDF disimpan untuk $contentId ($partsCount bagian, $pageCount halaman)';
  }

  @override
  String pdfExistsForContent(String contentId, String exists) {
    return 'PDF ada untuk $contentId: $exists';
  }

  @override
  String pdfFoundFiles(String contentId, int count) {
    return 'Ditemukan $count file PDF untuk $contentId';
  }

  @override
  String pdfDeletedFiles(String contentId, int count) {
    return 'Berhasil menghapus $count file PDF untuk $contentId';
  }

  @override
  String pdfTotalSize(String contentId, int sizeBytes) {
    return 'Total ukuran PDF untuk $contentId: $sizeBytes bytes';
  }

  @override
  String pdfCleanupStarted(int maxAge) {
    return 'Memulai pembersihan PDF, menghapus file yang lebih lama dari $maxAge hari';
  }

  @override
  String pdfCleanupCompleted(int deletedCount) {
    return 'Pembersihan selesai, menghapus $deletedCount file PDF lama';
  }

  @override
  String pdfStatistics(Object averageFilesPerContent, Object totalFiles,
      Object totalSizeFormatted, Object uniqueContents) {
    return 'Statistik PDF - $totalFiles file, $totalSizeFormatted total ukuran, $uniqueContents konten unik, $averageFilesPerContent rata-rata file per konten';
  }

  @override
  String get historyCleanupMessages => 'Pesan Layanan Pembersihan Riwayat';

  @override
  String get historyCleanupServiceInitialized =>
      'Layanan Pembersihan Riwayat diinisialisasi';

  @override
  String get historyCleanupServiceDisposed =>
      'Layanan Pembersihan Riwayat dibuang';

  @override
  String get autoCleanupDisabled =>
      'Pembersihan otomatis riwayat dinonaktifkan';

  @override
  String cleanupServiceStarted(int intervalHours) {
    return 'Layanan pembersihan dimulai dengan interval $intervalHours jam';
  }

  @override
  String performingHistoryCleanup(String reason) {
    return 'Melakukan pembersihan riwayat: $reason';
  }

  @override
  String historyCleanupCompleted(int clearedCount, String reason) {
    return 'Pembersihan riwayat selesai: membersihkan $clearedCount entri ($reason)';
  }

  @override
  String get manualHistoryCleanup => 'Melakukan pembersihan riwayat manual';

  @override
  String get updatedLastAppAccess =>
      'Memperbarui waktu akses aplikasi terakhir';

  @override
  String get updatedLastCleanupTime => 'Memperbarui waktu pembersihan terakhir';

  @override
  String intervalCleanup(int intervalHours) {
    return 'Pembersihan interval ($intervalHours jam)';
  }

  @override
  String inactivityCleanup(int inactivityDays) {
    return 'Pembersihan tidak aktif ($inactivityDays hari)';
  }

  @override
  String maxAgeCleanup(int maxDays) {
    return 'Pembersihan usia maksimal ($maxDays hari)';
  }

  @override
  String get initialCleanupSetup => 'Pengaturan pembersihan awal';

  @override
  String shouldCleanupOldHistory(String shouldCleanup) {
    return 'Harus membersihkan riwayat lama: $shouldCleanup';
  }

  @override
  String get analyticsMessages => 'Pesan Layanan Analytics';

  @override
  String analyticsServiceInitialized(String enabled) {
    return 'Layanan analytics diinisialisasi - pelacakan $enabled';
  }

  @override
  String get analyticsTrackingEnabled =>
      'Pelacakan analytics diaktifkan oleh pengguna';

  @override
  String get analyticsTrackingDisabled =>
      'Pelacakan analytics dinonaktifkan oleh pengguna - data dibersihkan';

  @override
  String get analyticsDataCleared =>
      'Data analytics dibersihkan atas permintaan pengguna';

  @override
  String get analyticsServiceDisposed => 'Layanan analytics dibuang';

  @override
  String analyticsEventTracked(String eventType, String eventName) {
    return '📊 Analytics: $eventType - $eventName';
  }

  @override
  String get appStartedEvent => 'Event aplikasi dimulai dilacak';

  @override
  String sessionEndEvent(int minutes) {
    return 'Event akhir sesi dilacak ($minutes menit)';
  }

  @override
  String get analyticsEnabledEvent => 'Event analytics diaktifkan dilacak';

  @override
  String get analyticsDisabledEvent => 'Event analytics dinonaktifkan dilacak';

  @override
  String screenViewEvent(String screenName) {
    return 'Tampilan layar dilacak: $screenName';
  }

  @override
  String userActionEvent(String action) {
    return 'Aksi pengguna dilacak: $action';
  }

  @override
  String performanceEvent(String operation, int durationMs) {
    return 'Performa dilacak: $operation (${durationMs}ms)';
  }

  @override
  String errorEvent(String errorType, String errorMessage) {
    return 'Kesalahan dilacak: $errorType - $errorMessage';
  }

  @override
  String featureUsageEvent(String feature) {
    return 'Penggunaan fitur dilacak: $feature';
  }

  @override
  String readingSessionEvent(String contentId, int minutes, int pages) {
    return 'Sesi membaca dilacak: $contentId (${minutes}mnt, $pages halaman)';
  }

  @override
  String get pages => 'Halaman';

  @override
  String get offlineManagerMessages => 'Pesan Manajer Konten Offline';

  @override
  String offlineContentAvailable(String contentId, String available) {
    return 'Konten Offline Tersedia';
  }

  @override
  String offlineContentPath(String contentId, String path) {
    return 'Path konten offline untuk $contentId: $path';
  }

  @override
  String foundExistingFiles(int count) {
    return 'Ditemukan $count file yang sudah diunduh';
  }

  @override
  String offlineImageUrlsFound(String contentId, int count) {
    return 'Ditemukan $count URL gambar offline untuk $contentId';
  }

  @override
  String offlineContentIdsFound(int count) {
    return 'Ditemukan $count ID konten offline';
  }

  @override
  String searchingOfflineContent(String query) {
    return 'Mencari konten offline untuk: $query';
  }

  @override
  String offlineContentMetadata(String contentId, String source) {
    return 'Metadata konten offline untuk $contentId: $source';
  }

  @override
  String offlineContentCreated(String contentId) {
    return 'Konten offline dibuat untuk $contentId';
  }

  @override
  String offlineStorageUsage(int sizeBytes) {
    return 'Penggunaan penyimpanan offline: $sizeBytes bytes';
  }

  @override
  String get cleanupOrphanedFilesStarted =>
      'Memulai pembersihan file offline yang yatim piatu';

  @override
  String get cleanupOrphanedFilesCompleted =>
      'Pembersihan file offline yang yatim piatu selesai';

  @override
  String removedOrphanedDirectory(String path) {
    return 'Direktori yatim piatu dihapus: $path';
  }

  @override
  String daysAgo(int count, String suffix) {
    return '$count hari$suffix yang lalu';
  }

  @override
  String hoursAgo(int count, String suffix) {
    return '$count jam$suffix yang lalu';
  }

  @override
  String minutesAgo(int count, String suffix) {
    return '$count menit$suffix yang lalu';
  }

  @override
  String get justNow => 'Baru saja';

  @override
  String get queryLabel => 'Kueri';

  @override
  String get tagsLabel => 'Tag';

  @override
  String get excludeTagsLabel => 'Kecualikan Tag';

  @override
  String get groupsLabel => 'Grup';

  @override
  String get excludeGroupsLabel => 'Kecualikan Grup';

  @override
  String get charactersLabel => 'Karakter';

  @override
  String get excludeCharactersLabel => 'Kecualikan Karakter';

  @override
  String get parodiesLabel => 'Parodi';

  @override
  String get excludeParodiesLabel => 'Kecualikan Parodi';

  @override
  String get artistsLabel => 'Artis';

  @override
  String get excludeArtistsLabel => 'Kecualikan Artis';

  @override
  String get languageLabel => 'Bahasa';

  @override
  String get categoryLabel => 'Kategori';

  @override
  String hours(int count) {
    return '${count}j';
  }

  @override
  String minutes(int count) {
    return '${count}m';
  }

  @override
  String seconds(int count) {
    return '${count}d';
  }

  @override
  String get loadingUserPreferences => 'Memuat preferensi pengguna';

  @override
  String get successfullyLoadedUserPreferences =>
      'Berhasil memuat preferensi pengguna';

  @override
  String invalidColumnsPortraitValue(int value) {
    return 'Nilai kolom potret tidak valid: $value';
  }

  @override
  String invalidColumnsLandscapeValue(int value) {
    return 'Nilai kolom lanskap tidak valid: $value';
  }

  @override
  String get updatingSettingsViaPreferencesService =>
      'Memperbarui pengaturan melalui PreferencesService';

  @override
  String get successfullyUpdatedSettings => 'Berhasil memperbarui pengaturan';

  @override
  String failedToUpdateSetting(String error) {
    return 'Gagal memperbarui pengaturan: $error';
  }

  @override
  String get resettingAllSettingsToDefaults =>
      'Mereset semua pengaturan ke default';

  @override
  String get successfullyResetAllSettingsToDefaults =>
      'Berhasil mereset semua pengaturan ke default';

  @override
  String failedToResetSettings(String error) {
    return 'Gagal mengatur ulang pengaturan: $error';
  }

  @override
  String get settingsNotLoaded => 'Pengaturan tidak dimuat';

  @override
  String get exportingSettings => 'Mengekspor pengaturan';

  @override
  String get successfullyExportedSettings => 'Berhasil mengekspor pengaturan';

  @override
  String failedToExportSettings(String error) {
    return 'Gagal mengekspor pengaturan: $error';
  }

  @override
  String get importingSettings => 'Mengimpor pengaturan';

  @override
  String get successfullyImportedSettings => 'Berhasil mengimpor pengaturan';

  @override
  String failedToImportSettings(String error) {
    return 'Gagal mengimpor pengaturan: $error';
  }

  @override
  String get unableToSyncSettings =>
      'Tidak dapat menyinkronkan pengaturan. Perubahan akan disimpan secara lokal.';

  @override
  String get unableToSaveSettings =>
      'Tidak dapat menyimpan pengaturan. Silakan periksa penyimpanan perangkat.';

  @override
  String get failedToUpdateSettings =>
      'Gagal memperbarui pengaturan. Silakan coba lagi.';

  @override
  String get loadingHistory => 'Memuat riwayat';

  @override
  String get noHistoryFound => 'Tidak ada riwayat ditemukan';

  @override
  String loadedHistoryEntries(int count) {
    return 'Memuat $count entri riwayat';
  }

  @override
  String failedToLoadHistory(String error) {
    return 'Gagal memuat riwayat: $error';
  }

  @override
  String loadingMoreHistory(int page) {
    return 'Memuat lebih banyak riwayat (halaman $page)';
  }

  @override
  String loadedMoreHistoryEntries(int count, int total) {
    return 'Memuat $count entri lagi, total: $total';
  }

  @override
  String get refreshingHistory => 'Menyegarkan riwayat';

  @override
  String refreshedHistoryWithEntries(int count) {
    return 'Riwayat disegarkan dengan $count entri';
  }

  @override
  String failedToRefreshHistory(String error) {
    return 'Gagal menyegarkan riwayat: $error';
  }

  @override
  String get clearingAllHistory => 'Menghapus semua riwayat';

  @override
  String get allHistoryCleared => 'Semua riwayat dihapus';

  @override
  String failedToClearHistory(String error) {
    return 'Gagal menghapus riwayat: $error';
  }

  @override
  String removingHistoryItem(String contentId) {
    return 'Menghapus item riwayat: $contentId';
  }

  @override
  String removedHistoryItem(String contentId) {
    return 'Item riwayat dihapus: $contentId';
  }

  @override
  String failedToRemoveHistoryItem(String error) {
    return 'Gagal menghapus item riwayat: $error';
  }

  @override
  String get performingManualHistoryCleanup =>
      'Melakukan pembersihan riwayat manual';

  @override
  String get manualCleanupCompleted => 'Pembersihan manual selesai';

  @override
  String failedToPerformCleanup(String error) {
    return 'Gagal melakukan pembersihan: $error';
  }

  @override
  String get updatingCleanupSettings => 'Memperbarui pengaturan pembersihan';

  @override
  String get cleanupSettingsUpdated => 'Pengaturan pembersihan diperbarui';

  @override
  String addingContentToFavorites(String title) {
    return 'Menambahkan konten ke favorit: $title';
  }

  @override
  String successfullyAddedToFavorites(String title) {
    return 'Berhasil ditambahkan ke favorit: $title';
  }

  @override
  String contentNotInFavorites(String contentId) {
    return 'Konten $contentId tidak ada di favorit, melewati penghapusan';
  }

  @override
  String callingRemoveFromFavoritesUseCase(String params) {
    return 'Memanggil removeFromFavoritesUseCase dengan parameter: $params';
  }

  @override
  String get successfullyCalledRemoveFromFavoritesUseCase =>
      'Berhasil memanggil removeFromFavoritesUseCase';

  @override
  String updatingFavoritesListInState(String contentId) {
    return 'Memperbarui daftar favorit di state, menghapus contentId: $contentId';
  }

  @override
  String favoritesCountBeforeAfter(int before, int after) {
    return 'Jumlah favorit: sebelum=$before, setelah=$after';
  }

  @override
  String get stateUpdatedSuccessfully => 'State berhasil diperbarui';

  @override
  String successfullyRemovedFromFavorites(String contentId) {
    return 'Berhasil dihapus dari favorit: $contentId';
  }

  @override
  String errorRemovingContentFromFavorites(String contentId, String error) {
    return 'Kesalahan menghapus konten $contentId dari favorit: $error';
  }

  @override
  String removingFavoritesInBatch(int count) {
    return 'Menghapus $count favorit dalam batch';
  }

  @override
  String successfullyRemovedFavoritesInBatch(int count) {
    return 'Berhasil menghapus $count favorit dalam batch';
  }

  @override
  String searchingFavoritesWithQuery(String query) {
    return 'Mencari favorit dengan query: $query';
  }

  @override
  String foundFavoritesMatchingQuery(int count) {
    return 'Ditemukan $count favorit yang cocok dengan query';
  }

  @override
  String get clearingFavoritesSearch => 'Menghapus pencarian favorit';

  @override
  String get exportingFavoritesData => 'Mengekspor data favorit';

  @override
  String successfullyExportedFavorites(int count) {
    return 'Berhasil mengekspor $count favorit';
  }

  @override
  String get importingFavoritesData => 'Mengimpor data favorit';

  @override
  String successfullyImportedFavorites(int count) {
    return 'Berhasil mengimpor $count favorit';
  }

  @override
  String failedToImportFavorite(String error) {
    return 'Gagal mengimpor favorit: $error';
  }

  @override
  String get retryingFavoritesLoading => 'Mencoba lagi memuat favorit';

  @override
  String get refreshingFavorites => 'Menyegarkan favorit';

  @override
  String failedToLoadFavorites(String error) {
    return 'Gagal memuat favorit: $error';
  }

  @override
  String failedToInitializeDownloadManager(String error) {
    return 'Gagal menginisialisasi manajer unduhan: $error';
  }

  @override
  String get waitingForWifiConnection => 'Menunggu koneksi Wi-Fi';

  @override
  String failedToQueueDownload(String error) {
    return 'Gagal mengantri unduhan: $error';
  }

  @override
  String retryingDownload(int current, int total) {
    return 'Mencoba lagi... ($current/$total)';
  }

  @override
  String get downloadCancelledByUser => 'Unduhan dibatalkan oleh pengguna';

  @override
  String get pausingAllDownloads => 'Menjeda semua unduhan';

  @override
  String get resumingAllDownloads => 'Melanjutkan semua unduhan';

  @override
  String get cancellingAllDownloads => 'Membatalkan semua unduhan';

  @override
  String get clearingCompletedDownloads => 'Menghapus unduhan yang selesai';

  @override
  String failedToQueueRangeDownload(String error) {
    return 'Gagal mengantri unduhan rentang: $error';
  }

  @override
  String failedToPauseDownload(String error) {
    return 'Gagal menjeda unduhan: $error';
  }

  @override
  String failedToCancelDownload(String error) {
    return 'Gagal membatalkan unduhan: $error';
  }

  @override
  String failedToRetryDownload(String error) {
    return 'Gagal mencoba lagi unduhan: $error';
  }

  @override
  String failedToResumeDownload(String error) {
    return 'Gagal melanjutkan unduhan: $error';
  }

  @override
  String failedToRemoveDownload(String error) {
    return 'Gagal menghapus unduhan: $error';
  }

  @override
  String failedToRefreshDownloads(String error) {
    return 'Gagal menyegarkan unduhan: $error';
  }

  @override
  String failedToUpdateDownloadSettings(String error) {
    return 'Gagal memperbarui pengaturan unduhan: $error';
  }

  @override
  String failedToPauseAllDownloads(String error) {
    return 'Gagal menjeda semua unduhan: $error';
  }

  @override
  String failedToResumeAllDownloads(String error) {
    return 'Gagal melanjutkan semua unduhan: $error';
  }

  @override
  String failedToCancelAllDownloads(String error) {
    return 'Gagal membatalkan semua unduhan: $error';
  }

  @override
  String failedToClearCompletedDownloads(String error) {
    return 'Gagal menghapus unduhan yang selesai: $error';
  }

  @override
  String get downloadNotCompletedYet => 'Unduhan belum selesai';

  @override
  String get noImagesFoundForConversion =>
      'Tidak ada gambar yang ditemukan untuk konversi';

  @override
  String storageCleanupCompleted(int cleanedFiles, String freedSpace) {
    return 'Pembersihan penyimpanan selesai. Membersihkan $cleanedFiles direktori, membebaskan $freedSpace MB';
  }

  @override
  String storageCleanupComplete(int cleanedFiles, String freedSpace) {
    return 'Pembersihan Penyimpanan Selesai: Membersihkan $cleanedFiles item, membebaskan $freedSpace MB';
  }

  @override
  String storageCleanupFailed(String error) {
    return 'Pembersihan Penyimpanan Gagal: $error';
  }

  @override
  String exportDownloadsComplete(String fileName) {
    return 'Ekspor Selesai: Unduhan diekspor ke $fileName';
  }

  @override
  String exportFailed(String error) {
    return 'Ekspor Gagal: $error';
  }

  @override
  String failedToDeleteDirectory(String path, String error) {
    return 'Gagal menghapus direktori: $path, error: $error';
  }

  @override
  String failedToDeleteTempFile(String path, String error) {
    return 'Gagal menghapus file temp: $path, error: $error';
  }

  @override
  String downloadDirectoryNotFound(String path) {
    return 'Direktori unduhan tidak ditemukan: $path';
  }

  @override
  String cannotOpenIncompleteDownload(String contentId) {
    return 'Tidak dapat membuka - unduhan belum selesai atau path hilang untuk $contentId';
  }

  @override
  String allStrategiesFailedToOpenDownload(String contentId) {
    return 'Semua strategi gagal membuka konten yang diunduh untuk $contentId';
  }

  @override
  String failedToSaveProgressToDatabase(String error) {
    return 'Gagal menyimpan progress ke database: $error';
  }

  @override
  String failedToUpdatePauseNotification(String error) {
    return 'Gagal memperbarui notifikasi jeda: $error';
  }

  @override
  String failedToUpdateResumeNotification(String error) {
    return 'Gagal memperbarui notifikasi lanjut: $error';
  }

  @override
  String failedToUpdateNotificationProgress(String error) {
    return 'Gagal memperbarui progress notifikasi: $error';
  }

  @override
  String errorCalculatingDirectorySize(String error) {
    return 'Kesalahan menghitung ukuran direktori: $error';
  }

  @override
  String errorCleaningTempFiles(String path, String error) {
    return 'Kesalahan membersihkan file temp di: $path, kesalahan: $error';
  }

  @override
  String errorDetectingDownloadsDirectory(String error) {
    return 'Kesalahan mendeteksi direktori Unduhan: $error';
  }

  @override
  String usingEmergencyFallbackDirectory(String path) {
    return 'Menggunakan direktori fallback darurat: $path';
  }

  @override
  String get errorDuringStorageCleanup =>
      'Kesalahan selama pembersihan penyimpanan';

  @override
  String get errorDuringExport => 'Kesalahan selama ekspor';

  @override
  String errorDuringPdfConversion(String contentId) {
    return 'Kesalahan selama konversi PDF untuk $contentId';
  }

  @override
  String errorRetryingPdfConversion(String error) {
    return 'Kesalahan mencoba lagi konversi PDF: $error';
  }

  @override
  String errorOpeningDownloadedContent(String error) {
    return 'Kesalahan membuka konten yang diunduh: $error';
  }

  @override
  String get importBackupFolder => 'Impor Folder Cadangan';

  @override
  String get importBackupFolderDescription =>
      'Masukkan path ke folder backup yang berisi folder konten nhasix:';

  @override
  String get scanningBackupFolder => 'Memindai folder backup...';

  @override
  String backupContentFound(int count) {
    return 'Ditemukan $count item backup';
  }

  @override
  String get noBackupContentFound =>
      'Tidak ada konten valid ditemukan di folder backup';

  @override
  String errorScanningBackup(String error) {
    return 'Kesalahan memindai cadangan: $error';
  }

  @override
  String get themeDescription => 'Tema warna untuk antarmuka aplikasi.';

  @override
  String get imageQualityDescription => 'Kualitas gambar untuk unduhan.';

  @override
  String get gridColumnsDescription => 'Jumlah kolom grid dalam mode potret.';

  @override
  String get gridPreview => 'Pratinjau Grid';

  @override
  String get autoCleanupDescription =>
      'Kelola pembersihan otomatis riwayat baca untuk menghemat ruang penyimpanan.';

  @override
  String get testCacheClearing => 'Tes Pembersihan Cache Update App';

  @override
  String get testCacheClearingDescription =>
      'Simulasikan update aplikasi dan tes perilaku pembersihan cache.';

  @override
  String get forceClearCache => 'Paksa Bersihkan Semua Cache';

  @override
  String get forceClearCacheDescription =>
      'Bersihkan semua cache gambar secara manual.';

  @override
  String get runTest => 'Jalankan Tes';

  @override
  String get clearCacheButton => 'Bersihkan Cache';

  @override
  String get disguiseModeDescription =>
      'Tampilan aplikasi di launcher untuk privasi.';

  @override
  String get applyingDisguiseMode => 'Menerapkan perubahan mode penyamaran...';

  @override
  String get disguiseDefault => 'Default';

  @override
  String get disguiseCalculator => 'Kalkulator';

  @override
  String get disguiseNotes => 'Catatan';

  @override
  String get disguiseWeather => 'Cuaca';

  @override
  String get storagePermissionScan =>
      'Izin penyimpanan diperlukan untuk memindai folder backup';

  @override
  String get exportingLibrary => 'Mengekspor Perpustakaan';

  @override
  String get libraryExportSuccess => 'Perpustakaan berhasil diekspor!';

  @override
  String get browseDownloads => 'Jelajahi Unduhan';

  @override
  String deletingContent(String title) {
    return 'Menghapus $title...';
  }

  @override
  String contentDeletedFreed(String title, String size) {
    return '$title dihapus. Menghemat $size MB';
  }

  @override
  String get size => 'Ukuran';

  @override
  String failedToDeleteContent(String title) {
    return 'Gagal menghapus $title';
  }

  @override
  String errorGeneric(String error) {
    return 'Kesalahan: $error';
  }

  @override
  String get contentDeleted => 'Konten dihapus';

  @override
  String get cacheManagementDebug => '🚀 Manajemen Cache (Debug)';

  @override
  String get convertToPdf => 'Konversi ke PDF';

  @override
  String get convertingToPdf => 'Mengonversi ke PDF...';

  @override
  String pdfConversionFailedWithError(String title, String error) {
    return 'Konversi PDF gagal untuk $title: $error';
  }

  @override
  String get syncStarted => 'Menyinkronkan Cadangan...';

  @override
  String get syncStartedMessage => 'Memindai dan mengimpor konten offline';

  @override
  String syncInProgress(int percent) {
    return 'Menyinkronkan Cadangan ($percent%)';
  }

  @override
  String syncProgressMessage(int processed, int total) {
    return 'Diproses $processed dari $total item';
  }

  @override
  String get total => 'Total';

  @override
  String get syncCompleted => 'Sinkronisasi Selesai';

  @override
  String syncCompletedMessage(int synced, int updated) {
    return 'Diimpor: $synced, Diperbarui: $updated';
  }

  @override
  String syncResult(int synced, int updated) {
    return 'Hasil Sinkronisasi: $synced diimpor, $updated diperbarui';
  }

  @override
  String get storageSection => 'Lokasi Penyimpanan';

  @override
  String get storageLocation => 'Folder Unduhan Kustom';

  @override
  String get defaultStorage => 'Default (Internal)';

  @override
  String get storageDescription => 'Pilih folder untuk menyimpan unduhan';

  @override
  String get downloadDirectory => 'Direktori Unduhan';

  @override
  String get changeDirectory => 'Ubah Direktori';

  @override
  String get downloadDirectoryUpdated => 'Direktori unduhan diperbarui';

  @override
  String get useDefaultInternalStorage =>
      'Gunakan lokasi penyimpanan internal default';

  @override
  String get confirmResetStorageDirectory =>
      'Reset direktori unduhan ke penyimpanan internal default?';

  @override
  String get downloadDirectoryReset => 'Direktori unduhan direset ke default';

  @override
  String get backupNotFound => 'Cadangan Tidak Ditemukan';

  @override
  String get backupNotFoundMessage =>
      'Folder cadangan \'nhasix\' tidak ditemukan di lokasi default. Apakah Anda ingin memilih folder kustom yang berisi cadangan Anda?';

  @override
  String get selectFolder => 'Folder';

  @override
  String get premiumFeature => 'Fitur Premium';

  @override
  String get commentsMaintenance => 'Komentar Dalam Pemeliharaan';

  @override
  String get estimatedRecovery => 'Perkiraan Pemulihan';

  @override
  String get fullColor => 'full color';

  @override
  String downloadBlocInitializedWithDownloads(int count) {
    return 'DownloadBloc: Diinisialisasi dengan $count unduhan';
  }

  @override
  String get downloadBlocProgressStreamSubscriptionInitialized =>
      'DownloadBloc: Langganan stream progress diinisialisasi';

  @override
  String get downloadBlocNotificationCallbacksConfigured =>
      'DownloadBloc: Callback notifikasi dikonfigurasi';

  @override
  String downloadBlocReceivedProgressUpdate(String update) {
    return 'DownloadBloc: Menerima pembaruan progress: $update';
  }

  @override
  String downloadBlocReceivedCompletionEvent(String contentId) {
    return 'DownloadBloc: Menerima event penyelesaian untuk $contentId';
  }

  @override
  String downloadBlocProgressStreamError(String error) {
    return 'DownloadBloc: Kesalahan stream progress: $error';
  }

  @override
  String notificationActionPauseRequested(String contentId) {
    return 'NotificationAction: Pause diminta untuk $contentId';
  }

  @override
  String notificationActionResumeRequested(String contentId) {
    return 'NotificationAction: Resume diminta untuk $contentId';
  }

  @override
  String notificationActionCancelRequested(String contentId) {
    return 'NotificationAction: Cancel diminta untuk $contentId';
  }

  @override
  String notificationActionRetryRequested(String contentId) {
    return 'NotificationAction: Retry diminta untuk $contentId';
  }

  @override
  String notificationActionPdfRetryRequested(String contentId) {
    return 'NotificationAction: PDF retry diminta untuk $contentId';
  }

  @override
  String notificationActionOpenDownloadRequested(String contentId) {
    return 'NotificationAction: Open download diminta untuk $contentId';
  }

  @override
  String notificationActionNavigateToDownloadsRequested(String contentId) {
    return 'NotificationAction: Navigasi ke downloads diminta untuk $contentId';
  }

  @override
  String get downloadBlocErrorInitializing =>
      'DownloadBloc: Kesalahan saat inisialisasi';

  @override
  String downloadBlocFailedToReadDownloadBlocState(String error) {
    return 'Gagal membaca state DownloadBloc, kembali ke pengecekan filesystem: $error';
  }

  @override
  String get sourceSelectorSelectSource => 'Sumber';

  @override
  String get sourceSelectorDescription =>
      'Ganti provider untuk feed, detail, pencarian, dan data reader.';

  @override
  String get sourceSelectorNoSourceSelected => 'Belum ada sumber dipilih';

  @override
  String get sourceSelectorActiveSource => 'Sumber aktif';

  @override
  String get sourceSelectorUnderMaintenance => 'Dalam pemeliharaan';

  @override
  String get sourceSelectorCurrentlySelected => 'Sedang dipilih';

  @override
  String get sourceSelectorTapToSwitch => 'Ketuk untuk mengganti';

  @override
  String get sourceSelectorSearchHint => 'Cari sumber';

  @override
  String get sourceSelectorNoResults => 'Tidak ada sumber yang cocok';

  @override
  String get settingsCustomSourceTitle => 'Tambah Sumber Kustom';

  @override
  String get settingsCustomSourceSubtitle =>
      'Pasang paket sumber dari URL manifest bertanda tangan atau paket ZIP.';

  @override
  String get settingsAddViaLink => 'Tambah via Link';

  @override
  String get settingsImportZip => 'Impor ZIP';

  @override
  String get sourceImportLinkDialogTitle => 'Pasang Sumber via Link';

  @override
  String get sourceImportConfigUrlLabel => 'URL Manifest';

  @override
  String get sourceImportConfigUrlHint =>
      'https://example.com/source-manifest.json';

  @override
  String get sourceImportInstallingFromLink => 'Memasang sumber dari link...';

  @override
  String get sourceImportInstallingFromZip => 'Mengimpor sumber dari ZIP...';

  @override
  String get sourceImportPreviewTitle => 'Pratinjau Instalasi Sumber';

  @override
  String get sourceImportPreviewSourceId => 'ID Sumber';

  @override
  String get sourceImportPreviewVersion => 'Versi';

  @override
  String get sourceImportPreviewDisplayName => 'Nama tampilan';

  @override
  String get sourceImportPreviewVerified => 'Integritas';

  @override
  String get sourceImportPreviewVerifiedYes => 'Terverifikasi';

  @override
  String get sourceImportPreviewVerifiedNo => 'Tidak terverifikasi';

  @override
  String get sourceImportConfirmInstall => 'Pasang';

  @override
  String get sourceImportManifestInvalid =>
      'Format manifest sumber tidak valid.';

  @override
  String get sourceImportConfigEmpty =>
      'Konfigurasi sumber yang diunduh kosong.';

  @override
  String get sourceImportZipManifestRequired =>
      'ZIP harus berisi manifest.json.';

  @override
  String get sourceImportChecksumMismatch =>
      'Verifikasi checksum sumber gagal.';

  @override
  String get sourceImportSourceMismatch =>
      'ID sumber antara manifest dan config tidak cocok.';

  @override
  String sourceImportInstalledFromLink(String sourceId) {
    return '$sourceId berhasil dipasang dari link';
  }

  @override
  String sourceImportInstalledFromZip(String sourceId) {
    return '$sourceId berhasil dipasang dari ZIP';
  }

  @override
  String sourceImportFailedFromLink(String error) {
    return 'Gagal memasang sumber dari link: $error';
  }

  @override
  String sourceImportFailedFromZip(String error) {
    return 'Gagal mengimpor sumber ZIP: $error';
  }

  @override
  String get aboutTitle => 'Tentang';

  @override
  String get appIsUpToDate => 'Aplikasi sudah versi terbaru!';

  @override
  String checkFailedMessage(String message) {
    return 'Pemeriksaan gagal: $message';
  }

  @override
  String get updatesSection => 'Pembaruan';

  @override
  String get communityAndInfo => 'Komunitas & Info';

  @override
  String get githubRepository => 'Repositori GitHub';

  @override
  String get viewSourceCodeContribute => 'Lihat kode sumber & berkontribusi';

  @override
  String get openSourceLicenses => 'Lisensi Sumber Terbuka';

  @override
  String get librariesUsedInApp => 'Pustaka yang digunakan di aplikasi ini';

  @override
  String get builtWith => 'Dibangun Dengan';

  @override
  String get madeWithLoveBy => 'Dibuat dengan ❤️ oleh Shirokun20';

  @override
  String get allRightsReserved => '© 2025 Hak Cipta Dilindungi';

  @override
  String get appUpdates => 'Pembaruan Aplikasi';

  @override
  String get checkForUpdates => 'Periksa pembaruan';

  @override
  String get checking => 'Memeriksa...';

  @override
  String get updateAvailable => 'Pembaruan Tersedia!';

  @override
  String get upToDate => 'Sudah terbaru';

  @override
  String get checkFailed => 'Pemeriksaan gagal';

  @override
  String couldNotLaunchUrl(String url) {
    return 'Tidak bisa membuka $url';
  }

  @override
  String get solveCaptchaTitle => 'Selesaikan CAPTCHA';

  @override
  String get reloadChallenge => 'Muat ulang tantangan';

  @override
  String get loginToCrotpedia => 'Masuk ke Crotpedia';

  @override
  String syncedAsUser(String username) {
    return 'Tersinkronisasi sebagai $username';
  }

  @override
  String loggedInAsUser(String username) {
    return 'Masuk sebagai $username';
  }

  @override
  String get logout => 'Keluar';

  @override
  String get loginViaSecureBrowser => 'Masuk via Browser Aman';

  @override
  String get loginIncomplete => 'Masuk tidak lengkap. Silakan coba lagi.';

  @override
  String loginFailedError(String error) {
    return 'Masuk gagal: $error';
  }

  @override
  String get doujinListTitle => 'Daftar Doujin (A-Z)';

  @override
  String get errorLoadingDoujinList => 'Kesalahan Memuat Daftar Doujin';

  @override
  String get noDoujinsFound => 'Doujin Tidak Ditemukan';

  @override
  String get doujinListEmpty => 'Daftar doujin kosong.';

  @override
  String get searchDoujinsHint => 'Cari doujin...';

  @override
  String cannotParseSlug(String url) {
    return 'Tidak dapat mengurai slug dari URL: $url';
  }

  @override
  String errorParsingUrl(String url) {
    return 'Kesalahan mengurai URL: $url';
  }

  @override
  String get checkAll => 'Periksa Semua';

  @override
  String get copyPath => 'Salin path';

  @override
  String get createCollection => 'Buat koleksi';

  @override
  String daysAgoShort(Object days) {
    return '${days}hr yg lalu';
  }

  @override
  String get deleteCollection => 'Hapus koleksi';

  @override
  String deleteCollectionConfirm(Object name) {
    return 'Hapus \"$name\"? Favorit item tetap tersimpan, hanya pengelompokan koleksi yang dihapus.';
  }

  @override
  String deleteItems(Object count) {
    return 'Hapus $count item?';
  }

  @override
  String deletingItems(Object count) {
    return 'Menghapus $count item...';
  }

  @override
  String get doujinList => 'Daftar Doujin';

  @override
  String get downloadGalleryRange => 'Pilih rentang galeri';

  @override
  String get downloadGalleryRangeDesc =>
      'Menggunakan nomor halaman galeri asli.';

  @override
  String get downloadGalleryWide => 'Rentang seluruh galeri';

  @override
  String get downloadGalleryWideDesc =>
      'Menggunakan nomor halaman galeri E-Hentai asli.';

  @override
  String get downloadThisPart => 'Unduh bagian ini';

  @override
  String get downloadThisPartDesc => 'Mengunduh hanya bagian yang dipilih.';

  @override
  String get downloadWholeGallery => 'Unduh seluruh galeri';

  @override
  String get downloadWholeGalleryDesc =>
      'Antrikan setiap bagian sesuai urutan galeri.';

  @override
  String get ehentaiOnly => 'Hanya tersedia untuk galeri E-Hentai.';

  @override
  String get ehentaiOnlyDesc =>
      'Opsi unduh galeri untuk seluruh seri dan rentang hanya tersedia di E-Hentai.';

  @override
  String get ehentaiOnlyTitle => 'Khusus E-Hentai';

  @override
  String get genres => 'Genre';

  @override
  String get genreOptionsFailed => 'Opsi genre gagal';

  @override
  String get gitHubRaw => 'GitHub raw';

  @override
  String get hide => 'Sembunyikan';

  @override
  String get liveTags => 'Tag live';

  @override
  String get loadingGenreOptions => 'Memuat opsi genre';

  @override
  String monthsAgo(int months) {
    return '${months}bln yg lalu';
  }

  @override
  String get openInExplorer => 'Buka di explorer';

  @override
  String pageFailedDownload(Object page) {
    return 'Halaman $page gagal diunduh';
  }

  @override
  String pageInputPage(Object page) {
    return 'Halaman $page';
  }

  @override
  String get pathCopied => 'Path disalin ke clipboard';

  @override
  String get pathsCopied => 'Path disalin';

  @override
  String get reloadSearchUI => 'Muat ulang UI cari';

  @override
  String get reloadingSearchFilters => 'Memuat ulang filter';

  @override
  String get remoteSource => 'Sumber remote';

  @override
  String removeOfflineChapters(Object count) {
    return 'Hapus $count chapter offline?';
  }

  @override
  String get requestList => 'Daftar Permintaan';

  @override
  String get retryFetch => 'Ambil ulang';

  @override
  String get selectMode => 'Mode Pilih';

  @override
  String get showAvailability => 'Lihat ketersediaan';

  @override
  String showingFirstChapters(Object count) {
    return 'Menampilkan $count chapter pertama. Buka halaman detail dan gunakan \"Lihat Semua\" untuk lebih.';
  }

  @override
  String get sortAZ => 'A - Z';

  @override
  String get sortDirectionAZ => 'A - Z';

  @override
  String get sortDirectionZA => 'Z - A';

  @override
  String get sortNewToOld => 'Baru ke Lama';

  @override
  String get sortNewest => 'Terbaru';

  @override
  String get sortOldToNew => 'Lama ke Baru';

  @override
  String get sortOldest => 'Terlama';

  @override
  String get sortOptions => 'Opsi Urutan';

  @override
  String get sortPagesAsc => 'Halaman (Naik)';

  @override
  String get sortPagesDesc => 'Halaman (Turun)';

  @override
  String get sortZA => 'Z - A';

  @override
  String get specialSeriesDownload => 'Unduh Seri Khusus';

  @override
  String get starOnGitHub => 'Star di GitHub';

  @override
  String get statusError => 'Error';

  @override
  String get statusIdle => 'Menganggur';

  @override
  String get statusLoading => 'Memuat';

  @override
  String get statusLocal => 'Lokal';

  @override
  String get today => 'Hari ini';

  @override
  String weeksAgo(int weeks) {
    return '${weeks}mg yg lalu';
  }

  @override
  String get yesterday => 'Kemarin';

  @override
  String get noGenreListLoaded =>
      'Daftar genre remote belum dimuat. Muat ulang untuk sinkronisasi.';

  @override
  String get genreListTitle => 'Daftar Genre';

  @override
  String get errorLoadingGenres => 'Kesalahan Memuat Genre';

  @override
  String get noGenresFound => 'Genre Tidak Ditemukan';

  @override
  String get noGenresAvailable => 'Belum ada genre tersedia saat ini.';

  @override
  String get projectRequests => 'Permintaan Proyek';

  @override
  String get errorLoadingRequests => 'Kesalahan Memuat Permintaan';

  @override
  String get noRequestsFound => 'Permintaan Tidak Ditemukan';

  @override
  String get noProjectRequests => 'Belum ada permintaan proyek saat ini.';

  @override
  String get manageCollections => 'Kelola Koleksi';

  @override
  String get addToFavoritesFirst => 'Tambahkan ke favorit terlebih dahulu';

  @override
  String get favoriteOffline => 'Favorit Offline';

  @override
  String get favoriteOnline => 'Favorit Online';

  @override
  String get favoriteBoth => 'Favorit Keduanya';

  @override
  String get unsupportedGalleryId =>
      'ID galeri tidak didukung untuk favorit online.';

  @override
  String get addToFavoritesManageCollections =>
      'Tambahkan ke favorit terlebih dahulu untuk mengelola koleksi';

  @override
  String get loginRequiredAction => 'Masuk diperlukan untuk tindakan ini';

  @override
  String get newCollection => 'Koleksi baru';

  @override
  String get collectionName => 'Nama koleksi';

  @override
  String failedToCreateCollection(String error) {
    return 'Gagal membuat koleksi: $error';
  }

  @override
  String get clearSelection => 'Hapus Pilihan';

  @override
  String get refreshingDownloads => 'Menyegarkan unduhan...';

  @override
  String get refresh => 'Segarkan';

  @override
  String failedToSaveCollection(String error) {
    return 'Gagal menyimpan koleksi: $error';
  }

  @override
  String get renameCollection => 'Ubah nama koleksi';

  @override
  String get pressBackToExit => 'Tekan kembali untuk keluar';

  @override
  String get backToDetail => 'Kembali ke Detail';

  @override
  String get backToPreviousPage => 'Kembali ke halaman sebelumnya';

  @override
  String failedToOpenPdf(String error) {
    return 'Gagal membuka PDF: $error';
  }

  @override
  String get noChaptersAvailable => 'Tidak ada chapter tersedia';

  @override
  String failedToApplySearch(String error) {
    return 'Gagal menerapkan pencarian: $error';
  }

  @override
  String get addTag => 'Tambah tag';

  @override
  String includeCountLabel(int count) {
    return 'Sertakan $count';
  }

  @override
  String excludeCountLabel(int count) {
    return 'Kecualikan $count';
  }

  @override
  String get searchTagsHint => 'Cari tag...';

  @override
  String applyWithCounts(int include, int exclude) {
    return 'Terapkan ($include / $exclude)';
  }

  @override
  String applyWithCount(int count) {
    return 'Terapkan ($count)';
  }

  @override
  String get searchByTitleHint =>
      'Cari berdasarkan judul, ID, atau kata kunci...';

  @override
  String get pagesLabel2 => 'Halaman';

  @override
  String get favoritesGte => 'Favorit ≥';

  @override
  String get manage => 'Kelola';

  @override
  String get local => 'Lokal';

  @override
  String get rules => 'Aturan';

  @override
  String failedToSave(String error) {
    return 'Gagal menyimpan: $error';
  }

  @override
  String failedToDelete(String error) {
    return 'Gagal menghapus: $error';
  }

  @override
  String get searchExampleHint => 'romansa, artis:contoh, 12345';

  @override
  String get refreshOnline => 'Segarkan online';

  @override
  String get addRules => 'Tambah aturan';

  @override
  String get pickFromTags => 'Dari tag';

  @override
  String get done => 'Selesai';

  @override
  String get uninstallSource => 'Hapus sumber';

  @override
  String get uninstallSourceTitle => 'Hapus Sumber';

  @override
  String get uninstall => 'Hapus';

  @override
  String failedToUninstall(String sourceId, String error) {
    return 'Gagal menghapus \"$sourceId\": $error';
  }

  @override
  String get chooseOneSource => 'Instal sumber';

  @override
  String get chooseMultipleSources => 'Instal sumber';

  @override
  String installSelectedCount(int count) {
    return 'Instal Terpilih ($count)';
  }

  @override
  String get installSelected => 'Instal Terpilih';

  @override
  String get offlineModeLabel => 'Mode Luring';

  @override
  String get descriptionLabel => 'Deskripsi';

  @override
  String get aliasesLabel => 'Alias';

  @override
  String get searchContentWithTag => 'Cari Konten Dengan Tag Ini';

  @override
  String get backToFilters => 'Kembali ke Filter';

  @override
  String get dnsSettings => 'Pengaturan DNS';

  @override
  String get resetToDefaults => 'Kembalikan ke bawaan';

  @override
  String get enableDnsOverHttps => 'Aktifkan DNS-over-HTTPS';

  @override
  String get dnsServerIp => 'IP Server DNS';

  @override
  String get primaryDnsAddress => 'Alamat server DNS utama';

  @override
  String get dnsOverHttpsUrl => 'URL endpoint DNS-over-HTTPS';

  @override
  String get resetDnsSettings => 'Reset Pengaturan DNS';

  @override
  String get syncRefresh => 'Sinkronisasi/Segarkan';

  @override
  String get importFromBackup => 'Impor dari Cadangan';

  @override
  String get importZipFile => 'Impor File ZIP';

  @override
  String get exportLibrary => 'Ekspor Pustaka';

  @override
  String get loginRequired => 'Login Diperlukan';

  @override
  String get openPdf => 'Buka PDF';

  @override
  String get maybeLater => 'Nanti Saja';

  @override
  String get noContentAtMoment => 'Tidak ada konten tersedia saat ini.';

  @override
  String get refreshingContentMsg => 'Menyegarkan konten...';

  @override
  String get retryingMsg => 'Mencoba lagi...';

  @override
  String get clearingSearchMsg => 'Membersihkan pencarian...';

  @override
  String failedToClearSearch(String error) {
    return 'Gagal membersihkan hasil pencarian: $error';
  }

  @override
  String get searchingContentMsg => 'Mencari konten...';

  @override
  String get noContentMatchingSearch =>
      'Tidak ada konten yang cocok dengan kriteria pencarian Anda.';

  @override
  String get loadingPopularContent => 'Memuat konten populer...';

  @override
  String get noPopularContent => 'Tidak ada konten populer tersedia saat ini.';

  @override
  String get loadingContentByTag => 'Memuat konten berdasarkan tag...';

  @override
  String get noContentForTag => 'Tidak ada konten ditemukan untuk tag ini.';

  @override
  String loadingPageNum(int page) {
    return 'Memuat halaman $page...';
  }

  @override
  String get noContentOnPage => 'Tidak ada konten ditemukan di halaman ini.';

  @override
  String get noDownloadableImages =>
      'Konten ini tidak memiliki gambar yang dapat diunduh.';

  @override
  String failedToStartDownload(String error) {
    return 'Gagal memulai unduhan: $error';
  }

  @override
  String get bulkDeleteCompleted => 'Hapus Massal Selesai';

  @override
  String get bulkDeletePartial => 'Hapus Massal Sebagian';

  @override
  String get failedToInitSearch => 'Gagal menginisialisasi pencarian';

  @override
  String get searchingMsg => 'Mencari...';

  @override
  String noResultsForQuery(String query) {
    return 'Tidak ada hasil untuk \"$query\"';
  }

  @override
  String get searchingWithFiltersMsg => 'Mencari dengan filter...';

  @override
  String get noResultsWithFilters => 'Tidak ada hasil dengan filter saat ini';

  @override
  String invalidFilterErrors(String errors) {
    return 'Filter tidak valid: $errors';
  }

  @override
  String get noResultsGeneric => 'Tidak ada hasil ditemukan';

  @override
  String get loadingConfigMsg => 'Memuat konfigurasi...';

  @override
  String get initTagsDbMsg => 'Menginisialisasi database tag...';

  @override
  String downloadingTagsMsg(String source) {
    return 'Mengunduh tag untuk $source...';
  }

  @override
  String initFailedMsg(String error) {
    return 'Inisialisasi gagal: $error';
  }

  @override
  String get initBypassMsg => 'Menginisialisasi sistem bypass...';

  @override
  String get connectingToSite => 'Menghubungkan ke nhentai.net...';

  @override
  String get connectedSuccess => 'Berhasil terhubung ke nhentai.net';

  @override
  String get failedToConnect =>
      'Gagal terhubung ke nhentai.net. Silakan coba lagi.';

  @override
  String failedInitBypass(String error) {
    return 'Gagal menginisialisasi sistem bypass: $error';
  }

  @override
  String get bypassFailed => 'Verifikasi bypass gagal. Silakan coba lagi.';

  @override
  String get offlineBypassFailed => 'Mode Luring (Bypass Gagal)';

  @override
  String errorBypassResult(String error) {
    return 'Kesalahan memproses hasil bypass: $error';
  }

  @override
  String get readyOfflineLimited => 'Siap (Mode Luring - Terbatas)';

  @override
  String get downloadingInitConfig => 'Mengunduh konfigurasi awal...';

  @override
  String get readyOffline => 'Siap (Mode Luring)';

  @override
  String get connectingMsg => 'Menghubungkan...';

  @override
  String failedLoadOffline(String error) {
    return 'Gagal memuat konten offline: $error';
  }

  @override
  String get noInternetCheckOffline =>
      'Tidak ada koneksi internet. Memeriksa konten offline...';

  @override
  String foundOfflineItems(int count) {
    return 'Ditemukan $count item offline. Melanjutkan...';
  }

  @override
  String get noInternetNoOffline =>
      'Tidak ada koneksi internet dan tidak ada konten offline tersedia.';

  @override
  String unableCheckOffline(String error) {
    return 'Tidak dapat memeriksa konten offline. $error';
  }

  @override
  String get offlineLimitedFeatures => 'Mode Luring (Fitur Terbatas)';

  @override
  String get readyOfflineLimitedFeatures =>
      'Siap (Mode Luring - Fitur Terbatas)';

  @override
  String failedEnableOffline(String error) {
    return 'Gagal mengaktifkan mode offline: $error';
  }

  @override
  String failedCheckOffline(String error) {
    return 'Gagal memeriksa konten offline: $error';
  }

  @override
  String failedOpenChapter(String message) {
    return 'Gagal membuka chapter: $message';
  }

  @override
  String externalChapterBadge(String host) {
    return 'Eksternal • $host';
  }

  @override
  String get externalChapterHint => 'Semua chapter tersedia di situs resmi';

  @override
  String get externalChapterOpenFailed => 'Tidak bisa membuka link eksternal';

  @override
  String get externalChapterDownloadBlocked =>
      'Chapter eksternal tidak bisa di-download, buka di browser';

  @override
  String failedInitFilterData(String error) {
    return 'Gagal menginisialisasi data filter: $error';
  }

  @override
  String failedSwitchFilterType(String error) {
    return 'Gagal mengganti tipe filter: $error';
  }

  @override
  String get failedMonitorNetwork => 'Gagal memantau konektivitas jaringan';

  @override
  String failedInitNetwork(String error) {
    return 'Gagal menginisialisasi pemantauan jaringan: $error';
  }

  @override
  String failedUpdateConnection(String error) {
    return 'Gagal memperbarui status koneksi: $error';
  }

  @override
  String failedCheckConnectivity(String error) {
    return 'Gagal memeriksa konektivitas: $error';
  }

  @override
  String failedSearchOffline(String error) {
    return 'Gagal mencari konten offline: $error';
  }

  @override
  String get failedLoadOfflineContent => 'Gagal memuat konten offline';

  @override
  String failedScanBackup(String error) {
    return 'Gagal memindai folder cadangan: $error';
  }

  @override
  String failedLoadContentError(String error) {
    return 'Gagal memuat konten: $error';
  }

  @override
  String get chapterNavNotAvailable => 'Navigasi chapter tidak tersedia';

  @override
  String get unknownChapter => 'Chapter Tidak Dikenal';

  @override
  String get failedLoadChapterImages => 'Gagal memuat gambar chapter';

  @override
  String failedLoadChapter(String error) {
    return 'Gagal memuat chapter: $error';
  }

  @override
  String importFailedError(String error) {
    return 'Impor gagal: $error';
  }

  @override
  String errorImportingZip(String error) {
    return 'Kesalahan mengimpor ZIP: $error';
  }

  @override
  String get error => 'Kesalahan';

  @override
  String get lightThemeDesc => 'Tema terang dengan warna cerah';

  @override
  String get darkThemeDesc => 'Tema gelap dengan warna redup';

  @override
  String get amoledThemeDesc => 'Tema hitam pekat untuk layar AMOLED';

  @override
  String get systemThemeDesc => 'Ikuti pengaturan tema sistem';

  @override
  String nItems(int count) {
    return '$count item';
  }

  @override
  String nPages(int count) {
    return '$count halaman';
  }

  @override
  String nGalleries(int count) {
    return '$count galeri';
  }

  @override
  String sourceUninstalled(String sourceId) {
    return 'Sumber \"$sourceId\" dicopot.';
  }

  @override
  String selectedSourcesCount(int count) {
    return 'Sumber dipilih: $count';
  }

  @override
  String timeoutMinutes(int minutes) {
    return '$minutes menit';
  }

  @override
  String get dohUrlOptional => 'URL DoH (Opsional)';

  @override
  String get dnsEncryptedDescription =>
      'Gunakan DNS terenkripsi untuk privasi yang lebih baik dan melewati pemblokiran';

  @override
  String get usingSystemDns => 'Menggunakan DNS bawaan sistem';

  @override
  String get dnsProvider => 'Penyedia DNS';

  @override
  String get customConfiguration => 'Konfigurasi Kustom';

  @override
  String get aboutDoh => 'Tentang DNS-over-HTTPS';

  @override
  String get dohDescription =>
      'DNS-over-HTTPS mengenkripsi kueri DNS untuk mencegah pemantauan dan menyensor.';

  @override
  String get dnsQueriesEncrypted => 'Semua kueri DNS dienkripsi melalui HTTPS';

  @override
  String get enhancedPrivacy => 'Privasi dan keamanan yang ditingkatkan';

  @override
  String get resetDnsConfirmation =>
      'Ini akan mengatur ulang pengaturan DNS ke bawaan sistem. Lanjutkan?';

  @override
  String get appDns => 'DNS Aplikasi';

  @override
  String get devicePrivateDns => 'DNS Pribadi';

  @override
  String get dnsModeOn => 'HIDUP';

  @override
  String get dnsModeOff => 'MATI';

  @override
  String get dnsSystemDns => 'DNS Sistem';

  @override
  String dnsPrivateDnsStrict(Object hostname) {
    return 'Ketat ($hostname)';
  }

  @override
  String get dnsPrivateDnsOpportunistic => 'Opportunistik';

  @override
  String get dnsPrivateDnsRequirements => 'Memerlukan Android 10+';

  @override
  String get dnsPrivateDnsOff => 'Mati';

  @override
  String get dnsPrivateDnsGuidance =>
      'Aktifkan DNS Pribadi di pengaturan Android untuk mengenkripsi semua kueri DNS di perangkat Anda.';

  @override
  String get dnsPrivateDnsRequiresAndroid10 =>
      'Status DNS Pribadi perangkat memerlukan Android 10+.';

  @override
  String get dnsPrivateDnsCannotAutoSet =>
      'Kuron tidak dapat mengatur DNS Pribadi perangkat secara otomatis pada instalasi standar.';

  @override
  String get openDnsSettings => 'Buka Pengaturan DNS';

  @override
  String get collections => 'Koleksi';

  @override
  String get collectionsUpdatedSuccessfully => 'Koleksi berhasil diperbarui';

  @override
  String get blacklistMatchWarning =>
      'Galeri ini cocok dengan aturan daftar hitam. Sampul/kartu dapat diburamkan di tampilan daftar.';

  @override
  String get chapterCompleted => 'Bab selesai';

  @override
  String continueFromPage(int page) {
    return 'Lanjutkan dari halaman $page';
  }

  @override
  String get loginRequiredForContent =>
      'Anda harus masuk ke Crotpedia untuk melihat konten ini.';

  @override
  String commentsCount(int count) {
    return 'Komentar ($count)';
  }

  @override
  String get postComment => 'Kirim Komentar';

  @override
  String get commentInputHint =>
      'Tulis komentar. Markdown didukung. 10-1000 karakter.';

  @override
  String get commentPosted => 'Komentar berhasil dikirim';

  @override
  String get commentLengthRequirement => 'Komentar harus 10-1000 karakter.';

  @override
  String get noCommentsYet => 'Belum ada komentar';

  @override
  String get failedToLoadComments => 'Gagal memuat komentar';

  @override
  String nSelected(int count) {
    return '$count dipilih';
  }

  @override
  String get bulkDelete => 'Hapus Massal';

  @override
  String bulkDeleteConfirmation(int count) {
    return 'Apakah Anda yakin ingin menghapus $count unduhan?';
  }

  @override
  String exportedFavoritesTo(int count, String path) {
    return 'Mengekspor favorit saja ($count item) ke:\n$path';
  }

  @override
  String get failedToSaveExportFile => 'Gagal menyimpan file ekspor';

  @override
  String get importFavorites => 'Impor Favorit';

  @override
  String importFailed(String error) {
    return 'Impor gagal: $error';
  }

  @override
  String get noOnlineFavoritesSource =>
      'Tidak ada sumber favorit online yang tersedia.';

  @override
  String collectionWithCount(String name, int count) {
    return '$name ($count)';
  }

  @override
  String get newLabel => 'Baru';

  @override
  String get tryDifferentSearchTerm => 'Coba istilah pencarian yang berbeda';

  @override
  String get apply => 'Terapkan';

  @override
  String nItemsInHistory(int count) {
    return '$count item dalam riwayat';
  }

  @override
  String pageProgress(int lastPage, int totalPages) {
    return '$lastPage/$totalPages halaman';
  }

  @override
  String get chapterComplete => 'Bab Selesai!';

  @override
  String get finishedReading => 'Selesai Membaca';

  @override
  String get chapterLabel => 'Bab';

  @override
  String get noChapterSelected => 'Tidak ada bab yang dipilih';

  @override
  String get preventScreenOff => 'Mencegah layar mati saat membaca';

  @override
  String get chapters => 'Bab-bab';

  @override
  String get readerSettingsReset =>
      'Pengaturan pembaca telah diatur ulang ke bawaan.';

  @override
  String get tagInputTip =>
      'Tips: tekan Enter atau tombol + untuk menambah tag. Bisa ketik banyak tag pakai koma atau baris baru.';

  @override
  String get loadingOptions => 'Memuat opsi...';

  @override
  String get filterTags => 'Filter Tag';

  @override
  String get noOptionsAvailable => 'Tidak ada opsi tersedia untuk kolom ini';

  @override
  String get failedLoadingOptions =>
      'Gagal memuat opsi. Periksa koneksi dan coba lagi.';

  @override
  String get noTagsFound => 'Tag tidak ditemukan';

  @override
  String get previewQuery => 'Pratinjau Kueri (q)';

  @override
  String get showLess => 'Tampilkan Lebih Sedikit';

  @override
  String showAllCount(int count) {
    return 'Tampilkan Semua ($count)';
  }

  @override
  String get advancedFilters => 'Filter Lanjutan';

  @override
  String get min => 'Min';

  @override
  String get max => 'Maks';

  @override
  String searchConfigUnavailable(String sourceId) {
    return 'Konfigurasi pencarian tidak tersedia untuk $sourceId';
  }

  @override
  String get checkInternetOrReload =>
      'Silakan periksa koneksi internet Anda atau coba muat ulang aplikasi.';

  @override
  String get tagBlacklist => 'Daftar hitam tag';

  @override
  String get blacklistDescription =>
      'Fitur khusus nhentai. Entri lokal berfungsi offline untuk nhentai, dan akun nhentai yang masuk juga menarik ID daftar hitam online. Source lain tidak terpengaruh.';

  @override
  String onlineRuleDetailsCount(int count) {
    return 'Detail aturan online ($count)';
  }

  @override
  String get noBlacklistRulesYet =>
      'Belum ada aturan daftar hitam. Tambahkan nama tag seperti romance, artist:foo, atau ID tag numerik.';

  @override
  String activeCoverageDescription(int count) {
    return 'Cakupan aktif diaktifkan untuk $count token (lokal + ID online). Disembunyikan di sini agar tampilan tetap mudah dibaca.';
  }

  @override
  String get manageTagBlacklist => 'Kelola daftar hitam tag';

  @override
  String get addTagRulesDescription =>
      'Tambahkan nama tag, aturan bertipe seperti artist:foo, atau ID tag numerik. Pisahkan beberapa nilai dengan koma atau baris baru.';

  @override
  String localRulesCount(int count) {
    return 'Aturan lokal ($count)';
  }

  @override
  String onlineRulesMetadataCount(int count) {
    return 'Metadata aturan online ($count)';
  }

  @override
  String get onlineRulesMetadata => 'Metadata aturan online';

  @override
  String activeCoverageCount(int count) {
    return 'Cakupan aktif ($count)';
  }

  @override
  String nSourcesInstalled(int count) {
    return '$count sumber terpasang';
  }

  @override
  String removeSourceConfirmation(String sourceId) {
    return 'Hapus \"$sourceId\" dari sumber terpasang lokal?';
  }

  @override
  String installedSourcesFromZip(int count) {
    return 'Memasang $count sumber dari ZIP';
  }

  @override
  String get enhancedReadingExperience =>
      'Pengalaman Membaca yang Ditingkatkan';

  @override
  String get initializingApplication => 'Menginisialisasi Aplikasi...';

  @override
  String get offlineContentAvailableLabel => 'Konten Offline Tersedia';

  @override
  String get offlineModeEnabled => 'Mode Offline Diaktifkan';

  @override
  String get confirmExit => 'Apakah Anda yakin ingin keluar?';

  @override
  String get resize => 'Ubah Ukuran';

  @override
  String get offlineFeaturesLimited =>
      'Beberapa fitur terbatas. Hubungkan ke internet untuk akses penuh.';

  @override
  String get downloadSettings => 'Pengaturan Unduhan';

  @override
  String get higherValuesBandwidth =>
      'Nilai lebih tinggi dapat mengonsumsi lebih banyak bandwidth dan sumber daya perangkat';

  @override
  String get autoRetryFailed => 'Coba Ulang Otomatis Unduhan Gagal';

  @override
  String get wifiOnlyDownload => 'Hanya unduh saat terhubung ke Wi-Fi';

  @override
  String get downloadTimeout => 'Batas Waktu Unduhan';

  @override
  String get enableNotifications => 'Aktifkan Notifikasi';

  @override
  String get showNotificationsProgress =>
      'Tampilkan notifikasi untuk progres unduhan';

  @override
  String get failedToLoadImage => 'Gagal memuat gambar';

  @override
  String get retrying => 'Mencoba ulang...';

  @override
  String get readerRedownloadImage => 'Unduh ulang halaman';

  @override
  String get readerRepairingImage => 'Memperbaiki gambar...';

  @override
  String readerPageNotDownloaded(int pageNumber) {
    return 'Halaman $pageNumber belum diunduh';
  }

  @override
  String get readerPageSkippedDuringDownload =>
      'Halaman ini dilewati saat pengunduhan (timeout atau error). Ketuk di bawah untuk mengunduhnya sekarang.';

  @override
  String get readerPageDownloadSuccess => 'Berhasil diunduh';

  @override
  String get readerOpenSourcePage => 'Buka halaman sumber';

  @override
  String get readerOpeningSourcePage => 'Membuka halaman sumber...';

  @override
  String readerImageRepairSuccess(int pageNumber) {
    return 'Halaman $pageNumber berhasil diunduh ulang.';
  }

  @override
  String readerImageRepairHttpStatus(int pageNumber, int statusCode) {
    return 'Halaman $pageNumber tidak bisa diunduh ulang. Server mengembalikan HTTP $statusCode.';
  }

  @override
  String readerImageRepairInvalidImage(int pageNumber) {
    return 'Halaman $pageNumber tidak bisa diunduh ulang karena responsnya bukan file gambar yang valid.';
  }

  @override
  String readerImageRepairUnavailable(int pageNumber) {
    return 'Halaman $pageNumber tidak bisa diunduh ulang dari sumber.';
  }

  @override
  String readerImageRepairFailed(int pageNumber) {
    return 'Gagal mengunduh ulang halaman $pageNumber.';
  }

  @override
  String pageAttempt(int pageNumber, int current, int max) {
    return 'Halaman $pageNumber • Percobaan $current/$max';
  }

  @override
  String downloadingNItems(int count) {
    return 'Mengunduh $count item';
  }

  @override
  String get noOfflineContent => 'Tidak ada konten offline';

  @override
  String get howToGetStarted => 'Cara memulai';

  @override
  String get loadingMore => 'Memuat lebih banyak...';

  @override
  String get noImagesFound => 'Gambar tidak ditemukan';

  @override
  String get dontAskAgain => 'Jangan tanya lagi';

  @override
  String pageOfTotal(int current, int total) {
    return 'Halaman $current dari $total';
  }

  @override
  String loadingPageNumber(int pageNumber) {
    return 'Memuat halaman $pageNumber...';
  }

  @override
  String get recentSearches => 'Pencarian Terbaru';

  @override
  String get pageCountRange => 'Rentang Jumlah Halaman';

  @override
  String nMoreFilters(int count) {
    return '+$count lagi';
  }

  @override
  String get newUpdateAvailable => 'Pembaruan Baru Tersedia!';

  @override
  String get newVersion => 'Versi Baru: ';

  @override
  String get whatsNew => 'Yang Baru';

  @override
  String get downloadUpdate => 'Unduh Pembaruan';

  @override
  String exportPath(String path) {
    return 'Jalur: $path';
  }

  @override
  String importedContentWithImages(String contentId, int count) {
    return 'Mengimpor \"$contentId\" dengan $count gambar ke folder lokal';
  }

  @override
  String failedToLoadCaptcha(String error) {
    return 'Gagal memuat CAPTCHA: $error';
  }

  @override
  String get turnstileRejected =>
      'Cloudflare Turnstile menolak tantangan (110200). Silakan coba lagi atau gunakan input token manual.';

  @override
  String get openingNativeCaptcha => 'Membuka pemecah CAPTCHA bawaan...';

  @override
  String get tapRefreshToRetry =>
      'Ketuk segarkan untuk mencoba ulang tantangan CAPTCHA bawaan.';

  @override
  String get loginToCrotpediaDescription =>
      'Masuk ke Crotpedia menggunakan browser aman bawaan untuk mengakses bookmark dan lainnya.';

  @override
  String get crotpediaBookmarkLoginPrompt =>
      'Fitur ini (Bookmark) mengharuskan Anda masuk ke Crotpedia.\n\nApakah Anda ingin masuk sekarang?';

  @override
  String get browseByGenre => 'Jelajahi berdasarkan Genre';

  @override
  String nMoreGenres(int count) {
    return '+$count lagi';
  }

  @override
  String get selectSourceFromManifest => 'Pilih Sumber dari Manifest';

  @override
  String pagesWithSize(int pageCount, String size) {
    return '$pageCount halaman • $size';
  }

  @override
  String get browseComics => '1. Jelajahi komik yang Anda suka';

  @override
  String get tapDownloadButton => '2. Ketuk tombol unduh';

  @override
  String get accessOffline => '3. Akses kapan saja, bahkan offline!';

  @override
  String get source => 'Sumber';

  @override
  String nPagesText(int count) {
    return '$count halaman';
  }

  @override
  String checkItOut(String url) {
    return 'Lihat di sini: $url';
  }

  @override
  String get filteredResults => 'Hasil Filter';

  @override
  String get filter => 'Filter';

  @override
  String crotpediaMaintenance(String reason) {
    return 'Pemeliharaan Crotpedia: $reason';
  }

  @override
  String get tapToChangeFilters => 'Ketuk untuk mengubah filter pencarian';

  @override
  String get prevChapter => 'Bab Sebelumnya';

  @override
  String get nextChapter => 'Bab Berikutnya';

  @override
  String pageOfContent(int current, int total) {
    return 'Halaman $current dari $total';
  }

  @override
  String nChapters(int count) {
    return '$count bab';
  }

  @override
  String get failedToLoadOptionsTap =>
      'Gagal memuat opsi. Ketuk untuk mencoba lagi.';

  @override
  String chooseField(String field) {
    return '$field';
  }

  @override
  String get tapToLoadOptions => 'Ketuk untuk memuat opsi';

  @override
  String nSelectedItems(int count) {
    return '$count dipilih';
  }

  @override
  String get tapToChooseTags =>
      'Ketuk untuk memilih tag disertakan/dikecualikan';

  @override
  String includeExcludeCount(int include, int exclude) {
    return 'Sertakan $include • Kecualikan $exclude';
  }

  @override
  String get searchLabel => 'Cari';

  @override
  String get genreLabel => 'Genre';

  @override
  String get statusLabel => 'Status';

  @override
  String get orderBy => 'Urutkan';

  @override
  String get authorLabel => 'Penulis';

  @override
  String get artistFilterLabel => 'Seniman';

  @override
  String get artists => 'Seniman';

  @override
  String get characters => 'Karakter';

  @override
  String get parodies => 'Parodi';

  @override
  String get groups => 'Grup';

  @override
  String get filterCategories => 'KATEGORI FILTER';

  @override
  String get dateUploaded => 'TANGGAL DIUNGGAH';

  @override
  String get numericFilters => 'FILTER NUMERIK';

  @override
  String get older => 'Lebih Lama';

  @override
  String get contentFilters => 'FILTER KONTEN';

  @override
  String get blurCoversDescription =>
      'Buramkan sampul yang cocok dengan aturan tag lokal Anda, bahkan saat menjelajah offline. Jika Anda masuk ke nhentai, ID daftar hitam online digabungkan secara otomatis.';

  @override
  String get developerTools => 'ALAT PENGEMBANG';

  @override
  String get noOnlineRulesYet =>
      'Belum ada aturan online terperinci. Tarik untuk menyegarkan dan mengambil data /blacklist.';

  @override
  String get nothingSavedLocally =>
      'Belum ada yang disimpan secara lokal. Aturan lokal selalu diterapkan, termasuk hasil offline.';

  @override
  String get loginRequiredForRules =>
      'Login diperlukan untuk mengambil metadata aturan terperinci dari /blacklist.';

  @override
  String get syncingOnlineRules => 'Menyinkronkan detail aturan online...';

  @override
  String get noOnlineRuleDetails =>
      'Belum ada detail aturan online. Ketuk segarkan untuk mengambil /blacklist.';

  @override
  String get blacklistGalleriesInfo =>
      'Galeri yang masuk daftar hitam akan diburamkan di sini setelah Anda menambahkan aturan lokal atau menyinkronkan ID online.';

  @override
  String coverageActiveDescription(int count) {
    return 'Cakupan aktif untuk $count token. Token ID disembunyikan di sini atas permintaan; hanya aturan online yang dinamai ditampilkan di atas.';
  }

  @override
  String get availableSources => 'SUMBER TERSEDIA';

  @override
  String get settingUpConnection =>
      'Menyiapkan komponen dan memeriksa koneksi...';

  @override
  String get tagId => 'ID Tag';

  @override
  String get slug => 'Slug';

  @override
  String get path => 'Jalur';

  @override
  String get tag => 'Tag';

  @override
  String profileWithName(String name) {
    return 'Profil ($name)';
  }

  @override
  String get profile => 'Profil';

  @override
  String get loginAccount => 'Masuk / Akun';

  @override
  String accountWithName(String name) {
    return 'Akun ($name)';
  }

  @override
  String get performance => 'Performa';

  @override
  String get autoRetry => 'Coba Ulang Otomatis';

  @override
  String get network => 'Jaringan';

  @override
  String get notifications => 'Notifikasi';

  @override
  String get estimatingProgress => 'Memperkirakan progres...';

  @override
  String get processingBadAvifToWebp =>
      'Memproses konversi AVIF rusak ke WebP...';

  @override
  String get downloadingImageData => 'Mengunduh data gambar...';

  @override
  String get hideFilters => 'Sembunyikan filter';

  @override
  String get showMoreFilters => 'Tampilkan lebih banyak filter';

  @override
  String get preparingExport => 'Mempersiapkan ekspor...';

  @override
  String get readingFavorites => 'Membaca favorit dari database...';

  @override
  String get encodingFavorites => 'Mengenkode data favorit...';

  @override
  String get writingExportFile => 'Menulis file ekspor...';

  @override
  String get finalizingExport => 'Menyelesaikan ekspor...';

  @override
  String get readerContinuousDisabledHeavyImage =>
      'Mode baca full vertical dinonaktifkan: gambar animasi berat terdeteksi. Gunakan mode Horizontal/Vertikal.';

  @override
  String get readerContinuousOffHeavyImage =>
      'Mode baca full vertical nonaktif (gambar berat)';

  @override
  String get chapterCurrentBadge => 'AKTIF';

  @override
  String readerDaysAgoShort(int count) {
    return '${count}h lalu';
  }

  @override
  String readerWeeksAgoShort(int count) {
    return '${count}mgg lalu';
  }

  @override
  String readerMonthsAgoShort(int count) {
    return '${count}bln lalu';
  }

  @override
  String get readerTapDirectionLabel => 'Arah Tap';

  @override
  String get readerTapDirectionNormal => 'Normal';

  @override
  String get readerTapDirectionInverted => 'Balik';

  @override
  String get readerTapDirectionNormalDescription =>
      'Tap kanan untuk ke halaman berikutnya';

  @override
  String get readerTapDirectionInvertedDescription =>
      'Tap kiri untuk ke halaman berikutnya';

  @override
  String get readerClearImageCache => 'Bersihkan Cache Gambar';

  @override
  String get readerImageCacheCleared =>
      'Cache gambar dibersihkan. Gulir untuk memuat ulang halaman.';

  @override
  String get readerOpenInGallery => 'Buka di galeri';

  @override
  String get readerPinchToZoom => 'Cubit untuk zoom';

  @override
  String get captchaCancelled => 'Tantangan CAPTCHA dibatalkan atau gagal.';

  @override
  String failedToOpenCaptcha(String error) {
    return 'Gagal membuka pemecah CAPTCHA bawaan: $error';
  }

  @override
  String get readFirstChapter => 'Baca Chapter Pertama';

  @override
  String get convertAllToPdf => 'Konversi Semua ke PDF';

  @override
  String deleteSeriesConfirmation(int count, String title) {
    return 'Apakah Anda yakin ingin menghapus $count chapter dari \"$title\"?';
  }

  @override
  String deleteSeriesWithCount(int count) {
    return 'Hapus Series ($count)';
  }

  @override
  String get readerScreenSupporter => 'Dukung Developer';

  @override
  String get readerScreenSupporterDesc =>
      'Jika kamu suka aplikasi ini, pertimbangkan untuk mendukung pengembangannya.';

  @override
  String get readerScreenThanks => 'Terima Kasih Sudah Membaca!';

  @override
  String get readerScreenThanksDesc =>
      'Semoga kamu menikmati chapter ini. Sampai jumpa di chapter berikutnya!';

  @override
  String get readerScreenGoToFirstPage => 'Baca dari Awal';

  @override
  String get appLockSectionTitle => 'KUNCI APLIKASI';

  @override
  String get pinLock => 'Kunci PIN';

  @override
  String get pinLockActive => 'PIN sudah diatur dan aktif';

  @override
  String get pinLockSet => 'Atur PIN untuk mengunci aplikasi';

  @override
  String get changePin => 'Ubah PIN';

  @override
  String get changePinDescription => 'Atur PIN baru';

  @override
  String get biometricUnlock => 'Buka dengan Biometrik';

  @override
  String get biometricAvailable =>
      'Gunakan sidik jari atau wajah untuk membuka';

  @override
  String get biometricUnavailable =>
      'Biometrik tidak tersedia di perangkat ini';

  @override
  String get enterPin => 'Masukkan PIN';

  @override
  String get enterCurrentPin => 'Masukkan PIN Saat Ini';

  @override
  String get enterCurrentPinSubtitle =>
      'Verifikasi identitas Anda terlebih dahulu';

  @override
  String get enterNewPin => 'Masukkan PIN Baru';

  @override
  String enterNewPinSubtitle(int maxDigits) {
    return 'Pilih PIN $maxDigits digit';
  }

  @override
  String get confirmNewPin => 'Konfirmasi PIN Baru';

  @override
  String get confirmNewPinSubtitle => 'Masukkan PIN lagi';

  @override
  String get setupPin => 'Atur PIN';

  @override
  String setupPinSubtitle(int maxDigits) {
    return 'Pilih PIN $maxDigits digit';
  }

  @override
  String get confirmPin => 'Konfirmasi PIN';

  @override
  String get confirmPinSubtitle => 'Masukkan PIN lagi untuk konfirmasi';

  @override
  String get wrongPin => 'PIN Salah';

  @override
  String get pinsDoNotMatch => 'PIN tidak cocok';

  @override
  String get pinChangedSuccess => 'PIN berhasil diubah';

  @override
  String get failedToSavePin => 'Gagal menyimpan PIN. Coba lagi.';

  @override
  String get failedToChangePin => 'Gagal mengubah PIN. Coba lagi.';

  @override
  String get disablePinLock => 'Nonaktifkan Kunci PIN?';

  @override
  String get disablePinLockDescription =>
      'Untuk menonaktifkan kunci PIN, masukkan PIN Anda saat ini.';

  @override
  String get enterPinToDisable => 'Masukkan PIN untuk Menonaktifkan';

  @override
  String get enterPinToDisableSubtitle =>
      'Ini akan menghapus PIN dan menonaktifkan kunci';

  @override
  String get unlockKuron => 'Buka Kuron untuk melanjutkan';

  @override
  String get continue_ => 'Lanjutkan';

  @override
  String get aiTranslate => 'AI Translate';

  @override
  String get aiTutorialHint => 'Tap di mana saja untuk tutup';

  @override
  String get aiTutorialTranslateTitle => '✨ Translate halaman';

  @override
  String get aiTutorialTranslateDesc =>
      'Deteksi bubble otomatis → terjemahan di-overlay di atas teks asli. Tap lagi untuk hide/show.';

  @override
  String get aiTutorialDrawTitle => '✏️ Draw bubbles';

  @override
  String get aiTutorialDrawDesc =>
      'Koreksi manual. Drag untuk tambah bubble (merah), 🛰 Detect untuk lihat deteksi ONNX (biru). Done mengunci tapi bubble tetap tampil.';

  @override
  String get aiTutorialClearTitle => '🗑 Clear';

  @override
  String get aiTutorialClearDesc =>
      'Hapus hasil translate + semua bubble referensi.';

  @override
  String get aiTutorialGotIt => 'Paham!';

  @override
  String get aiNotAvailableCS =>
      'AI translate tidak tersedia di continue scroll.';

  @override
  String get aiHideTranslation => 'Sembunyikan terjemahan';

  @override
  String get aiTranslating => 'Menerjemahkan...';

  @override
  String get aiDetecting => 'Mendeteksi bubble...';

  @override
  String get aiTranslatePage => 'Translate halaman';

  @override
  String get aiClearTranslateBubbles => 'Bersihkan translate + bubble';

  @override
  String get aiExitDrawMode => 'Keluar mode gambar';

  @override
  String get aiDrawBubbles => 'Gambar bubble';

  @override
  String get aiDrawRect => 'Persegi';

  @override
  String get aiDrawEllipse => 'Elips';

  @override
  String get aiDrawFreeform => 'Bentuk bebas';

  @override
  String get aiExpandDraw => 'Tampilkan aksi';

  @override
  String get aiCollapseDraw => 'Sembunyikan aksi';

  @override
  String get aiDrawDetect => 'Deteksi bubble';

  @override
  String get aiDrawUndo => 'Urungkan';

  @override
  String get aiDrawClear => 'Bersihkan';

  @override
  String get aiSkipSfxOn => 'Skip SFX: NYALA';

  @override
  String get aiSkipSfxOff => 'Skip SFX: MATI';

  @override
  String get moreActions => 'Aksi lainnya';

  @override
  String get aiEditTranslation => 'Edit Terjemahan';

  @override
  String get aiTranslation => 'Terjemahan';

  @override
  String get aiSave => 'Simpan';

  @override
  String get aiSaveToGlossaryHint => 'Simpan ke glossary belajar';

  @override
  String get aiSaveToGlossary => 'Simpan ke Glossary';

  @override
  String get aiSavedToGlossary => 'Tersimpan ke Glossary';

  @override
  String aiTranslateFailed(Object error) {
    return 'Translate gagal: $error';
  }

  @override
  String get aiNeedVisionProvider =>
      'AI translate butuh vision provider. Setup di Settings → AI Translation.';

  @override
  String aiRateLimited(Object fallback) {
    return 'Rate limited. $fallback';
  }

  @override
  String aiUsingFallback(Object name) {
    return 'Pakai $name sebagai fallback.';
  }

  @override
  String aiWaitCooldown(Object seconds) {
    return 'Tunggu ${seconds}s.';
  }

  @override
  String get aiGagalFetch =>
      'Gagal mengambil gambar halaman. Coba lagi atau cek koneksi.';

  @override
  String get aiCapturingViewport => 'Mengambil gambar layar... mohon tunggu.';

  @override
  String get aiGagalCapture => 'Gagal mengambil gambar layar. Coba lagi.';

  @override
  String get aiCapturedViewport => 'Gambar layar berhasil diambil.';

  @override
  String get aiSettings => 'AI Settings';

  @override
  String get aiProvidersSubtitle => 'Provider, bahasa, gaya, cache terjemahan';

  @override
  String get aiManageProviders => 'Provider AI';

  @override
  String get aiOpen => 'Buka';

  @override
  String get aiTargetLanguage => 'Bahasa Target';

  @override
  String get aiTargetLangSubtitle => 'Bahasa yang AI terjemahkan ke';

  @override
  String get aiTranslationStyle => 'Gaya Terjemahan';

  @override
  String get aiSkipSfx => 'Skip bubble SFX';

  @override
  String get aiSkipSfxSubtitle =>
      'Lewati bubble berisi efek suara saja (default nyala)';

  @override
  String get aiMosaicQuality => 'Kualitas mosaic';

  @override
  String get aiMosaicQualitySubtitle =>
      'Rendah hemat token (JPEG 75, 1 MB); Tinggi menjaga detail (JPEG 85, 2 MB)';

  @override
  String get aiSwitchModel => 'Ganti model';

  @override
  String aiModelSwitched(Object name) {
    return 'Model diganti ke $name';
  }

  @override
  String get aiPrivacyDisclosure => 'Pemberitahuan Privasi';

  @override
  String get aiPrivacyDesc =>
      'Gambar dikirim ke provider pilihanmu. Kuron tidak meneruskan datamu.';

  @override
  String get aiClearCache => 'Bersihkan Cache Terjemahan';

  @override
  String get aiClearCacheSubtitle => 'Hapus semua cache terjemahan halaman';

  @override
  String get aiGlossary => 'Glossary Belajar';

  @override
  String get aiGlossarySubtitle => 'Tinjau kosakata tersimpan';

  @override
  String get aiAddProvider => 'Tambah Provider';

  @override
  String get aiEditProvider => 'Edit Provider';

  @override
  String get aiProviderType => 'Tipe';

  @override
  String get aiDisplayName => 'Nama Tampilan';

  @override
  String get aiApiKey => 'API Key';

  @override
  String get aiApiKeyHint => 'Kosongkan untuk model free tanpa key';

  @override
  String get aiModel => 'Model';

  @override
  String get aiBaseUrl => 'Base URL';

  @override
  String get aiTestKey => 'Tes Key';

  @override
  String get aiTesting => 'Menguji...';

  @override
  String get aiDelete => 'Hapus';

  @override
  String get aiValidKey => '✓ Key valid';

  @override
  String aiCheckIconD(Object model) {
    return '✓ Key valid — model $model OK';
  }

  @override
  String get aiCustomTypeDefault => 'wajib diisi user';

  @override
  String get aiModeKasarTitle => 'Mode Kasar (18+)';

  @override
  String get aiModeKasarConfirm =>
      'Mode Kasar menggunakan kata-kata keras. Lanjutkan?';

  @override
  String get aiEnable => 'Aktifkan';

  @override
  String get aiCancel => 'Batal';

  @override
  String aiModelNotVision(Object model) {
    return 'Model \"$model\" tidak support image translation (text-only/free). Pilih model vision (mis. kimi-k2.6, gemini-2.5-flash, gpt-4o-mini) di Settings → AI Translation.';
  }

  @override
  String aiNoVisionProvider(Object model) {
    return 'Model \"$model\" text-only/free — pilih model vision di Settings → AI Translation (mis. kimi-k2.6).';
  }

  @override
  String get aiGlossaryEmpty =>
      'Belum ada entri glossary.\\nTekan lama bubble terjemahan untuk menyimpan.';

  @override
  String aiDefaultModel(Object model) {
    return 'Default: $model';
  }

  @override
  String get aiLoadModels => 'Muat model';

  @override
  String get aiReload => 'Muat ulang';

  @override
  String get aiManualEntry => 'Input manual';

  @override
  String get aiUseLov => 'Pakai daftar';

  @override
  String get aiEnterApiKeyFirst => 'Masukkan API key dulu';

  @override
  String get aiAll => 'Semua';

  @override
  String get aiVision => 'Vision';

  @override
  String get aiTextOnly => 'Teks saja';

  @override
  String get aiSearchModels => 'Cari model';

  @override
  String get aiSelectModel => 'Pilih model';

  @override
  String aiStaleModel(Object model) {
    return 'Model tersimpan \"$model\" tidak ada di daftar saat ini';
  }

  @override
  String get aiModelHint =>
      'Pilih model dari daftar live, atau pakai input manual';

  @override
  String get aiClearCacheCleared => 'Cache terjemahan dibersihkan';

  @override
  String get aiPrivacyDialogDesc =>
      'Gambar halaman yang kamu translate akan dikirim ke provider yang kamu pilih menggunakan key kamu sendiri. Tidak ada data yang melalui server Kuron.';

  @override
  String get aiPrivacyAgree => 'Setuju & Translate';

  @override
  String get aiNoKeyNeeded => 'Tanpa key';

  @override
  String get glossaryPage => 'halaman';

  @override
  String get nclientImport => 'Impor dari NClient';

  @override
  String get nclientImportSubtitle =>
      'Favorit, koleksi, riwayat, dan posisi baca dari backup NClient V2/V3';

  @override
  String get nclientImportAction => 'Impor';

  @override
  String get nclientPreview => 'Pratinjau impor';

  @override
  String get nclientResult => 'Hasil impor';

  @override
  String get nclientPositions => 'Posisi baca';

  @override
  String get nclientMemberships => 'Isi koleksi';

  @override
  String nclientSummaryRow(String label, int success, int skipped, int failed) {
    return '$label: $success ditambah, $skipped dilewati, $failed gagal';
  }
}
