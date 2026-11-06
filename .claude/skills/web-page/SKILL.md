---
name: web-page
description: House style for static HTML pages in personal projects — the parchment-and-serif design system, its palette with dark mode, a complete starter stylesheet, page templates, non-Latin text and the accessibility rules every page must meet. Use before building, styling or restyling any static HTML page, writing its CSS, or reviewing one for contrast and accessibility; when the user says "make a page", "build a site", "style this page", "add dark mode" or "check the contrast".
---

# Web page

House style for any static HTML page built in a personal project: warm, editorial, serif — readable, not a developer dashboard. Everything needed is here, including a starter stylesheet. Build from it rather than hunting for an existing page to copy, and extend it in the same spirit when a page needs something it doesn't cover.

## Files

- A site of more than one page is `public/index.html`, one `.html` per further page, and a shared `public/style.css`.
- A one-page site inlines its stylesheet in a `<style>` block in the `<head>`, in place of the `<link>`.
- Plain HTML and CSS. No build step, no framework, no JavaScript unless the page truly can't work without it.

Every page starts from this `<head>`:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Page title — Site name</title>
  <meta name="description" content="One sentence on what this page is.">
  <link rel="stylesheet" href="style.css">
</head>
```

The stylesheet link is relative so the page also works from a subpath or opened from disk. On a one-page site the `<title>` is just the page title. Everything after the `<head>` goes in `<body><main>…</main></body>`; the templates below show only what goes inside `<main>`, plus a `<nav>` after it where there is one.

## Palette

| Token | Light | Dark | Use |
|---|---|---|---|
| `--bg` | `#f5f1e8` | `#1a1a1a` | page background |
| `--text` | `#1a1a1a` (15.4:1) | `#e8e4db` (13.7:1) | body copy, headings |
| `--text-muted` | `#595959` (6.2:1) | `#a09888` (6.1:1) | meta lines, labels, table headers |
| `--link` | `#5c2d0a` (10.2:1) | `#d4a96e` (8.0:1) | links, focus outline |
| `--border` | `#c8c0b0` (1.6:1) | `#383028` (1.3:1) | row separators only |

Ratios are against `--bg`. Every text colour passes AA in both modes; body text and links pass AAA, muted text does not, so keep it for secondary text. The borders are decorative: they separate rows that are already separated by space, so they are exempt from the 3:1 non-text rule. Never use `--border` for anything a reader needs to see — an input's edge, a chart line, a focus ring.

Never use colour as the only way to convey information: pair it with text, an icon or position.

## Stylesheet

Copy this whole into a site's shared `style.css`. When inlining it on a one-page site, keep only the rules the page uses (a single list needs no `.back`, `.content`, `.page-nav` or table rules). It contains no comments, and nor should the copy.

```css
:root {
  --bg: #f5f1e8;
  --text: #1a1a1a;
  --text-muted: #595959;
  --link: #5c2d0a;
  --border: #c8c0b0;
  --sans: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  --serif: "Times New Roman", Times, serif;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #1a1a1a;
    --text: #e8e4db;
    --text-muted: #a09888;
    --link: #d4a96e;
    --border: #383028;
  }
}

html { font-size: 17px; }

body {
  margin: 0 auto;
  max-width: 620px;
  padding: 48px 24px 80px;
  background: var(--bg);
  color: var(--text);
  font-family: var(--serif);
  line-height: 1.7;
}

h1 { font-size: 1.75rem; line-height: 1.25; margin: 0 0 1.5rem; }

a { color: var(--link); }
a:focus-visible { outline: 3px solid var(--link); outline-offset: 2px; }

.label {
  margin: 2.5rem 0 0.75rem;
  font-family: var(--sans);
  font-size: 0.72rem;
  font-weight: 600;
  letter-spacing: 0.13em;
  text-transform: uppercase;
  color: var(--text-muted);
}

.page-list { list-style: none; margin: 0; padding: 0; }
.page-list li { padding: 0.75rem 0; border-bottom: 1px solid var(--border); }
.page-list li:first-child { border-top: 1px solid var(--border); }
.page-list a { font-weight: bold; }
.page-list p { margin: 0.25rem 0 0; }

.meta { font-family: var(--sans); font-size: 0.82rem; color: var(--text-muted); }

.back { display: inline-block; margin-bottom: 1.5rem; font-family: var(--sans); font-size: 0.82rem; }

.content h2 { font-size: 1rem; margin: 2rem 0 0.5rem; }

.page-nav {
  display: flex;
  justify-content: space-between;
  margin-top: 3rem;
  padding-top: 1rem;
  border-top: 1px solid var(--border);
  font-family: var(--sans);
  font-size: 0.82rem;
}

table { width: 100%; border-collapse: collapse; }
th {
  text-align: left;
  font-family: var(--sans);
  font-size: 0.72rem;
  font-weight: 600;
  letter-spacing: 0.13em;
  text-transform: uppercase;
  color: var(--text-muted);
}
th, td { padding: 0.5rem 0.75rem 0.5rem 0; border-bottom: 1px solid var(--border); vertical-align: top; }

:lang(ko) { font-family: "Times New Roman", AppleMyungjo, "Noto Serif KR", serif; word-break: keep-all; }
```

