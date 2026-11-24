#!/usr/bin/env python3
"""Generate docs/apply-sequence.svg: what happens when a developer applies an App.

Edit the participants (P), messages (M) or phase bands (BANDS) below, then run:

    python3 docs/gen-apply-sequence.py            # writes docs/apply-sequence.svg
    python3 docs/gen-apply-sequence.py out.svg    # or somewhere else

Standard library only. Colours match docs/architecture.svg and docs/glossary.svg.
"""
import os
import sys
from xml.sax.saxutils import escape as e

W = 1280
# name, title, subtitle, css class, center x
P = [
    ("dev",  "Developer",           "Mac · kubectl",                    "mac", 90),
    ("api",  "kube-apiserver",      "Docker Desktop Kubernetes",        "k8",  265),
    ("xp",   "Crossplane",          "core controller",                  "xp",  435),
    ("fn",   "Functions",           "3 composition functions",          "fn",  615),
    ("helm", "provider-helm",       "Release MRs",                      "pv",  795),
    ("cnpg", "CNPG operator",       "runs PostgreSQL",                  "pg",  960),
    ("k8s",  "provider-kubernetes", "Object MRs (observe-only)",        "pv",  1120),
]
X = {p[0]: p[4] for p in P}

# (from, to, label, dashed=reply)
M = [
    ("dev", "api", "kubectl apply App/hello", False),
    ("api", "dev", "rejected if the schema\nis invalid (e.g. size: huge)", True),
    ("api", "xp",  "App created (watch event)", False),
    ("xp",  "fn",  "run pipeline: observed state → desired state", False),
    ("fn",  "xp",  "Deployment, Service, Release (+ status)", True),
    ("xp",  "api", "apply Deployment + Service directly", False),
    ("xp",  "api", "apply Release (helm.m.crossplane.io)", False),
    ("helm", "api", "helm install cnpg/cluster → Cluster CR", False),
    ("cnpg", "api", "Postgres pod, Services, Secret hello-db-app", False),
    ("xp",  "fn",  "re-run pipeline (Release now observed)", False),
    ("fn",  "xp",  "+ observe-only Objects for Cluster & Secret", True),
    ("k8s", "api", "read Cluster status / Secret data", False),
    ("xp",  "fn",  "re-run (credentials observed, Cluster Ready)", False),
    ("fn",  "xp",  "+ Secret hello-db-conn, status.dbReady=true", True),
]
# phase bands: (first msg index, last msg index, label)
BANDS = [
    (0, 2, "request"),
    (3, 6, "first render"),
    (7, 8, "database starts"),
    (9, 11, "observe database"),
    (12, 13, "connect + Ready"),
]

TOP = 60          # header box top
HH = 50           # header box height
Y0 = TOP + HH + 34
ROW = 38
NOTE_H = 44
y_msg = [Y0 + i * ROW for i in range(len(M))]
y_note = y_msg[-1] + 26
BOT = y_note + NOTE_H + 24
H = BOT + 70

o = []
a = o.append
a(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
  'font-family="-apple-system, BlinkMacSystemFont, \'Segoe UI\', Helvetica, Arial, sans-serif" font-size="12">')
a('  <title>Sequence: what happens when a developer applies an App</title>')
a('''  <defs>
    <marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#334155"/></marker>
    <marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#64748B"/></marker>
    <style>
      .t  { fill:#0F172A; }
      .s  { fill:#475569; font-size:11px; }
      .h  { font-weight:600; font-size:13px; fill:#0F172A; }
      .msg{ font-size:11.5px; fill:#0F172A; stroke:#FFFFFF; stroke-width:4px; paint-order:stroke; stroke-linejoin:round; }
      .rep{ font-size:11.5px; fill:#475569; stroke:#FFFFFF; stroke-width:4px; paint-order:stroke; stroke-linejoin:round; }
      .num{ font-size:10px; font-weight:700; fill:#FFFFFF; }
      .band{ font-size:10.5px; font-weight:600; fill:#64748B; letter-spacing:.04em; }
      .xp { fill:#EDE9FE; stroke:#6D28D9; }
      .fn { fill:#CCFBF1; stroke:#0F766E; }
      .pv { fill:#DBEAFE; stroke:#1D4ED8; }
      .k8 { fill:#DCFCE7; stroke:#15803D; }
      .pg { fill:#FFEDD5; stroke:#C2410C; }
      .mac{ fill:#F8FAFC; stroke:#64748B; }
      .box{ stroke-width:1.4; }
      .life{ stroke:#CBD5E1; stroke-width:1.4; stroke-dasharray:4 4; }
      .ln { stroke:#334155; stroke-width:1.4; fill:none; }
      .lr { stroke:#64748B; stroke-width:1.4; fill:none; stroke-dasharray:6 4; }
    </style>
  </defs>''')
