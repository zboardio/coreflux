# coreflux

Public repository: Coreflux LoT templates (`templates/`) and, over time, Coreflux best-practice notes.
**Everything committed here is public** — on GitHub and, for each template, on templates.coreflux.org.

## Security

- NEVER read `.env`, `.env.*`, or files in `env/` — they contain secrets. `.env.example` (and any
  `.env.example.*`) is the committed template and safe to read and edit; it never holds a real value.
  A secret the user must generate gets a commented generator command above it, never a value.
- Never commit real secrets. `secret.yaml` and a Zigbee2MQTT data folder (`z2m-data/`) hold
  credentials and the Zigbee network key; `.gitignore` keeps them out.
- `.pre-commit-config.yaml` runs gitleaks; run `pre-commit install` once per clone. Never
  `git commit --no-verify`.

## What may never appear in a committed file

Nothing of the estate a template was generalised from: no host, site, tenant or customer name, no IP
address of a real network, no real device id (Zigbee IEEE address, Netatmo home/room/module id,
dongle serial), no personal name or email address, no local path. Examples use `acme/site01/…`,
documentation-range or loopback addresses, and obviously fake ids. The organisation's name appears
only as this repository's URL, the org link in `README.md`, and the LICENSE copyright line.

Commits carry the organisation identity set in this clone's `.git/config`, never a personal
address: check `git config user.email` before the first commit in a new clone. Claude never pushes;
the owner does.

## A template folder

Layout and conventions: [`templates/README.md`](templates/README.md). The rules that matter when editing:

- **`src/<notebook>.lotnb.md` is the source.** The `.lotnb` next to it is rendered from it and is
  never edited by hand: every fenced `lot` or `python` block is one code cell, the prose between two
  blocks one markdown cell (`<!-- cell -->` splits prose).
- **`VERIFICATION.md` is generated** by the maintainers' broker run; never edit it by hand. A change
  to a notebook is not done until that run passes on the broker version `GALLERY.md` names.
- **`GALLERY.md` is the templates.coreflux.org entry**, field by field, then the page text under
  `## Content`. The gallery ships only the `.lotnb` files and that text, so both are self-contained:
  never point a notebook or the Content at the README, `VERIFICATION.md`, `compose/` or another file —
  state the fact inline. The Content renders headings, paragraphs, lists, bold, italics and inline
  code only: no tables, no fenced blocks, no H3, no inline code inside bold.
- **LoT traps measured on 2.14.3** are listed in `templates/README.md` § LoT lessons; a notebook follows
  all of them.
- Keep `README.md`, `src/`, the notebooks and `GALLERY.md` saying the same thing in one change.
