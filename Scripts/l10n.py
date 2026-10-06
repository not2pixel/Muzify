#!/usr/bin/env python3
"""Công cụ song ngữ Muzify (vi → en).

  python3 Scripts/l10n.py wrap     bọc mọi chuỗi tiếng Việt chưa bọc bằng L("…")
  python3 Scripts/l10n.py keys     in danh sách khoá (chuỗi gốc tiếng Việt)
  python3 Scripts/l10n.py check    báo khoá thiếu bản tiếng Anh / chuỗi tiếng Việt chưa bọc (mã thoát 1 nếu có lỗi)

Quy ước:
  - Chuỗi hiển thị viết tiếng Việt trong L("…"); mọi \\(…) thành %@ trong khoá.
  - Dòng chứa chuỗi là dữ liệu (không dịch) ghi chú `// l10n:skip`.
  - Bản tiếng Anh: Resources/en.lproj/Localizable.strings
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Sources")
EN = os.path.join(ROOT, "Resources", "en.lproj", "Localizable.strings")


def swift_files():
    for d, _, fs in os.walk(SRC):
        for f in sorted(fs):
            if f.endswith(".swift"):
                yield os.path.join(d, f)


def scan(text):
    """Trả về các chuỗi cấp ngoài cùng: (start, end, multiline, raw_body)."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i); i = n if j < 0 else j; continue
        if text.startswith("/*", i):
            j = text.find("*/", i); i = n if j < 0 else j + 2; continue
        if c == "#" and text.startswith('#"', i):  # chuỗi thô (regex) — bỏ qua
            j = text.find('"#', i + 2); i = n if j < 0 else j + 2; continue
        if c == '"':
            end, multi = read_literal(text, i)
            body = text[i + (3 if multi else 1): end - (3 if multi else 1)]
            out.append((i, end, multi, body)); i = end; continue
        i += 1
    return out


def read_literal(text, i):
    multi = text.startswith('"""', i)
    j = i + (3 if multi else 1)
    while j < len(text):
        if text[j] == "\\":
            if text.startswith("\\(", j):
                j = skip_interp(text, j + 2); continue
            j += 2; continue
        if multi and text.startswith('"""', j): return j + 3, True
        if not multi and text[j] == '"': return j + 1, False
        j += 1
    raise ValueError("chuỗi không đóng")


def skip_interp(text, j):
    depth = 1
    while depth:
        c = text[j]
        if c == '"':
            j, _ = read_literal(text, j); continue
        if c == "(": depth += 1
        elif c == ")": depth -= 1
        j += 1
    return j


def key_of(body, multi):
    """Giá trị khoá lúc chạy: xử lý escape, \\(…) → %@, % → %%."""
    if multi:
        lines = body.split("\n")
        lines = lines[1:-1] if len(lines) >= 2 else lines
        indent = min((len(l) - len(l.lstrip(" ")) for l in lines if l.strip()), default=0)
        body = "\n".join(l[indent:] for l in lines)
        body = body.replace("\\\n", "")
    out, j = [], 0
    while j < len(body):
        c = body[j]
        if c == "\\":
            if body.startswith("\\(", j):
                j = skip_interp(body, j + 2); out.append("%@"); continue
            nxt = body[j + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "0": "\0"}.get(nxt, nxt)); j += 2; continue
        out.append("%%" if c == "%" else c); j += 1
    return "".join(out)


def is_vi(s):
    return any(ord(ch) > 127 for ch in s) and any(ch.isalpha() for ch in s)


def wrapped(text, start):
    return text[max(0, start - 2):start] == "L("


def line_of(text, pos):
    a = text.rfind("\n", 0, pos) + 1; b = text.find("\n", pos)
    return text[a: b if b >= 0 else len(text)]


def candidates(text):
    for s, e, multi, body in scan(text):
        if not is_vi(body): continue
        line = line_of(text, s)
        if "l10n:skip" in line: continue
        before = text[max(0, s - 8):s]
        if before.endswith("query: "): continue
        yield s, e, multi, body


def cmd_wrap():
    total = 0
    for p in swift_files():
        if p.endswith("Localization.swift"): continue
        text = open(p, encoding="utf-8").read()
        edits = [(s, e) for s, e, _, _ in candidates(text) if not wrapped(text, s)]
        for s, e in reversed(edits):
            text = text[:s] + "L(" + text[s:e] + ")" + text[e:]
        if edits:
            open(p, "w", encoding="utf-8").write(text); total += len(edits)
            print(f"{os.path.relpath(p, ROOT)}: {len(edits)}")
    print(f"Đã bọc {total} chuỗi.")


def all_keys():
    keys, unwrapped = {}, []
    for p in swift_files():
        text = open(p, encoding="utf-8").read()
        for s, e, multi, body in scan(text):
            if wrapped(text, s):
                keys.setdefault(key_of(body, multi), f"{os.path.relpath(p, ROOT)}:{text.count(chr(10), 0, s) + 1}")
        for s, e, multi, body in candidates(text):
            if not wrapped(text, s) and not p.endswith("Localization.swift"):
                unwrapped.append(f"{os.path.relpath(p, ROOT)}:{text.count(chr(10), 0, s) + 1}: {body[:60]}")
    return keys, unwrapped


def read_strings(path):
    if not os.path.exists(path): return {}
    text = open(path, encoding="utf-8").read()
    def unesc(s): return re.sub(r'\\(.)', lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)
    return {unesc(k): unesc(v) for k, v in re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', text, re.M)}


def cmd_keys():
    keys, _ = all_keys()
    for k in sorted(keys): print(repr(k))
    print(len(keys), "khoá", file=sys.stderr)


def cmd_check():
    keys, unwrapped = all_keys()
    en = read_strings(EN)
    missing = [k for k in keys if k not in en]
    unused = [k for k in en if k not in keys]
    bad = [k for k in keys if k in en and en[k].count("%@") + len(re.findall(r"%\d+\$@", en[k])) != k.count("%@")]
    for u in unwrapped: print("Chưa bọc L():", u)
    for k in missing: print("Thiếu bản tiếng Anh:", repr(k), "←", keys[k])
    for k in bad: print("Sai số %@:", repr(k))
    for k in unused: print("Khoá thừa (không còn dùng):", repr(k))
    print(f"{len(keys)} khoá · thiếu {len(missing)} · chưa bọc {len(unwrapped)} · sai %@ {len(bad)} · thừa {len(unused)}")
    sys.exit(1 if missing or unwrapped or bad else 0)


if __name__ == "__main__":
    {"wrap": cmd_wrap, "keys": cmd_keys, "check": cmd_check}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: print(__doc__))()
