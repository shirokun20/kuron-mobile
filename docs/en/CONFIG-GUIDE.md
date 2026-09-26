# Config-Driven Source Guide

> **Kuron App** — How to create, register, and validate a new content source config.

---

## Overview

Kuron uses a **config-driven architecture**. Every content source (manga/doujin site) is described entirely by a single JSON file. No Dart code needs to be changed to add a new source — the config file is the only required artifact.

A complete config describes **six things**:

| # | What | Key |  
|---|------|-----|
| 1 | Source identity & base URL | `source`, `baseUrl`, `version` |
| 2 | UI display info (name, icon, color) | `ui` |
| 3 | Network rules (bypass, headers, rate limit) | `network` |
| 4 | How to fetch list / detail / chapters | `scraper` or `api` |
| 5 | How to fetch and display images in the reader | `scraper.selectors.reader` |
| 6 | Which features the source supports | `features` |

---

## Config Anatomy

A config file is a single JSON object. At minimum it must have:

```
source        (required)  Unique source ID — must match filename prefix
version       (required)  Semantic version string, e.g. "1.0.0"
enabled       (required)  true/false — toggle without removing the file
baseUrl       (required)  Root URL of the site
defaultLanguage (required) e.g. "english", "japanese", "indonesian", "unknown"
scraper or api (required) At least one data driver must be present
features      (required)  Capability flags
ui            (required)  Display metadata for the app UI
```

---

## Top-Level Fields

```jsonc
{
  // ── Identity ─────────────────────────────────────────────────────
  "source": "mysite",               // REQUIRED. Unique snake_case ID
  "version": "1.0.0",              // REQUIRED. Bump on every config change
  "enabled": true,                  // REQUIRED. false = source hidden in app
  "baseUrl": "https://mysite.com", // REQUIRED. Used to resolve relative URLs

  // ── Language ─────────────────────────────────────────────────────
  "defaultLanguage": "english",
  // Values: "english" | "japanese" | "chinese" | "korean"
  //         "indonesian" | "thai" | "vietnamese" | "unknown"
  // Applied when individual items have no language tag

  // ── Remote sync (optional) ────────────────────────────────────────
  "configUrl": "https://raw.githubusercontent.com/.../mysite-config.json",
  // If present, the app can hot-reload this config from the remote URL

  // ── Content ID pattern (optional) ────────────────────────────────
  "contentIdPattern": "/manga/([^/]+)",
  // Regex used to extract the content ID from a full URL
  // Required if the app needs to detect links from this source

  // ── UI display ────────────────────────────────────────────────────
  "ui": {
    "displayName": "My Site",
    "iconPath": "https://raw.githubusercontent.com/shirokun20/nhasixapp/refs/heads/master/app/images/mysite.png",
    "brandColor": "#FF6740",           // Hex color for accents
    "openInBrowserUrl": "https://mysite.com" // Fallback open-in-browser URL
  },

  // ── Network rules ─────────────────────────────────────────────────
  "network": {
    "requiresBypass": false,           // true = needs Cloudflare/WebView bypass
    "headers": {                       // Extra headers sent with every request
      "Referer": "https://mysite.com/",
      "User-Agent": "Mozilla/5.0"
    },
    "rateLimit": {                     // Optional: throttle requests
      "requestsPerSecond": 1,
      "maxConcurrentRequests": 2
    }
  }
}
```

---

## Data Driver: `scraper` (HTML)

Use this when the site serves HTML pages only.

