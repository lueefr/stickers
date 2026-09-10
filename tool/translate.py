#!/usr/bin/env python3
"""Automatic translations for every language, using the free Google Translate endpoint.

This keeps `lib/l10n/` in sync with `lib/l10n/app_en.arb`: it machine-translates
any missing (or, with --force, all) strings into the requested languages and
writes `lib/l10n/app_<lang>.arb` files. Because `AppLocalizations.supportedLocales`
is generated from these files, every language that gets an ARB file becomes
available in the app automatically — no code change required.

Usage (requires internet access):
    python3 tool/translate.py                 # top up ALL known languages with missing keys
    python3 tool/translate.py --langs es,pt   # only the given languages
    python3 tool/translate.py --force --langs es
    python3 tool/translate.py --list            # show supported language codes

Placeholders such as {pack} or {item} are protected during translation and
verified afterwards; a string whose translation lost a placeholder is skipped
(the key will simply show up in English) and reported.
"""

import argparse
import concurrent.futures
import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ARB_DIR = REPO_ROOT / "lib" / "l10n"
TEMPLATE = ARB_DIR / "app_en.arb"
ENDPOINT = "https://translate.googleapis.com/translate_a/single"
CACHE_FILE = REPO_ROOT / ".dart_tool" / "translate_cache.json"

# Google Translate language codes that flutter_localizations supports
# (kMaterialSupportedLanguages), so MaterialApp keeps working for every
# generated ARB file. Only language-level codes are used, so the ARB naming
# (app_<lang>.arb) stays valid for Flutter's gen-l10n.
LANGUAGES = {
    "af", "am", "ar", "as", "az", "be", "bg", "bn", "bo", "bs", "ca", "cs",
    "cy", "da", "de", "el", "en", "es", "et", "eu", "fa", "fi", "fil", "fr",
    "gl", "gsw", "gu", "he", "hi", "hr", "hu", "hy", "id", "is", "it",
    "ja", "ka", "kk", "km", "kn", "ko", "ky", "lo", "lt", "lv", "mk",
    "ml", "mn", "mr", "ms", "my", "nb", "ne", "nl", "or", "pa", "pl",
    "ps", "pt", "ro", "ru", "si", "sk", "sl", "sq", "sr", "sv", "sw", "ta",
    "te", "th", "tl", "tr", "ug", "uk", "ur", "uz", "vi", "zh", "zu",
}
# "iw"/"no" (legacy Google codes) intentionally not listed; they are covered by "he"/"nb".

# Codes that Google knows under a legacy name, mapped to the code we use for ARB files.
CODE_ALIASES = {
    "iw": "he",  # Hebrew: Google's endpoint also answers with the legacy code
    "no": "nb",  # Norwegian: prefer Bokmål
}

PLACEHOLDER_RE = re.compile(r"\{[a-zA-Z_][a-zA-Z0-9_]*\}")


def arb_locale_name(google_code: str):
    code = CODE_ALIASES.get(google_code, google_code).split("-")[0]
    return code if re.fullmatch(r"[a-z]{2,3}", code) else None


