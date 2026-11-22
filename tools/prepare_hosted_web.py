#!/usr/bin/env python3
"""Build the published game's static-hosting format from an existing Godot web export."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--export-dir', type=Path, default=ROOT / 'build/web')
parser.add_argument('--output-dir', type=Path, default=ROOT / 'build/hosted-web')
parser.add_argument('--site-url', default='https://kyoto-midnight-signal-game.idealpig30.chatgpt.site')
args = parser.parse_args()
source, output = args.export_dir.resolve(), args.output_dir.resolve()
if source == output:
    raise SystemExit('Use separate export and output directories.')
names = ['index.html', 'index.js', 'index.pck', 'index.audio.worklet.js', 'index.audio.position.worklet.js']
for name in [*names, 'index.wasm']:
    if not (source / name).is_file():
        raise SystemExit(f'Missing {source / name}; export the Godot Web preset first.')
output.mkdir(parents=True, exist_ok=True)
for name in names:
    shutil.copy2(source / name, output / name)
wasm = (source / 'index.wasm').read_bytes()
compressed = gzip.compress(wasm, compresslevel=9, mtime=0)
(output / 'index.wasm.gz').write_bytes(compressed)
(output / 'engine-integrity.json').write_text(json.dumps({
    'uncompressed_bytes': len(wasm), 'compressed_bytes': len(compressed),
    'sha256': hashlib.sha256(wasm).hexdigest()
}, indent=2) + '\n')
loader = (ROOT / 'hosting/engine-loader.js.in').read_text().replace('__ENGINE_BYTES__', str(len(wasm)))
(output / 'engine-loader.js').write_text(loader)
html = (source / 'index.html').read_text()
html = html.replace('<script src="index.js"></script>', '<script src="engine-loader.js"></script><script src="index.js"></script>')
extras = (ROOT / 'hosting/fullscreen.html').read_text()
button, script = extras.split('\n', 1)
html = html.replace('<noscript>', button + '<noscript>')
html = html.replace('</body>', script.strip() + '</body>')
# The canonical URL is metadata only; escape it rather than treating it as markup.
from html import escape
metadata = '<meta name="description" content="A cozy neon exploration game. Play as a programmer with Kyoto, his golden retriever. Keyboard and controller supported.">'
metadata += '<link rel="canonical" href="' + escape(args.site_url, quote=True) + '">'
html = html.replace('</head>', metadata + '</head>')
(output / 'index.html').write_text(html)
shutil.copytree(ROOT / 'licenses', output / 'licenses', dirs_exist_ok=True)
print(f'Prepared {output}; engine: {len(wasm):,} bytes -> {len(compressed):,} compressed bytes.')
