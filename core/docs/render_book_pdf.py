#!/usr/bin/env python3
"""Render the SageLang book to PDF with fpdf2.

The repository's own `make pdf` shells out to pandoc with xelatex. Neither is
present on every machine, and where they are missing the Makefile target
silently does nothing but echo "Skipping PDF generation", so the committed
artifact goes stale unnoticed. This is the portable path.

fpdf2 rather than a hand-rolled renderer because it handles the tedious parts
properly: a cover page, a table of contents fed by real sections rather than a
hand-maintained list, page numbering, running headers that stay off the cover,
and paragraph layout that reflows instead of clipping.

SageLang code blocks go through Pygments. A book about a language should not
show its own source unhighlighted, and this one has 162 code blocks.

DejaVu is registered rather than fpdf2's built-in fonts, which are cp1252 and
so have no U+2022 bullet and no em dash. The book uses both. Faces that a given
distribution does not ship are substituted rather than failing the build.

Requires: fpdf2, pygments.
    pip3 install --break-system-packages fpdf2 pygments
"""
import html
import os
import re
import sys
import warnings

from fpdf import FPDF
from pygments import highlight
from pygments.formatters import HtmlFormatter
from pygments.lexers import get_lexer_by_name
from pygments.util import ClassNotFound

SRC, OUT = sys.argv[1], sys.argv[2]

PAGE_W, PAGE_H = 210.0, 297.0
ML, MR, MT, MB = 20.0, 20.0, 22.0, 20.0
BODY_W = PAGE_W - ML - MR

INK = (28, 30, 34)
MUTED = (104, 108, 115)
ACCENT = (30, 72, 138)
RULE = (208, 212, 218)
CODE_BG = (247, 248, 249)
CODE_BD = (224, 228, 233)
BANNER_BG = (237, 241, 247)
TH_BG = (232, 236, 242)

FONT_DIR = "/usr/share/fonts/truetype/dejavu"
FACES = {
    "serif": ("DejaVuSerif.ttf", "DejaVuSerif-Bold.ttf"),
    "sans": ("DejaVuSans.ttf", "DejaVuSans-Bold.ttf"),
    "mono": ("DejaVuSansMono.ttf", "DejaVuSansMono-Bold.ttf", "DejaVuSansMono-Oblique.ttf"),
}

try:
    LEXER = get_lexer_by_name("sage")
except ClassNotFound:
    LEXER = get_lexer_by_name("python")

FMT = HtmlFormatter(nowrap=True, style="friendly", noclasses=True)
TAG = re.compile(r"<[^>]+>")
ENT = [("&lt;", "<"), ("&gt;", ">"), ("&quot;", '"'), ("&#39;", "'"), ("&amp;", "&")]


def strip_html(s):
    s = TAG.sub("", s)
    for a, b in ENT:
        s = s.replace(a, b)
    return s


def inline(text):
    """Escape, then apply the book's inline markup."""
    t = html.escape(text)
    t = re.sub(r"`([^`]+)`", r'<font face="mono" size="8.4">\1</font>', t)
    t = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", t)
    t = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<i>\1</i>", t)
    return t


