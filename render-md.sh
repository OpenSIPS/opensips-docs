#!/usr/bin/env bash
#
# render-md.sh - render one OpenSIPS docs Markdown file to a standalone HTML file.
#
# Usage:
#   ./render-md.sh docs/tutorials-websocket.md
#   ./render-md.sh docs/tutorials-websocket.md /tmp/tutorials-websocket.html
#
# The full website renderer lives in the main Astro site.  This script is a
# lightweight local preview renderer for this extracted docs tree: it preserves
# frontmatter title/description, fenced code blocks, GitHub-style admonitions,
# tables, local uploads, and common Markdown inline syntax.

set -euo pipefail

usage() {
  cat >&2 <<EOF
Python helper to render an .md file as .html, for quick pre-viewing of the content.
WARNING: may or may NOT look similar to the docs.opensips.org site rendering as of now!

usage: $0 INPUT.md [OUTPUT.html]
EOF
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
  exit 2
fi

input=$1
output=${2:-${input%.md}.html}

if [ ! -f "$input" ]; then
  echo "render-md.sh: input file not found: $input" >&2
  exit 1
fi

case "$input" in
  *.md) ;;
  *)
    echo "render-md.sh: input must be a .md file: $input" >&2
    exit 1
    ;;
esac

mkdir -p "$(dirname "$output")"

python3 - "$input" "$output" <<'PY'
import ast
import html
import os
import re
import sys
from pathlib import Path


src = Path(sys.argv[1]).resolve()
dst = Path(sys.argv[2]).resolve()
root = Path.cwd().resolve()


def rel_from_output(path: Path) -> str:
    return os.path.relpath(path.resolve(), dst.parent).replace(os.sep, "/")


def page_href(slug: str) -> str:
    if slug.startswith("/"):
        slug = slug[1:]
    target = root / "docs" / f"{slug}.html"
    return rel_from_output(target)


def rewrite_url(url: str) -> str:
    url = url.strip()
    if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", url) or url.startswith("#"):
        return url
    if url.startswith("/public/"):
        return rel_from_output(root / url.lstrip("/"))
    if url.startswith("/"):
        path, sep, frag = url.partition("#")
        local_md = root / "docs" / f"{path.lstrip('/')}.md"
        if local_md.exists():
            return page_href(path) + (sep + frag if sep else "")
        return "https://www.opensips.org" + url
    return url


def slugify(text: str) -> str:
    # Use visible heading text, preserving underscores in literal identifiers.
    text = html.unescape(re.sub(r"<[^>]+>", "", inline(text)))
    text = re.sub(r"[*~\[\]()]", "", text)
    text = re.sub(r"[^a-zA-Z0-9_]+", "-", text.lower()).strip("-")
    return text or "section"


def parse_frontmatter(text: str):
    meta = {}
    if not text.startswith("---\n"):
        return meta, text
    end = text.find("\n---", 4)
    if end == -1:
        return meta, text
    raw = text[4:end].strip().splitlines()
    for line in raw:
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if not m:
            continue
        value = m.group(2).strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            if value[0] == '"':
                try:
                    value = ast.literal_eval(value)
                except (SyntaxError, ValueError):
                    value = value[1:-1].replace(r'\"', '"').replace('\\\\', '\\')
            else:
                value = value[1:-1].replace("''", "'")
        meta[m.group(1)] = value
    rest = text[end + 4 :]
    if rest.startswith("\n"):
        rest = rest[1:]
    return meta, rest


def split_link_dest(raw: str):
    raw = raw.strip()
    if not raw:
        return "", ""
    if raw[0] == "<" and ">" in raw:
        end = raw.find(">")
        return raw[1:end], raw[end + 1 :].strip().strip("'\"")
    parts = raw.split(None, 1)
    url = parts[0]
    title = parts[1].strip().strip("'\"") if len(parts) > 1 else ""
    return url, title


