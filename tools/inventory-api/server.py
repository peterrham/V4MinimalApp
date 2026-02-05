"""
Home Inventory API Server
Serves inventory data for ChatGPT Custom GPT Actions

Deploy to: Vercel, Railway, Render, or Cloudflare Workers (with Python adapter)
Local dev: uvicorn server:app --reload --port 8000
"""

from fastapi import FastAPI, HTTPException, Query, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
import json
import os
from pathlib import Path
from datetime import datetime

app = FastAPI(
    title="Home Inventory API",
    description="API for accessing home inventory data from a Custom GPT",
    version="1.0.0"
)

# CORS for ChatGPT
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://chat.openai.com", "https://chatgpt.com"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

# --- Configuration ---

# For local dev, point to your Google Drive inventory file
# For production, you'd sync this file or use a database
INVENTORY_PATH = os.environ.get(
    "INVENTORY_PATH",
    "/Users/peterham/Library/CloudStorage/GoogleDrive-peterrham@gmail.com/My Drive/inventory.json"
)

# Simple API key auth (set in environment)
API_KEY = os.environ.get("INVENTORY_API_KEY", "dev-key-change-me")


# --- Models ---

class InventoryItem(BaseModel):
    id: str
    name: str
    category: Optional[str] = None
    room: Optional[str] = None
    brand: Optional[str] = None
    color: Optional[str] = None
    size: Optional[str] = None
    quantity: int = 1
    estimatedValue: Optional[float] = None
    purchasePrice: Optional[float] = None
    notes: Optional[str] = None
    createdAt: Optional[str] = None

class InventorySummary(BaseModel):
    totalItems: int
    totalValue: float
    roomCounts: dict[str, int]
    categoryCounts: dict[str, int]
    recentItems: list[str]

class SearchResult(BaseModel):
    items: list[InventoryItem]
    count: int
    query: str


# --- Auth ---

async def verify_api_key(authorization: str = Header(None)):
    """Simple API key verification"""
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing Authorization header")

    # Expect: "Bearer <api_key>"
    parts = authorization.split(" ")
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(status_code=401, detail="Invalid Authorization format")

    if parts[1] != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")

    return True


# --- Data Access ---

def load_inventory() -> list[dict]:
    """Load inventory from JSON file"""
    path = Path(INVENTORY_PATH)

    # Also check local fallback paths
    fallbacks = [
        Path("inventory.json"),
        Path("data/inventory.json"),
        Path.home() / "Documents/V4MinimalApp/Documents/inventory.json"
    ]

    for p in [path] + fallbacks:
        if p.exists():
            with open(p, "r") as f:
                return json.load(f)

    return []


# --- Endpoints ---

@app.get("/")
async def root():
    """Health check"""
    return {"status": "ok", "service": "Home Inventory API"}


@app.get("/inventory/summary", response_model=InventorySummary)
async def get_summary(auth: bool = Depends(verify_api_key)):
    """
    Get a summary of the entire inventory.
    Returns total counts, value, and breakdowns by room and category.
    """
    items = load_inventory()

    room_counts: dict[str, int] = {}
    category_counts: dict[str, int] = {}
    total_value = 0.0

    for item in items:
        # Room counts
        room = item.get("room", "Unassigned") or "Unassigned"
        room_counts[room] = room_counts.get(room, 0) + 1

        # Category counts
        category = item.get("category", "Other") or "Other"
        category_counts[category] = category_counts.get(category, 0) + 1

        # Total value
        value = item.get("estimatedValue") or item.get("purchasePrice") or 0
        total_value += float(value)

    # Recent items (last 10 by creation date)
    sorted_items = sorted(
        items,
        key=lambda x: x.get("createdAt", ""),
        reverse=True
    )
    recent = [item.get("name", "Unknown") for item in sorted_items[:10]]

    return InventorySummary(
        totalItems=len(items),
        totalValue=total_value,
        roomCounts=room_counts,
        categoryCounts=category_counts,
        recentItems=recent
    )


@app.get("/inventory/items")
async def get_items(
    room: Optional[str] = Query(None, description="Filter by room name"),
    category: Optional[str] = Query(None, description="Filter by category"),
    limit: int = Query(50, ge=1, le=200, description="Max items to return"),
    auth: bool = Depends(verify_api_key)
):
    """
    Get inventory items, optionally filtered by room or category.
    """
    items = load_inventory()

    # Apply filters
    if room:
        items = [i for i in items if (i.get("room") or "").lower() == room.lower()]
    if category:
        items = [i for i in items if (i.get("category") or "").lower() == category.lower()]

    # Limit results
    items = items[:limit]

    return {
        "items": items,
        "count": len(items),
        "filters": {"room": room, "category": category}
    }


@app.get("/inventory/search", response_model=SearchResult)
async def search_items(
    q: str = Query(..., min_length=1, description="Search query"),
    limit: int = Query(20, ge=1, le=100),
    auth: bool = Depends(verify_api_key)
):
    """
    Search inventory items by name, brand, notes, or other text fields.
    """
    items = load_inventory()
    query_lower = q.lower()

    matches = []
    for item in items:
        searchable = " ".join([
            item.get("name", ""),
            item.get("brand", ""),
            item.get("notes", ""),
            item.get("color", ""),
            item.get("category", ""),
            item.get("room", "")
        ]).lower()

        if query_lower in searchable:
            matches.append(item)

    return SearchResult(
        items=matches[:limit],
        count=len(matches),
        query=q
    )


@app.get("/inventory/rooms")
async def get_rooms(auth: bool = Depends(verify_api_key)):
    """
    Get list of all rooms with item counts.
    """
    items = load_inventory()
    rooms: dict[str, dict] = {}

    for item in items:
        room = item.get("room", "Unassigned") or "Unassigned"
        if room not in rooms:
            rooms[room] = {"name": room, "itemCount": 0, "totalValue": 0}
        rooms[room]["itemCount"] += 1
        value = item.get("estimatedValue") or item.get("purchasePrice") or 0
        rooms[room]["totalValue"] += float(value)

    return {"rooms": list(rooms.values())}


@app.get("/inventory/room/{room_name}")
async def get_room_items(
    room_name: str,
    auth: bool = Depends(verify_api_key)
):
    """
    Get all items in a specific room.
    """
    items = load_inventory()
    room_items = [
        i for i in items
        if (i.get("room") or "").lower() == room_name.lower()
    ]

    total_value = sum(
        float(i.get("estimatedValue") or i.get("purchasePrice") or 0)
        for i in room_items
    )

    return {
        "room": room_name,
        "items": room_items,
        "count": len(room_items),
        "totalValue": total_value
    }


@app.get("/inventory/categories")
async def get_categories(auth: bool = Depends(verify_api_key)):
    """
    Get list of all categories with item counts.
    """
    items = load_inventory()
    categories: dict[str, int] = {}

    for item in items:
        cat = item.get("category", "Other") or "Other"
        categories[cat] = categories.get(cat, 0) + 1

    return {
        "categories": [
            {"name": k, "count": v}
            for k, v in sorted(categories.items(), key=lambda x: -x[1])
        ]
    }


# --- Run with: uvicorn server:app --reload ---
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
