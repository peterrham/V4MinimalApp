#!/usr/bin/env python3
"""
AI-powered inventory cleanup using Gemini.

Reads inventory JSON, sends items in batches to Gemini for correction,
saves corrections to Google Drive for review before applying.

Usage:
    python3 tools/ai_cleanup_inventory.py                              # full run (flash, fast)
    python3 tools/ai_cleanup_inventory.py --model gemini-2.5-pro       # use Pro (slower, better)
    python3 tools/ai_cleanup_inventory.py --batch-size 10              # smaller batches
    python3 tools/ai_cleanup_inventory.py --start 0 --end 50          # subset
    python3 tools/ai_cleanup_inventory.py --parallel 4                 # concurrent requests
    python3 tools/ai_cleanup_inventory.py --apply corrections.json     # apply reviewed corrections
"""

import json
import urllib.request
import urllib.error
import time
import os
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

# ── Config ──────────────────────────────────────────────────────────────────

API_KEY = os.environ.get("GEMINI_API_KEY", "")
DEFAULT_MODEL = "gemini-2.5-flash"
BATCH_SIZE = 40
PARALLEL_REQUESTS = 4

INPUT_FILE = "/tmp/inventory_device_current.json"
GDRIVE_DIR = os.path.expanduser(
    "~/Library/CloudStorage/GoogleDrive-peterrham@gmail.com/My Drive/HomeInventory"
)

VALID_CATEGORIES = [
    "Electronics", "Furniture", "Kitchenware", "Clothing", "Books", "Tools",
    "Sports", "Toys", "Decor", "Storage", "Office", "Health", "Automotive",
    "Garden", "Musical", "Pet", "Cleaning", "Lighting", "Bathroom", "Bedding",
    "Appliances", "Groceries", "Media", "Safety", "Luggage", "Craft", "Baby",
    "Seasonal", "Household", "Other"
]

PROMPT_TEMPLATE = """You are a home inventory data cleanup assistant. For each item, return corrected fields.

RULES:
1. **name**: Concise product name with key specs (keep model numbers, sizes like "3.5mm", material type). Remove brand from name (it goes in brand field). Fix typos. If name is AI refusal text ("I'm sorry", "I cannot...", "I'm unable..."), set is_garbage=true.
2. **brand**: Fix misspellings ("Belcon"→"Belkin", "Plant ronics"→"Plantronics"). If brand is the product name not the manufacturer, fix it (brand "MacBook Pro"→"Apple"). If you can identify the actual product, set the correct brand. Keep real brands like "Bankers Box".
3. **category**: Best fit from: {categories}
4. **itemColor**: Extract color from name/notes if present ("Black small AC adapter" → itemColor="Black"). Keep existing color if already correct. Don't use materials like "wooden" as colors.
5. **quantity**: Extract from name if embedded ("2 jackets"→quantity=2, "100 count"→quantity=100). Default 1.
6. **notes**: Keep genuine user notes. Fix typos in notes ("assus"→"Asus"). Remove AI-generated image descriptions (sentences describing what the camera sees). Clear numeric junk notes ("1.0"→""). Preserve useful info like model numbers, measurements, conditions.
7. **size**: Extract size/dimensions if present in name ("2x24 inch"→size="2x24 in", "4x6"→size="4x6").
8. **is_garbage**: true ONLY if item should be deleted — AI refusal/apology text, completely meaningless entries (<3 chars with no context), JSON fragments as names.
9. **is_structural**: true if it's part of the house itself (doors, walls, windows, built-in shelving), NOT inventory. Freestanding furniture IS inventory.
10. **confidence**: 0.0-1.0. Use 1.0 for obvious fixes (typos, clear brand corrections). Use 0.7-0.9 for inferred fixes. Use <0.7 if uncertain.

IMPORTANT:
- If an item looks correct already, return it unchanged with confidence 1.0.
- When you recognize the actual product (e.g., "keto Mojo" is a blood glucose/ketone meter), use the correct product name.
- Preserve all meaningful information — just restructure it into the right fields.

Return ONLY a JSON array. Each object must have exactly these keys:
{name, brand, category, itemColor, quantity, size, notes, is_garbage, is_structural, confidence}

Items to clean:
"""


