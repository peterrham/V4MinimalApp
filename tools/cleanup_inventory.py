#!/usr/bin/env python3
"""
Comprehensive inventory cleanup script.

Reads:  /tmp/inventory_device_current.json
Writes: /tmp/inventory_final.json

12-step offline pipeline (no API calls):
 1. Delete garbage items
 2. Add default fields (quantity, upc, isEmptyBox)
 3. Extract quantities from names/notes
 4. Move UPC codes from names to upc field
 5. Handle empty box items
 6. Correct brand spellings
 7. Strip redundant brand/color from names
 8. Clean verbose names
 9. Split multi-item voice entries
10. Fix container names
11. Recategorize "Other" items
12. Disambiguate duplicate names
"""

import json
import re
import uuid
import copy
import sys
from datetime import datetime, timezone
from collections import Counter

INPUT_PATH = "/tmp/inventory_device_current.json"
OUTPUT_PATH = "/tmp/inventory_final.json"

# ──────────────────────────────────────────────
# Step 1: Delete garbage
# ──────────────────────────────────────────────

GARBAGE_PATTERNS = [
    "cannot", "unable", "provided image", "bounding box",
    "no visible", "no visual", "therefore", "no discernible",
    "impossible to identify", "not contain any", "entirely black",
    "completely black", "solid color", "no objects",
    "i cannot provide", "but i cannot detect",
]

GARBAGE_EXACT = {"le", "..", "move", "works", "wall", "24 ld", "teal to"}


def delete_garbage(items):
    before = len(items)
    result = []
    for item in items:
        name = item["name"].strip()
        lower = name.lower()
        if len(name) <= 2:
            continue
        if lower in GARBAGE_EXACT:
            continue
        if any(p in lower for p in GARBAGE_PATTERNS):
            continue
        result.append(item)
    print(f"  Step 1: Deleted {before - len(result)} garbage items")
    return result


# ──────────────────────────────────────────────
# Step 2: Add default fields
# ──────────────────────────────────────────────

def add_defaults(items):
    for item in items:
        item.setdefault("quantity", 1)
        if item["quantity"] is None:
            item["quantity"] = 1
        item.setdefault("upc", None)
        item.setdefault("isEmptyBox", False)
    print(f"  Step 2: Added default fields to {len(items)} items")
    return items


# ──────────────────────────────────────────────
# Step 3: Extract quantities
# ──────────────────────────────────────────────

WORD_TO_NUM = {
    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    "eleven": 11, "twelve": 12,
}


def extract_quantities(items):
    count = 0
    for item in items:
        qty = item.get("quantity") or 1

        # From notes: "Qty: N"
        notes = item.get("notes", "") or ""
        qty_match = re.search(r"Qty:\s*(\d+)", notes, re.IGNORECASE)
        if qty_match:
            qty = max(qty, int(qty_match.group(1)))
            notes = re.sub(r";?\s*Qty:\s*\d+", "", notes).strip().strip(";").strip()
            item["notes"] = notes

        # From name prefix: "One jacket" -> quantity=1, name="Jacket"
        name = item["name"].strip()
        words = name.split()
        if len(words) >= 2 and words[0].lower() in WORD_TO_NUM:
            # Don't extract from names where the word is part of a product
            # e.g. "One Direction poster" — skip if 2nd word is capitalized and not a common noun
            extracted_qty = WORD_TO_NUM[words[0].lower()]
            if extracted_qty <= 12:
                qty = max(qty, extracted_qty)
                name = " ".join(words[1:])
                if name:
                    name = name[0].upper() + name[1:]
                count += 1

        # From digit prefix: "2 jackets"
        num_match = re.match(r"^(\d+)\s+(.+)", name)
        if num_match:
            num_val = int(num_match.group(1))
            if 2 <= num_val <= 100:
                qty = max(qty, num_val)
                name = num_match.group(2)
                if name:
                    name = name[0].upper() + name[1:]
                count += 1

        item["quantity"] = qty
        item["name"] = name

    print(f"  Step 3: Extracted quantities from {count} items")
    return items


# ──────────────────────────────────────────────
# Step 4: Move UPC codes
# ──────────────────────────────────────────────