Two kinds of `h2`: `.label` is the small uppercase sans label that names a group on an index page; an `h2` inside `.content` is a real heading in the body serif. Don't style content headings as labels.

## Templates

Index page — a list of pages or items, each with an optional meta line and note:

```html
<h1>Site title</h1>
<h2 class="label">Section label</h2>
<ul class="page-list">
  <li>
    <a href="/page.html">Item title</a>
    <div class="meta">Author, date or one-line description</div>
    <p>An optional short note.</p>
  </li>
</ul>
```

An item with nothing to link to keeps its title as `<strong>` in place of the `<a>`. The `.meta` line carries the author, any date, and the romanisation or translation of the title, separated by ` · `, with a name in another script after its romanisation: `The Vegetarian · Han Kang (<span lang="ko">한강</span>)`.

Content page:

```html
<a class="back" href="/">← Site name</a>
<h1>Page title</h1>
<div class="content">
  <h2>Section heading</h2>
  <p>…</p>
</div>
<nav class="page-nav" aria-label="Previous and next page">
  <a href="/prev.html">← Previous</a>
  <a href="/next.html">Next →</a>
</nav>
```

Tables: a `<thead>` with label-style headers, rows separated by `border-bottom`, no zebra striping. Keep them to two or three columns; wider tables break on a phone, so turn them into a `.page-list` instead.

## Non-Latin text

The page stays `<html lang="en">`; mark each run of another language at the element that holds it, e.g. `<span lang="ko">채식주의자</span>`. That lets screen readers switch voice and lets the stylesheet pick fonts.

Times New Roman has no Hangul, so without help the browser falls back to a sans system font mid-line. The `:lang(ko)` rule keeps Latin in Times and sends Hangul to a serif Korean face, and `word-break: keep-all` stops lines breaking inside a Korean word. For another script, add the same kind of rule with its serif face (e.g. `"Hiragino Mincho ProN", "Noto Serif JP"` for Japanese). Romanisation or a translation goes in the `.meta` line, not in brackets in the title.

## Accessibility

Non-negotiable on every page:

- **Contrast:** all text passes WCAG AA (4.5:1, or 3:1 for large text); aim for AAA on body copy. Check any colour not in the palette before using it.
- **Focus:** always visible, using the `a:focus-visible` rule above. Never `outline: none` without a replacement.
- **Landmarks:** the page content inside `<main>`; prev/next and other navigation inside `<nav aria-label="…">`.
- **Language:** `<html lang="en">`, plus `lang` on any other-language run.
- **Viewport:** `width=device-width, initial-scale=1.0`, never `user-scalable=no`.
- **Dark mode:** always, through the custom properties in one `@media` block, never scattered overrides.
- **Title and description:** every page has its own `<title>` and meta description.

Before judging a page by eye, ask the user to disable DarkReader (see AGENTS.md).

## What to avoid

- Inline styles for anything that repeats — it belongs in the stylesheet
- JavaScript for anything HTML and CSS can do
- Frameworks (React, Vue), Tailwind or utility-class CSS — write semantic CSS on the custom properties
- Colour-only distinctions
- New colours outside the palette without a contrast check
