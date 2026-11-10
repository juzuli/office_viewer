# Bundled formatting samples

Public fixtures used by the example app segmented buttons. Filenames stay stable;
content is chosen for styles, tables, images, and charts.

| File | Source | Contents | License / reuse |
|---|---|---|---|
| `sample.docx` | [freetoolsforweb medium DOCX](https://pnb-freetoolsforweb.s3.us-east-2.amazonaws.com/samples/documents/docx/sample-document-medium.docx) | Heading styles, lists, bordered table, embedded JPEG, page breaks | Free redistribution (no attribution required per publisher) |
| `large_sheet.xlsx` | [Testaroo embedded-charts.xlsx](https://www.testaroo.com/files/documents/excel/embedded-charts.xlsx) | Sheet `Data` with a table plus native bar and line charts | Demo/test fixture from Testaroo / Novus examples |
| `sample_deck.pptx` | [SampleLib sample-presentation.pptx](https://samplelib.com/ppt/sample-presentation.pptx) | 8 slides: lists, table, chart, image | SampleLib — free test files, no licensing restrictions stated |
| `sample.pdf` | [PDFKit kitchen-sink.pdf](https://pdfkit.org/examples/kitchen-sink.pdf) | Embedded fonts, PNG/JPEG, vector graphics, wrapped styled text | PDFKit example (MIT project) |

Re-fetch:

```bash
cd example/assets
curl -fsSL -A "Mozilla/5.0" -o sample.docx \
  "https://pnb-freetoolsforweb.s3.us-east-2.amazonaws.com/samples/documents/docx/sample-document-medium.docx"
curl -fsSL -A "Mozilla/5.0" -o large_sheet.xlsx \
  "https://www.testaroo.com/files/documents/excel/embedded-charts.xlsx"
curl -fsSL -A "Mozilla/5.0" -o sample_deck.pptx \
  "https://samplelib.com/ppt/sample-presentation.pptx"
curl -fsSL -A "Mozilla/5.0" -o sample.pdf \
  "https://pdfkit.org/examples/kitchen-sink.pdf"
```
