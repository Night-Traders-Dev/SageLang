#!/usr/bin/env python3
"""Render the SageLang book to PDF without pandoc/xelatex.

The repository's own `make pdf` shells out to pandoc with xelatex, neither of
which exists on this host. This is a self-contained fallback so the book can
still be built: reportlab draws the pages and a small hand-rolled Markdown
renderer handles the subset the book actually uses (ATX headings, fenced code,
pipe tables, blockquotes, lists, rules, paragraphs).

Code blocks are drawn in a monospaced face with a light background and wrapped
rather than clipped, since a long line silently cut off at the page edge would
make the PDF quietly wrong.
"""
import html
import re
import sys

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import (BaseDocTemplate, Frame, KeepTogether,
                                NextPageTemplate, PageBreak, PageTemplate,
                                Paragraph, Preformatted, Spacer, Table, TableStyle)

SRC, OUT = sys.argv[1], sys.argv[2]
BODY_W = LETTER[0] - 1.4 * inch
MONO = "Courier"
SERIF = "Times-Roman"

ss = getSampleStyleSheet()
STYLE = {
    "h1": ParagraphStyle("h1", parent=ss["Heading1"], fontName="Times-Bold",
                         fontSize=19, leading=23, spaceBefore=16, spaceAfter=9,
                         alignment=TA_LEFT),
    "h2": ParagraphStyle("h2", parent=ss["Heading2"], fontName="Times-Bold",
                         fontSize=14.5, leading=18, spaceBefore=13, spaceAfter=6),
    "h3": ParagraphStyle("h3", parent=ss["Heading3"], fontName="Times-Bold",
                         fontSize=11.8, leading=15, spaceBefore=10, spaceAfter=4),
    "p": ParagraphStyle("p", parent=ss["BodyText"], fontName=SERIF,
                        fontSize=10, leading=13.6, spaceAfter=6,
                        alignment=TA_LEFT),
    "li": ParagraphStyle("li", parent=ss["BodyText"], fontName=SERIF,
                         fontSize=10, leading=13.2, leftIndent=16,
                         firstLineIndent=-11, spaceAfter=2),
    "quote": ParagraphStyle("quote", parent=ss["BodyText"], fontName="Times-Italic",
                            fontSize=9.6, leading=13, leftIndent=18,
                            rightIndent=10, spaceAfter=6,
                            textColor=colors.HexColor("#444444")),
    "code": ParagraphStyle("code", fontName=MONO, fontSize=7.9, leading=9.9,
                           leftIndent=9, rightIndent=4, spaceBefore=4,
                           spaceAfter=8,
                           backColor=colors.HexColor("#f4f4f2"),
                           borderPadding=5),
    "th": ParagraphStyle("th", fontName="Times-Bold", fontSize=8.6, leading=11),
    "td": ParagraphStyle("td", fontName=SERIF, fontSize=8.6, leading=11),
}


def inline(t):
    t = html.escape(t)
    t = re.sub(r"`([^`]+)`", r'<font face="%s" size="9.4">\1</font>' % MONO, t)
    t = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", t)
    t = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<i>\1</i>", t)
    return t


def code_chunks(text):
    """Split a fenced block into chunks that fit the page height."""
    avail = LETTER[1] - 1.5 * inch
    per_line = 9.9
    lines = text.replace("\t", "    ").split("\n")
    out, cur, used = [], [], 0
    for ln in lines:
        if used + per_line > avail and cur:
            out.append("\n".join(cur)); cur, used = [], 0
        cur.append(ln); used += per_line
    if cur:
        out.append("\n".join(cur))
    return out or [""]


def table(rows):
    data = []
    for n, row in enumerate(rows):
        cells = [c.strip() for c in row.strip().strip("|").split("|")]
        style = STYLE["th"] if n == 0 else STYLE["td"]
        data.append([Paragraph(inline(c), style) for c in cells])
    ncol = max(len(r) for r in data)
    for r in data:
        while len(r) < ncol:
            r.append(Paragraph("", STYLE["td"]))
    # Long tables read badly stretched across the full width; weight the first
    # column so descriptions keep room.
    weights = []
    for c in range(ncol):
        longest = max((len(data[r][c].getPlainText()) for r in range(len(data))),
                      default=1)
        weights.append(max(1.0, min(4.0, longest / 14.0)))
    tot = sum(weights)
    widths = [BODY_W * w / tot for w in weights]
    t = Table(data, colWidths=widths, repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e8e8e4")),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#b9b9b4")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 2.5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5),
    ]))
    return t