```jsonc
"scraper": {
  "enabled": true,

  // ── URL templates ─────────────────────────────────────────────────
  "urlPatterns": {
    // Home / latest page
    "home": {
      "url": "/",
      "list": {
        "container": ".gallery-item",         // CSS selector for each card
        "fields": {
          "id": {
            "selector": "a",
            "attribute": "href",
            "transform": "slug"               // IMPORTANT: always use for IDs
          },
          "title": { "selector": ".title" },
          "coverUrl": { "selector": "img", "attribute": "src" }
        },
        "pagination": {
          "next": "a.next-page",              // CSS for "next page" link
          "links": ".pagination a"            // CSS for numbered page links
        }
      }
    },

    // Page N of home (use {page} placeholder)
    "homePage": { "url": "/page/{page}/", "inherits": "home" },

    // Search
    "search": { "url": "/?s={query}", "inherits": "home" },
    "searchPage": { "url": "/page/{page}/?s={query}", "inherits": "search" },

    // Genre/tag browse
    "genreSearch": { "url": "/genre/{tag}/", "inherits": "home" },
    "genreSearchPage": { "url": "/genre/{tag}/page/{page}/", "inherits": "home" },

    // Detail page (series overview)
    "detail": "/manga/{id}/",

    // Chapter/reader page
    "chapter": "/{id}/"
  },

  // ── CSS selectors ─────────────────────────────────────────────────
  "selectors": {
    "detail": {
      "fields": {
        "title":       { "selector": "h1.title" },
        "coverUrl":    { "selector": ".cover img", "attribute": "src" },
        "author":      { "selector": ".author a" },
        "tags":        { "selector": ".tags a", "multi": true },
        "status":      { "selector": ".status" },
        "description": { "selector": ".synopsis" }
      },

      // Chapter list (only for multi-chapter sources)
      "chapters": {
        "container": ".chapter-list li",
        "fields": {
          "id": {
            "selector": "a",
            "attribute": "href",
            "transform": "slug"     // MUST match reader nav output
          },
          "title": { "selector": ".chapter-name" },
          "date":  { "selector": ".chapter-date" }
        }
      }
    },

    "reader": {
      "container": "#reader-wrap",
      "images": {
        "selector": "#reader-wrap img",
        "attribute": "src"
      },
      // Navigation links scraped from the reader page DOM
      "nav": {
        "next": "a.btn-next",
        "prev": "a.btn-prev"
      }
    }
  }
}
```

### Field Selector Options

| Key | Type | Description |
|-----|------|-------------|
| `selector` | string | CSS selector |
| `attribute` | string | HTML attribute to read (omit for text content) |
| `transform` | `"slug"` | Extract last meaningful path segment from a URL |
| `regex` | string | Regex with one capture group to filter/extract value |
| `multi` | boolean | Return array instead of single value |
| `fallback` | string | Static fallback if extraction returns empty |

> ⚠️ **Critical rule**: Chapter `id` fields **must** use `"transform": "slug"` when extracted from `href`. Without it, the reader's next/prev navigation cannot match chapters in `_allChapters` and will display `unknownChapter`.

---

## Data Driver: `api` (REST JSON)

Use this when the site exposes a JSON API.

```jsonc
"api": {
  "enabled": true,
  "url": "https://api.mysite.com",    // Optional: overrides baseUrl for API calls

  "endpoints": {
    "allGalleries": "/manga?page={page}",
    "search": "/manga?q={query}&page={page}",
    "detail": "/manga/{id}"
  },

  // List response parsing
  "list": {
    "items": "$.data[*]",              // JSONPath to items array
    "pagination": {
      "offsetMode": false,             // true = use offset, false = use page number
      "currentPage": { "path": "$.page" },
      "total":       { "path": "$.total" },
      "limit":       { "path": "$.limit" }
    },
    "fields": {
      "id":       { "selector": "$.id" },
      "title":    { "selector": "$.attributes.title" },
      "coverUrl": { "selector": "$.cover.url" },
      "tags":     { "selector": "$.tags[*].name", "multi": true },
      "language": { "selector": "$.language" }
    }
  },

  // Detail response parsing
  "detail": {
    "fields": {
      "id":    { "selector": "$.data.id" },
      "title": { "selector": "$.data.attributes.title" }
    },
    // Chapter list from separate endpoint
    "chapters": {
      "endpoint": "/manga/{id}/chapters?limit=100",
      "items": "$.data[*]",
      "fields": {
        "id":          { "selector": "$.id" },
        "chapterNum":  { "selector": "$.attributes.chapter" },
        "title":       { "selector": "$.attributes.title" },
        "language":    { "selector": "$.attributes.translatedLanguage" },
        "externalUrl": { "selector": "$.attributes.externalUrl" },
        "pages":       { "selector": "$.attributes.pages" },
        "isUnavailable": { "selector": "$.attributes.isUnavailable" },
        "date":        { "selector": "$.attributes.publishAt" }
      }
    }
  },

  // How to fetch chapter images
  "images": {
    "mode": "atHome",
    "atHomeEndpoint": "/at-home/server/{chapterId}"
    // Other modes: "directUrl", "hentaifoxCdn"
  }
}
```

