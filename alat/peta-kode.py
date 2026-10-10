#!/usr/bin/env python3
"""Buat PETA-KODE.md dari index.html — peta bagian, fungsi, RPC, dan tabel.

Pakai:  python3 alat/peta-kode.py            (menulis PETA-KODE.md di akar repo)
Jalankan ulang setiap index.html berubah cukup banyak (bagian/fungsi baru),
supaya nomor baris di peta tetap cocok.
"""
import os, re, sys, datetime

AKAR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUMBER = os.path.join(AKAR, "index.html")
TUJUAN = os.path.join(AKAR, "PETA-KODE.md")

L = open(SUMBER, encoding="utf-8").read().split("\n")
N = len(L)

# ── 1. bagian: spanduk /* ═══ … */ di kolom 0, judul = baris sesudahnya ──
bagian = []
for i, b in enumerate(L):
    if re.match(r"^/\* ═{10,}", b) and i + 1 < N:
        judul = L[i + 1].strip().rstrip("*/").strip()
        bagian.append([i + 1, judul])
for k, s in enumerate(bagian):
    s.append(bagian[k + 1][0] - 1 if k + 1 < len(bagian) else N)

# sub-bagian: spanduk pendek /* ── judul ── */ di kolom 0
sub = []
for i, b in enumerate(L):
    m = re.match(r"^/\* ── (.+?)\s*─", b)
    if m: sub.append((i + 1, m.group(1).strip()))

# ── 2. fungsi tingkat atas ──
fungsi = [(i + 1, m.group(1)) for i, b in enumerate(L)
          for m in [re.match(r"^function\s+([A-Za-z_$][\w$]*)\s*\(", b)] if m]

# ── 3. panggilan REST / RPC / storage per baris ──
re_rpc = re.compile(r'["\']/rpc/([a-z_][a-z0-9_]*)')
re_tab = re.compile(r'api\(\s*"(GET|POST|PATCH|DELETE)"\s*,\s*["\']/(?!rpc/)([a-z_][a-z0-9_]*)')
re_sto = re.compile(r'storage\(\s*"(GET|POST|PUT|DELETE)"')
re_fn = re.compile(r'/functions/v1/([a-z0-9_-]+)')

def isi(a, z):
    rpc, tab, sto, edge = {}, {}, 0, set()
    for i in range(a - 1, min(z, N)):
        b = L[i]
        for m in re_rpc.finditer(b): rpc.setdefault(m.group(1), i + 1)
        for m in re_tab.finditer(b): tab.setdefault(m.group(2), set()).add(m.group(1))
        sto += len(re_sto.findall(b))
        edge.update(re_fn.findall(b))
    return rpc, tab, sto, edge

# ── 4. tab: id, label, peran (array TAB) + fungsi panel (PANEL_LANJUT / panel<Id>) ──
tab_teks = "\n".join(L)
tabs = []
mulai = tab_teks.find("var TAB = [")
if mulai >= 0:
    ujung = tab_teks.find("\n];", mulai)
    blok = tab_teks[mulai:ujung]
    for m in re.finditer(r'id:"([^"]+)"\s*,\s*label:"([^"]+)".*?peran:\[([^\]]*)\]', blok, re.S):
        tabs.append((m.group(1), m.group(2), m.group(3).replace('"', "").replace(",", ", ")))
peta_panel = dict(re.findall(r"^\s+([a-z]+):\s+(panel[A-Za-z]+),?$", tab_teks, re.M))
nama_fungsi = {n: l for l, n in fungsi}

def panel_untuk(tid):
    if tid in peta_panel: return peta_panel[tid]
    tebak = "panel" + tid[:1].upper() + tid[1:]
    return tebak if tebak in nama_fungsi else ""

# ── tulis ──
o = []
o.append("# PETA-KODE — index.html\n")
o.append(f"Dibuat otomatis oleh `alat/peta-kode.py` pada {datetime.date.today().isoformat()} dari `index.html` ({N:,} baris). "
         "Jangan disunting tangan — jalankan ulang skripnya. Nomor baris berlaku untuk versi itu; "
         "kalau meleset sedikit, cari nama fungsinya dengan `grep -n`.\n")
o.append("**Cara pakai (hemat token):** cari bagian atau fungsi di peta ini dulu, lalu baca `index.html` "
         "hanya pada rentang barisnya (`Read` dengan offset/limit). Definisi database: migrasi di `db/NNN-*.sql`; "
         "objek yang hanya ada di DEV (migrasi 1–58) ada di `db/_snapshot/`.\n")

if tabs:
    o.append("## Tab → fungsi panel → peran\n")
    o.append("| Tab (id) | Label | Fungsi panel | Baris | Peran yang melihat tab |")
    o.append("|---|---|---|---|---|")
    for tid, lab, per in tabs:
        p = panel_untuk(tid)
        o.append(f"| `{tid}` | {lab} | {('`'+p+'`') if p else '—'} | {nama_fungsi.get(p, '')} | {per} |")
    o.append("\nKeamanan ditegakkan di DB; daftar peran di atas hanya menyembunyikan tab.\n")

o.append("## Bagian\n")
o.append("| Baris | Bagian |")
o.append("|---|---|")
for a, j, z in bagian:
    o.append(f"| {a}–{z} | {j} |")
o.append("")

o.append("## Rincian per bagian\n")
for a, j, z in bagian:
    fs = [(l, n) for l, n in fungsi if a <= l <= z]
    rpc, tab, sto, edge = isi(a, z)
    if not fs and not rpc and not tab: continue
    o.append(f"### {a}–{z} · {j}\n")
    subs = [f"{t} ({l})" for l, t in sub if a <= l <= z]
    if subs: o.append("- **Sub-bagian:** " + "; ".join(subs))
    utama = [f"`{n}` {l}" for l, n in fs if re.match(r"^(panel|muat|simpan|kirim|ajukan|putus|buka|gambar)", n)]
    if utama: o.append("- **Fungsi utama:** " + ", ".join(utama))
    lain = len(fs) - len(utama)
    if lain > 0: o.append(f"- Fungsi lain: {lain} (cari dengan `grep -n \"^function\" index.html`)")
    if rpc: o.append("- **RPC:** " + ", ".join(f"`{r}` {l}" for r, l in sorted(rpc.items(), key=lambda x: x[1])))
    if tab: o.append("- **Tabel/view:** " + ", ".join(f"`{t}` ({'/'.join(sorted(m))})" for t, m in sorted(tab.items())))
    if sto: o.append(f"- Storage: {sto} panggilan")
    if edge: o.append("- Edge function: " + ", ".join(f"`{e}`" for e in sorted(edge)))
    o.append("")

# indeks balik: RPC → baris pemanggil
semua_rpc = {}
for i, b in enumerate(L):
    for m in re_rpc.finditer(b): semua_rpc.setdefault(m.group(1), []).append(i + 1)
o.append("## Indeks RPC → baris pemanggil di index.html\n")
o.append("| RPC | Baris |")
o.append("|---|---|")
for r in sorted(semua_rpc):
    o.append(f"| `{r}` | {', '.join(map(str, semua_rpc[r][:8]))}{' …' if len(semua_rpc[r]) > 8 else ''} |")
o.append("")

open(TUJUAN, "w", encoding="utf-8").write("\n".join(o) + "\n")
print(f"PETA-KODE.md: {len(bagian)} bagian, {len(fungsi)} fungsi, {len(tabs)} tab, {len(semua_rpc)} RPC")
