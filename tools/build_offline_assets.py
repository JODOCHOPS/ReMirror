"""Rebuild the bundled English-Chinese model and lookup database.

Requires Python 3 and ``pip install zstandard``. All downloads are pinned by
their SHA-256 hashes. Run from the repository root.
"""

import csv
import hashlib
import io
import re
import sqlite3
import urllib.request
from pathlib import Path

import zstandard


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets' / 'offline'
MODEL = OUT / 'model'
ECDICT_COMMIT = 'bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b'
ECDICT_SHA256 = '1a6947e04785db63613a92e14903cdae7954f7e84860b10e68e5c7cbb3f9c3cf'
ECDICT_URL = f'https://raw.githubusercontent.com/skywind3000/ECDICT/{ECDICT_COMMIT}/ecdict.csv'
CDN = 'https://firefox-settings-attachments.cdn.mozilla.net/'

# Mozilla Firefox Translations en -> zh-Hans, base-memory, version 3.0.
# Remote Settings collection: main/translations-models-v2.
FILES = {
    'model.enzh.intgemm.alphas.bin': (
        'main-workspace/translations-models-v2/321191b6-2c42-4bca-84ec-b7b074b67bd6.zst',
        'f0c96e546b0af7c1fe84647d450b1eba0b0591c167e1ead135b334e4b54f6e08',
        '4e5accc141373565ddc8fa1565bceaa8d0c3482a82cab8131c719ebcc6c2157c'),
    'srcvocab.enzh.spm': (
        'main-workspace/translations-models-v2/83278466-fec4-4944-a99d-c2372fa9de88.zst',
        'ec495ad8f0c80ba4eae5ac3b9a8e2ccb4a3a7becb1992efcfea5f4653ffdece1',
        'bd9b65504acc6d9726dd281f7defc2adb7c2c22d0688fe2f84697de25197c8c5'),
    'trgvocab.enzh.spm': (
        'main-workspace/translations-models-v2/84236654-1b66-42fc-9ba2-74c37f27e5eb.zst',
        '25c6c984a7556cb6478b9f1748ff68d8fd433c0e7d472bfdbd4d64a2dffa21f1',
        'aded6993c36e440284d11cec3f6b8aef9c0e43188a772d80be342a713adf223d'),
    'lex.50.50.enzh.s2t.bin': (
        'main-workspace/translations-models-v2/900beaed-2dba-4a88-ad7c-852ec9e73f6a.zst',
        'c7e4b2ee202e6cf526d07f9c5a47b759ba32b0b42a5353d3db4ee1ff3bfb5217',
        '4a5e5827788060f1d718a8132b69440929387514a045796e9b77f935db68c055'),
}


def download(url, expected_hash):
    data = urllib.request.urlopen(url, timeout=120).read()
    actual = hashlib.sha256(data).hexdigest()
    if actual != expected_hash:
        raise ValueError(f'SHA-256 mismatch for {url}: {actual}')
    return data


def build_model():
    MODEL.mkdir(parents=True, exist_ok=True)
    for name, (location, compressed_hash, raw_hash) in FILES.items():
        target = MODEL / name
        if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() == raw_hash:
            continue
        compressed = download(CDN + location, compressed_hash)
        with zstandard.ZstdDecompressor().stream_reader(io.BytesIO(compressed)) as stream:
            raw = stream.read()
        if hashlib.sha256(raw).hexdigest() != raw_hash:
            raise ValueError(f'Decompressed SHA-256 mismatch for {name}')
        target.write_bytes(raw)
        print(f'{name}: {len(raw):,} bytes')


def build_dictionary():
    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / 'dictionary.sqlite'
    if target.exists():
        target.unlink()
    db = sqlite3.connect(target)
    db.execute('PRAGMA journal_mode=OFF')
    db.execute('PRAGMA synchronous=OFF')
    db.execute('CREATE TABLE entries (word TEXT PRIMARY KEY, phonetic TEXT, '
               'translation TEXT, lemma TEXT) WITHOUT ROWID')
    raw = download(ECDICT_URL, ECDICT_SHA256)
    reader = csv.DictReader(io.StringIO(raw.decode('utf-8-sig')))
    word_pattern = re.compile(r"[a-z][a-z' -]*", re.I)
    count = 0
    for row in reader:
        word = row['word'].strip().lower()
        if not word_pattern.fullmatch(word) or not row['translation'].strip():
            continue
        source = row['translation'].replace('\\n', '\n')
        lines = [line.strip() for line in source.splitlines()
                 if line.strip() and not line.lstrip().startswith('[')]
        if not lines:
            lines = [line.strip() for line in source.splitlines() if line.strip()]
        translation = '\n'.join(lines[:6])[:700]
        lemma = next((part[2:] for part in row['exchange'].split('/')
                      if part.startswith('0:')), '')
        phonetic = row['phonetic'].strip().replace('ә', 'ə').replace(':', 'ː')
        db.execute('INSERT OR REPLACE INTO entries VALUES (?, ?, ?, ?)',
                   (word, phonetic, translation, lemma))
        count += 1
        if count % 10000 == 0:
            db.commit()
    db.commit()
    db.execute('VACUUM')
    db.close()
    print(f'dictionary: {count:,} entries, {target.stat().st_size:,} bytes')


if __name__ == '__main__':
    build_model()
    build_dictionary()