def read_arb(path: Path):
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def write_arb(path: Path, locale: str, entries: dict, author_note: str):
    out = {"@@locale": locale, "@@author": author_note}
    out.update(entries)
    with path.open("w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
        f.write("\n")


def protect(text: str):
    """Replace {placeholders} with tokens that survive machine translation."""
    tokens = list(dict.fromkeys(re.findall(r"\{[a-zA-Z_][a-zA-Z0-9_]*\}", text)))
    for i, tok in enumerate(tokens):
        text = text.replace(tok, f"«{i}»")
    return text, tokens


def unprotect(text: str, tokens: list):
    for i, tok in enumerate(tokens):
        for token_pattern in (f"«{i}»", f"<{i}>", f"« {i} »", f"[{i}]"):
            text = text.replace(token_pattern, tok)
    return text


def translate(text: str, target: str, source: str, cache: dict) -> str:
    key = f"{target}\n{text}"
    if key in cache:
        return cache[key]
    protected, tokens = protect(text)
    query = urllib.parse.urlencode(
        {"client": "gtx", "dj": "1", "sl": source, "tl": target, "dt": "t", "q": protected}
    )
    req = urllib.request.Request(
        f"{ENDPOINT}?{query}", headers={"User-Agent": "stickers-translate-tool/1.0"}
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    translated = "".join(part.get("trans", "") for part in data.get("sentences", []))
    translated = unprotect(translated.strip(), tokens)
    cache[key] = translated
    return translated


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--langs", default="all", help="comma separated Google language codes, or 'all'")
    ap.add_argument("--force", action="store_true", help="retranslate keys that already have a value")
    ap.add_argument("--list", action="store_true", help="print supported language codes and exit")
    ap.add_argument("--workers", type=int, default=4, help="parallel requests (default 4, be polite)")
    args = ap.parse_args()

    if args.list:
        print(" ".join(sorted(LANGUAGES)))
        return

    if not TEMPLATE.exists():
        sys.exit(f"template arb not found: {TEMPLATE}")
    template = read_arb(TEMPLATE)
    keys = [k for k in template if not k.startswith("@") and isinstance(template[k], str)]
    source_text = {k: template[k] for k in keys}

    langs = sorted(LANGUAGES) if args.langs == "all" else [
        l.strip() for l in args.langs.split(",") if l.strip()
    ]

    cache = {}
    if CACHE_FILE.exists():
        try:
            cache = json.loads(CACHE_FILE.read_text(encoding="utf-8"))
        except Exception:
            cache = {}

    # Collect the work: for every language, the keys that still need translating.
    todo = []  # (path, locale, google_code, {key: english_text})
    for lang in langs:
        if lang == "en":
            continue
        locale = arb_locale_name(lang)
        if locale is None:
            print(f"skip {lang}: not a valid Flutter locale code")
            continue
        path = ARB_DIR / f"app_{locale}.arb"
        existing = read_arb(path) if path.exists() else {}
        if args.force:
            missing = dict(source_text)
        else:
            missing = {
                k: source_text[k]
                for k in keys
                if k not in existing or not str(existing[k]).strip()
            }
        if missing:
            todo.append((path, locale, lang, missing))

    total = sum(len(t[3]) for t in todo)
    print(f"translating {total} strings across {len(todo)} languages via Google Translate...")

    jobs = [(path, loc, lang, k, txt) for (path, loc, lang, missing) in todo for k, txt in missing.items()]
    results = {}

    def work(job):
        path, loc, lang, k, txt = job
        return (str(path), k, translate(txt, lang, "en", cache))

    done = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as ex:
        for str_path, k, translated in ex.map(work, jobs):
            results.setdefault(str_path, {})[k] = translated
            done += 1
            if done % 50 == 0:
                print(f"  {done}/{len(jobs)}")

    failures = []
    for (path, locale, lang, _missing) in todo:
        existing = read_arb(path) if path.exists() else {}
        out = {k: v for k, v in existing.items() if not k.startswith("@@")}
        for k in keys:
            if k in out and str(out[k]).strip() and not args.force:
                continue
            cand = results.get(str(path), {}).get(k)
            if cand is None:
                continue
            src_tokens = set(PLACEHOLDER_RE.findall(source_text[k]))
            cand_tokens = set(PLACEHOLDER_RE.findall(cand))
            if src_tokens and src_tokens != cand_tokens:
                failures.append((locale, k, cand))
                continue  # leave it untranslated; English fallback applies
            out[k] = cand
        write_arb(path, locale, out, "auto (Google Translate via tool/translate.py)")
        print(f"wrote {path.name}")

    CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
    CACHE_FILE.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")

    if failures:
        print("\nSkipped (placeholders lost in translation):")
        for loc, k, v in failures:
            print(f"  {loc}/{k}: {v!r}")
        print("Run `flutter gen-l10n` and check untranslated.json for details.")


if __name__ == "__main__":
    main()