> **MangaDex external chapters**: When `externalUrl` is non-empty the chapter is hosted on a third-party site (e.g. `comikey.com`) and `pages` is `0`. The app opens `externalUrl` in the external browser instead of calling `/at-home/server/{chapterId}`. Do **not** set `includeExternalUrl` — without it the API returns both internal and external chapters (with `externalUrl` still present); `includeExternalUrl=1` filters to *only* external and breaks manga with no external chapters.

---

## Features Flags

These control which UI features appear for this source.

```jsonc
"features": {
  "search":       true,   // Search bar visible
  "chapters":     true,   // Chapter navigation enabled (multi-chapter series)
  "download":     true,   // Allow offline download
  "favorite":     true,   // Allow adding to favorites
  "comments":     false,  // Show comments section
  "related":      false,  // Show related content
  "generatePdf":  true,   // Allow PDF export
  "offlineMode":  true,   // Allow offline reading
  "advancedSearch": false,// Show advanced search form
  "supportsAuth": false   // Show login button
}
```

---

## Search Form

Declares which query parameters the search UI should expose.

```jsonc
"searchForm": {
  "urlPattern": "search",        // Which urlPattern key to use
  "params": {
    "query": {
      "queryParam": "s",          // URL parameter name
      "type": "text",
      "placeholder": "Search..."
    },
    "page": {
      "queryParam": "page",
      "type": "page"
    }
  }
}
```

For advanced search with selects/tags/multi-values, see `mangadex-config.json` or `hentainexus-config.json` as reference.

---

## Authentication (Optional)

Only needed for sources with login-gated content.

```jsonc
"auth": {
  "enabled": true,
  "loginUrl": "https://mysite.com/login/",
  "registerUrl": "https://mysite.com/register/",
  "bookmarkUrl": "https://mysite.com/bookmarks/",
  "nonceRegex": "name=\"_nonce\" value=\"([^\"]+)\"",   // CSRF token extraction
  "loginSuccessFilter": "/dashboard"                    // String in redirect URL on success
}
```

---

## Navigation Tag Mapping (Optional)

Maps tag types to search query format when user taps a tag.

```jsonc
"navigation": {
  "tagQueryMapping": {
    "artist": {
      "mode": "rawParam",
      "param": "q",
      "valueSource": "tagName",
      "valuePrefix": "artist:\"",
      "valueSuffix": "\""
    },
    "default": {
      "mode": "rawParam",
      "param": "q",
      "valueSource": "tagName",
      "valuePrefix": "tag:\""
    }
  }
}
```

---

## Decryption (Special Sources)

For sources that encrypt their reader data (e.g., HentaiNexus XOR/RC4).

```jsonc
"decryption": {
  "method": "initReader_xor_rc4_variant",
  "hostname": "mysite.com",
  "readerPath": "/read/{id}",
  "encryptedDataPattern": "initReader\\(\\s*\"([^\"]+)\""
}
```

---

## Step-by-Step: Adding a New Source

### 1. Create the config file

```
<kuron-extensions>/config/new/<source-id>-config.json
```

