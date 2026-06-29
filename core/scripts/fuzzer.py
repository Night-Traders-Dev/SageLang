#!/usr/bin/env python3
import os
import re
import json
from pathlib import Path

ROOT = Path.cwd()
MAX_FILE_BYTES = 2_000_000
TEXT_EXTS = {
    '.py', '.nim', '.nims', '.c', '.h', '.hpp', '.cpp', '.cc', '.rs', '.zig', '.kt', '.kts',
    '.java', '.js', '.ts', '.tsx', '.jsx', '.mjs', '.json', '.toml', '.yaml', '.yml', '.md',
    '.txt', '.sh', '.bash', '.zsh', '.fish', '.cmake', '.gradle', '.properties', '.cfg', '.ini'
}
SKIP_DIRS = {
    '.git', '.github', '.idea', '.vscode', '.gradle', '.venv', 'venv', 'node_modules',
    'dist', 'build', 'out', 'target', '__pycache__', '.mypy_cache', '.pytest_cache'
}

FEATURES = {
    'volatile_memory_access': [
        ('regex', r'\bvolatile\b'),
        ('literal', 'mmio'),
        ('literal', 'memory-mapped'),
        ('literal', 'memory mapped'),
        ('literal', 'ptr::read_volatile'),
        ('literal', 'ptr::write_volatile'),
        ('literal', 'read_volatile'),
        ('literal', 'write_volatile'),
        ('literal', 'volatileLoad'),
        ('literal', 'volatileStore'),
    ],
    'inline_assembly': [
        ('literal', 'inline asm'),
        ('literal', 'inline assembly'),
        ('literal', 'asm!'),
        ('literal', '__asm__'),
        ('literal', '__asm'),
        ('literal', 'asm('),
        ('literal', 'llvm_asm!'),
    ],
    'linker_sections': [
        ('regex', r'\bsection\b'),
        ('regex', r'\blinker\b'),
        ('literal', 'link_section'),
        ('literal', '__attribute__((section'),
        ('literal', '#[link_section'),
        ('literal', '.text'),
        ('literal', '.data'),
        ('literal', '.bss'),
        ('literal', '.rodata'),
    ],
    'interrupt_attributes': [
        ('regex', r'\binterrupt\b'),
        ('regex', r'\bisr\b'),
        ('regex', r'\birq\b'),
        ('regex', r'\bfiq\b'),
        ('literal', '__attribute__((interrupt'),
        ('literal', '#[interrupt'),
        ('literal', '@Interrupt'),
    ],
    'packed_structs': [
        ('regex', r'\bpacked\b'),
        ('literal', '__attribute__((packed'),
        ('literal', '#[repr(packed'),
        ('literal', '@Packed'),
    ],
    'compile_time_constants': [
        ('regex', r'\bconst\b'),
        ('regex', r'\bconstexpr\b'),
        ('regex', r'\bcomptime\b'),
        ('literal', 'compile-time'),
        ('literal', 'compile time'),
        ('literal', 'static final'),
        ('regex', r'\bimmutable\b'),
        ('literal', 'eval_const'),
    ],
    'zero_cost_abstractions': [
        ('literal', 'zero-cost'),
        ('literal', 'zero cost'),
        ('literal', 'monomorph'),
        ('regex', r'\binline\b'),
        ('regex', r'\bgeneric\b'),
        ('regex', r'\btrait\b'),
        ('literal', 'static dispatch'),
        ('literal', 'specializ'),
        ('literal', 'no allocation'),
    ],
}


def is_text_file(path: Path) -> bool:
    if path.suffix.lower() in TEXT_EXTS:
        return True
    try:
        with open(path, 'rb') as f:
            chunk = f.read(4096)
        if b'' in chunk:
            return False
        chunk.decode('utf-8')
        return True
    except Exception:
        return False


def iter_files(root: Path):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            p = Path(dirpath) / name
            try:
                if p.stat().st_size > MAX_FILE_BYTES:
                    continue
            except Exception:
                continue
            if is_text_file(p):
                yield p


