import '../../l10n/app_localizations.dart';

String? _arg(Map<String, dynamic>? args, String key, [String? fallback]) {
  if (args == null || !args.containsKey(key)) return fallback;
  final v = args[key];
  return v?.toString() ?? fallback;
}

Object _objArg(Map<String, dynamic>? args, String key, [Object fallback = 0]) {
  if (args == null || !args.containsKey(key)) return fallback;
  return args[key] ?? fallback;
}

int? _intArg(Map<String, dynamic>? args, String key) {
  if (args == null || !args.containsKey(key)) return null;
  final v = args[key];
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// Maps the string keys used by [NotificationService] onto generated ARB
/// getters. Every mascot notification string is routed through here so the
/// custom Kuron notifications follow the app locale. Unknown keys return
/// `null` and the caller keeps its sensible English/Indonesian fallback.
String? localizeNotification(
    AppLocalizations l10n, String key, Map<String, dynamic>? args) {
  switch (key) {
    // ── Download (existing mascot notifications) ──
    case 'downloadStarted':
      return l10n.downloadStarted(_arg(args, 'title', '')!);
    case 'downloadingWithTitle':
      return l10n.downloadingWithTitle(_arg(args, 'title', '')!);
    case 'downloadingProgress':
      return l10n.downloadingProgress(_objArg(args, 'progress'));
    case 'downloadComplete':
      return l10n.downloadComplete;
    case 'downloadedWithTitle':
      return l10n.downloadedWithTitle(_arg(args, 'title', '')!);
    case 'downloadFailed':
      return l10n.downloadFailed;
    case 'downloadFailedWithTitle':
      return l10n.downloadFailedWithTitle(_arg(args, 'title', '')!);
    case 'downloadPaused':
      return l10n.downloadPaused;

    case 'kuronNotifDownloadPacking':
      return l10n.kuronNotifDownloadPacking;
    case 'kuronNotifDownloadNapping':
      return l10n.kuronNotifDownloadNapping;
    case 'kuronNotifDownloadPackedProgress':
      return l10n.kuronNotifDownloadPackedProgress(
          _arg(args, 'progress', '0')!);
    case 'kuronNotifDownloadDeliveryComplete':
      return l10n.kuronNotifDownloadDeliveryComplete;
    case 'kuronNotifBatchLoaded':
      return l10n.kuronNotifBatchLoaded(_arg(args, 'count', '0')!);
    case 'kuronNotifBatchPacking':
      return l10n.kuronNotifBatchPacking;
    case 'kuronNotifDownloadArrived':
      return l10n.kuronNotifDownloadArrived;
    case 'kuronNotifDownloadAllPackedMeta':
      return l10n.kuronNotifDownloadAllPackedMeta;
    case 'kuronNotifDownloadProgressSpeech':
      return l10n.kuronNotifDownloadProgressSpeech(
        _arg(args, 'progress', '0')!,
        _arg(args, 'speed', '')!,
      );
    case 'kuronNotifBatchSpeech':
      return l10n.kuronNotifBatchSpeech(
        _arg(args, 'count', '0')!,
        _arg(args, 'speed', '')!,
      );
    case 'kuronNotifDownloadGroupDone':
      return l10n.kuronNotifDownloadGroupDone(_arg(args, 'count', '0')!);
    case 'kuronNotifDownloadGroupMeta':
      return l10n.kuronNotifDownloadGroupMeta;

    // ── PDF (existing + fallback mascot notifications) ──
    case 'convertingToPdf':
      return l10n.convertingToPdf;
    case 'convertingToPdfWithTitle':
      return l10n.convertingToPdfWithTitle(_arg(args, 'title', '')!);
    case 'convertingToPdfProgress':
      return l10n.convertingToPdfProgress(_objArg(args, 'progress'));
    case 'convertingToPdfProgressWithTitle':
      return l10n.convertingToPdfProgressWithTitle(
          _arg(args, 'title', '')!, _intArg(args, 'progress') ?? 0);
    case 'pdfCreatedSuccessfully':
      return l10n.pdfCreatedSuccessfully;
    case 'pdfCreatedWithParts':
      return l10n.pdfCreatedWithParts(
          _arg(args, 'title', '')!, _intArg(args, 'partsCount') ?? 1);
    case 'pdfConversionFailedWithError':
      return l10n.pdfConversionFailedWithError(
          _arg(args, 'title', '')!, _arg(args, 'error', '')!);
    case 'convertingPdfQueued':
      return l10n.convertingPdfQueued(
        _arg(args, 'current', '0')!,
        _arg(args, 'total', '0')!,
      );
    case 'pdfQueueWaiting':
      return l10n.pdfQueueWaiting(_arg(args, 'count', '0')!);
    case 'pdfQueueNext':
      return l10n.pdfQueueNext(_arg(args, 'titles', '')!);
    case 'pdfBatchCompleted':
      return l10n.pdfBatchCompleted;
    case 'pdfBatchCompletedCount':
      return l10n.pdfBatchCompletedCount(_arg(args, 'count', '0')!);

    case 'kuronNotifPdfConverting':
      return l10n.kuronNotifPdfConverting;
    case 'kuronNotifPdfRenderingPages':
      return l10n.kuronNotifPdfRenderingPages(
        _arg(args, 'done', '0')!,
        _arg(args, 'total', '0')!,
      );
    case 'kuronNotifPdfReady':
      return l10n.kuronNotifPdfReady;
    case 'kuronNotifPdfReadyMeta':
      return l10n.kuronNotifPdfReadyMeta;
    case 'kuronNotifPdfCancelled':
      return l10n.kuronNotifPdfCancelled;
    case 'kuronNotifPdfCancelMeta':
      return l10n.kuronNotifPdfCancelMeta;
    case 'kuronNotifPdfFailedTitle':
      return l10n.kuronNotifPdfFailedTitle;
    case 'kuronNotifPdfGroupTitle':
      return l10n.kuronNotifPdfGroupTitle;
    case 'kuronNotifPdfMetaParts':
      return l10n.kuronNotifPdfMetaParts(_arg(args, 'count', '0')!);
    case 'kuronNotifPdfProgressMeta':
      return l10n.kuronNotifPdfProgressMeta(
        _arg(args, 'page', '0')!,
        _arg(args, 'total', '0')!,
      );
    case 'kuronNotifPdfBatchMeta':
      return l10n.kuronNotifPdfBatchMeta(_arg(args, 'count', '0')!);
    case 'kuronNotifPdfQueueTitle':
      return l10n.kuronNotifPdfQueueTitle;
    case 'kuronNotifPdfQueueSpeech':
      return l10n.kuronNotifPdfQueueSpeech;
    case 'kuronNotifPdfQueueWaitSpeech':
      return l10n.kuronNotifPdfQueueWaitSpeech;
    case 'kuronNotifPdfBatchDoneSpeech':
      return l10n.kuronNotifPdfBatchDoneSpeech;
    case 'kuronNotifPdfConvertErrorSpeech':
      return l10n.kuronNotifPdfConvertErrorSpeech;
    case 'kuronNotifPdfGroupErrorSpeech':
      return l10n.kuronNotifPdfGroupErrorSpeech;
    case 'kuronNotifPdfGroupErrorTitle':
      return l10n.kuronNotifPdfGroupErrorTitle(
        _arg(args, 'current', '0')!,
        _arg(args, 'total', '0')!,
      );
    case 'kuronNotifDownloadGroupTitleOne':
      return l10n.kuronNotifDownloadGroupTitleOne;
    case 'kuronNotifDownloadGroupTitleMany':
      return l10n.kuronNotifDownloadGroupTitleMany(
          _arg(args, 'count', '0')!);
    case 'kuronNotifDownloadGroupDoneTitle':
      return l10n.kuronNotifDownloadGroupDoneTitle(
          _arg(args, 'count', '0')!);

    // ── Verification (existing + new) ──
    case 'verifyingFiles':
      return l10n.verifyingFiles;
    case 'verifyingFilesWithTitle':
      return l10n.verifyingFilesWithTitle(_arg(args, 'title', '')!);
    case 'verifyingProgress':
      return l10n.verifyingProgress(_intArg(args, 'progress') ?? 0);
    case 'kuronNotifVerifyStartSpeech':
      return l10n.kuronNotifVerifyStartSpeech;
    case 'kuronNotifVerifyProgressSpeech':
      return l10n.kuronNotifVerifyProgressSpeech(
          _arg(args, 'progress', '0')!);

    // ── Sync ──
    case 'kuronNotifSyncTitle':
      return l10n.kuronNotifSyncTitle;
    case 'syncingOfflineContent':
      return l10n.syncingOfflineContent;
    case 'syncingProgress':
      return l10n.syncingProgress(_arg(args, 'progress', '0')!);
    case 'syncComplete':
      return l10n.syncComplete;
    case 'syncCompletedWithCount':
      return l10n.syncCompletedWithCount(_arg(args, 'count', '0')!);
    case 'kuronNotifSyncStartSpeech':
      return l10n.kuronNotifSyncStartSpeech;
    case 'kuronNotifSyncProgressSpeech':
      return l10n.kuronNotifSyncProgressSpeech(
          _arg(args, 'progress', '0')!);
    case 'kuronNotifSyncDoneSpeech':
      return l10n.kuronNotifSyncDoneSpeech;
    case 'kuronNotifSyncDoneMeta':
      return l10n.kuronNotifSyncDoneMeta(_arg(args, 'count', '0')!);

    // ── ZIP extraction ──
    case 'zipExtractionInProgress':
      return l10n.zipExtractionInProgress;
    case 'extractingZipContent':
      return l10n.extractingZipContent;
    case 'extractingProgress':
      return l10n.extractingProgress(_arg(args, 'progress', '0')!);
    case 'zipExtractionComplete':
      return l10n.zipExtractionComplete;
    case 'zipExtractedWithCount':
      return l10n.zipExtractedWithCount(_arg(args, 'count', '0')!);
    case 'zipExtractionFailed':
      return l10n.zipExtractionFailed;
    case 'zipExtractionFailedWithError':
      return l10n.zipExtractionFailedWithError(_arg(args, 'error', '')!);
    case 'kuronNotifZipStartSpeech':
      return l10n.kuronNotifZipStartSpeech;
    case 'kuronNotifZipProgressSpeech':
      return l10n.kuronNotifZipProgressSpeech(
          _arg(args, 'progress', '0')!);
    case 'kuronNotifZipDoneSpeech':
      return l10n.kuronNotifZipDoneSpeech;
    case 'kuronNotifZipDoneMeta':
      return l10n.kuronNotifZipDoneMeta(_arg(args, 'count', '0')!);
    case 'kuronNotifZipErrorSpeech':
      return l10n.kuronNotifZipErrorSpeech;

    // ── Generic task card defaults ──
    case 'kuronNotifTaskProcessing':
      return l10n.kuronNotifTaskProcessing;
    case 'kuronNotifTaskWorking':
      return l10n.kuronNotifTaskWorking;
    case 'kuronNotifTaskComplete':
      return l10n.kuronNotifTaskComplete;
    case 'kuronNotifTaskCompleteTitle':
      return l10n.kuronNotifTaskCompleteTitle;
    case 'kuronNotifTaskAllDoneMeta':
      return l10n.kuronNotifTaskAllDoneMeta;

    // ── Backup / restore / NClient import ──
    case 'kuronNotifBackupStartSpeech':
      return l10n.kuronNotifBackupStartSpeech;
    case 'kuronNotifBackupCategorySpeech':
      return l10n.kuronNotifBackupCategorySpeech(
          _arg(args, 'label', '')!);
    case 'kuronNotifBackupDoneSpeech':
      return l10n.kuronNotifBackupDoneSpeech;
    case 'kuronNotifBackupMeta':
      return l10n.kuronNotifBackupMeta(_arg(args, 'title', '')!);
    case 'kuronNotifBackupErrorSpeech':
      return l10n.kuronNotifBackupErrorSpeech;
    case 'kuronNotifBackupProgressMeta':
      return l10n.kuronNotifBackupProgressMeta(
        _arg(args, 'label', '')!,
        _arg(args, 'done', '0')!,
        _arg(args, 'total', '0')!,
      );

    // ── AI model download ──
    case 'kuronNotifAiDownloadSpeech':
      return l10n.kuronNotifAiDownloadSpeech;
    case 'kuronNotifAiDownloadingMeta':
      return l10n.kuronNotifAiDownloadingMeta;
    case 'kuronNotifAiDoneSpeech':
      return l10n.kuronNotifAiDoneSpeech;
    case 'kuronNotifAiDoneMeta':
      return l10n.kuronNotifAiDoneMeta;
    case 'kuronNotifAiErrorSpeech':
      return l10n.kuronNotifAiErrorSpeech;

    default:
      return null;
  }
}