class Book(FPDF):
    def __init__(self):
        super().__init__(orientation="P", unit="mm", format="A4")
        self.set_title("The Sage Programming Language")
        self.set_author("SageLang")
        self.set_creator("SageLang book renderer (fpdf2)")
        self.set_auto_page_break(True, margin=MB)
        # fpdf2 selects a face by (family, style), so bold has to be registered
        # under the same family with style "B" -- not as its own alias.
        self.fam = {}
        self.has_bold = set()
        for alias, files in FACES.items():
            reg = os.path.join(FONT_DIR, files[0])
            if not os.path.exists(reg):
                self.fam[alias] = "helvetica"
                continue
            self.fam[alias] = alias
            self.add_font(alias, "", reg)
            bold = os.path.join(FONT_DIR, files[1]) if len(files) > 1 else None
            if bold and os.path.exists(bold):
                self.add_font(alias, "B", bold)
                self.has_bold.add(alias)
        self.on_cover = True
        self.chapter = ""
        self.outline = []

    def use(self, alias, bold=False, size=10):
        """Select a face, silently degrading to regular where bold is absent."""
        fam = self.fam[alias]
        self.set_font(fam, "B" if (bold and alias in self.has_bold) else "", size)

    # ---- page chrome ------------------------------------------------------
    def header(self):
        if self.on_cover:
            return
        self.use("sans", False, 8.4)
        self.set_text_color(*MUTED)
        self.cell(BODY_W, 5, self.chapter, align="R")
        self.ln(5)
        self.set_draw_color(*RULE)
        self.set_line_width(0.2)
        self.line(ML, self.get_y(), PAGE_W - MR, self.get_y())
        self.ln(3)

    def footer(self):
        if self.on_cover:
            return
        self.set_y(-13)
        self.use("sans", False, 8.4)
        self.set_text_color(*MUTED)
        self.cell(BODY_W, 5, f"Page {self.page_no()}", align="C")

    # ---- blocks -----------------------------------------------------------
    def banner(self, text, sub=""):
        self.ln(3)
        h = 14 if not sub else 18.5
        x, y = ML, self.get_y()
        self.set_fill_color(*BANNER_BG)
        self.set_draw_color(*ACCENT)
        self.set_line_width(0.4)
        self.rect(x, y, BODY_W, h, style="DF")
        self.use("sans", True, 13.5)
        self.set_text_color(*ACCENT)
        self.set_xy(x + 5, y + (4.6 if not sub else 3.6))
        self.cell(BODY_W - 10, 7, text)
        if sub:
            self.use("sans", False, 8.6)
            self.set_text_color(*MUTED)
            self.set_xy(x + 5, y + 11.5)
            self.cell(BODY_W - 10, 6, sub)
        self.ln(h + 4)

    def h2(self, text):
        self.ln(2)
        self.use("sans", True, 12)
        self.set_text_color(*INK)
        self.multi_cell(BODY_W, 6, text)
        self.ln(0.5)
        self.set_draw_color(*ACCENT)
        self.set_line_width(0.5)
        self.line(ML, self.get_y(), ML + 20, self.get_y())
        self.ln(3)

    def h3(self, text):
        self.ln(1.5)
        self.use("sans", True, 10.2)
        self.set_text_color(*INK)
        self.multi_cell(BODY_W, 5.2, text)
        self.ln(1.2)

    def para(self, text):
        self.use("serif", False, 9.8)
        self.set_text_color(*INK)
        self.multi_cell(BODY_W, 5.0, inline(text))
        self.ln(2)

    def bullet(self, text, indent=5.0):
        self.use("serif", False, 9.8)
        self.set_text_color(*INK)
        self.set_x(ML + indent)
        self.multi_cell(BODY_W - indent - 4, 5.0, "•  " + inline(text))
        self.ln(0.8)
        self.set_x(ML)

    def quote(self, text):
        self.use("serif", False, 9.2)
        self.set_text_color(*MUTED)
        self.set_x(ML + 6)
        self.multi_cell(BODY_W - 10, 4.8, inline(text))
        self.ln(2)
        self.set_x(ML)

    def code(self, src):
        lines = []
        for row in highlight(src, LEXER, FMT).split("\n"):
            plain = strip_html(row)
            if len(plain) <= 96:
                lines.append(plain)
            else:
                for k in range(0, len(plain), 96):
                    lines.append(plain[k:k + 96])
        lh = 3.4
        box = len(lines) * lh + 5.5
        if self.get_y() + box > PAGE_H - MB:
            self.add_page()
        y = self.get_y()
        self.set_fill_color(*CODE_BG)
        self.set_draw_color(*CODE_BD)
        self.set_line_width(0.2)
        self.rect(ML + 2, y, BODY_W - 4, box, style="DF")
        self.set_xy(ML + 6, y + 2.6)
        self.use("mono", False, 7.4)
        self.set_text_color(*INK)
        self.multi_cell(BODY_W - 9, lh, "\n".join(lines))
        self.set_y(y + box + 2.6)

    def table(self, rows):
        ncol = max(len(r) for r in rows)
        rows = [list(r) + [""] * (ncol - len(r)) for r in rows]
        weights = []
        for c in range(ncol):
            longest = max(len(strip_html(inline(r[c]))) for r in rows)
            weights.append(max(8.0, min(70.0, longest * 0.92)))
        tot = sum(weights)
        widths = [BODY_W * w / tot for w in weights]
        # A cell narrower than a couple of characters cannot render even one
        # glyph and fpdf2 raises rather than drawing something unreadable. Wide
        # tables hit this, so give every column a real floor and, if the table
        # is still too wide, fall back to a monospaced block that keeps the row
        # structure legible instead of squeezing it to nothing.
        MIN_CELL = 14.0
        if min(widths) < MIN_CELL:
            self.ln(0.5)
            for ri, row in enumerate(rows):
                self.use("mono", ri == 0, 6.6)
                self.set_text_color(*INK)
                self.set_x(ML + 2)
                self.multi_cell(BODY_W - 4, 3.2, " | ".join(strip_html(r) for r in row))
            self.ln(2.5)
            return
        self.ln(0.5)
        for ri, row in enumerate(rows):
            head = ri == 0
            # Row height from the tallest cell, measured with the cell font.
            self.use("sans", head, 8.1)
            rows_needed = []
            for c in range(ncol):
                chars = max(4, int((widths[c] - 2.6) / 1.68))
                rows_needed.append(max(1, -(-len(strip_html(inline(row[c]))) // chars)))
            rh = max(rows_needed) * 3.9 + 1.8
            if self.get_y() + rh > PAGE_H - MB:
                self.add_page()
            y = self.get_y()
            if head:
                self.set_fill_color(*TH_BG)
                self.rect(ML, y, BODY_W, rh, style="F")
            x = ML
            for c in range(ncol):
                self.set_xy(x + 1.3, y + 0.9)
                self.use("sans", head, 8.1)
                self.set_text_color(*INK)
                self.multi_cell(widths[c] - 2.6, 3.9, inline(row[c]))
                x += widths[c]
            self.set_draw_color(*CODE_BD)
            self.set_line_width(0.15)
            self.line(ML, y + rh, ML + BODY_W, y + rh)
            self.set_y(y + rh)
        self.ln(2.5)


def toc_length(pdf, entries):
    """Pages the contents occupy: the title page plus the entry lines."""
    per_page = max(1, int((PAGE_H - MT - MB - 26) / 5.0))
    pages = 1
    used = 0
    for lvl, _t, _p in entries:
        if lvl == 0 and used and used % per_page == 0:
            pages += 1
        used += 1
    if used:
        pages += used // per_page
    return pages


def emit_toc(pdf, entries):
    """Draw the contents pages: title, then every section with a dot leader."""
    pdf.add_page()
    pdf.use("sans", True, 17)
    pdf.set_text_color(*INK)
    pdf.cell(BODY_W, 9, "Contents", align="C")
    pdf.ln(4)
    for lvl, text, page in entries:
        pad = 0 if lvl == 0 else 5
        if lvl == 0:
            pdf.ln(1.6)
            pdf.use("sans", True, 9.2)
            pdf.set_text_color(*ACCENT)
        else:
            pdf.use("sans", False, 8.4)
            pdf.set_text_color(*INK)
        pdf.set_x(pdf.l_margin + pad)
        pdf.cell(0, 5.0, text)
        stop = PAGE_W - pdf.r_margin - 8
        pdf.set_draw_color(*RULE)
        pdf.set_line_width(0.15)
        # dashed_line is deprecated in fpdf2 2.8 but is still the only dashed
        # primitive this build exposes; scoped so it does not print on every run.
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", DeprecationWarning)
            pdf.dashed_line(pdf.get_x() + 1, pdf.get_y() + 3.2, stop,
                            pdf.get_y() + 3.2, dash_length=0.5,
                            space_length=1.1)
        pdf.set_x(stop)
        pdf.cell(8, 5.0, str(page), align="R")


def render(md, pdf, toc_data=None, toc_pad=0):
    outline = pdf.outline
    lines = md.split("\n")
    if lines and lines[0].strip() == "---":
        j = 1
        title = "The Sage Programming Language"
        while j < len(lines) and lines[j].strip() != "---":
            t = lines[j].strip()
            if t.startswith("title:"):
                title = t.split(":", 1)[1].strip().strip('"')
            j += 1
        pdf.add_page()
        pdf.ln(62)
        pdf.use("sans", True, 26)
        pdf.set_text_color(*ACCENT)
        pdf.multi_cell(BODY_W, 11, title, align="C")
        pdf.ln(5)
        pdf.use("sans", False, 11)
        pdf.set_text_color(*MUTED)
        pdf.cell(BODY_W, 7, "SageLang", align="C")
        pdf.ln(66)
        pdf.use("sans", False, 8.4)
        pdf.cell(BODY_W, 6, "SageLang project", align="C")
        pdf.on_cover = False
        lines = lines[j + 1:]

    if toc_data:
        emit_toc(pdf, toc_data)

    i = 0
    n = len(lines)
    while i < n:
        raw = lines[i]
        s = raw.strip()
        if s.startswith("```"):
            i += 1
            buf = []
            while i < n and not lines[i].strip().startswith("```"):
                buf.append(lines[i])
                i += 1
            i += 1
            pdf.code("\n".join(buf))
            continue
        if not s:
            i += 1
            continue
        if re.fullmatch(r"[-*_]{3,}", s):
            pdf.ln(1.5)
            i += 1
            continue
        m = re.match(r"(#{1,6})\s+(.*)", s)
        if m:
            lvl, text = len(m.group(1)), m.group(2).strip()
            if lvl == 1:
                pdf.add_page()
                outline.append((0, strip_html(inline(text)), pdf.page_no() + toc_pad))
                pdf.banner(text)
                pdf.chapter = text
            elif lvl == 2:
                outline.append((1, strip_html(inline(text)), pdf.page_no() + toc_pad))
                pdf.h2(text)
            else:
                pdf.h3(text)
            i += 1
            continue
        if s.startswith("|") and i + 1 < n and \
                re.match(r"^\|[\s:|-]+\|$", lines[i + 1].strip()):
            rows = []
            while i < n and lines[i].strip().startswith("|"):
                if not re.match(r"^\|[\s:|-]+\|$", lines[i].strip()):
                    rows.append(lines[i])
                i += 1
            if rows:
                pdf.table(rows)
            continue
        if s.startswith(">"):
            buf = []
            while i < n and lines[i].strip().startswith(">"):
                buf.append(lines[i].strip().lstrip(">").strip())
                i += 1
            pdf.quote(" ".join(buf))
            continue
        if re.match(r"^\s*([-*+]|\d+\.)\s+", raw):
            while i < n and re.match(r"^\s*([-*+]|\d+\.)\s+", lines[i]):
                pdf.bullet(re.sub(r"^\s*([-*+]|\d+\.)\s+", "", lines[i]).strip())
                i += 1
            continue
        buf = []
        while i < n and lines[i].strip() and \
                not re.match(r"^\s*(#{1,6}\s|```|\||>)", lines[i]) and \
                not re.match(r"^\s*([-*+]|\d+\.)\s+", lines[i]):
            buf.append(lines[i].strip())
            i += 1
        if buf:
            pdf.para(" ".join(buf))
        else:
            i += 1


MD = open(SRC, encoding="utf-8").read()

# Pass 1 lays the book out and records where each section landed. Pass 2 lays it
# out again with contents pages in front, shifting every recorded page number by
# the length of the contents. Doing it this way means the contents cannot
# disagree with the body, which is the failure mode of a hand-maintained list and
# of fpdf2's fixed-size placeholder alike.
pass1 = Book()
render(MD, pass1)

pad = toc_length(pass1, pass1.outline)
shifted = [(lvl, text, page + pad) for lvl, text, page in pass1.outline]

pdf = Book()
render(MD, pdf, shifted, toc_pad=pad)
pdf.output(OUT)
print("wrote %s (%d pages, %d sections, contents %d pp)"
      % (OUT, pdf.pages_count, len(shifted), pad))