# 配置驱动的内容源指南

> **Kuron App** — 如何创建、注册并验证新的内容源配置文件。

---

## 概述

Kuron 采用**配置驱动架构**。每个内容源（漫画/同人志网站）完全由一个 JSON 文件描述。添加新源**无需修改任何 Dart 代码**，只需提供配置文件即可。

一份完整的配置描述**六件事**：

| # | 内容 | 键名 |
|---|------|------|
| 1 | 源的身份标识与基础 URL | `source`, `baseUrl`, `version` |
| 2 | UI 显示信息（名称、图标、颜色） | `ui` |
| 3 | 网络规则（Bypass、请求头、频率限制） | `network` |
| 4 | 如何获取列表 / 详情 / 章节 | `scraper` 或 `api` |
| 5 | 如何在阅读器中获取并显示图片 | `scraper.selectors.reader` |
| 6 | 该源支持哪些功能 | `features` |

---

## 配置结构

配置文件是一个 JSON 对象，最少必须包含：

```
source          （必填）唯一的源 ID — 必须与文件名前缀一致
version         （必填）语义化版本字符串，如 "1.0.0"
enabled         （必填）true/false — 不删除文件直接禁用
baseUrl         （必填）网站根 URL
defaultLanguage （必填）如 "english"、"japanese"、"chinese"、"unknown"
scraper 或 api  （必填）至少需要一个数据驱动器
features        （必填）功能开关标志
ui              （必填）App UI 显示元数据
```

---

## 顶层字段

```jsonc
{
  // ── 身份标识 ──────────────────────────────────────────────────────
  "source": "mysite",               // 必填。唯一的 snake_case ID
  "version": "1.0.0",              // 必填。每次配置变更时递增
  "enabled": true,                  // 必填。false = 在 App 中隐藏该源
  "baseUrl": "https://mysite.com", // 必填。用于解析相对 URL

  // ── 语言 ──────────────────────────────────────────────────────────
  "defaultLanguage": "japanese",
  // 可选值："english" | "japanese" | "chinese" | "korean"
  //         "indonesian" | "thai" | "vietnamese" | "unknown"
  // 当单个条目没有语言标签时使用此默认值

  // ── 远程同步（可选） ──────────────────────────────────────────────
  "configUrl": "https://raw.githubusercontent.com/.../mysite-config.json",
  // 若存在，App 可从远程 URL 热加载此配置

  // ── 内容 ID 匹配模式（可选） ──────────────────────────────────────
  "contentIdPattern": "/manga/([^/]+)",
  // 从完整 URL 中提取内容 ID 的正则表达式

  // ── UI 显示 ───────────────────────────────────────────────────────
  "ui": {
    "displayName": "My Site",
    "iconPath": "https://raw.githubusercontent.com/shirokun20/nhasixapp/refs/heads/master/app/images/mysite.png",
    "brandColor": "#FF6740",
    "openInBrowserUrl": "https://mysite.com"
  },

  // ── 网络规则 ──────────────────────────────────────────────────────
  "network": {
    "requiresBypass": false,       // true = 需要 Cloudflare/WebView 绕过
    "headers": {
      "Referer": "https://mysite.com/",
      "User-Agent": "Mozilla/5.0"
    },
    "rateLimit": {                 // 可选：限制请求频率
      "requestsPerSecond": 1,
      "maxConcurrentRequests": 2
    }
  }
}
```

---

## 数据驱动器：`scraper`（HTML 抓取）

当网站只提供 HTML 页面时使用此驱动器。

```jsonc
"scraper": {
  "enabled": true,

  // ── URL 模板 ──────────────────────────────────────────────────────
  "urlPatterns": {
    // 首页 / 最新页
    "home": {
      "url": "/",
      "list": {
        "container": ".gallery-item",        // 每张卡片的 CSS 选择器
        "fields": {
          "id": {
            "selector": "a",
            "attribute": "href",
            "transform": "slug"              // 重要：ID 字段必须使用
          },
          "title": { "selector": ".title" },
          "coverUrl": { "selector": "img", "attribute": "src" }
        },
        "pagination": {
          "next": "a.next-page",
          "links": ".pagination a"
        }
      }
    },

    // 第 N 页（使用 {page} 占位符）
    "homePage": { "url": "/page/{page}/", "inherits": "home" },

    // 搜索
    "search": { "url": "/?s={query}", "inherits": "home" },
    "searchPage": { "url": "/page/{page}/?s={query}", "inherits": "search" },

    // 按标签/类型浏览
    "genreSearch": { "url": "/genre/{tag}/", "inherits": "home" },
    "genreSearchPage": { "url": "/genre/{tag}/page/{page}/", "inherits": "home" },

    // 详情页（系列概览）
    "detail": "/manga/{id}/",

    // 章节/阅读器页面
    "chapter": "/{id}/"
  },

  // ── CSS 选择器 ────────────────────────────────────────────────────
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

      // 章节列表（仅用于多章节源）
      "chapters": {
        "container": ".chapter-list li",
        "fields": {
          "id": {
            "selector": "a",
            "attribute": "href",
            "transform": "slug"   // 必须与阅读器导航输出格式一致
          },
          "title": { "selector": ".chapter-name" },
          "date":  { "selector": ".chapter-date" }
        }
      }
    },

    // ── 阅读器（要使阅读器正常工作，此项为必填） ──────────────────
    "reader": {
      "container": "#reader-wrap",       // 图片容器元素
      "images": {
        "selector": "#reader-wrap img",  // 图片选择器
        "attribute": "src"               // 图片 URL 属性（src/data-src 等）
      },
      // 从阅读器页面 DOM 中抓取的章节导航链接
      "nav": {
        "next": "a.btn-next",
        "prev": "a.btn-prev"
      }
    }
  }
}
```