Start new configs in the `config/new/` staging bucket, then move to the
language bucket (`config/<lang>/`) per the kuron-source-config skill.
Filename prefix **must** match the `"source"` field value.

### 2. Minimum required structure

```json
{
  "source": "mysite",
  "version": "1.0.0",
  "enabled": true,
  "baseUrl": "https://mysite.com",
  "defaultLanguage": "english",
  "ui": {
    "displayName": "My Site",
    "iconPath": "https://...",
    "brandColor": "#000000"
  },
  "network": {
    "requiresBypass": false,
    "headers": {}
  },
  "scraper": {
    "enabled": true,
    "urlPatterns": {
      "home": { "url": "/", "list": { "container": "...", "fields": { "id": {}, "title": {}, "coverUrl": {} } } },
      "detail": "/{id}",
      "chapter": "/{id}"
    },
    "selectors": {
      "detail": { "fields": {} },
      "reader": { "images": { "selector": "img" } }
    }
  },
  "features": {
    "chapters": false,
    "download": true,
    "favorite": true
  }
}
```

### 3. Validate JSON

```bash
python3 -c "import json; json.load(open('<kuron-extensions>/config/new/mysite-config.json'))"
```

### 4. Test key selectors

Open the target page in browser DevTools and test your CSS selectors in the console:

```js
document.querySelectorAll(".gallery-item")  // Should return items
document.querySelector(".gallery-item a").getAttribute("href")  // Should return a URL
```

### 5. Data flow — until the reader works

```
Config                       App
──────                       ───
urlPatterns.detail      →    Fetch series detail page
selectors.detail            → Parse title, cover, tags
selectors.detail.chapters   → Build chapter list (_allChapters)

urlPatterns.chapter     →    Fetch chapter reader page
selectors.reader.images     → Extract image URLs → display in reader

selectors.reader.nav        → Extract next/prev links from reader page DOM
                              Must be slug format → matched against _allChapters.id
```

### 6. Common pitfalls

| Symptom | Cause | Fix |
|---------|-------|-----|
| `unknownChapter` in reader | Chapter `id` format mismatch between list and nav | Add `"transform": "slug"` to chapter list `id` field |
| No images in reader | Wrong `images.selector` or `images.attribute` | Inspect the real DOM for the correct selector |
| Empty chapter list | Wrong `chapters.container` | Inspect the detail page DOM |
| Pagination breaks at page 2 | Missing `homePage` / `searchPage` url pattern | Add separate pattern for paginated URL |
| Tags show as slugs | Missing `text` extraction | Remove `attribute` so selector reads text content |
| Images missing (lazy-load) | Site uses `data-src` instead of `src` | Change `"attribute": "src"` to `"attribute": "data-src"` |

---

## Source Config Reference Matrix

| Field | scraper source | API source | Required |
|-------|---------------|-----------|---------|
| `source` | ✅ | ✅ | **Required** |
| `version` | ✅ | ✅ | **Required** |
| `enabled` | ✅ | ✅ | **Required** |
| `baseUrl` | ✅ | ✅ | **Required** |
| `defaultLanguage` | ✅ | ✅ | **Required** |
| `ui` | ✅ | ✅ | **Required** |
| `network` | ✅ | ✅ | **Required** |
| `scraper` | ✅ | ❌ | One of scraper/api |
| `api` | ❌ | ✅ | One of scraper/api |
| `features` | ✅ | ✅ | **Required** |
| `scraper.selectors.reader` | ✅ | — | **Required** for reader to work |
| `scraper.selectors.reader.nav` | optional | — | Required for next/prev chapter nav |
| `contentIdPattern` | optional | optional | Optional |
| `configUrl` | optional | optional | Optional |
| `auth` | optional | optional | Optional |
| `searchForm` | optional | optional | Optional |
| `navigation.tagQueryMapping` | optional | optional | Optional |
| `decryption` | optional | optional | Optional |
| `rateLimit` | optional | optional | Optional |