def move_upc_codes(items):
    count = 0
    for item in items:
        name = item["name"].strip()
        # Match 8-14 digit codes (UPC/EAN/ISBN), possibly with .0 suffix
        cleaned = name.rstrip("0").rstrip(".")
        if re.match(r"^\d{8,14}$", cleaned):
            item["upc"] = cleaned
            container = item.get("container", "")
            if container:
                # Use container as a hint for the name
                item["name"] = f"Unknown ({container[:40]})"
            else:
                item["name"] = f"Unknown (UPC: {cleaned[:10]})"
            count += 1
    print(f"  Step 4: Moved {count} UPC codes from name to upc field")
    return items


# ──────────────────────────────────────────────
# Step 5: Handle empty boxes
# ──────────────────────────────────────────────

BRAND_HINTS = {
    "airpod": "Apple", "iphone": "Apple", "ipad": "Apple",
    "macbook": "Apple", "apple watch": "Apple", "apple": "Apple",
    "kindle": "Amazon", "echo ": "Amazon", "alexa": "Amazon",
    "gopro": "GoPro", "bose": "Bose", "nvidia": "Nvidia",
    "geforce": "Nvidia", "corsair": "Corsair", "logitech": "Logitech",
    "samsung": "Samsung", "sony": "Sony", "lg ": "LG",
    "dell": "Dell", "hp ": "HP", "lenovo": "Lenovo",
    "canon": "Canon", "nikon": "Nikon", "dyson": "Dyson",
    "anker": "Anker", "belkin": "Belkin", "roku": "Roku",
    "tesla": "Tesla", "roomba": "iRobot", "omron": "Omron",
    "manfrotto": "Manfrotto",
}

EMPTY_BOX_PATTERNS = [
    # "empty box [product]" or "empty box for [product]" or "empty box of [product]"
    re.compile(r"^empty\s+box\.?\s+(?:of\s+|for\s+)?(.+)$", re.IGNORECASE),
    # "[product] empty box"
    re.compile(r"^(.+?)\s+empty\s+box\.?$", re.IGNORECASE),
    # "[product], empty box"
    re.compile(r"^(.+?),?\s+empty\s+box\.?$", re.IGNORECASE),
    # "Empty box" by itself (keep as is but flag)
    re.compile(r"^empty\s+box\.?$", re.IGNORECASE),
]


def handle_empty_boxes(items):
    count = 0
    for item in items:
        name = item["name"].strip()
        lower = name.lower()

        if "empty box" not in lower:
            continue

        for pattern in EMPTY_BOX_PATTERNS:
            m = pattern.match(name)
            if m:
                groups = m.groups()
                if groups and groups[0]:
                    product = groups[0].strip().strip(".,;")
                    # Title case the product name
                    if product and not any(c.isupper() for c in product[1:]):
                        product = product.title()
                    item["name"] = product if product else "Unknown Item"
                else:
                    item["name"] = "Unknown Item"

                item["isEmptyBox"] = True

                # Try to infer brand
                if not item.get("brand"):
                    product_lower = item["name"].lower()
                    for keyword, brand in BRAND_HINTS.items():
                        if keyword in product_lower:
                            item["brand"] = brand
                            break

                count += 1
                break

    print(f"  Step 5: Flagged {count} empty box items")
    return items


# ──────────────────────────────────────────────
# Step 6: Correct brand spellings
# ──────────────────────────────────────────────

BRAND_CORRECTIONS = {}
# Build case-insensitive lookup
_raw = {
    "apple": "Apple",
    "macbook": "Apple",
    "macbook pro": "Apple",
    "keto mojo": "Keto-Mojo",
    "keto-mojo": "Keto-Mojo",
    "scotch": "Scotch",
    "roomba": "iRobot",
    "kassa": "Kassa",
    "jadens": "Jadens",
    "ikea": "IKEA",
    "logitech": "Logitech",
    "samsung": "Samsung",
    "sony": "Sony",
    "bose": "Bose",
    "canon": "Canon",
    "hp": "HP",
    "hewlett packard": "HP",
    "dell": "Dell",
    "lenovo": "Lenovo",
    "gopro": "GoPro",
    "amazon": "Amazon",
    "google": "Google",
    "microsoft": "Microsoft",
    "nvidia": "Nvidia",
    "asus": "Asus",
    "corsair": "Corsair",
    "nikon": "Nikon",
    "anker": "Anker",
    "belkin": "Belkin",
    "dyson": "Dyson",
    "kitchenaid": "KitchenAid",
    "kitchen aid": "KitchenAid",
    "philips": "Philips",
    "panasonic": "Panasonic",
    "brother": "Brother",
    "yamaha": "Yamaha",
    "tesla": "Tesla",
    "3m": "3M",
    "at&t": "AT&T",
    "rubbermaid": "Rubbermaid",
    "rust-oleum": "Rust-Oleum",
    "shure": "Shure",
    "directv": "DirecTV",
    "manfrotto": "Manfrotto",
    "maxell": "Maxell",
    "kinesis": "Kinesis",
    "bombas": "Bombas",
    "kirkland": "Kirkland",
    "kirkland signature": "Kirkland Signature",
    "paper mate": "Paper Mate",
    "phomemo": "Phomemo",
    "plant ronics": "Plantronics",
    "plantronics": "Plantronics",
    "hitachi": "Hitachi",
    "volex": "Volex",
    "lakeshore": "Lakeshore",
    "home depot": "Home Depot",
    "u-haul": "U-Haul",
    "bankers box": "Bankers Box",
}
for k, v in _raw.items():
    BRAND_CORRECTIONS[k] = v