def call_gemini(items, batch_num, total_batches, model, retries=3):
    """Send a batch to Gemini and return parsed corrections."""
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={API_KEY}"
    categories_str = ", ".join(VALID_CATEGORIES)
    prompt = PROMPT_TEMPLATE.replace("{categories}", categories_str)

    # Only send the fields Gemini needs to see
    slim_items = []
    for it in items:
        slim_items.append({
            "name": it.get("name", ""),
            "brand": it.get("brand", ""),
            "category": it.get("category", "Other"),
            "itemColor": it.get("itemColor", ""),
            "quantity": it.get("quantity", 1),
            "size": it.get("size", ""),
            "notes": it.get("notes", ""),
            "room": it.get("room", ""),
            "container": it.get("container", ""),
        })

    payload = {
        "contents": [{"parts": [{"text": prompt + json.dumps(slim_items)}]}],
        "generationConfig": {
            "temperature": 0.1,
            "maxOutputTokens": 16000,
            "responseMimeType": "application/json",
        }
    }

    for attempt in range(retries):
        try:
            req = urllib.request.Request(
                url,
                data=json.dumps(payload).encode(),
                headers={"Content-Type": "application/json"},
                method="POST"
            )
            with urllib.request.urlopen(req, timeout=120) as resp:
                result = json.loads(resp.read())

            text = result["candidates"][0]["content"]["parts"][0]["text"]

            # Parse JSON — strip markdown fences if model ignores responseMimeType
            clean = text.strip()
            if clean.startswith("```"):
                clean = clean.split("\n", 1)[1].rsplit("```", 1)[0].strip()

            corrections = json.loads(clean)

            if len(corrections) != len(items):
                print(f"\n  WARNING: batch {batch_num} returned {len(corrections)} items, expected {len(items)}")
                if attempt < retries - 1:
                    print(f"  Retrying...")
                    time.sleep(2)
                    continue
                # Pad with unchanged items
                while len(corrections) < len(items):
                    idx = len(corrections)
                    corrections.append({
                        "name": items[idx]["name"] if idx < len(items) else "",
                        "confidence": 0.0, "brand": "", "category": "Other",
                        "itemColor": "", "quantity": 1, "size": "",
                        "notes": "", "is_garbage": False, "is_structural": False
                    })
                corrections = corrections[:len(items)]

            usage = result.get("usageMetadata", {})
            return batch_num, corrections, usage

        except (urllib.error.URLError, json.JSONDecodeError, KeyError, IndexError) as e:
            print(f"\n  Batch {batch_num} attempt {attempt+1} failed: {e}")
            if attempt < retries - 1:
                time.sleep(3)
            else:
                # Return items unchanged on total failure
                return batch_num, [{
                    "name": it.get("name", ""), "brand": it.get("brand", ""),
                    "category": it.get("category", "Other"), "itemColor": it.get("itemColor", ""),
                    "quantity": it.get("quantity", 1), "size": it.get("size", ""),
                    "notes": it.get("notes", ""), "is_garbage": False,
                    "is_structural": False, "confidence": 0.0
                } for it in items], {}

    return batch_num, [], {}


def compute_diff(original, corrected):
    """Compute what changed between original and corrected item."""
    changes = {}
    field_map = {
        "name": "name", "brand": "brand", "category": "category",
        "itemColor": "itemColor", "quantity": "quantity", "size": "size",
        "notes": "notes"
    }
    for field, key in field_map.items():
        orig_val = original.get(key, "" if key != "quantity" else 1)
        new_val = corrected.get(key, "" if key != "quantity" else 1)
        if orig_val is None:
            orig_val = "" if key != "quantity" else 1
        if new_val is None:
            new_val = "" if key != "quantity" else 1
        if str(orig_val) != str(new_val):
            changes[field] = {"from": orig_val, "to": new_val}
    return changes


def apply_corrections(inventory_file, corrections_file):
    """Apply reviewed corrections to inventory."""
    with open(inventory_file) as f:
        items = json.load(f)
    with open(corrections_file) as f:
        corrections = json.load(f)

    items_by_id = {it["id"]: it for it in items}
    applied = 0
    deleted = 0
    skipped = 0

    for corr in corrections["corrections"]:
        item_id = corr["id"]
        if item_id not in items_by_id:
            skipped += 1
            continue

        item = items_by_id[item_id]

        if corr.get("is_garbage"):
            del items_by_id[item_id]
            deleted += 1
            continue

        # Apply field changes
        for field, change in corr.get("changes", {}).items():
            item[field] = change["to"]
        applied += 1

    result = list(items_by_id.values())
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output = os.path.join(GDRIVE_DIR, f"inventory_ai_cleaned_{timestamp}.json")
    with open(output, "w") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    # Also write to /tmp for device push
    with open("/tmp/inventory_final.json", "w") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    print(f"\nApplied: {applied} items updated, {deleted} deleted, {skipped} skipped")
    print(f"Result: {len(result)} items")
    print(f"Output: {output}")
    print(f"Also: /tmp/inventory_final.json")
    return result


