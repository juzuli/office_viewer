# API change proposals

Rule: do **not** change `office_viewer` core public API unless unavoidable.
List proposals here instead of landing them silently.

## Current status

**No core API changes proposed for M0–M1.**

Existing types cover the Dart engine:

- `OfficeEngine` / `OfficeDocumentHandle` / `TileRequest` / `RenderedTile`
- `ResourceLimitError` for budgets
- `PasswordRequiredError` for encrypted OOXML
- Registry first-match order (PDF then Dart)

## Possible future proposals (not accepted)

1. **Provisional / async parts updates** for DOCX pagination that discovers page
   count after background layout — may need a listener or mutable parts
   notification. Investigate against how `OfficeDocumentController` / view
   consume `parts` before proposing anything.
2. **Format sniff with head bytes in controller** — controller currently calls
   `OfficeFormat.fromName(fileName)` without `head`; engines can sniff on open.
3. **Engine priority field** — unnecessary while registration order is documented.