def correct_brands(items):
    count = 0
    for item in items:
        brand = item.get("brand")
        if not brand:
            continue
        key = brand.lower().strip()
        if key in BRAND_CORRECTIONS:
            correct = BRAND_CORRECTIONS[key]
            if brand != correct:
                item["brand"] = correct
                count += 1
    print(f"  Step 6: Corrected {count} brand spellings")
    return items


# ──────────────────────────────────────────────
# Step 7: Strip redundant brand/color from name
# ──────────────────────────────────────────────

def strip_redundant_from_name(items):
    brand_count = 0
    color_count = 0
    for item in items:
        name = item["name"]
        brand = item.get("brand") or ""
        color = item.get("itemColor") or ""

        if brand and brand.lower() in name.lower():
            pattern = re.compile(re.escape(brand), re.IGNORECASE)
            new_name = pattern.sub("", name, count=1).strip()
            new_name = re.sub(r"^[\s,\-'\"]+", "", new_name).strip()
            if len(new_name) >= 2:
                name = new_name
                brand_count += 1

        if color and color.lower() in name.lower():
            pattern = re.compile(re.escape(color), re.IGNORECASE)
            new_name = pattern.sub("", name, count=1).strip()
            new_name = re.sub(r"^[\s,\-'\"]+", "", new_name).strip()
            if len(new_name) >= 2:
                name = new_name
                color_count += 1

        # Capitalize first letter
        if name and name[0].islower():
            name = name[0].upper() + name[1:]

        item["name"] = name

    print(f"  Step 7: Stripped {brand_count} redundant brands, {color_count} redundant colors from names")
    return items


# ──────────────────────────────────────────────
# Step 8: Clean verbose names
# ──────────────────────────────────────────────

def clean_verbose_names(items):
    count = 0
    for item in items:
        name = item["name"]
        if len(name) <= 60:
            continue

        # Move full text to notes if notes is short
        existing_notes = item.get("notes", "") or ""
        if len(existing_notes) < 20:
            if existing_notes:
                item["notes"] = f"{name}; {existing_notes}"
            else:
                item["notes"] = name

        # Try to extract the essential part at natural break points
        truncated = name
        for sep in [" - ", ", ", " | ", " (", " /"]:
            idx = name.find(sep)
            if idx >= 10:
                truncated = name[:idx].strip()
                break

        if len(truncated) > 60:
            # Hard truncate at word boundary
            truncated = truncated[:57]
            last_space = truncated.rfind(" ")
            if last_space > 30:
                truncated = truncated[:last_space]
            truncated = truncated.rstrip(" ,.-") + "..."

        item["name"] = truncated
        count += 1

    print(f"  Step 8: Cleaned {count} verbose names")
    return items


# ──────────────────────────────────────────────
# Step 9: Split multi-item voice entries
# ──────────────────────────────────────────────