def inline(text: str) -> str:
    tokens = []

    def keep(value: str) -> str:
        tokens.append(value)
        return f"\u0000{len(tokens) - 1}\u0000"

    def restore_tokens(value: str) -> str:
        for idx, token in enumerate(tokens):
            value = value.replace(f"\u0000{idx}\u0000", token)
        return value

    text = re.sub(
        r"`([^`]+)`",
        lambda m: keep(f"<code>{html.escape(m.group(1))}</code>"),
        text,
    )
    text = html.escape(text)

    def image_repl(m):
        alt = html.unescape(m.group(1))
        url, title = split_link_dest(html.unescape(m.group(2)))
        attrs = [
            f'src="{html.escape(rewrite_url(url), quote=True)}"',
            f'alt="{html.escape(alt, quote=True)}"',
        ]
        if title:
            attrs.append(f'title="{html.escape(title, quote=True)}"')
        return keep(f"<img {' '.join(attrs)}>")

    def link_repl(m):
        label = m.group(1)
        url, title = split_link_dest(html.unescape(m.group(2)))
        attrs = [f'href="{html.escape(rewrite_url(url), quote=True)}"']
        if title:
            attrs.append(f'title="{html.escape(title, quote=True)}"')
        return keep(f"<a {' '.join(attrs)}>{restore_tokens(label)}</a>")

    text = re.sub(r"!\[([^\]]*)\]\(([^)]+)\)", image_repl, text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link_repl, text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<!\w)__([^_]+)__(?!\w)", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<!\*)\*([^*\n]+)\*(?!\*)", r"<em>\1</em>", text)
    text = re.sub(r"(?<!\w)_([^_\n]+)_(?!\w)", r"<em>\1</em>", text)

    return restore_tokens(text)


def table_align(spec: str) -> str:
    spec = spec.strip()
    if spec.startswith(":") and spec.endswith(":"):
        return ' class="align-center"'
    if spec.endswith(":"):
        return ' class="align-right"'
    if spec.startswith(":"):
        return ' class="align-left"'
    return ""


def split_table_row(line: str):
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [cell.strip() for cell in line.split("|")]


def is_table_sep(line: str) -> bool:
    cells = split_table_row(line)
    return bool(cells) and all(re.match(r"^:?-{3,}:?$", cell.strip()) for cell in cells)


def render_table(lines, start):
    header = split_table_row(lines[start])
    aligns = split_table_row(lines[start + 1])
    i = start + 2
    rows = []
    while i < len(lines) and "|" in lines[i].strip() and lines[i].strip():
        rows.append(split_table_row(lines[i]))
        i += 1
    out = ["<table>", "<thead><tr>"]
    for idx, cell in enumerate(header):
        align = table_align(aligns[idx]) if idx < len(aligns) else ""
        out.append(f"<th{align}>{inline(cell)}</th>")
    out.append("</tr></thead>")
    if rows:
        out.append("<tbody>")
        for row in rows:
            out.append("<tr>")
            for idx, cell in enumerate(row):
                align = table_align(aligns[idx]) if idx < len(aligns) else ""
                out.append(f"<td{align}>{inline(cell)}</td>")
            out.append("</tr>")
        out.append("</tbody>")
    out.append("</table>")
    return "\n".join(out), i


def strip_quote(line: str) -> str:
    return re.sub(r"^>\s?", "", line)


def collect_list(lines, start, ordered):
    marker = r"\d+\.\s+" if ordered else r"[-*+]\s+"
    tag = "ol" if ordered else "ul"
    out = [f"<{tag}>"]
    i = start
    while i < len(lines):
        m = re.match(rf"^\s*{marker}(.*)$", lines[i])
        if not m:
            break
        item = [m.group(1)]
        i += 1
        while i < len(lines):
            if not lines[i].strip():
                break
            if re.match(r"^\s*(?:[-*+]|\d+\.)\s+", lines[i]):
                break
            if re.match(r"^\s{2,}\S+", lines[i]):
                item.append(lines[i].strip())
                i += 1
                continue
            break
        out.append(f"<li>{inline(' '.join(item).strip())}</li>")
        if i < len(lines) and not lines[i].strip():
            i += 1
            break
    out.append(f"</{tag}>")
    return "\n".join(out), i