a(f'  <rect width="{W}" height="{H}" fill="#FFFFFF"/>')
a('  <text x="20" y="34" font-size="18" font-weight="700" class="t">What happens when a developer applies an App</text>')
a('  <text x="470" y="34" class="s">App/hello with database.enabled: true · Crossplane v2 · each step waits for the previous one to be observed</text>')

# phase bands
for i, (f, l, label) in enumerate(BANDS):
    y1 = y_msg[f] - 26
    y2 = (y_msg[l] + 14) if i < len(BANDS) - 1 else (y_note + NOTE_H + 8)
    fill = "#F8FAFC" if i % 2 == 0 else "#FFFFFF"
    a(f'  <rect x="10" y="{y1}" width="{W-20}" height="{y2-y1}" fill="{fill}"/>')
    a(f'  <text x="{W-18}" y="{y1+16}" text-anchor="end" class="band">{i+1} · {e(label.upper())}</text>')

# lifelines + headers (top and bottom)
for key, title, sub, cls, cx in P:
    w = 150
    a(f'  <line x1="{cx}" y1="{TOP+HH}" x2="{cx}" y2="{BOT}" class="life"/>')
    for y in (TOP, BOT):
        a(f'  <rect x="{cx-w/2}" y="{y}" width="{w}" height="{HH if y == TOP else 28}" rx="7" class="{cls} box"/>')
    a(f'  <text x="{cx}" y="{TOP+21}" text-anchor="middle" class="h">{e(title)}</text>')
    a(f'  <text x="{cx}" y="{TOP+38}" text-anchor="middle" class="s">{e(sub)}</text>')
    a(f'  <text x="{cx}" y="{BOT+18}" text-anchor="middle" class="h" font-size="12">{e(title)}</text>')

# messages
for i, (f, t, label, reply) in enumerate(M):
    y = y_msg[i]
    x1, x2 = X[f], X[t]
    d = 1 if x2 > x1 else -1
    a(f'  <line x1="{x1 + d*4}" y1="{y}" x2="{x2 - d*3}" y2="{y}" class="{"lr" if reply else "ln"}" '
      f'marker-end="url(#{"ar" if reply else "a"})"/>')
    # number badge at the sender
    bx = x1 + d * 16
    a(f'  <circle cx="{bx}" cy="{y}" r="8.5" fill="{"#64748B" if reply else "#334155"}"/>')
    a(f'  <text x="{bx}" y="{y+3.5}" text-anchor="middle" class="num">{i+1}</text>')
    # label above the arrow, starting after the badge
    lx = bx + d * 14
    anchor = "start" if d > 0 else "end"
    lines = label.split("\n")
    for j, ln in enumerate(lines):
        a(f'  <text x="{lx}" y="{y - 7 - (len(lines)-1-j)*14}" text-anchor="{anchor}" class="{"rep" if reply else "msg"}">{e(ln)}</text>')

# note over Crossplane .. Functions
nx1, nx2 = X["xp"] - 70, X["fn"] + 70
a(f'  <rect x="{nx1}" y="{y_note}" width="{nx2-nx1}" height="{NOTE_H}" rx="6" fill="#FEF9C3" stroke="#CA8A04" stroke-width="1.2"/>')
a(f'  <text x="{(nx1+nx2)/2}" y="{y_note+18}" text-anchor="middle" class="t">function-auto-ready marks the App <tspan font-weight="600">Ready</tspan></text>')
a(f'  <text x="{(nx1+nx2)/2}" y="{y_note+34}" text-anchor="middle" class="t">only when every composed resource is Ready</text>')

# legend
ly = H - 26
a(f'  <g transform="translate(20,{ly})">')
a('    <line x1="0" y1="0" x2="34" y2="0" class="ln" marker-end="url(#a)"/><text x="42" y="4" class="s">request / action</text>')
a('    <line x1="160" y1="0" x2="194" y2="0" class="lr" marker-end="url(#ar)"/><text x="202" y="4" class="s">response / result</text>')
a('    <text x="340" y="4" class="s">Crossplane re-runs the pipeline whenever something it composed changes (watches), so steps 4, 10 and 13 are the same loop.</text>')
a('  </g>')
a('</svg>')
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "apply-sequence.svg")
with open(out, "w") as fh:
    fh.write("\n".join(o) + "\n")
print("wrote", out, f"({W}x{H})")