def split_multi_items(items):
    """Split entries like 'One jacket one dress two pants' into separate items."""
    new_items = []
    to_remove = []

    # Build a pattern that finds "quantity word(s)" sequences
    qty_words = "|".join(WORD_TO_NUM.keys())
    # Match: (qty_word) (2+ words of item description) — greedy until next qty word or end
    split_pattern = re.compile(
        rf"(?:({qty_words}|\d+))\s+((?:(?!(?:{qty_words})\s).)+)",
        re.IGNORECASE
    )

    for idx, item in enumerate(items):
        name = item["name"]
        # Only split if the name has multiple quantity words
        matches = split_pattern.findall(name)
        if len(matches) < 2:
            continue

        # Verify this looks like a multi-item entry (not a product name)
        if len(name) < 40:
            continue

        to_remove.append(idx)
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

        for qty_word, item_desc in matches:
            qty_lower = qty_word.lower()
            qty = WORD_TO_NUM.get(qty_lower, None)
            if qty is None:
                try:
                    qty = int(qty_word)
                except ValueError:
                    qty = 1

            clean_name = item_desc.strip().strip(".,;")
            if clean_name:
                clean_name = clean_name[0].upper() + clean_name[1:]

            new_item = copy.deepcopy(item)
            new_item["id"] = str(uuid.uuid4()).upper()
            new_item["name"] = clean_name
            new_item["quantity"] = qty
            new_item["updatedAt"] = now
            new_items.append(new_item)

    # Remove originals in reverse order
    for idx in sorted(to_remove, reverse=True):
        items.pop(idx)

    items.extend(new_items)
    print(f"  Step 9: Split {len(to_remove)} multi-item entries into {len(new_items)} items")
    return items


# ──────────────────────────────────────────────
# Step 10: Fix containers
# ──────────────────────────────────────────────

CONTAINER_RENAMES = {
    "Furnace Room or Abouts": "Furnace Room",
}


def fix_containers(items):
    count = 0
    for item in items:
        container = item.get("container")
        if not container:
            continue

        # Known renames
        if container in CONTAINER_RENAMES:
            item["container"] = CONTAINER_RENAMES[container]
            count += 1
            continue

        # Numeric: "23.0" -> "Box 23"
        m = re.match(r"^(\d+)\.0$", container)
        if m:
            item["container"] = f"Box {m.group(1)}"
            count += 1

    print(f"  Step 10: Fixed {count} container names")
    return items


# ──────────────────────────────────────────────
# Step 11: Recategorize "Other" items
# ──────────────────────────────────────────────

CATEGORY_KEYWORDS = {
    "Electronics": [
        "tv", "television", "monitor", "laptop", "computer", "phone",
        "tablet", "speaker", "headphone", "earphone", "earbud", "camera",
        "remote control", "remote", "cable", "charger", "adapter", "router",
        "modem", "printer", "scanner", "keyboard", "mouse", "usb", "hdmi",
        "airpod", "gopro", "webcam", "microphone", "hard drive", "ssd",
        "flash drive", "power supply", "battery", "displayport", "dvi",
        "vga", "ethernet", "hub", "docking station", "cd", "dvd",
        "floppy", "raspberry pi", "arduino",
    ],
    "Furniture": [
        "chair", "table", "desk", "sofa", "couch", "bed", "dresser",
        "shelf", "bookcase", "cabinet", "nightstand", "ottoman", "bench",
        "armchair", "stool", "futon", "mattress", "headboard",
    ],
    "Appliances": [
        "washer", "dryer", "microwave", "blender", "toaster",
        "coffee maker", "vacuum", "iron", "fan", "heater", "humidifier",
        "air purifier", "dehumidifier", "dishwasher", "refrigerator",
        "freezer", "oven", "mixer", "food processor",
    ],
    "Clothing": [
        "shirt", "pants", "jacket", "coat", "dress", "skirt", "sweater",
        "jeans", "shorts", "suit", "tie", "scarf", "hat", "glove", "sock",
        "shoe", "boot", "sneaker", "underwear", "hoodie", "vest", "belt",
        "trouser", "pajama", "robe", "swimsuit", "legging",
    ],
    "Kitchenware": [
        "pot", "pan", "plate", "bowl", "cup", "mug", "glass",
        "knife set", "fork", "spoon", "spatula", "cutting board", "baking",
        "colander", "tupperware", "container store", "utensil",
    ],
    "Books": [
        "book", "novel", "textbook", "manual", "guide", "dictionary",
        "magazine", "journal", "suzuki", "edition",
    ],
    "Tools": [
        "hammer", "drill", "wrench", "screwdriver", "saw", "plier",
        "level", "tape measure", "toolbox", "sandpaper", "clamp",
    ],
    "Decor": [
        "lamp", "vase", "candle", "frame", "picture", "mirror", "rug",
        "curtain", "pillow", "cushion", "plant pot", "figurine", "artwork",
    ],
    "Sports & Fitness": [
        "ball", "racket", "yoga", "dumbbell", "weight", "exercise",
        "bicycle", "helmet", "ski", "golf", "tennis", "fitness",
        "resistance band", "jump rope",
    ],
    "Toys & Games": [
        "toy", "puzzle", "lego", "doll", "action figure",
        "board game", "card game", "playstation", "xbox", "nintendo",
        "game", "catan", "monopoly", "risk", "sorry",
    ],
    "Jewelry": [
        "ring", "necklace", "bracelet", "earring", "watch", "pendant",
        "brooch", "cufflink",
    ],
}


