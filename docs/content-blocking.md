# Content Blocking

Detour includes a built-in content blocker that filters ads, trackers, cookie notices, and malicious URLs using WebKit's `WKContentRuleList` API.

## Architecture

```
ContentBlockerManager.shared
  +-- EasyListParser           Parses EasyList/AdBlock Plus filter syntax -> WebKit JSON rules
  +-- ContentRuleStore         Compiles and caches WKContentRuleLists
  +-- ContentBlockerWhitelist  Per-profile domain exceptions
  +-- BlockedResourceTracker   Injected JS that counts blocked resources per page
```

All files are in `Browser/ContentBlocker/`.

## Filter Lists

Four filter lists are supported, fetched from upstream sources:

| Identifier | Source | Purpose | Profile Toggle |
|------------|--------|---------|----------------|
| `easylist` | easylist.to | Ad blocking | `isEasyListEnabled` |
| `easyprivacy` | easylist.to | Tracker blocking | `isEasyPrivacyEnabled` |
| `easylist-cookie` | fanboy.co.nz | Cookie consent notices | `isEasyListCookieEnabled` |
| `urlhaus-filter` | malware-filter.gitlab.io | Malicious URLs | `isMalwareFilterEnabled` |

Each list can be independently toggled per profile. The master `isAdBlockingEnabled` toggle disables all lists at once.

## Initialization Flow

On app launch, `ContentBlockerManager.shared.initialize()`:

1. Load whitelist entries from the database
2. For each filter list:
   - Check if a compiled `WKContentRuleList` already exists in WebKit's store
   - If yes: check if a refresh is needed (24-hour interval)
   - If no: try loading from cached text file in `~/Library/Application Support/Detour/ContentBlocker/`
   - If no cache: fetch from upstream URL
3. Recompile whitelist rules for all profiles

## Fetch & Compile Pipeline

```
Fetch (HTTP)
  +-- Conditional: If-None-Match (ETag) / If-Modified-Since
  +-- 304 Not Modified: update timestamp, done
  +-- 200 OK: cache raw text to disk
       |
       v
Parse (EasyListParser)
  +-- Converts AdBlock Plus filter syntax to WebKit content rule JSON
  +-- Tracks rule count and skipped rules
       |
       v
Compile (ContentRuleStore)
  +-- WKContentRuleListStore.compileContentRuleList(forIdentifier:encodedContentRuleList:)
  +-- Caches compiled WKContentRuleList in memory
       |
       v
Apply (reapplyRuleLists)
  +-- Posts .contentBlockerRulesDidChange notification
  +-- All windows re-apply rules to their WebViews
```

## Applying Rules to WebViews

Rules are applied when creating a new `WKWebViewConfiguration` in `Space.makeWebViewConfiguration()`:

```swift
ContentBlockerManager.shared.applyRuleLists(to: config.userContentController, profile: profile)
```

This method:
1. Always adds the `BlockedResourceTracker` user script
2. If `profile.isAdBlockingEnabled`:
   - Adds each enabled filter list's compiled `WKContentRuleList`
   - Adds the profile's whitelist rules **last** (so `ignore-previous-rules` overrides the block lists)

## Per-Profile Whitelist

The whitelist allows users to disable content blocking for specific domains on a per-profile basis.

**Storage**: `contentBlockerWhitelist` table with composite key `(profileID, host)`.

**Mechanism**: Generates a `WKContentRuleList` with `ignore-previous-rules` action for whitelisted domains. This rule is added after all block rules, effectively disabling blocking for those domains.

```
whitelist.addException(profileID: id, host: "example.com")
  -> Save to DB
  -> Recompile whitelist WKContentRuleList for this profile
  -> reapplyRuleLists() to all windows
```

## Blocked Resource Counting

`BlockedResourceTracker` injects a `WKUserScript` that monitors blocked resources. The count is exposed via `BrowserTab.blockedCount` (`@Published`), allowing the UI to display how many resources were blocked on the current page.

The count resets to 0 on each new navigation.

## Settings UI

`ContentBlockerSettingsViewController` provides:

- Per-list display: parsed rule count, compiled rule count, last fetch date
- Refresh button: re-fetches and recompiles a single list
- Clear cache & redownload: invalidates all compiled rules, deletes cached text, re-fetches everything

`ProfilesSettingsViewController` provides per-profile toggles for each filter list and the master ad-blocking switch.

## Cache Locations

| Data | Location |
|------|----------|
| Raw filter text | `~/Library/Application Support/Detour/ContentBlocker/{identifier}.txt` |
| Compiled rules | WebKit's internal `WKContentRuleListStore` (managed by WebKit) |
| Fetch metadata | `UserDefaults`: `ContentBlocker.{id}.lastFetch`, `ContentBlocker.{id}.etag`, `ContentBlocker.{id}.ruleCount` |
