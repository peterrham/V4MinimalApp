# V4MinimalApp Log Server

A UDP-based logging system that allows the iOS app to stream logs to your Mac for debugging.

## Quick Start

### 1. Start the Server (on Mac)

```bash
cd tools/log-server
python3 log_server.py
```

The server will display its IP address - you'll need this for the iOS app.

### 2. Test Locally (on Mac)

In a second terminal:

```bash
cd tools/log-server
python3 test_client.py
```

You should see test messages appear in the server terminal.

### 3. Configure iOS App

Once local testing works, configure the iOS app's NetworkLogger with your Mac's IP.

## Server Options

```bash
# Basic usage (port 9999)
python3 log_server.py

# Custom port
python3 log_server.py --port 8888

# Write logs to file (for Claude Code to read)
python3 log_server.py --output /tmp/app_logs.txt

# Quiet mode (file only, no terminal output)
python3 log_server.py --output /tmp/app_logs.txt --quiet
```

## Test Client Options

```bash
# Run test suite
python3 test_client.py

# Test specific host
python3 test_client.py --host 192.168.1.100

# Interactive mode (type your own messages)
python3 test_client.py --interactive

# Just test connectivity
python3 test_client.py --connectivity
```

## Log Format

Logs are formatted in Apple unified log style:

```
2025-01-25 14:07:28.123 V4MinimalApp <Info> [CameraManager] Camera session started
2025-01-25 14:07:28.456 V4MinimalApp <Debug> [GeminiService] Analyzing frame...
2025-01-25 14:07:28.789 V4MinimalApp <Error> [GeminiService] API error: 429
```

## For Claude Code Debugging

To let Claude Code see the logs:

```bash
# Start server with file output
python3 log_server.py --output /tmp/app_logs.txt

# Claude can then read the logs:
# tail -100 /tmp/app_logs.txt
```

## Troubleshooting

### Server won't start - port in use
```bash
# Find what's using the port
lsof -i :9999

# Use a different port
python3 log_server.py --port 8888
```

### iPhone can't connect
1. Ensure both devices are on the same WiFi network
2. Check Mac firewall allows incoming connections
3. Verify the IP address is correct: `ipconfig getifaddr en0`
4. Try pinging the Mac from iPhone (use a network utility app)

### Messages not appearing
- Check that UDP port isn't blocked by firewall
- Verify the iOS app is configured with correct IP and port
- Use test_client.py to verify server is working
