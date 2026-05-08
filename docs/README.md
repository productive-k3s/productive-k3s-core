# Productive K3S Core Documentation Workspace

This directory contains the MkDocs workspace for the Productive K3S Core documentation site.

## Layout

```text
docs/
├── build.sh
├── serve.sh
├── clean.sh
├── requirements.txt
├── mkdocs.yml
└── src/
    ├── index.md
    ├── assets/
    ├── overrides/
    ├── en/
    └── es/
```

## Language policy

- English is the default documentation language
- Spanish is maintained as a mirrored tree
- every publishable page under `src/en/` must have a matching page under `src/es/`

## Local workflow

Build the site:

```bash
./docs/build.sh
make docs-build
```

Serve the site locally in the foreground:

```bash
./docs/serve.sh
make docs-serve
```

Start MkDocs in the background:

```bash
make docs-up
```

Stop the background server and clean generated artifacts:

```bash
make docs-down
```

Full cleanup of generated artifacts and the local virtual environment:

```bash
./docs/clean.sh
make docs-clean
```

## Validation

The structural bilingual check is:

```bash
bash tests/test-docs-structure.sh
```

The strict site build is:

```bash
./docs/build.sh
```

## Where to review the site

The local MkDocs server publishes at:

```text
http://127.0.0.1:8000
```

In most browsers, `http://localhost:8000` should also work.

## What to check in the browser

At minimum, review:

1. `/`
   Confirm the landing page keeps the expected clean visual style and that both language buttons work.
2. `/en/`
   Confirm English is the default documentation tree and navigation renders correctly.
3. `/es/`
   Confirm the Spanish tree mirrors the English structure.
4. Header language switcher
   Confirm `EN | ES` is visible and links into the expected language trees.
5. Footer and navigation
   Confirm the footer renders cleanly and that section navigation works on desktop and mobile widths.

If you started the server with `make docs-up`, the runtime log is written to:

```text
docs/.mkdocs.log
```
