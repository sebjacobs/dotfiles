# Web standards

House style for any static HTML pages built across personal projects.

## Reference implementation

The canonical examples live in the `public/` directories of personal projects that use this stack. Check `~/Tech/Projects/personal/current/` for repos with a `wrangler.toml` and a `public/` directory — those are built to this standard. When in doubt, read the CSS from an existing project first.

---

## Design system

### Aesthetic
Warm, editorial, serif — not a developer dashboard. Pages should feel readable, not technical.

### Palette

```css
:root {
  --bg: #f5f1e8;         /* warm parchment */
  --text: #1a1a1a;
  --text-muted: #595959; /* 7:1 on light bg — AAA */
  --link: #5c2d0a;       /* 8.2:1 on light bg */
  --border: #c8c0b0;
  --label: #595959;      /* section labels, table headers */
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #1a1a1a;
    --text: #e8e4db;
    --text-muted: #a09888; /* 4.6:1 — AA */
    --link: #d4a96e;       /* 6.1:1 */
    --border: #383028;
    --label: #a09888;
  }
}
```

Never use colour as the only way to convey information (colourblind-safe by default).

### Typography
- **Body / headings:** `'Times New Roman', Times, serif` — warm, editorial
- **UI chrome** (labels, tables, nav, meta): `-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`
- Base size: `17px`; line-height: `1.7` for body text
- Section labels (`h2` on index/nav): `0.72rem`, uppercase, `letter-spacing: 0.13em`, sans-serif, muted colour — used for navigation categories, not content headings
- Content headings (`h2` inside `.content`): normal serif, bold, same size as body — not transformed

### Layout
- `max-width: 620px`, centred, `padding: 48px 24px 80px`
- Mobile-first — the narrow column works on all screens without media queries

---

## Accessibility requirements

These are non-negotiable on every page:

- **Contrast:** all text must pass WCAG AA (4.5:1 normal, 3:1 large). Aim for AAA on body copy.
- **Focus styles:** always visible — use `a:focus-visible { outline: 3px solid var(--link); outline-offset: 2px; }`. Never `outline: none` without a replacement.
- **Landmark nav:** wrap prev/next navigation in `<nav aria-label="...">` so screen readers can skip it.
- **`lang` attribute:** always `<html lang="en">`.
- **Viewport meta:** always `<meta name="viewport" content="width=device-width, initial-scale=1.0">` — never `user-scalable=no`.
- **Dark mode:** always implement `@media (prefers-color-scheme: dark)` — use CSS custom properties so it's one block, not scattered overrides.

---

## Page templates

### Index page

```html
<h1>Site title</h1>
<h2>Section label</h2>        <!-- small-caps sans label -->
<ul class="week-list">
  <li>
    <a href="/page.html">Link title</a>
    <div class="meta">One-line description</div>
  </li>
</ul>
```

### Content page

```html
<a class="back" href="/">← Parent</a>
<h1>Page title</h1>
<div class="content">
  <h2>Section heading</h2>   <!-- real heading, not label style -->
  <ul><li>...</li></ul>
</div>
<nav class="week-nav" aria-label="Week navigation">
  <a href="/prev.html">← Previous</a>
  <a href="/next.html">Next →</a>
</nav>
```

### Tables

Use `<thead>` with label-style column headers (small, uppercase, sans). No zebra striping — rely on `border-bottom` between rows. Keep tables to 2–3 columns; wide tables break badly on mobile.

---

## What to avoid

- `user-scalable=no` in viewport meta
- `outline: none` without a replacement focus style
- Colour-only distinctions (e.g. red = bad, green = good with no other cue)
- Inline styles for anything that will repeat — put it in the stylesheet
- JavaScript for anything achievable in HTML/CSS
- Frameworks (React, Vue, etc.) — these are read-only content pages, plain HTML is correct
- Tailwind or utility-class CSS — write semantic CSS with custom properties