### 字段选择器选项

| 键 | 类型 | 说明 |
|----|------|------|
| `selector` | string | CSS 选择器 |
| `attribute` | string | 读取的 HTML 属性（省略则读取文本内容） |
| `transform` | `"slug"` | 从 URL 中提取最后一个有意义的路径段 |
| `regex` | string | 带一个捕获组的正则，用于过滤/提取值 |
| `multi` | boolean | 返回数组而非单个值 |
| `fallback` | string | 提取为空时的静态回退值 |

> ⚠️ **关键规则**：从 `href` 提取章节 `id` 时，**必须**使用 `"transform": "slug"`。否则阅读器的上一章/下一章导航无法在 `_allChapters` 中匹配章节，将显示 `unknownChapter`。

---

## 数据驱动器：`api`（REST JSON）

当网站提供 JSON API 时使用此驱动器。

```jsonc
"api": {
  "enabled": true,
  "url": "https://api.mysite.com",   // 可选：覆盖 baseUrl 用于 API 调用

  "endpoints": {
    "allGalleries": "/manga?page={page}",
    "search": "/manga?q={query}&page={page}",
    "detail": "/manga/{id}"
  },

  // 列表响应解析
  "list": {
    "items": "$.data[*]",              // 指向条目数组的 JSONPath
    "pagination": {
      "offsetMode": false,             // true = 使用 offset，false = 使用页码
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

  // 详情响应解析
  "detail": {
    "fields": {
      "id":    { "selector": "$.data.id" },
      "title": { "selector": "$.data.attributes.title" }
    },
    // 从独立接口获取章节列表
    "chapters": {
      "endpoint": "/manga/{id}/chapters?limit=100",
      "items": "$.data[*]",
      "fields": {
        "id":         { "selector": "$.id" },
        "chapterNum": { "selector": "$.attributes.chapter" },
        "language":   { "selector": "$.attributes.translatedLanguage" },
        "date":       { "selector": "$.attributes.publishAt" }
      }
    }
  },

  // 获取章节图片的方式
  "images": {
    "mode": "atHome",
    "atHomeEndpoint": "/at-home/server/{chapterId}"
    // 其他模式："directUrl"、"hentaifoxCdn"
  }
}
```

---

## 功能标志

控制该源在 UI 中显示哪些功能。

```jsonc
"features": {
  "search":         true,   // 显示搜索栏
  "chapters":       true,   // 启用章节导航（多章节系列）
  "download":       true,   // 允许离线下载
  "favorite":       true,   // 允许添加到收藏
  "comments":       false,  // 显示评论区
  "related":        false,  // 显示相关内容
  "generatePdf":    true,   // 允许导出 PDF
  "offlineMode":    true,   // 允许离线阅读
  "advancedSearch": false,  // 显示高级搜索表单
  "supportsAuth":   false   // 显示登录按钮
}
```

---

## 搜索表单

声明搜索 UI 中应公开哪些查询参数。

```jsonc
"searchForm": {
  "urlPattern": "search",
  "params": {
    "query": {
      "queryParam": "s",
      "type": "text",
      "placeholder": "搜索漫画..."
    },
    "page": {
      "queryParam": "page",
      "type": "page"
    }
  }
}
```

---

## 身份验证（可选）

仅在内容需要登录的源中使用。

```jsonc
"auth": {
  "enabled": true,
  "loginUrl": "https://mysite.com/login/",
  "registerUrl": "https://mysite.com/register/",
  "bookmarkUrl": "https://mysite.com/bookmarks/",
  "nonceRegex": "name=\"_nonce\" value=\"([^\"]+)\"",
  "loginSuccessFilter": "/dashboard"
}
```

---

## 标签导航映射（可选）

当用户点击标签时，将标签类型映射到搜索查询格式。

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

## 解密（特殊源）

用于加密阅读器数据的源（如 HentaiNexus XOR/RC4）。

```jsonc
"decryption": {
  "method": "initReader_xor_rc4_variant",
  "hostname": "mysite.com",
  "readerPath": "/read/{id}",
  "encryptedDataPattern": "initReader\\(\\s*\"([^\"]+)\""
}
```

