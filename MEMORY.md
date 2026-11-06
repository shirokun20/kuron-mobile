# Kuron — Project Memory

> **Unified context file** for tracking progress across AI tools.
> Read by: **Codex** | **OpenCode** | **GitHub Copilot** | **Antigravity** | **Manual Review**

---

## Project Identity

| Key | Value |
|---|---|
| **App Name** | **Kuron** (formerly NhasixApp) |
| **Repo** | `shirokun20/nhasixapp` |
| **Platform** | Android (Flutter) |
| **Flutter SDK** | Stable (3.24+, Dart 3.5+ via FVM) |
| **Version** | 0.9.28+38 |
| **Architecture** | Clean Architecture (Domain → Data → Presentation) |
| **State Management** | `flutter_bloc` / `Cubit` (extending `BaseCubit`) |
| **DI** | `GetIt` (`core/di/`) |
| **Networking** | `Dio` + `native_dio_adapter` |
| **Routing** | GoRouter (`go_router`) |
| **Database** | SQLite (`sqflite`) + `SharedPreferences` |
| **Logging** | `logger` package (`.t` to `.f`) — NO `print`/`debugPrint` |

### Packages (Internal)
| Package | Description |
|---|---|
| `kuron_core` | Shared core utilities |
| `kuron_config_generator` | Configuration generator |
| `kuron_generic` | Generic utilities |
| `kuron_native` | Native Android (Kotlin) integrations |
| `kuron_special` | Special utilities |
| `kuron_native` | Native Android (Kotlin) integrations |

### Key Features
- Immersive Reader with smooth page transitions
- App Disguise mode (Calculator, Notes, Weather)
- Offline-first with background downloading
- Smart Search with advanced filtering
- Material 3, Dark/Light/AMOLED modes, responsive UI
- Community comments on detail pages

---

## Architecture Overview

```
lib/
├── core/              # Shared utilities, DI, constants, themes
│   ├── di/            # GetIt setup
│   ├── network/       # Dio clients, interceptors
│   └── utils/         # Helpers, extensions
├── domain/            # Pure Dart — entities, use cases, repo interfaces
├── data/              # Implementations — models, sources, repos
│   ├── models/        # extend entities (.fromEntity/.toEntity/.fromMap)
│   ├── datasources/   # Remote/Local data sources
│   └── repositories/  # Repository implementations
├── presentation/      # Flutter UI — BLoC/Cubit, pages, widgets
│   ├── blocs/         # State management (cubits)
│   ├── pages/         # Screen-level widgets
│   └── widgets/       # Reusable components
└── packages/          # Internal packages (kuron_core, kuron_generic, kuron_native, kuron_special, etc.)
```

### Layer Rules
- **Domain**: Pure Dart. Zero dependencies on Data/Presentation.
- **Data**: Depends only on Domain. JSON parsing, API calls, DB storage.
- **Presentation**: Depends only on Domain (+ DI). BLoC/Cubit + UI widgets.

---

## Current Progress Dashboard

> Tracked via `openspec/` — Last updated: 2026-11-06

