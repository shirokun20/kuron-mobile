# Security Policy

> **Thank you for helping keep Kuron and its users safe.** 🙏
> Every report matters — even if you're not sure it's a real vulnerability, we'd rather hear from you than miss something important.

Kuron is a privacy-first reader. Security and user trust are core to the project. This policy explains which versions are supported, how to report issues privately, and what to expect after you report.

---

## Supported Versions

We actively maintain the latest release line. Only the following versions receive security and bug-fix updates:

| Version | Supported | Notes |
| ------- | :-------: | ----- |
| `0.9.x` | ✅ | Current stable — all security fixes land here |
| `< 0.9.0` | ❌ | No longer supported — please update to the latest `0.9.x` |

If you're on an older version, updating to the latest release is the fastest way to stay protected. If you can't update, let us know in your report — we'll advise on mitigations.

---

## How to Report a Vulnerability

**Please do not open a public issue, discussion, or pull request for security vulnerabilities.** Public disclosure before a fix puts users at risk.

### Preferred: Private Security Advisory (fastest & fully private)

1. Go to **Security → Advisories** on GitHub:
   👉 [Open the Advisories page](https://github.com/shirokun20/kuron-mobile/security/advisories)
2. Click **"Report a vulnerability"** and fill in the details.
3. Submit — only maintainers can see it. You can add comments and updates privately.

### Alternative: Direct contact

If you can't use Advisories, contact the maintainers via the email listed on the [maintainer profile](https://github.com/shirokun20). Prefix the subject with `[SECURITY] Kuron` and mention you'd like to use encrypted communication if needed.

> **No perfect report required.** A short description + steps to reproduce is enough to start. We'll ask follow-ups kindly — no pressure, no blame.

---

## What to Include (if you can)

Help us triage faster by including any of the following — share only what you're comfortable with:

- **Description** — what the issue is and why you think it's a security risk
- **Impact** — what an attacker could do (e.g., data leak, bypass, privilege escalation)
- **Reproduction** — step-by-step, PoC, or minimal sample (screenshots / screen recording help)
- **Environment** — Kuron version (`pubspec.yaml` → `version`), Android version, device, install source (APK / build from source)
- **Scope** — does it need user interaction? Is it limited to a specific source/provider?
- **Logs** — relevant logs (please redact tokens, cookies, or personal data)

If you're unsure about any field, just leave it blank — we'll figure it out together.

---

## What to Expect After You Report

We aim to be responsive, transparent, and respectful of your time:

| Stage | Timeline | What happens |
| ----- | -------- | ------------ |
| **Acknowledge** | within **48 hours** | We confirm receipt and tell you who's handling it |
| **Triage** | within **7 days** | We validate, assess severity, and share next steps |
| **Fix & release** | depends on severity | Critical issues are prioritized; we keep you updated on progress |
| **Disclosure** | coordinated | We agree on a disclosure date with you — default is after a fix is released |

- We will **not** share your report publicly without your consent.
- If we need more info, we'll ask in the private advisory thread.
- If the issue is not a vulnerability, we'll explain why and — with your permission — can turn it into a regular bug report.

---

## Scope

In scope (examples):

- Authentication / session handling, app disguise & privacy features, local data storage (SQLite, SharedPreferences, secure storage), deep links / intent handling, WebView / network layer, build / supply-chain issues in this repo

Out of scope (examples):

- Social engineering, physical device access, vulnerabilities in third-party content providers (unless Kuron amplifies the risk), issues requiring a rooted device with user-granted permissions beyond normal use

When in doubt, report it — we'll triage and let you know.

---

## Safe Harbor

We support good-faith security research:

- We will not pursue legal action against researchers who follow this policy, act in good faith, and avoid privacy violations, data destruction, or service disruption.
- Please **do not** access, modify, or exfiltrate other users' data, and avoid automated testing that could degrade services.
- Give us reasonable time to fix the issue before any public disclosure.

---

## Acknowledgments

With your permission, we'll credit you in the release notes and in a **Security Acknowledgments** section. If you prefer to stay anonymous, that's fully respected — just let us know.

Thanks again for making Kuron safer for everyone. 💙

---

*For non-security bugs and feature ideas, please use the [Issue Templates](https://github.com/shirokun20/nhasixapp/issues/new/choose) — they're designed to be quick and friendly.*