---

## 分步操作：添加新源

### 1. 创建配置文件

文件名：`<source-id>-config.json`，放置于暂存区 `<kuron-extensions>/config/new/`，然后按 kuron-source-config skill 移至语言目录（`config/<lang>/`）。  
文件名前缀**必须**与 `"source"` 字段值一致。

### 2. 最小必需结构

```json
{
  "source": "mysite",
  "version": "1.0.0",
  "enabled": true,
  "baseUrl": "https://mysite.com",
  "defaultLanguage": "japanese",
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
      "home": {
        "url": "/",
        "list": {
          "container": ".item",
          "fields": {
            "id": { "selector": "a", "attribute": "href", "transform": "slug" },
            "title": { "selector": ".title" },
            "coverUrl": { "selector": "img", "attribute": "src" }
          }
        }
      },
      "detail": "/manga/{id}/",
      "chapter": "/{id}/"
    },
    "selectors": {
      "detail": {
        "fields": {
          "title": { "selector": "h1" }
        },
        "chapters": {
          "container": ".chapter-list li",
          "fields": {
            "id": { "selector": "a", "attribute": "href", "transform": "slug" },
            "title": { "selector": "a" }
          }
        }
      },
      "reader": {
        "images": {
          "selector": ".reader-container img",
          "attribute": "src"
        },
        "nav": {
          "next": "a.next-chapter",
          "prev": "a.prev-chapter"
        }
      }
    }
  },
  "features": {
    "chapters": true,
    "download": true,
    "favorite": true
  }
}
```

### 3. 验证 JSON

```bash
python3 -c "import json; json.load(open('<kuron-extensions>/config/new/mysite-config.json'))"
```

### 4. 在浏览器中测试选择器

在目标页面的浏览器开发者工具中测试 CSS 选择器：

```js
document.querySelectorAll(".chapter-list li")  // 应返回章节条目
document.querySelector(".chapter-list li a").getAttribute("href")  // 章节 URL
document.querySelectorAll(".reader-container img")  // 应返回图片
```

### 5. 数据流：直到阅读器正常工作

```
配置                       App
────                       ───
urlPatterns.detail    →    获取系列详情页
selectors.detail          → 解析标题、封面、标签
selectors.detail.chapters → 构建章节列表（_allChapters）

urlPatterns.chapter   →    获取章节阅读器页面
selectors.reader.images   → 提取图片 URL → 在阅读器中显示

selectors.reader.nav      → 从阅读器页面 DOM 提取上/下章链接
                            必须为 slug 格式 → 与 _allChapters.id 匹配
```

### 6. 常见问题与解决方案

| 现象 | 原因 | 解决方案 |
|------|------|----------|
| 阅读器显示 `unknownChapter` | 章节列表与导航的 `id` 格式不一致 | 在章节列表的 `id` 字段添加 `"transform": "slug"` |
| 阅读器无图片 | `images` 的选择器或属性错误 | 检查实际 DOM 找到正确的选择器 |
| 章节列表为空 | `chapters.container` 错误 | 检查详情页 DOM |
| 翻页在第 2 页失败 | 缺少分页 URL 模板 | 添加带 `{page}` 占位符的 `homePage` / `searchPage` |
| 标签显示为 slug | 读取了 `attribute` 而非文本 | 删除 `attribute`，让选择器读取文本内容 |
| 图片不显示（data-src） | 图片懒加载使用了其他属性 | 将 `"attribute": "src"` 改为 `"attribute": "data-src"` |

---

## 字段参考矩阵

| 字段 | scraper 源 | API 源 | 是否必填 |
|------|-----------|--------|---------|
| `source` | ✅ | ✅ | **必填** |
| `version` | ✅ | ✅ | **必填** |
| `enabled` | ✅ | ✅ | **必填** |
| `baseUrl` | ✅ | ✅ | **必填** |
| `defaultLanguage` | ✅ | ✅ | **必填** |
| `ui` | ✅ | ✅ | **必填** |
| `network` | ✅ | ✅ | **必填** |
| `scraper` | ✅ | ❌ | scraper/api 二选一 |
| `api` | ❌ | ✅ | scraper/api 二选一 |
| `features` | ✅ | ✅ | **必填** |
| `scraper.selectors.reader` | ✅ | — | **必填**（阅读器正常工作） |
| `scraper.selectors.reader.nav` | 可选 | — | 上/下章导航必需 |
| `contentIdPattern` | 可选 | 可选 | 可选 |
| `configUrl` | 可选 | 可选 | 可选 |
| `auth` | 可选 | 可选 | 可选 |
| `searchForm` | 可选 | 可选 | 可选 |
| `navigation.tagQueryMapping` | 可选 | 可选 | 可选 |
| `decryption` | 可选 | 可选 | 可选 |
| `network.rateLimit` | 可选 | 可选 | 可选 |