def recategorize(items):
    count = 0
    for item in items:
        if item["category"] != "Other":
            continue
        name_lower = item["name"].lower()
        container_lower = (item.get("container") or "").lower()
        notes_lower = (item.get("notes") or "").lower()
        search_text = f"{name_lower} {container_lower} {notes_lower}"

        for category, keywords in CATEGORY_KEYWORDS.items():
            if any(kw in search_text for kw in keywords):
                item["category"] = category
                count += 1
                break

    print(f"  Step 11: Recategorized {count} items from 'Other'")
    return items


# ──────────────────────────────────────────────
# Step 12: Disambiguate duplicate names
# ──────────────────────────────────────────────

def disambiguate_names(items):
    name_groups = {}
    for idx, item in enumerate(items):
        key = item["name"].lower().strip()
        name_groups.setdefault(key, []).append(idx)

    count = 0
    for key, indices in name_groups.items():
        if len(indices) <= 1:
            continue
        for idx in indices:
            item = items[idx]
            suffix_parts = []
            if item.get("brand"):
                suffix_parts.append(item["brand"])
            elif item.get("container"):
                # Shorten container for suffix
                container = item["container"]
                if len(container) > 25:
                    container = container[:25].rstrip() + "..."
                suffix_parts.append(container)
            elif item.get("room"):
                suffix_parts.append(item["room"])

            if suffix_parts:
                item["name"] = f"{item['name']} ({', '.join(suffix_parts)})"
                count += 1

    print(f"  Step 12: Disambiguated {count} duplicate names")
    return items


# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────

def main():
    print(f"Loading {INPUT_PATH}...")
    with open(INPUT_PATH) as f:
        items = json.load(f)
    print(f"Loaded {len(items)} items\n")

    items = delete_garbage(items)
    items = add_defaults(items)
    items = extract_quantities(items)
    items = move_upc_codes(items)
    items = handle_empty_boxes(items)
    items = correct_brands(items)
    items = strip_redundant_from_name(items)
    items = clean_verbose_names(items)
    items = split_multi_items(items)
    items = fix_containers(items)
    items = recategorize(items)
    items = disambiguate_names(items)

    # ── Final stats ──
    print(f"\n{'='*50}")
    print(f"Final: {len(items)} items")
    print(f"  With UPC:       {sum(1 for i in items if i.get('upc'))}")
    print(f"  Empty boxes:    {sum(1 for i in items if i.get('isEmptyBox'))}")
    print(f"  Qty > 1:        {sum(1 for i in items if (i.get('quantity') or 1) > 1)}")

    with_brand = sum(1 for i in items if i.get("brand"))
    with_color = sum(1 for i in items if i.get("itemColor"))
    with_room = sum(1 for i in items if i.get("room"))
    with_container = sum(1 for i in items if i.get("container"))
    print(f"  With brand:     {with_brand}")
    print(f"  With color:     {with_color}")
    print(f"  With room:      {with_room}")
    print(f"  With container: {with_container}")

    cats = Counter(i["category"] for i in items)
    print(f"\n  Categories:")
    for cat, cnt in cats.most_common():
        print(f"    {cnt:5d}  {cat}")

    # Name length stats
    lengths = [len(i["name"]) for i in items]
    print(f"\n  Name lengths: min={min(lengths)}, max={max(lengths)}, avg={sum(lengths)/len(lengths):.0f}")
    over60 = sum(1 for l in lengths if l > 60)
    print(f"  Names > 60 chars: {over60}")

    # Sample output
    print(f"\n  Sample items:")
    import random
    random.seed(42)
    for item in random.sample(items, min(15, len(items))):
        box = " [BOX]" if item.get("isEmptyBox") else ""
        qty = f" x{item['quantity']}" if item.get("quantity", 1) > 1 else ""
        upc = f" UPC:{item['upc']}" if item.get("upc") else ""
        brand = f" ({item['brand']})" if item.get("brand") else ""
        color = f" [{item.get('itemColor')}]" if item.get("itemColor") else ""
        print(f"    \"{item['name']}\"{brand}{color}{qty}{box}{upc} -> {item['category']}")

    with open(OUTPUT_PATH, "w") as f:
        json.dump(items, f, indent=2, default=str)
    print(f"\nWrote {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