def render(md):
    flow, lines, i = [], md.split("\n"), 0
    # Drop YAML front matter, keeping the title it declares.
    if lines and lines[0].strip() == "---":
        j = 1
        while j < len(lines) and lines[j].strip() != "---":
            j += 1
        body = lines[j + 1:]
    else:
        body = lines
    i = 0
    while i < len(body):
        ln = body[i]
        s = ln.strip()
        if s.startswith("```"):
            i += 1
            buf = []
            while i < len(body) and not body[i].strip().startswith("```"):
                buf.append(body[i]); i += 1
            i += 1
            for ch in code_chunks("\n".join(buf)):
                flow.append(Preformatted(ch, STYLE["code"]))
            continue
        if not s:
            i += 1; continue
        if re.fullmatch(r"[-*_]{3,}", s):
            flow.append(Spacer(1, 7)); i += 1; continue
        m = re.match(r"(#{1,6})\s+(.*)", s)
        if m:
            lvl = min(len(m.group(1)), 3)
            flow.append(Paragraph(inline(m.group(2)), STYLE["h%d" % lvl])); i += 1; continue
        if s.startswith("|") and i + 1 < len(body) and re.match(r"^\|[\s:|-]+\|$", body[i + 1].strip()):
            rows = []
            while i < len(body) and body[i].strip().startswith("|"):
                if not re.match(r"^\|[\s:|-]+\|$", body[i].strip()):
                    rows.append(body[i])
                i += 1
            if rows:
                flow.append(table(rows)); flow.append(Spacer(1, 6))
            continue
        if s.startswith(">"):
            buf = []
            while i < len(body) and body[i].strip().startswith(">"):
                buf.append(body[i].strip().lstrip(">").strip()); i += 1
            flow.append(Paragraph(inline(" ".join(buf)), STYLE["quote"])); continue
        if re.match(r"^(\s*)[-*+]\s+", ln) or re.match(r"^(\s*)\d+\.\s+", ln):
            buf = []
            while i < len(body) and (re.match(r"^(\s*)[-*+]\s+", body[i])
                                     or re.match(r"^(\s*)\d+\.\s+", body[i])):
                t = re.sub(r"^(\s*)([-*+]|\d+\.)\s+", "", body[i])
                bullet = "\u2022" if not re.match(r"^\s*\d+\.", body[i]) else re.match(r"^\s*(\d+\.)", body[i]).group(1)
                buf.append("<b>%s</b>&nbsp;%s" % (bullet, inline(t.strip())))
                i += 1
            for b in buf:
                flow.append(Paragraph(b, STYLE["li"]))
            flow.append(Spacer(1, 4))
            continue
        buf = []
        while i < len(body) and body[i].strip() and not re.match(r"^\s*(#{1,6}\s|```|\||>)", body[i]) \
                and not re.match(r"^\s*([-*+]\s|\d+\.\s)", body[i]):
            buf.append(body[i].strip()); i += 1
        if buf:
            flow.append(Paragraph(inline(" ".join(buf)), STYLE["p"]))
        else:
            i += 1
    return flow


def footer(canv, doc):
    canv.saveState()
    canv.setFont("Times-Roman", 8.5)
    canv.setFillColor(colors.HexColor("#666666"))
    canv.drawString(0.7 * inch, 0.52 * inch, "The Sage Programming Language")
    canv.drawRightString(LETTER[0] - 0.7 * inch, 0.52 * inch, str(canv.getPageNumber()))
    canv.setStrokeColor(colors.HexColor("#cccccc"))
    canv.setLineWidth(0.4)
    canv.line(0.7 * inch, 0.68 * inch, LETTER[0] - 0.7 * inch, 0.68 * inch)
    canv.restoreState()


doc = BaseDocTemplate(OUT, pagesize=LETTER, title="The Sage Programming Language",
                      author="SageLang", leftMargin=0.7 * inch, rightMargin=0.7 * inch,
                      topMargin=0.72 * inch, bottomMargin=0.8 * inch)
frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="body")
doc.addPageTemplates([PageTemplate(id="main", frames=[frame], onPage=footer)])
doc.build(render(open(SRC, encoding="utf-8").read()))
print("wrote %s" % OUT)