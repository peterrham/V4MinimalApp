# Home Inventory API for ChatGPT Custom GPT

This API serves your inventory data to a ChatGPT Custom GPT.

## Quick Start (Local Testing)

```bash
cd tools/inventory-api
pip install -r requirements.txt
export INVENTORY_PATH="/path/to/your/inventory.json"
export INVENTORY_API_KEY="your-secret-key"
uvicorn server:app --reload --port 8000
```

Test it: `curl -H "Authorization: Bearer your-secret-key" http://localhost:8000/inventory/summary`

## Deploy to Vercel (Free)

1. Install Vercel CLI: `npm i -g vercel`

2. Create `vercel.json` in this directory:
```json
{
  "builds": [{"src": "server.py", "use": "@vercel/python"}],
  "routes": [{"src": "/(.*)", "dest": "server.py"}]
}
```

3. Deploy:
```bash
vercel
vercel env add INVENTORY_API_KEY  # your secret key
```

4. For the inventory data, you have options:
   - Upload `inventory.json` alongside `server.py` and set `INVENTORY_PATH=inventory.json`
   - Use a database (Vercel Postgres, Supabase, etc.)
   - Sync from Google Drive via a cron job

## Deploy to Railway (Easy)

1. Push this directory to a GitHub repo
2. Connect Railway to the repo
3. Set environment variables in Railway dashboard:
   - `INVENTORY_API_KEY`: your secret key
   - `INVENTORY_PATH`: path to inventory file (or use a database)
4. Railway auto-deploys on push

## Create the Custom GPT

1. Go to https://chat.openai.com/gpts/editor

2. **Name**: Home Inventory Assistant

3. **Description**: Access and search your home inventory. Ask about what you own, get room summaries, find specific items.

4. **Instructions**: Copy from `gpt-instructions.md`

5. **Conversation starters**:
   - What's in my kitchen?
   - Give me a summary of my inventory
   - Do I have any duplicates?
   - What's my most valuable room?

6. **Actions**:
   - Click "Create new action"
   - Paste the contents of `openapi.yaml`
   - Update the `servers.url` to your deployed API URL
   - Under Authentication: select "API Key", Header name: `Authorization`, value: `Bearer YOUR_API_KEY`

7. **Save** and test!

## Syncing Inventory Data

The iOS app stores inventory at `Documents/inventory.json`. To make it available to the API:

**Option A: Google Drive Sync (you already have this)**
- Your app can write to Google Drive
- Set up a sync script to copy from Drive to your server

**Option B: Direct Upload Endpoint**
- Add a POST /inventory/sync endpoint to the API
- Have the iOS app push updates when inventory changes

**Option C: Shared Database**
- Migrate from JSON to a cloud database (Supabase, Firestore, etc.)
- Both iOS app and API read/write to the same database

## Security Notes

- The API key is sent in the Authorization header
- ChatGPT stores this securely and sends it with each request
- Use a strong random key (e.g., `openssl rand -hex 32`)
- The API only allows read operations - no one can modify your inventory through it