def snippet(lines, idx, radius=2):
    start = max(0, idx - radius)
    end = min(len(lines), idx + radius + 1)
    out = []
    for i in range(start, end):
        out.append({'line': i + 1, 'text': lines[i].rstrip()[:300]})
    return out


def confidence_for(feature, line):
    l = line.lower()
    strong = {
        'volatile_memory_access': ['volatile', 'read_volatile', 'write_volatile', 'mmio'],
        'inline_assembly': ['asm(', '__asm', '__asm__', 'asm!'],
        'linker_sections': ['link_section', 'section', '.text', '.data', '.bss', '.rodata', 'linker'],
        'interrupt_attributes': ['interrupt', 'isr', 'irq', 'fiq'],
        'packed_structs': ['packed', 'repr(packed'],
        'compile_time_constants': ['const', 'constexpr', 'comptime', 'static final'],
        'zero_cost_abstractions': ['zero-cost', 'zero cost', 'monomorph', 'static dispatch', 'generic', 'trait'],
    }
    score = sum(tok in l for tok in strong[feature])
    if score >= 2:
        return 'high'
    if score == 1:
        return 'medium'
    return 'low'


def build_matchers():
    compiled = {}
    bad = []
    for feature, specs in FEATURES.items():
        compiled[feature] = []
        for kind, pattern in specs:
            if kind == 'regex':
                try:
                    compiled[feature].append((kind, re.compile(pattern, re.IGNORECASE), pattern))
                except re.error as e:
                    bad.append({'feature': feature, 'pattern': pattern, 'error': str(e)})
            else:
                compiled[feature].append((kind, pattern.lower(), pattern))
    return compiled, bad


def matches_line(matcher, line):
    kind, obj, original = matcher
    if kind == 'regex':
        return bool(obj.search(line))
    return obj in line.lower()


def main():
    compiled, bad_patterns = build_matchers()
    findings = {k: [] for k in FEATURES}
    scanned = 0

    for path in iter_files(ROOT):
        scanned += 1
        try:
            text = path.read_text(encoding='utf-8', errors='replace')
        except Exception:
            continue
        lines = text.splitlines()
        rel = str(path.relative_to(ROOT))

        for feature, matchers in compiled.items():
            for i, line in enumerate(lines):
                matched = [original for kind, obj, original in matchers if matches_line((kind, obj, original), line)]
                if matched:
                    findings[feature].append({
                        'file': rel,
                        'line': i + 1,
                        'match_text': line.strip()[:300],
                        'matched_patterns': matched[:5],
                        'confidence': confidence_for(feature, line),
                        'context': snippet(lines, i, radius=2),
                    })

    summary = {}
    for feature, items in findings.items():
        files = sorted({x['file'] for x in items})
        summary[feature] = {
            'matches': len(items),
            'files': len(files),
            'sample_files': files[:10],
        }

    report = {
        'root': str(ROOT),
        'files_scanned': scanned,
        'features': summary,
        'findings': findings,
        'bad_patterns': bad_patterns,
        'notes': [
            'This is a heuristic scanner, not a formal proof of language support.',
            'Many feature probes are done as case-insensitive literal substring checks to avoid regex fragility.',
            'Hits in tests, docs, examples, generated files, or dependencies can be false positives.',
            'For best results, run from the repository root after pulling submodules.',
        ]
    }

    out = ROOT / 'sage_feature_fuzz_report.json'
    out.write_text(json.dumps(report, indent=2), encoding='utf-8')

    print(f'Wrote {out}')
    print(f'Files scanned: {scanned}')
    if bad_patterns:
        print(f'Skipped {len(bad_patterns)} invalid regex patterns')
        for bp in bad_patterns[:10]:
            print(f"  {bp['feature']}: {bp['pattern']} -> {bp['error']}")
    for feature, meta in summary.items():
        print(f'{feature}: {meta["matches"]} matches across {meta["files"]} files')


if __name__ == '__main__':
    main()