### Archived (in `openspec/changes/archive/`) — Newest first (showing recent ~15; full list in folder)
- `2026-11-06-bulk-source-configs` (142/143 — 10.3 hentaikisu PARKED atas permintaan bos; spec baru `bulk-source-batch` tersinkron; Batch 7-8 + engine issues #62–68 jadi backlog)
- `2026-11-06-fix-kuron-packages-concurrency-and-state` (10/10 — single-flight clearance, executor split Kotlin, slot RateLimiter, BaseCubit + hapus DoH Dart; spec baru `kuron-runtime-concurrency` + 1 req tambah di `native-dns-runtime`/`presentation-layering`; 3 bug review terarsip sebagai known issue: race `clearToken`, negative cache, `_extractPageNumber`)
- `2026-11-06-unified-dev-cli` (12/15 — KURO v1.1.0: wizard panah, step counter, result box, banner gradient; spec baru `dev-cli-automation`; terbuka: 3.1 shim, 3.2 CI, 4.2 README)
- `2026-11-06-reader-jank-during-active-downloads` (22/22 — refcount reader, page-match preloader, negative lookup cache; spec baru `reader-download-coexistence` + modifikasi `image-download-cancellation`)
- `2026-11-06-reader-image-misrouting-native-decision` (13/13 — pisah hint Content-Length vs animated, page-gen guard, ValueKey triple-identity; spec baru `reader-image-routing`)
- `2026-10-31-reader-animated-fps-throttle` (9/9 — `validate --strict` valid; cap animasi 900/720→720/540 + badge tap-to-pause `_userPaused`; spec `reader-thermal-management` tersinkron; device-accept user tanpa after-fix build: scroll VRAM stabil 232MB)
- `2026-10-31-memory-bottleneck-remediation` (31/31 — spec baru `memory-budget` tersinkron; delta `offline-library` MODIFIED-only tanpa main spec → tidak tersinkron, tetap di arsip)
- `2026-10-21-chapter-continue-button` (12/12 — `validate --strict` valid; 16 test terkait hijau, analyze 0; spec `chapter-continue-button` tersinkron ke `openspec/specs/`; device-verify tombol di detail masih milik user)
- `2026-10-12-kuro-streak-widget-card` (13/13 — device gates diterima user; spec `reading-streak-widget` tersinkron ke `openspec/specs/`; 3 varian widget 4×2/4×1/2×2 + `StreakCard` Varian A + ARB en/id/zh)
- `2026-09-27-smooth-page-transitions` (10/10 — device gates diterima user "lumayan bagus"; spec `page-transitions` tersinkron ke `openspec/specs/`; follow-up: predictive back + container transform)
- `2026-09-26-nclient-v2v3-import` (19/19 — device-verify 5.2 masih perlu user; spec `nclient-library-import` tersinkron ke `openspec/specs/`)
- `2026-09-26-kuron-full-backup` (12/13 — 4.2 device-blocked, lihat Recent Sessions; spec `kuron-full-backup` tersinkron ke `openspec/specs/`)
- `2026-09-02-show-last-update-on-cards`
- `2026-09-01-mangadex-external-chapter-support`
- `2026-08-29-reader-cpu-gpu-ram-kill`
- `2026-08-29-reader-dispose-and-coldstart-kill`
- `2026-08-27-fix-mangaforfree-reader-online-blank`
- `2026-08-21-update-nicomanga-config`
- `2026-08-21-improve-config-generator-validation-loop-2`
- `2026-08-21-update-nicomanga-config`
- `2026-08-21-rust-image-pipeline-migration`
- `2026-08-21-improve-reader-translation-draw-and-architecture`
- `2026-08-16-reader-ai-translate-improvements`
- `2026-08-16-provider-manager-screen`
- `2026-08-16-add-doujin-desu-xxx-source`
- `2026-08-11-reader-ai-bubble-segmentation`
- `2026-08-09-reader-ai-render-polish`
- `2026-08-09-reader-ai-webtoon-cs-translate`
- `2026-08-09-security-hardening-review-fixes`
- `2026-08-09-komiktap-ssl-websocket-bypass`
- `2026-08-07-reader-ai-learning-mode`
- `2026-08-06-hero-animation-detail-navigation`
- `2026-07-30-rust-hotspot-acceleration`
- `2026-07-30-fix-ehentai-cs-restart-on-scroll`
- `2026-07-30-fix-ehentai-animated-loading-card`
- `2026-07-29-rust-image-processing-engine`
- `2026-07-29-rust-content-decryptors`
- `2026-07-29-reader-engine-performance-boost`
- `2026-07-27-add-mangapill-mangahere-sources`
- `2026-07-26-add-mangapill-source`
- `2026-07-26-cancel-image-download-on-dispose`
- `2026-07-25-pin-biometric-app-lock`
- `2026-07-25-download-bloc-refactor`
- `2026-07-24-reader-download-overheat-fix`
- `2026-07-24-add-mangafire-vrf-capture`
- `2026-07-18-notification-snackbar-audit-fix`
- `2026-07-18-hdoujin-source-integration`
- `2026-07-18-fix-performance-overheat`
- `2026-07-18-code-quality-refactor-phase-2`
- `2026-07-17-code-quality-refactor-phase-1`
- `2026-07-16-fix-overheat-lock-screen`
- `2026-07-14-schale-network-source`
- `2026-07-14-note-mode`
- `2026-07-13-sync-native-theme`
- `2026-07-13-rawdevart-config`
- `2026-07-13-download-jank-reduction`
- `2026-07-12-reader-120fps-optimization`
- `2026-07-10-revamp-mangafire-to-json-api`
- `2026-07-10-add-vihentai-source`
- `2026-07-06-source-health-monitor`
- `2026-07-06-smart-query-parser`
- `2026-07-06-migrate-legacy-search-configs`
- `2026-07-06-deprecate-legacy-search-ui`
- `2026-07-05-upgrade-android-deps-july-2026`
- `2026-07-05-revamp-kuron-config-runtime`
- `2026-07-05-config-generator-validation-loop`
- `2026-07-05-add-kuron-config-generator`
- `2026-07-03-smart-config-generator`
- `2026-07-03-search-form-ui-parity`
- `2026-07-03-migrate-legacy-search-configs`
- `2026-06-28-native-dns-rollout`
- `2026-06-28-home-scroll-reader-optimization`
- `2026-06-27-update-manhwaread-config`
- `2026-06-26-upgrade-core-packages`
- `2026-06-26-purge-ui-packages`
- `2026-06-26-bloc-pattern-modernization`
- `2026-06-25-refine-card-surface-a11y`
- `2026-06-23-mangafire-integration`
- `2026-06-23-lazy-load-chapters`
- `2026-06-23-ehentai-download-strategy`
- `2026-06-21-tabbed-multilang-chapters`
- `2026-06-21-search-runtime-autowiring`
- `2026-06-16-tachiyomi-extensions-integration`
- `2026-06-16-offline-library-sorting-source-buckets`
- `2026-06-16-offline-library-v2`
- `2026-06-01-reader-ux-revamp`
- `2026-06-01-doujindesuv2-scraper`
- `2026-05-28-fix-generic-rest-adapter-schema-support`
- `2026-05-24-ehentai-part-mode-metadata-sync`
- `2026-05-24-avif-to-webp-conversion`
- `2026-05-19-fix-url-special-chars`
- `2026-04-20-ehentai-download-reader-stability`
- `2026-04-19-blur-recent-apps-privacy`
- `2026-04-12-local-collection-categories`
- `2026-04-xx-komiktap-navigation-lists`
- `2026-04-xx-qol-enhancements`
- `2026-03-31-fix-import-zip-metadata`
- `2026-03-xx-crotpedia-ui-modernization`
- `2026-03-xx-fix-app-drawer-transparency`
- `2026-03-xx-multi-provider-integration`
- `2026-03-xx-smart-caching-and-fixes`
- `2026-03-xx-unity-ads-fix`
- `2026-03-xx-view-comments`
- `2026-03-15-cross-source-search-ui`
- `2026-03-15-mangadex-detail-pagination-bug`
- `2026-03-14-app-config-externalization`
- `2026-03-12-builtin-dns-resolver`
- `2026-03-07-fix-source-switch-shimmer`
- `2026-03-03-komiktap-migration`
- `2026-02-22-app-audit-hardcode-ui`
- `2026-02-17-fix-download-range-page-bounds`
- `2026-02-15-fix-download-metadata-parentid`
- `2026-02-15-download-metadata-revamp`
- `2026-02-15-chapter-reading-history`
- `2026-02-14-favorites-bug-fix`
- `2026-02-11-nhentai-search-revamp`
- `2026-02-xx-reader-header-auto-show`
- `2026-02-xx-offline-search-highlight`
- `2026-02-xx-doujin-search-highlight`

### Active Changes (in `openspec/changes/`)
> Counts per `openspec/STATUS.md` 2026-11-06. `video-and-image-separation` + `local-recommendation-engine` sudah terarsip 2026-09-30/27 (entri lama di sini basi, dibersihkan).
- `add-comix-webview-proxy-source` (27/34)
- `ai-image-upscaling` (0/51)
- `hls-video-download` (0/15)
- `home-semua` (0/10)
- `mangadex-search-language-to-detail` (0/14)
- `source-anomaly-report` (0/18)
- `text-only-mode-export` (0/49)

### Open Issues (in `openspec/changes/`)
- *(none)*

---

## RTK - Rust Token Killer

Project requires **RTK** for AI token optimization (60-90% savings):

| Rule | Description |
|---|---|
| **Prefix `rtk`** | Always prepend `rtk` to terminal commands (git, flutter, ls, etc.). |
| **Filtering** | RTK strips boilerplate/noise so AI focuses on relevant data. |
| **Statistics** | Use `rtk gain` to see token savings. |

> Global config at `~/.gemini/GEMINI.md`, `AGENTS.md`, `CLAUDE.md`.

---

### Recent Sessions

> Session log, newest first (latest on top). Detailed rows cover the last 30 days; older sessions are summarized per-month below. For code details, see `openspec/changes/archive/`.

| Date | Tool | Topic | Status | Detail |
|-----|-----|-----|-----|-----|
| 2026-11-06 | muse | Arsip 5 changes + sinkron 7 spec | Done, tanpa commit | `reader-image-misrouting` (13/13, spec `reader-image-routing` baru), `reader-jank` (22/22, spec `reader-download-coexistence` baru + `image-download-cancellation` dimodifikasi), `unified-dev-cli` (12/15, spec `dev-cli-automation` baru; 3.1/3.2/4.2 terbuka), `fix-kuron-packages` (10/10, spec `kuron-runtime-concurrency` baru + 2 req tambah; 3 bug review jadi known issue), `bulk-source-configs` (142/143, spec `bulk-source-batch` baru; 10.3 hentaikisu PARKED). Arsip: `openspec/changes/archive/2026-11-06-*/`. |
| 2026-11-06 | muse | KURO CLI v1.0→v1.1 + fix summary APK | Done, analyze 0, CLI test 5/5, tanpa commit | **Branding KURO** (`scripts/kuron.dart` zero-dep): banner gradient magenta→cyan, wizard menu panah ↑↓ + fallback angka, step counter `[n/N]`, result box, animasi Kuro pacing+shuttle (fix smear: erase-line + truncate sadar-lebar, terbukti via pty). **Fix summary** `build_optimized.sh` + CLI: hitung hanya file run ini + referensi universal flavor-aware (akar 2-APK/740M: summary ngitung seluruh `apk-output/`). Tabel skrip `AGENTS.md` + tasks `unified-dev-cli` 12/15 diupdate. |
| 2026-11-06 | muse | Review 3 changes agy (read-only) | Verified hijau + 4 temuan, tanpa ubah kode | `analyze` 7 area = No issues; 98 test app + paket hijau. **Temuan**: (1) race `clearToken()` vs single-flight (nyata), (2) negative cache 2 dtk vs download selesai (kondisional), (3) `_extractPageNumber` digit pertama (kondisional), (4) `inspectHeader()` 0 caller. Migrasi BaseCubit + refcount + ValueKey placement benar. |
| 2026-11-02 | muse | Komiku chapter 403 CF: daftarkan ke GenericBypassSourceFactory | Done code, analyze 0, tanpa commit | **Akar**: `GenericHttpSource.getChapterImages` panggil adapter langsung tanpa bypass; komiku tak terdaftar di `GenericBypassSourceFactory` (cuma hentaicosplay/spyfakku/mangaforfree/beauty3600000) meski config `requiresBypass:true` → 403 `cf-mitigated` rethrow tak ada yang menangani → `DetailCubit.openChapter` emit failure. **Fix** (`service_locator.dart`): adapter `cf_komiku` (cookie jar isolasi, `preferCapturedHtml`, auto-close `cf_clearance`) + factory `komiku`. Tanpa commit/push. |
### Session Archive by Month

> Ringkasan sesi yang berumur lebih dari 1 bulan (cutoff 2026-11-01 — baris detail hanya untuk November 2026; Oktober–September diringkas di bawah). Detail baris dihapus; arsip openspec tetap di `openspec/changes/archive/`.

| Month | Highlights |
|---|---|
| 2026-10 | Arsip `memory-bottleneck-remediation` (31/31, spec `memory-budget`) + `reader-animated-fps-throttle` (9/9, scroll VRAM 232MB); player video native `VideoPlayerActivity` (chrome hitam, judul pin, header Referer, landscape-only fullscreen, save file-langsung, HLS vs direct) + `ReaderVideoStrip` house-style + `videoIndex` plumbing; FAB lanjut-baca + `StreakCard`/widget 3 varian (arsip); port desktop macOS (flavor dev/prod, Swift plugin, dylib Rust, picker, entitlements); hardening rilis (R8 keep-rules, CI `verify.yml`, keystore re-encrypt); upgrade dep + security audit; splash token ARB; komiktap API v2 + comix bytag/pagination + rawkuma POST+nonce/mitaku pagination; batch UI (avatar tier, thumb placeholder, wifi-gate, sort manifest, sidebar desktop). |
| 2026-09 | Neobrutalism redesign 4-frame; arsip `offline-ai-polish-pack` (paginasi grup, mosaic tiers, glossary); CI universal-APK + telegram picker; fix dialog back-button ganda; rilis v0.9.26+36; reader model switcher (toolbar→menu ⋮); translate logging + template-echo hardening; fix hang 3000+ row; katalog model AI live + provider Meta/ClinePass/Cohere; last-update di kartu + tgl E-Hentai; MangaDex external-chapter + fix `includeExternalUrl`. Paruh akhir: engine `video-and-image-separation` 28/28 (`reader.video` scoped, dedupe pasca-sanitize, `ReaderVideoStrip` in-flow, mangadistrict 1.0.1 + rombak kartu house-style; arsip 2026-09-30); NClient V2/V3 import + `kuron-full-backup` (arsip + spec tersinkron, integration test round-trip); splash label CF jujur + cache TTL; fix namespace AGP9 `android.uniquePackageNames=false` (Cronet embedded); doujindesu taxonomy; arsip `page-transitions` + `local-recommendation-engine`; `bulk-source-configs` Batch 6 (7 shipped, manifest 105, bug wave 35 configs); home-semua planning 4/4 (belum apply). |
| 2026-08 | Test bawaan 9/9 + 12 pre-existing; reader paginasi WP; fix keyboard menutup bottom sheet; fix stale image A→B; arsip 2 reader-kill + mangaforfree; unify pipeline download-first; generator smoke loop fix; overlay z-order; Keiyoushi Phase-1 + 14 device-fix; draw pill + shape tools; translate improvements + NNAPI CPU fallback; spike Areakomik; bubble-seg polish ×4; render polish (font manga + font-fit); viewport capture webtoon; security review (proposal-only); analisis ComicX/MangaFire; Nicomanga chaotic + parseChapterApi; Learning Mode arsip; hapus rantai PDF Dart mati. |
| 2026-07 | Rust hotspot (hitomi/ehentai/header FFI); arsip 2 change E-Hentai + sync 3 spec; fix CS loading card; MangaPill build + eksplorasi 10+ situs; cancel download on dispose; App Lock PIN+biometrik; revert VRF; 4 reader fix; Nicomanga base64; refactor Phase 1+2; notif/snackbar audit; overheat lifecycle; HDoujin + Schale CF bypass; theme native + PDF routing; 120fps overhaul ×2; WebP non-CS; CS perf; ToonCubus; Hentaicosplay; RawDevArt; ViHentai regex; MangaDex lang filter; MangaFire paging + scanGroup; numeric search; deprecate legacy UI; ehentai heavy; AVIF offline (in progress); melos v8; search-form parity. |
| 2026-06 | Dynamic sort fix; analisis ViHentai; review + refactor CA + gitleaks; CMS templates; tag duplikat; DNS native; home/reader perf; bootstrap HentaiRead; ManhwaRead feed + full config; ShiroDoujin; SpyFakku tags; offline resync + card revamp; core upgrades + purge UI; BLoC modernization; rilis v0.9.21+31; LifecycleWatcher guard; generator Phase 1+2; integrasi MangaFire; tag routing; strategi download E-Hentai; dedupe offline ×2; arsip tabbed; chapter UI polish ×3; MangaDex lane paging; tabbed impl; Crotpedia dedupe; chip polish; search-runtime (in progress); offline polish + pagination plan; rate-limit hardening. |

---

## Release Runbook (v0.9.x)

> **⚠️ TAG PUSH TIDAK TRIGGER CI** sejak 2026-07-14 (push events loss — hanya `workflow_dispatch` yang jalan). Jangan andalkan `git push --tags` untuk build/release — gunakan dispatch ke ref tag:

```bash
# 1. Commit semua perubahan + bump versi di pubspec.yaml, CHANGELOG.md, README.md, README_id.md

# 2. Buat tag + push ke remote (untuk referensi release)
git tag v0.9.24+34
git push origin v0.9.24+34

# 3. TRIGGER CI — dispatch workflow ke REF TAG (github.ref = refs/tags/v0.9.24+34)
#    → release-step (`if: startsWith(github.ref, 'refs/tags/v')`) JALAN → GitHub Release dibuat otomatis
gh workflow run build.yml --ref v0.9.24+34 -f build_type=release -f split_abi=true -f upload_artifact=true

# 4. Pantau build (~8-10 menit)
gh run list --limit 5
gh run view <run-id> --json status,conclusion

# 5. Verifikasi release + APK assets
gh release list --limit 2
gh release view v0.9.24+34 --json assets -q '.assets[].name'
```

**Kenapa**: `on: push: tags: 'v*'` di `.github/workflows/build.yml` TIDAK trigger sejak Juli 2026 (GitHub event loss — `gh api .../actions/runs?event=push` tak ada run baru). `workflow_dispatch` ke `--ref <tag>` memaksa `github.ref = refs/tags/vX` sehingga release-step (`if: startsWith(github.ref, 'refs/tags/v')`) aktif — hasil sama dengan push-tag yang sehat.

**Hindari**: commit subject dengan `[ci skip]` pada commit yang akan di-tag — Actions skip workflow. Pastikan tag menunjuk commit normal.

---

## Protected Files (NEVER edit directly)
- `*.g.dart` — Generated by `build_runner`
- `*.freezed.dart` — Generated by Freezed
- `pubspec.lock` — Auto-generated

> Edit source file and run: `fvm flutter pub run build_runner build --delete-conflicting-outputs`

---

## Openspec Notes Archive and Change Log
> **📌 NOTE**: Openspec notes are archived here for reference. They are not meant to be edited directly.

| folder | notes |
|--------|-------|
| `2026-11-06-bulk-source-configs` | 142/143 (10.3 hentaikisu PARKED atas permintaan bos); spec baru `bulk-source-batch` (8 requirements); Batch 7-8 + engine issues #62–68 jadi backlog, bukan janji. |
| `2026-11-06-fix-kuron-packages-concurrency-and-state` | 10/10; single-flight clearance, executor split Kotlin, slot RateLimiter sinkron, BaseCubit/isClosed, hapus total DoH Dart. Spec baru `kuron-runtime-concurrency` + 1 req tambah di `native-dns-runtime`/`presentation-layering`. 3 bug review terarsip sebagai known issue: race `clearToken()` vs single-flight (nyata), negative cache 2 dtk (kondisional), `_extractPageNumber` digit pertama (kondisional). |
| `2026-11-06-unified-dev-cli` | KURO v1.1.0 (`scripts/kuron.dart` zero-dep + launcher `./kuron`): banner gradient, wizard menu panah ↑↓ + fallback angka, step counter `[n/N]`, result box, animasi Kuro pacing+shuttle (erase-line + truncate sadar-lebar), summary APK per-run + universal ref flavor-aware. 12/15 (terbuka: 3.1 shim, 3.2 CI, 4.2 README). Spec baru `dev-cli-automation`. |
| `2026-11-06-reader-jank-during-active-downloads` | 22/22; refcount reader (`increment/decrementReaderCount`), page-match by number + negative lookup cache di preloader, prefetch cancel + large-jump cleanup, `_processQueue` tanpa full DB reload. Spec baru `reader-download-coexistence` + modifikasi `image-download-cancellation`. Sisa manual: smoke test jank di device. |
| `2026-11-06-reader-image-misrouting-native-decision` | 13/13; pisah hint Content-Length ≥2MB dari set native animated, captured `(pageNumber, _pageGen)`, hapus asumsi `webp ⇒ animated`, ValueKey triple-identity. Spec baru `reader-image-routing`. Sisa manual: smoke test WebP di device. |
| `2026-11-06-audit-reader-and-kuron-packages` | Deep audit via 3 subagents: 1) `reader-jank-during-active-downloads` (temukan bug resume queue pasca-reader, plain bool race, prefetch cancel bypass saat jump>3, token remove race di prefetch cubit, burst DB reload). 2) `reader-image-misrouting-native-decision` (temukan post-frame callback dimension leak, routing native via content-length hint tanpa konfirmasi bytes). 3) `packages/kuron_*` concurrency & lifecycle (ClearanceService interceptor hang + stampede, single-thread executor bottleneck di Kotlin plugin, RateLimiter burst, ViHentai options copyWith, ReaderCubit emit after close) + identifikasi 8 file dead code Dart-side DNS stack untuk di-takeout. Specs & tasks di ketiga change telah diselaraskan & divalidasi. |
| `2026-09-07-offline-ai-polish-pack` | Offline group pagination (20 groups/page, source buckets, reset-to-page-1) + two-phase enrich hotfix 3000+ rows + glossary prompt injection (max 5, no extra AI calls) + mosaic quality tiers (low JPEG75/1MB, high JPEG85/2MB, default high) + `ModelJsonParser` template-echo hardening + translate structured logging + reader model switcher (menu ⋮) + back-button dialog removal. Delta specs DI-SYNC (pagination baru, translation 14→15, glossary 3→4). 11/11 tasks (5.1 centang instruksi user, flutter test user-run). |
| `2026-09-02-show-last-update-on-cards` | Home & by-tag cards show relative update time: `MainGridCard`/`MainFeaturedCard` + `RelativeTimeUtils` (epoch/future guard, l10n en/id/zh), `GenericContentMapper` Indonesian `lalu` parsing, config `mangadex`/`komikcast`/`rawdevart`/`komiku` list `uploadDate` (optional), E-Hentai list `posted_*/postedpop_*` → `uploadDate` enrichment. DoujinDesu.xxx/Hitomi already via adapter. Verified device. |
| `2026-09-01-mangadex-external-chapter-support` | MangaDex dual-mode chapter (internal vs external via `externalUrl`/`pages`) — `Chapter` entity `externalUrl/pages/isUnavailable` + `isExternal`/`isReadableInApp`, `GenericContentMapper`, `GenericRestAdapter` guard skip at-home + no-retry, `ContentModel`/`reader_route_extra` persist, `DetailCubit` `launchUrl`, UI badge `External • host` + `open_in_new` + hint + download guard, l10n 4 keys, pipeline `externalChapter` diagnostic. **Bug fix**: `includeExternalUrl=1` filter ke hanya external → dihapus, tanpa param return both (`externalUrl` tetap ada). Detail: Recent Sessions 2026-09-01. |
| `2026-08-21-update-nicomanga-config` | Config v1.2.0→v1.3.0 — redesign HTML list (grid → `article.list-manga-card`), URL pattern dipaksa view grid (`v=grid`); genreSearch/genreSearchPage ke format baru `/manga-list.html?g={tag}` (slug kebab, ganti `/g/{base64}.html`). Detail & reader tak berubah (chaotic payload `NicoMangaX2` stabil). |
| `2026-08-21-rust-image-pipeline-migration` | Migrasi 3 hot path CPU-bound Dart (`package:image`) ke Rust FFI `image_ops.rs`: `image_ops_chunk_webtoon` (ganti `_splitWebtoonIsolate`), `image_ops_build_mosaic` (ganti `MosaicBuilder.buildMosaic`), `image_ops_compress_page` (ganti `FallbackImageHandler.compressPage`). Null-safe fallback ke Dart bila `.so` tidak tersedia. Percepatan 3-10×. |
| `2026-08-21-improve-reader-translation-draw-and-architecture` | Draw mode shape tools (rect/ellipse/freeform) + architecture cleanup: `DownloadService.fetchRemoteImageBytes`, `SaveGlossaryEntryUsecase`, `_bumpUi()` uiVersion re-emit. 21/22 tasks (6.3 eyeball device pending). Detail: Recent Sessions 2026-08-17. |
| `2026-08-16-reader-ai-translate-improvements` | T2 prefetch + NNAPI hard fix (MTK tanpa kernel Flatten → fallback CPU-only session) + overlay stuck fix 3 lapis (buildWhen dihapus total, `SizedBox.expand`, emit Detecting paling depan) + fonts Bangers/ComicNeue. 25/25 test. Archived dgn 3 task device-blocked. Detail: Recent Sessions 2026-08-16. |
| `2026-08-16-provider-manager-screen` | Ekstrak kelola provider BYOK dari `AiSettingsScreen` (479 baris) jadi screen terpisah `ProviderManagerScreen` (route + shortcut). Settings sisakan prefs/lang/style/sfx/privacy/glossary. Repo CRUD sudah ada (`AiProviderRepository`), UI-nya yang inline-coy. |
| `2026-08-16-add-doujin-desu-xxx-source` | Standalone source doujin.desu.xxx (encrypted API, `adapterOverride` kustom). Fix pasca-implementasi: tags detail dari `manga_genres`+`term_list`, routing `raw:` prefix (search/tag_id→slug via cache `/api/genres`), pagination offset-based + `x-total-count` header. Config v1.1.0 schemaVersion 2.0. Delta spec DI-SYNC. 9/12 tasks. |
| `2026-08-11-reader-ai-bubble-segmentation` | Upgrade detektor YOLO26n box-only → instance segmentation (ShadowB YOLO26s-seg, mask+polygon, 3 class frame/text/balloon). Banyak follow-up render polish: polygon smooth/rect-like, inscribed font-fit, dedupe mosaic chip, AVIF animated detect, feather border, font cap 32px. Catatan MTK: NNAPI tanpa kernel Flatten → bench wajib sertakan CPU baseline + gate default-CPU. |
| `2026-08-09-reader-ai-render-polish` | Font manga Komika/KosugiMaru + `_fitText` loop size desc + bubble inflate <44px + flat-bubble heuristic (`needsWhitePatch`) + stroke putih 3-layer. Delta spec `reader-ai-render` DI-SYNC. 1 task screenshot device pending. |
| `2026-08-09-reader-ai-webtoon-cs-translate` | CS translate WYSIWYG viewport capture: snapshot `RenderRepaintBoundary` wrapper (boundary = layar), lazy capture saat Detect, cache key `$imageUrl#$cropYTop`. Delta spec TIDAK di-sync (usang). 1 task golden check pending. |
| `2026-08-09-security-hardening-review-fixes` | **PROPOSAL ONLY, NOT IMPLEMENTED**. Security review 10 temuan → 3 capability spec: `webview-ssl-trust` (gated consent), `credential-at-rest` (hapus password replay, secure storage cookie jar), `network-hardening` (cleartext off, redirect allowlist, cookie scoping, log redaction). Delta specs TIDAK di-sync. |
| `2026-08-09-komiktap-ssl-websocket-bypass` | SSL bypass komiktap: `onReceivedSslError` unconditional proceed + `_usedSslFallback` flag → Chrome Custom Tab retry. 3 task device-test pending. Akan DIUBAH oleh security-hardening (bypass → gated consent) jika diimplementasi. |
| `2026-08-07-reader-ai-learning-mode` | Full AI translation pipeline BYOK multi-provider: ONNX `BubbleDetector.kt`, domain entities, OpenAI-compatible + Gemini providers, MosaicBuilder, translation cache SQLite v14, AiSettingsScreen, ReaderTranslationCubit (NMS, 429 round-robin), draw mode, l10n en/id/zh. 53/55 tasks. |
| `2026-08-06-hero-animation-detail-navigation` | Hero animasi cover kartu → header detail: tag `content-cover-{content.id}` di `MainGridCard`/`MainFeaturedCard` + detail flexibleSpace. Hero aktif hanya jika image loaded (`onImageLoaded` callback), fallback fade-slide biasa. Mengaktifkan dead code `AppHeroHelper`. |