def main():
    import argparse
    parser = argparse.ArgumentParser(description="AI inventory cleanup with Gemini")
    parser.add_argument("--input", default=INPUT_FILE, help="Input inventory JSON")
    parser.add_argument("--model", default=DEFAULT_MODEL, help="Gemini model to use")
    parser.add_argument("--batch-size", type=int, default=BATCH_SIZE)
    parser.add_argument("--parallel", type=int, default=PARALLEL_REQUESTS, help="Concurrent requests")
    parser.add_argument("--start", type=int, default=0, help="Start index")
    parser.add_argument("--end", type=int, default=None, help="End index")
    parser.add_argument("--apply", metavar="FILE", help="Apply corrections from review file")
    args = parser.parse_args()

    if args.apply:
        apply_corrections(args.input, args.apply)
        return

    model = args.model

    # Load inventory
    with open(args.input) as f:
        items = json.load(f)
    print(f"Loaded {len(items)} items from {args.input}")

    subset = items[args.start:args.end]
    total = len(subset)
    num_batches = (total + args.batch_size - 1) // args.batch_size
    print(f"Processing items {args.start}-{args.start + total} in {num_batches} batches of {args.batch_size}")
    print(f"Model: {model}, Parallel: {args.parallel}")
    print()

    # Prepare all batches
    batches = []
    for batch_idx in range(num_batches):
        batch_start = batch_idx * args.batch_size
        batch_end = min(batch_start + args.batch_size, total)
        batches.append((batch_idx, subset[batch_start:batch_end]))

    all_corrections = [None] * total  # indexed by item position
    stats = {
        "total_items": total,
        "garbage": 0, "structural": 0, "changed": 0, "unchanged": 0,
        "brand_fixes": 0, "name_fixes": 0, "category_fixes": 0,
        "color_extracted": 0, "quantity_extracted": 0, "size_extracted": 0,
        "notes_cleaned": 0, "low_confidence": 0,
        "total_prompt_tokens": 0, "total_output_tokens": 0,
    }

    completed = 0
    t_start = time.time()

    def process_batch(batch_idx, batch_items):
        return call_gemini(batch_items, batch_idx + 1, num_batches, model)

    # Run batches with thread pool
    with ThreadPoolExecutor(max_workers=args.parallel) as executor:
        futures = {}
        for batch_idx, batch_items in batches:
            f = executor.submit(process_batch, batch_idx, batch_items)
            futures[f] = (batch_idx, batch_items)

        for future in as_completed(futures):
            batch_idx, batch_items = futures[future]
            try:
                _, corrections, usage = future.result()
            except Exception as e:
                print(f"\n  Batch {batch_idx+1} exception: {e}")
                corrections = [{
                    "name": it.get("name", ""), "brand": it.get("brand", ""),
                    "category": it.get("category", "Other"), "itemColor": it.get("itemColor", ""),
                    "quantity": it.get("quantity", 1), "size": it.get("size", ""),
                    "notes": it.get("notes", ""), "is_garbage": False,
                    "is_structural": False, "confidence": 0.0
                } for it in batch_items]
                usage = {}

            stats["total_prompt_tokens"] += usage.get("promptTokenCount", 0)
            stats["total_output_tokens"] += usage.get("candidatesTokenCount", 0)

            batch_start = batch_idx * args.batch_size
            for i, (orig, fixed) in enumerate(zip(batch_items, corrections)):
                changes = compute_diff(orig, fixed)
                entry = {
                    "id": orig["id"],
                    "original": {
                        "name": orig.get("name", ""),
                        "brand": orig.get("brand", ""),
                        "category": orig.get("category", ""),
                        "itemColor": orig.get("itemColor", ""),
                        "quantity": orig.get("quantity", 1),
                        "size": orig.get("size", ""),
                        "notes": orig.get("notes", ""),
                    },
                    "corrected": {
                        "name": fixed.get("name", ""),
                        "brand": fixed.get("brand", ""),
                        "category": fixed.get("category", ""),
                        "itemColor": fixed.get("itemColor", ""),
                        "quantity": fixed.get("quantity", 1),
                        "size": fixed.get("size", ""),
                        "notes": fixed.get("notes", ""),
                    },
                    "changes": changes,
                    "is_garbage": fixed.get("is_garbage", False),
                    "is_structural": fixed.get("is_structural", False),
                    "confidence": fixed.get("confidence", 0),
                }
                all_corrections[batch_start + i] = entry

                # Update stats
                if fixed.get("is_garbage"):
                    stats["garbage"] += 1
                elif fixed.get("is_structural"):
                    stats["structural"] += 1
                elif changes:
                    stats["changed"] += 1
                    if "brand" in changes: stats["brand_fixes"] += 1
                    if "name" in changes: stats["name_fixes"] += 1
                    if "category" in changes: stats["category_fixes"] += 1
                    if "itemColor" in changes and not orig.get("itemColor"): stats["color_extracted"] += 1
                    if "quantity" in changes and orig.get("quantity", 1) == 1: stats["quantity_extracted"] += 1
                    if "size" in changes and not orig.get("size"): stats["size_extracted"] += 1
                    if "notes" in changes: stats["notes_cleaned"] += 1
                else:
                    stats["unchanged"] += 1

                if fixed.get("confidence", 1) < 0.7:
                    stats["low_confidence"] += 1

            completed += 1
            n_changes = len([1 for o, f in zip(batch_items, corrections) if compute_diff(o, f)])
            elapsed_so_far = time.time() - t_start
            rate = completed / elapsed_so_far if elapsed_so_far > 0 else 0
            eta = (num_batches - completed) / rate if rate > 0 else 0
            print(f"  Batch {batch_idx+1}/{num_batches} done — {n_changes} changes  [{completed}/{num_batches}, ETA {eta:.0f}s]", flush=True)

    elapsed = time.time() - t_start

    # Filter out any None entries (shouldn't happen but safety)
    all_corrections = [c for c in all_corrections if c is not None]

    # Save corrections review file
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output = {
        "metadata": {
            "model": model,
            "timestamp": timestamp,
            "elapsed_seconds": round(elapsed, 1),
            "input_file": args.input,
            "items_processed": total,
            "batch_size": args.batch_size,
            "parallel": args.parallel,
        },
        "stats": stats,
        "corrections": all_corrections,
    }

    # Save to Google Drive
    os.makedirs(GDRIVE_DIR, exist_ok=True)
    gdrive_path = os.path.join(GDRIVE_DIR, f"inventory_ai_corrections_{timestamp}.json")
    with open(gdrive_path, "w") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    # Also save to /tmp for quick access
    tmp_path = f"/tmp/inventory_ai_corrections_{timestamp}.json"
    with open(tmp_path, "w") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    # Print summary
    print(f"\n{'='*60}")
    print(f"AI CLEANUP COMPLETE — {model}")
    print(f"{'='*60}")
    print(f"Time: {elapsed:.0f}s ({elapsed/total:.1f}s per item)")
    print(f"Tokens: {stats['total_prompt_tokens']:,} prompt + {stats['total_output_tokens']:,} output")
    print()
    print(f"Items processed:  {total}")
    print(f"  Changed:        {stats['changed']}")
    print(f"  Unchanged:      {stats['unchanged']}")
    print(f"  Garbage:        {stats['garbage']} (will delete)")
    print(f"  Structural:     {stats['structural']} (house parts)")
    print(f"  Low confidence: {stats['low_confidence']} (< 0.7)")
    print()
    print(f"Fix breakdown:")
    print(f"  Brand fixes:      {stats['brand_fixes']}")
    print(f"  Name fixes:       {stats['name_fixes']}")
    print(f"  Category fixes:   {stats['category_fixes']}")
    print(f"  Colors extracted: {stats['color_extracted']}")
    print(f"  Quantities:       {stats['quantity_extracted']}")
    print(f"  Sizes:            {stats['size_extracted']}")
    print(f"  Notes cleaned:    {stats['notes_cleaned']}")
    print()
    print(f"Review file: {gdrive_path}")
    print(f"Also at:     {tmp_path}")
    print()
    print(f"To apply:  python3 tools/ai_cleanup_inventory.py --apply {tmp_path}")

    # Print sample changes for quick review
    changed = [c for c in all_corrections if c["changes"] and not c["is_garbage"]]
    print(f"\n{'='*60}")
    print(f"SAMPLE CHANGES (first 30)")
    print(f"{'='*60}")
    for c in changed[:30]:
        print(f'\n  "{c["original"]["name"]}" [conf={c["confidence"]}]')
        for field, diff in c["changes"].items():
            fr = str(diff["from"])[:50]
            to = str(diff["to"])[:50]
            print(f'    {field}: "{fr}" → "{to}"')
        if c["is_structural"]:
            print(f'    >>> STRUCTURAL')

    garbage = [c for c in all_corrections if c["is_garbage"]]
    if garbage:
        print(f"\n{'='*60}")
        print(f"GARBAGE ITEMS ({len(garbage)} to delete)")
        print(f"{'='*60}")
        for c in garbage:
            print(f'  "{c["original"]["name"]}"')


if __name__ == "__main__":
    main()
