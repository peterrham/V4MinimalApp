#!/usr/bin/env python3
"""
Simple UDP log server for receiving logs from iOS app.
Run this on your Mac, then the iOS app will stream logs here.
"""

import socket
import datetime
import sys
import re

# ANSI colors for terminal output
class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

def colorize_log(message):
    """Add colors based on log content"""
    if '❌' in message or 'error' in message.lower() or 'Error' in message:
        return Colors.RED + message + Colors.ENDC
    elif '✅' in message or 'success' in message.lower():
        return Colors.GREEN + message + Colors.ENDC
    elif '⚠️' in message or 'warning' in message.lower():
        return Colors.YELLOW + message + Colors.ENDC
    elif 'Detected:' in message or '🎥' in message:
        return Colors.CYAN + message + Colors.ENDC
    elif 'API' in message or 'Gemini' in message:
        return Colors.BLUE + message + Colors.ENDC
    return message

def main():
    # Get local IP for display
    hostname = socket.gethostname()
    try:
        local_ip = socket.gethostbyname(hostname + ".local")
    except:
        local_ip = socket.gethostbyname(hostname)

    port = 9999

    # Create UDP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(('0.0.0.0', port))

    print(f"{Colors.BOLD}{'='*60}{Colors.ENDC}")
    print(f"{Colors.GREEN}📱 iOS Log Server Started{Colors.ENDC}")
    print(f"{Colors.BOLD}{'='*60}{Colors.ENDC}")
    print(f"Listening on: {Colors.CYAN}{local_ip}:{port}{Colors.ENDC}")
    print(f"Waiting for logs from V4MinimalApp...")
    print(f"{Colors.BOLD}{'='*60}{Colors.ENDC}\n")

    filter_pattern = sys.argv[1] if len(sys.argv) > 1 else None
    if filter_pattern:
        print(f"Filtering for: {filter_pattern}\n")

    try:
        while True:
            data, addr = sock.recvfrom(4096)
            message = data.decode('utf-8', errors='replace')

            # Apply filter if specified
            if filter_pattern and filter_pattern.lower() not in message.lower():
                continue

            timestamp = datetime.datetime.now().strftime('%H:%M:%S.%f')[:-3]
            colored_msg = colorize_log(message)
            print(f"{Colors.BOLD}[{timestamp}]{Colors.ENDC} {colored_msg}")

    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}Server stopped.{Colors.ENDC}")
        sock.close()

if __name__ == '__main__':
    main()