def render_blocks(text: str) -> str:
    lines = text.splitlines()
    out = []
    ids = {}
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if not stripped:
            i += 1
            continue

        fence = re.match(r"^```([A-Za-z0-9_-]+)?(?:[ \t]+.*)?$", stripped)
        if fence:
            lang = fence.group(1) or ""
            code = []
            i += 1
            while i < len(lines) and not re.match(r"^```\s*$", lines[i].strip()):
                code.append(lines[i])
                i += 1
            if i < len(lines):
                i += 1
            cls = f' class="language-{html.escape(lang, quote=True)}"' if lang else ""
            out.append(f"<pre><code{cls}>{html.escape(chr(10).join(code))}</code></pre>")
            continue

        if re.match(r"^\s{4,}\S", line):
            code = [line[4:] if line.startswith("    ") else line.lstrip()]
            i += 1
            while i < len(lines) and (re.match(r"^\s{4,}", lines[i]) or not lines[i].strip()):
                code.append(lines[i][4:] if lines[i].startswith("    ") else lines[i])
                i += 1
            out.append(f"<pre><code>{html.escape(chr(10).join(code).rstrip())}</code></pre>")
            continue

        if re.match(r"^---+\s*$", stripped):
            out.append("<hr>")
            i += 1
            continue

        heading = re.match(r"^(#{1,6})\s+(.+?)\s*#*\s*$", stripped)
        if heading:
            level = len(heading.group(1))
            body = heading.group(2)
            base = slugify(body)
            count = ids.get(base, 0)
            ids[base] = count + 1
            hid = base if count == 0 else f"{base}-{count + 1}"
            out.append(f'<h{level} id="{hid}">{inline(body)}</h{level}>')
            i += 1
            continue

        if i + 1 < len(lines) and "|" in stripped and is_table_sep(lines[i + 1]):
            rendered, i = render_table(lines, i)
            out.append(rendered)
            continue

        if stripped.startswith(">"):
            quote = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                quote.append(strip_quote(lines[i]))
                i += 1
            if quote and re.match(r"^\[![A-Z]+\]", quote[0].strip()):
                kind = re.match(r"^\[!([A-Z]+)\]", quote[0].strip()).group(1).lower()
                quote[0] = re.sub(r"^\[![A-Z]+\]\s*", "", quote[0].strip())
                body = render_blocks("\n".join(quote).strip())
                out.append(f'<aside class="admonition {kind}"><div class="admonition-title">{kind.title()}</div>{body}</aside>')
            else:
                body = render_blocks("\n".join(quote).strip())
                out.append(f"<blockquote>{body}</blockquote>")
            continue

        if re.match(r"^\s*[-*+]\s+", line):
            rendered, i = collect_list(lines, i, ordered=False)
            out.append(rendered)
            continue

        if re.match(r"^\s*\d+\.\s+", line):
            rendered, i = collect_list(lines, i, ordered=True)
            out.append(rendered)
            continue

        para = [stripped]
        i += 1
        while i < len(lines):
            nxt = lines[i].strip()
            if not nxt:
                break
            if (
                re.match(r"^```", nxt)
                or re.match(r"^#{1,6}\s+", nxt)
                or re.match(r"^---+\s*$", nxt)
                or nxt.startswith(">")
                or re.match(r"^\s*(?:[-*+]|\d+\.)\s+", lines[i])
                or (i + 1 < len(lines) and "|" in nxt and is_table_sep(lines[i + 1]))
            ):
                break
            para.append(nxt)
            i += 1
        paragraph = " ".join(para)
        if re.match(r"^<[^>]+>", paragraph):
            out.append(paragraph)
        else:
            out.append(f"<p>{inline(paragraph)}</p>")

    return "\n\n".join(out)


