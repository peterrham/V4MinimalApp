# AI Inventory Cleanup — Experiment Notes

## Problem

1,508 home inventory items captured by phone camera + Gemini vision have significant data quality issues:
- 752 items (50%) categorized "Other"
- Brand misspellings ("Belcon" for Belkin, "Plant ronics" for Plantronics, "keto Mojo" for Keto-Mojo)
- Brand field contains product name not manufacturer ("MacBook Pro" as brand instead of "Apple")
- AI refusal text saved as item names ("I'm sorry", "I cannot detect...")
- Voice transcriptions saved as items ("Create new box U-Haul number four")
- UPC barcodes saved as item names (numeric strings)
- Verbose Amazon-style descriptions as names (>60 chars)
- Quantities embedded in names ("2 jackets")
- Colors/brands duplicated between name and structured fields
- Numeric junk in notes fields ("1.0", "12.0")
- AI-generated image descriptions stored as notes

## Approach: Gemini API Batch Cleanup

### Architecture

1. Export inventory JSON from device
2. Send items in batches to Gemini with structured cleanup prompt
3. Gemini returns corrected fields as JSON
4. Save corrections as diff file (before/after for every item)
5. Review diffs, then apply to inventory
6. Push cleaned inventory back to device

### Script: `tools/ai_cleanup_inventory.py`

```bash
# Default: Flash model, 40 items/batch, 4 parallel requests
python3 tools/ai_cleanup_inventory.py

# Use Pro model for higher quality (5-6x slower, better product identification)
python3 tools/ai_cleanup_inventory.py --model gemini-2.5-pro

# Process a subset
python3 tools/ai_cleanup_inventory.py --start 0 --end 100

# Apply reviewed corrections
python3 tools/ai_cleanup_inventory.py --apply /tmp/inventory_ai_corrections_TIMESTAMP.json
```

### Output

- Corrections saved to Google Drive: `~/Google Drive/My Drive/HomeInventory/`
- Also saved to `/tmp/` for quick access
- Format: JSON with metadata, stats, and per-item before/after diffs

## Model Comparison

### Gemini 2.5 Pro
- **Speed**: ~26s per batch of 20 items (~2.3s/item)
- **Quality**: Excellent product identification ("keto Mojo" → "Blood Ketone and Glucose Meter")
- **Consistency**: Higher confidence scores (0.95-1.0)
- **Notes**: Fixed typos in notes ("assus" → "Asus"), removed AI descriptions
- **Cost**: Higher token usage, long thinking time
- **Serial estimate for 1,508 items**: ~60 minutes

### Gemini 2.5 Flash
- **Speed**: ~5s per batch of 40 items (~0.3s/item with parallelism)
- **Quality**: Good for most corrections (categories, brands, names)
- **Consistency**: Slightly lower confidence (0.8-0.9 typical)
- **Notes**: Sometimes less thorough on product identification
- **Cost**: Much cheaper, handles larger batches
- **Parallel estimate for 1,508 items**: ~7.5 minutes (4 concurrent)

### Gemini 2.5 Flash-Lite (app's detection model)
- **Speed**: ~2s per call
- **Quality**: Adequate for basic cleanup but occasionally produces malformed JSON
- **Not recommended** for batch cleanup — JSON reliability issues

### Recommendation

**Use Flash for routine cleanup** — the 8x speed advantage and parallelism make it practical for iterative runs. Use Pro only for targeted passes on difficult items (ambiguous products, complex brand identification).

## Prompt Design

### Key lessons learned

1. **`responseMimeType: "application/json"`** — Forces structured JSON output, reduces parsing failures. Flash-lite sometimes ignores this; Flash and Pro respect it.

2. **Send context fields (room, container)** — Even though we don't modify room/container, sending them helps Gemini make better inferences ("item in Kitchen" → likely Kitchenware).

3. **Explicit category list** — Providing the exact valid categories prevents Gemini from inventing new ones.

4. **Confidence scoring** — Having Gemini self-rate lets us filter uncertain corrections. Items below 0.7 confidence should be manually reviewed.

5. **Garbage/structural flags** — Separate from category assignment. "Wooden door" gets flagged structural even though it could be categorized as Furniture. Voice commands get flagged garbage even though they contain real words.

6. **Title casing** — Gemini naturally title-cases names ("couch" → "Couch"), which improves consistency.

7. **Batch size sweet spot**: 40 items for Flash, 20 for Pro. Larger batches risk count mismatches or truncated output.

8. **Parallel requests**: 4 concurrent for Flash works well. Pro is rate-limited more aggressively.

### Prompt structure

```
RULES (10 numbered):
  1. name — concise, keep specs, remove brand, fix typos
  2. brand — fix misspellings, correct manufacturer vs product
  3. category — from fixed list
  4. itemColor — extract from name/notes
  5. quantity — extract from name
  6. notes — clean junk, keep user notes, fix typos
  7. size — extract dimensions
  8. is_garbage — AI refusal, meaningless entries
  9. is_structural — house parts, not inventory
  10. confidence — self-rated 0.0-1.0

IMPORTANT guidance:
  - Leave correct items unchanged
  - Identify actual products when possible
  - Preserve meaningful information
```

## Results (Flash, Jan 31 2026)

| Metric | Count |
|--------|-------|
| Items processed | 1,508 |
| Changed | 1,363 (90%) |
| Unchanged | 75 (5%) |
| Garbage | 65 (4%) |
| Structural | 5 (<1%) |
| Low confidence | 35 (2%) |
| Brand fixes | 624 |
| Name fixes | 1,227 |
| Category fixes | 984 |
| Colors extracted | 57 |
| Quantities extracted | 128 |
| Sizes extracted | 174 |
| Notes cleaned | 317 |
| Total time | 445s |
| Tokens | 115K prompt + 138K output |

### Garbage items identified (65)
- AI refusal text: "I'm sorry", "lacking any discernible objects"
- Voice commands: "Create new box U-Haul number four", "Label this box the wee box"
- Short fragments: "Le", "..", "Move", "Works"
- UPC barcodes as names: 20+ numeric strings
- Ambiguous entries: "10 bucks", "Testing testing"

### Quality issues to watch
- Flash sometimes renames specific products generically ("Apple TV remote" → "TV remote" — loses "Apple TV" context)
- Flash may rename branded items ("Bankers Box" → "Storage Box" — Bankers Box is a real brand)
- "Earbuds case" → "AirPods case" — inference without evidence
- Some structural classifications debatable (is a doorway structural? what about built-in shelving?)

## Iteration Workflow

1. Pull device data: `xcrun devicectl device copy from --domain-type appDataContainer ...`
2. Run cleanup: `python3 tools/ai_cleanup_inventory.py`
3. Review corrections file on Google Drive
4. Edit corrections file to reject bad changes if needed
5. Apply: `python3 tools/ai_cleanup_inventory.py --apply <file>`
6. Push to device: `xcrun devicectl device copy to --domain-type appDataContainer ...`

All iterations are saved with timestamps on Google Drive under `HomeInventory/`.

## Future Improvements

- **Photo-based cleanup**: Send item photos to Gemini vision for even better identification
- **UPC lookup**: Use barcode API to fill in product details for items with UPC codes
- **Two-pass strategy**: Flash for bulk cleanup, then Pro for low-confidence items only
- **In-app integration**: Background enrichment service that runs cleanup on new items
- **Diff review UI**: In-app view to approve/reject individual corrections before applying
- **Incremental runs**: Only process items modified since last cleanup run
