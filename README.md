![Kuron](https://socialify.git.ci/shirokun20/nhasixapp/image?description=1&font=Source+Code+Pro&forks=1&issues=1&logo=https://github.com/shirokun20/nhasixapp/blob/master/assets/icons/logo_app.png%3Fraw%3Dtrue&name=1&owner=1&pattern=Floating+Cogs&pulls=1&stargazers=1&theme=Auto)
# 📱 Kuron - Unofficial Nhentai Client

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Android](https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://www.android.com)
[![18+](https://img.shields.io/badge/Age_Restriction-18%2B-red?style=for-the-badge&logo=warning&logoColor=white)](#)
[![RELEASE](https://img.shields.io/badge/Status-RELEASE_v0.9.27%2B37-green?style=for-the-badge&logo=android&logoColor=white)](#)
[![Build](https://img.shields.io/badge/build-passing-brightgreen?style=for-the-badge)](#)
[![Code Quality](https://img.shields.io/badge/code_quality-A+-blueviolet?style=for-the-badge)](#)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-ff69b4?style=for-the-badge)](#)
[![Downloads](https://img.shields.io/github/downloads/shirokun20/nhasixapp/total?style=for-the-badge&logo=github&logoColor=white&color=007ec6)](https://github.com/shirokun20/nhasixapp/releases)
[![Hits](https://komarev.com/ghpvc/?username=shirokun20&repo=nhasixapp&style=for-the-badge&color=007ec6)](https://github.com/shirokun20/nhasixapp)
[![Stars](https://img.shields.io/github/stars/shirokun20/nhasixapp?style=for-the-badge&logo=github&logoColor=white&color=yellow)](https://github.com/shirokun20/nhasixapp/stargazers)
<a href="https://trakteer.id/shirokun20" target="_blank"><img src="https://img.shields.io/badge/Support_Me-Trakteer-be1e2d?style=for-the-badge&logo=ko-fi&logoColor=white" height="30"/></a>

> [!TIP]
> **[🇮🇩 Baca dalam Bahasa Indonesia](README_ID.md)**

> **Kuron** — mobile reader that's **70% faster** than browser, **privacy-first**, **offline-ready**.
>
> 🚀 **70% faster** · 🔒 **App Disguise** + Recent Apps blur · 📦 **Offline-first** with background DL
> 🧩 **Multi-provider**: nhentai, E-Hentai, Hitomi, + config-driven extensions · 🎨 **Material 3**

---

## 📥 **Download Latest Release**

[📦 **Get v0.9.27+37**](https://github.com/shirokun20/nhasixapp/releases/tag/v0.9.27%2B37)

| Variant | Size | Best For | Status |
|:-------|:----:|:---------|:------:|
| **Universal** | 1 file | All devices (ARM64 / ARM32 / x86_64) — no need to pick | ✅ Available |

---

## ✨ **Key Features**

<table>
  <tr>
    <td width="50%">
      <h4>🔐 nhentai Login & Sync</h4>
      Sign in with nhentai account — CAPTCHA solver, online favorites (Offline/Online/Both), tag blacklist sync, comments, random gallery.
    </td>
    <td width="50%">
      <h4>🧩 Multi-Provider</h4>
      nhentai (default) + E-Hentai, HentaiNexus, Hitomi — all fully supported. Hundreds more via <a href="#🔧-adding-a-custom-source">config-driven extensions</a>.<br/>
      <small>⚠️ Premium sources install via Settings → Sources → Add via Link or Import ZIP.</small>
    </td>
  </tr>
  <tr>
    <td>
      <h4>🤖 AI Translation</h4>
      On-device ONNX bubble detection + BYOK providers (OpenAI-compatible, Gemini). 7 translation styles, per-bubble editing, manual draw mode, glossary, manga-style fonts.
    </td>
    <td>
      <h4>🔐 App Lock</h4>
      PIN + biometric (fingerprint/face) app lock with 10-min session and auto re-lock. Native Android Private DNS (DoH).
    </td>
  </tr>
  <tr>
    <td>
      <h4>📖 Immersive Reader</h4>
      Full-screen, 120fps smooth scrolling, dual-rate scroll, tap zones, draggable chrome toggle, auto-bookmark, continuous scroll <i>and</i> single-page modes.
    </td>
    <td>
      <h4>🔍 Smart Search</h4>
      Advanced filter by tags, popularity, date, language — dynamic form UI, sort, multi-select chips. Works across all providers.
    </td>
  </tr>
  <tr>
    <td>
      <h4>🛡️ Privacy First</h4>
      App Disguise (Calculator/Notes/Weather), Recent Apps blur, <code>.nomedia</code> downloads, blur thumbnails by default. Your data stays yours.
    </td>
    <td>
      <h4>📦 Offline-First</h4>
      Background download, bulk management, ZIP import, one-tap <b>full backup</b> ZIP (favorites, collections, history, reading positions, settings) with safe restore, <b>NClient V2/V3 import</b>, offline reader with progress sync. Full local library with sorting & filtering.
    </td>
  </tr>
  <tr>
    <td>
      <h4>🎨 Material 3 Design</h4>
      Adaptive Dark/Light/AMOLED themes, responsive layout, Lottie animations, shimmer loading. Built for modern Android.
    </td>
    <td>
      <h4>⚡ Performance</h4>
      70% faster than browser — smart preloading, image caching, GPU memory budget, battery-efficient with Wakelock control.
    </td>
  </tr>
</table>

---

## 📱 **Screenshots**

<details>
<summary>🖼️ Click to view screenshots (18+ content warning)</summary>

<table>
  <tr>
    <td align="center"><b>Home & Feed</b></td>
    <td align="center"><b>Detail & Content</b></td>
    <td align="center"><b>Immersive Reader</b></td>
  </tr>
  <tr>
    <td><img src="screenshots/flutter_02.png" width="250" alt="Home Screen" style="border-radius:12px;box-shadow:0 4px 12px rgba(0,0,0,0.15)"/></td>
    <td><img src="screenshots/flutter_13.png" width="250" alt="Detail Screen" style="border-radius:12px;box-shadow:0 4px 12px rgba(0,0,0,0.15)"/></td>
    <td><img src="screenshots/flutter_12.png" width="250" alt="Reader Mode" style="border-radius:12px;box-shadow:0 4px 12px rgba(0,0,0,0.15)"/></td>
  </tr>
  <tr>
    <td align="center"><b>Search & Filters</b></td>
    <td align="center"><b>Settings & Privacy</b></td>
    <td align="center"><b>Offline & Downloads</b></td>
  </tr>
  <tr>
    <td><img src="screenshots/flutter_04.png" width="250" alt="Search Filters" style="border-radius:12px;box-shadow:0 4px 12px rgba(0,0,0,0.15)"/></td>
    <td><img src="screenshots/flutter_06.png" width="250" alt="Settings" style="border-radius:12px;box-shadow:0 4px 12px rgba(0,0,0,0.15)"/></td>
    <td><img src="screenshots/flutter_11.png" width="250" alt="Downloads" style="border-radius:12px;box-shadow:0 4px 12px rgba(0,0,0,0.15)"/></td>
  </tr>
</table>

</details>

---

## 🛠️ **Tech Stack**

| Layer | Stack |
|:------|:------|
| 🎯 **Language** | Flutter 3.24+ · Dart 3.5+ |
| 🏗️ **Architecture** | Clean Architecture · BLoC/Cubit · GetIt DI (manual registration) |
| 🗄️ **Data** | SQLite · SharedPreferences · Dio · GoRouter |
| 🎨 **UI** | Material 3 · CachedNetworkImage · Lottie · PhotoView |
| 🔧 **System** | Wakelock+ · Local Notifications · Permission Handler |

---

## 🚀 **Quick Start**

### **Installation**
1. **Download APK** from [Releases](https://github.com/shirokun20/nhasixapp/releases).
2. **Enable Unknown Sources** in Settings > Security.
3. **Install** and enjoy!

### **Build from Source**
```bash
git clone https://github.com/shirokun20/nhasixapp.git
cd nhasixapp
flutter pub get
flutter run
```

---

## 🔧 **Adding a Custom Source**

> [!TIP]
> **Don't want to build from scratch?**  
> Install **hundreds of community-built extensions** from the official repo:
> 
> 🔗 **[github.com/shirokun20/kuron-extensions](https://github.com/shirokun20/kuron-extensions)**  
> Copy `manifest.json` link → paste in **Settings → Sources → Add via Link**.  
> Star the repo & support the devs! ❤️

Kuron's source system is fully config-driven — no code changes required. Each source is a single JSON file that tells the app how to scrape or call an API.

### Where to look

| Guide | Link |
|:------|:-----|
| Full guide (EN) | [docs/en/CONFIG-GUIDE.md](docs/en/CONFIG-GUIDE.md) |
| Full guide (ID) | [docs/id/CONFIG-GUIDE.md](docs/id/CONFIG-GUIDE.md) |
| Full guide (ZH) | [docs/zh/CONFIG-GUIDE.md](docs/zh/CONFIG-GUIDE.md) |

### Quick steps

1. **Write the config JSON** — create a JSON file describing how to scrape or call the target site's API. See the full guide below for selectors, reader, and auth details.
2. **Fill in selectors / endpoints** — use browser DevTools to inspect the target site.
3. **Create a manifest entry** — to make the source appear in Source Manager, register it via a `manifest.json` hosted online. Entry format:
   ```json
   {
     "id": "mysite",
     "version": "1.0.0",
     "url": "https://yourhost.com/config/mysite-config.json",
     "meta": {
       "displayName": "My Site",
       "description": "Short description",
       "contentType": "manga",
       "language": "en",
       "requiresAuth": false
     }
   }
   ```
4. **Install** — via **Settings → Sources → Add via Link** (paste manifest URL) or **Import ZIP**.
5. **Validate** — run `dart run kuron_generic:kuron_config_validate --help` to catch schema errors before testing.

> See [docs/en/CONFIG-GUIDE.md](docs/en/CONFIG-GUIDE.md) for the full walkthrough including reader nav, auth, decryption, and common pitfalls.

---

## 🆘 **Support**

**FAQ**
- **Can't Install?** Enable "Unknown Sources". One universal APK fits all devices.
- **Missing Images?** Check your internet or clear cache.
- **Hidden Downloads?** They are private by design. View them inside the app.
- **How to add new source?** Go to Settings → Sources → Add via Link (paste manifest URL) or Import ZIP.
- **Search shows nothing / "colliding tags" error?** NHentai API requires a search query when using sort or tag filters. Simply type at least 1 character in the search field before selecting sort/tags. Or use the Home tab sort dropdown for Popular browsing without a keyword. See [GitHub Issue #47](https://github.com/shirokun20/nhasixapp/issues/47) for details.
- **App slow on first load?** First load downloads source configs and caches data. Subsequent launches are faster.
- **Switching phones / reinstalling?** Settings → **BACKUP & RESTORE** → *Backup now* produces a `KuronBackup_*.zip` (share it to Files/Drive). On the new device use *Restore* — it shows a preview first and never overwrites data you already have. Coming from NClient? Use *Import from NClient* in the same section.

---

## ☕ **Support Developer**

If you love **Kuron** and want to support its development, you can sponsor me on GitHub or buy me a coffee! ☕  

[![Sponsor shirokun20](https://img.shields.io/badge/Sponsor-shirokun20-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/shirokun20)

You can also scan the QRIS below to donate:

<p align="center">
  <img src="assets/images/donation_qris.jpeg" width="300" alt="QRIS Donation" style="border-radius: 10px; box-shadow: 0 4px 8px rgba(0,0,0,0.1);"/>
</p>

> **Note:** Your support helps keep the servers running and the updates coming! 🚀

---

## 🤖 Built with AI Assistance

This project is heavily assisted by AI coding agents alongside human engineering:

| Tool | Role |
|:-----|:-----|
| [![Claude](https://img.shields.io/badge/Claude-205060?style=for-the-badge&logo=anthropic&logoColor=white)](https://claude.ai/code) | Architecture, feature implementation, code generation & review |
| [![OpenAI Codex](https://img.shields.io/badge/Codex-412991?style=for-the-badge&logo=openai&logoColor=white)](https://openai.com/codex) | Code generation, refactoring & debugging |
| [![OpenCode](https://img.shields.io/badge/OpenCode-FF6B6B?style=for-the-badge&logo=openai&logoColor=white)](https://opencode.ai) | Agentic coding sessions, AI translation research & credentials |

> 💡 Human supervision, architecture decisions, and final QA remain the core of Kuron — AI agents accelerate the workflow, they don't replace engineering judgment.

---

## 👥 Contributors

Thanks to all contributors who helped make kuron better!

[![Contributors](https://contrib.rocks/image?repo=shirokun20/nhasixapp&max=150&columns=15&anon=1&v=20260309)](https://github.com/shirokun20/nhasixapp/graphs/contributors)

---

## 📜 **License & Legal**

**⚠️ 18+ Content Warning** • **Educational Use Only** • **MIT License**

Licensed under the MIT License. See [LICENSE](LICENSE) for details.
We strongly support content creators; please support official releases whenever possible.