def page(title: str, description: str, body: str) -> str:
    title_esc = html.escape(title)
    desc_meta = f'\n  <meta name="description" content="{html.escape(description, quote=True)}">' if description else ""
    subtitle = f'\n      <p class="description">{inline(description)}</p>' if description else ""
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">{desc_meta}
  <title>{title_esc}</title>
  <style>
    :root {{
      color-scheme: light;
      --bg: #f7f8fb;
      --panel: #ffffff;
      --text: #22252a;
      --muted: #667085;
      --border: #d9dee8;
      --accent: #b5232e;
      --code-bg: #101820;
      --code-text: #edf2f7;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font: 16px/1.62 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }}
    .page {{
      width: min(100% - 32px, 1040px);
      margin: 0 auto;
      padding: 32px 0 56px;
    }}
    header {{
      margin-bottom: 28px;
      border-bottom: 1px solid var(--border);
      padding-bottom: 18px;
    }}
    h1, h2, h3, h4, h5, h6 {{
      line-height: 1.25;
      margin: 1.55em 0 0.55em;
      color: #1a1d21;
      letter-spacing: 0;
    }}
    h1 {{ margin-top: 0; font-size: 2.2rem; }}
    h2 {{ font-size: 1.55rem; border-bottom: 1px solid var(--border); padding-bottom: 0.25rem; }}
    h3 {{ font-size: 1.25rem; }}
    p, ul, ol, blockquote, table, pre {{ margin: 0 0 1rem; }}
    a {{ color: var(--accent); text-decoration-thickness: 0.08em; text-underline-offset: 0.16em; }}
    img {{
      max-width: 100%;
      height: auto;
      display: block;
      margin: 1rem auto;
      border: 1px solid var(--border);
      border-radius: 4px;
      background: white;
    }}
    code {{
      padding: 0.12em 0.32em;
      border-radius: 4px;
      background: #eef1f5;
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace;
      font-size: 0.92em;
    }}
    pre {{
      overflow-x: auto;
      padding: 16px;
      border-radius: 6px;
      background: var(--code-bg);
      color: var(--code-text);
      border: 1px solid #263241;
    }}
    pre code {{
      padding: 0;
      background: transparent;
      color: inherit;
      font-size: 0.88rem;
      line-height: 1.5;
    }}
    blockquote {{
      border-left: 4px solid var(--border);
      padding: 0.25rem 0 0.25rem 1rem;
      color: #3d4653;
      background: #f0f3f8;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      display: block;
      overflow-x: auto;
    }}
    th, td {{
      border: 1px solid var(--border);
      padding: 0.48rem 0.65rem;
      vertical-align: top;
    }}
    th {{ background: #eef1f5; text-align: left; }}
    .align-center {{ text-align: center; }}
    .align-right {{ text-align: right; }}
    .align-left {{ text-align: left; }}
    .description {{ margin: 0; color: var(--muted); font-size: 1.05rem; }}
    .content {{
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: clamp(20px, 4vw, 42px);
      box-shadow: 0 12px 32px rgb(15 23 42 / 0.08);
    }}
    .admonition {{
      margin: 1rem 0;
      padding: 0.8rem 1rem;
      border: 1px solid var(--border);
      border-left-width: 5px;
      border-radius: 6px;
      background: #f6f8fb;
    }}
    .admonition-title {{
      margin-bottom: 0.35rem;
      font-weight: 700;
      text-transform: uppercase;
      font-size: 0.78rem;
      letter-spacing: 0;
    }}
    .admonition.note {{ border-left-color: #2f6fed; background: #f3f7ff; }}
    .admonition.warning {{ border-left-color: #d07a00; background: #fff7e8; }}
    .admonition.important {{ border-left-color: #8a4be0; background: #f8f3ff; }}
    @media (max-width: 640px) {{
      .page {{ width: min(100% - 20px, 1040px); padding-top: 20px; }}
      h1 {{ font-size: 1.7rem; }}
      .content {{ padding: 18px; }}
    }}
  </style>
</head>
<body>
  <main class="page">
    <header>
      <h1>{title_esc}</h1>{subtitle}
    </header>
    <article class="content">
{body}
    </article>
  </main>
</body>
</html>
"""


text = src.read_text(encoding="utf-8")
meta, markdown = parse_frontmatter(text)
fallback_title = src.stem.replace("-", " ").title()
title = meta.get("title") or fallback_title
description = meta.get("description", "")
body = render_blocks(markdown)
dst.write_text(page(title, description, body), encoding="utf-8")
print(f"rendered {src.relative_to(root) if src.is_relative_to(root) else src} -> {dst.relative_to(root) if dst.is_relative_to(root) else dst}")
PY
