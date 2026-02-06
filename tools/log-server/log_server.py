#!/usr/bin/env python3
"""
V4MinimalApp Log Server

Receives logs from the iOS app over TCP and displays them in unified log format.
Also receives screenshots on a separate port for visual debugging.
Writes logs to a file that Claude Code can read for debugging.

Usage:
    python3 log_server.py [--port PORT] [--screenshot-port PORT] [--output FILE] [--rotate MINUTES]

Example:
    python3 log_server.py -o /tmp/app_logs.txt              # Rotate every 15 min (default)
    python3 log_server.py -o /tmp/app_logs.txt --rotate 30   # Rotate every 30 min
    python3 log_server.py -o /tmp/app_logs.txt --rotate 0    # No rotation (single file)
"""

import socket
import argparse
import datetime
import sys
import os
import signal
import threading
import struct
from pathlib import Path

# ANSI colors for terminal output
class Colors:
    RESET = '\033[0m'
    BOLD = '\033[1m'
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    MAGENTA = '\033[95m'
    CYAN = '\033[96m'
    GRAY = '\033[90m'

# Log level colors (matching Apple's unified logging)
LEVEL_COLORS = {
    'debug': Colors.GRAY,
    'info': Colors.RESET,
    'notice': Colors.CYAN,
    'warning': Colors.YELLOW,
    'error': Colors.RED,
    'fault': Colors.RED + Colors.BOLD,
}

LEVEL_SYMBOLS = {
    'debug': 'D',
    'info': 'I',
    'notice': 'N',
    'warning': 'W',
    'error': 'E',
    'fault': 'F',
}


def get_local_ip():
    """Get the Mac's local IP address for display."""
    try:
        # Create a socket to determine the local IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def format_unified_log(message: str, timestamp: datetime.datetime = None) -> str:
    """Format a log message in Apple unified log style."""
    if timestamp is None:
        timestamp = datetime.datetime.now()

    # Parse the incoming message to extract level and category if present
    # Expected format from iOS: "[LEVEL] [Category] message" or just "message"
    level = 'info'
    category = 'Default'
    text = message

    # Try to parse structured log format
    if message.startswith('['):
        parts = message.split('] ', 2)
        if len(parts) >= 2:
            level_str = parts[0][1:].lower()
            if level_str in LEVEL_COLORS:
                level = level_str
                remaining = '] '.join(parts[1:])
                if remaining.startswith('['):
                    cat_end = remaining.find(']')
                    if cat_end > 0:
                        category = remaining[1:cat_end]
                        text = remaining[cat_end+2:] if cat_end+2 < len(remaining) else ""
                else:
                    text = remaining
            else:
                # First bracket wasn't a level, might be category
                category = parts[0][1:]
                text = '] '.join(parts[1:])

    # Format timestamp like unified log
    ts_str = timestamp.strftime('%Y-%m-%d %H:%M:%S.') + f'{timestamp.microsecond // 1000:03d}'

    # Build the log line (unified log style)
    log_line = f"{ts_str} V4MinimalApp <{level.capitalize()}> [{category}] {text}"

    return log_line, level


def colorize_log(log_line: str, level: str) -> str:
    """Add ANSI colors to a log line for terminal display."""
    color = LEVEL_COLORS.get(level, Colors.RESET)
    return f"{color}{log_line}{Colors.RESET}"


class ScreenshotServer:
    """Handles incoming screenshots on a separate port."""

    def __init__(self, port: int, output_dir: str, quiet: bool = False):
        self.port = port
        self.output_dir = output_dir
        self.quiet = quiet
        self.running = False
        self.server_socket = None
        self.clients = []
        self.lock = threading.Lock()
        self.screenshot_count = 0

        # Create output directory
        Path(output_dir).mkdir(parents=True, exist_ok=True)

    def handle_client(self, client_socket, addr):
        """Handle a single screenshot client connection."""
        if not self.quiet:
            print(f"{Colors.MAGENTA}Screenshot client connected: {addr[0]}:{addr[1]}{Colors.RESET}")

        try:
            while self.running:
                try:
                    # Protocol:
                    # 1. Read 8 bytes for timestamp length (big-endian uint64)
                    # 2. Read timestamp string
                    # 3. Read 8 bytes for image size (big-endian uint64)
                    # 4. Read image data

                    # Read timestamp length
                    ts_len_data = self._recv_exact(client_socket, 8)
                    if not ts_len_data:
                        break
                    ts_len = struct.unpack('>Q', ts_len_data)[0]

                    # Read timestamp
                    ts_data = self._recv_exact(client_socket, ts_len)
                    if not ts_data:
                        break
                    timestamp = ts_data.decode('utf-8')

                    # Read image size
                    img_len_data = self._recv_exact(client_socket, 8)
                    if not img_len_data:
                        break
                    img_len = struct.unpack('>Q', img_len_data)[0]

                    # Read image data
                    img_data = self._recv_exact(client_socket, img_len)
                    if not img_data:
                        break

                    # Save the screenshot
                    safe_ts = timestamp.replace(':', '-').replace(' ', '_').replace('.', '-')
                    filename = f"screenshot_{safe_ts}.jpg"
                    filepath = os.path.join(self.output_dir, filename)

                    with open(filepath, 'wb') as f:
                        f.write(img_data)

                    self.screenshot_count += 1

                    if not self.quiet:
                        size_kb = len(img_data) / 1024
                        print(f"{Colors.MAGENTA}[Screenshot #{self.screenshot_count}] {filename} ({size_kb:.1f} KB){Colors.RESET}")

                except socket.timeout:
                    continue
                except Exception as e:
                    if self.running and not self.quiet:
                        print(f"{Colors.RED}Screenshot error from {addr}: {e}{Colors.RESET}")
                    break

        finally:
            client_socket.close()
            with self.lock:
                if client_socket in self.clients:
                    self.clients.remove(client_socket)
            if not self.quiet:
                print(f"{Colors.YELLOW}Screenshot client disconnected: {addr[0]}:{addr[1]}{Colors.RESET}")

    def _recv_exact(self, sock, n):
        """Receive exactly n bytes from socket."""
        data = b''
        while len(data) < n:
            try:
                chunk = sock.recv(n - len(data))
                if not chunk:
                    return None
                data += chunk
            except socket.timeout:
                if not self.running:
                    return None
                continue
        return data

    def run(self):
        """Run the screenshot server."""
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

        try:
            self.server_socket.bind(('0.0.0.0', self.port))
            self.server_socket.listen(5)
            self.server_socket.settimeout(1.0)
        except OSError as e:
            print(f"{Colors.RED}Error: Could not bind screenshot server to port {self.port}: {e}{Colors.RESET}")
            return

        self.running = True

        while self.running:
            try:
                client_socket, addr = self.server_socket.accept()
                client_socket.settimeout(5.0)
                with self.lock:
                    self.clients.append(client_socket)

                thread = threading.Thread(target=self.handle_client, args=(client_socket, addr))
                thread.daemon = True
                thread.start()

            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    print(f"{Colors.RED}Screenshot server error: {e}{Colors.RESET}")

    def shutdown(self):
        """Shutdown the screenshot server."""
        self.running = False

        with self.lock:
            for client in self.clients:
                try:
                    client.close()
                except:
                    pass
            self.clients.clear()

        if self.server_socket:
            try:
                self.server_socket.close()
            except:
                pass


class LogServer:
    def __init__(self, port: int, output_file: str = None, quiet: bool = False,
                 rotate_minutes: int = 0):
        self.port = port
        self.output_file = output_file
        self.quiet = quiet
        self.rotate_minutes = rotate_minutes
        self.running = False
        self.server_socket = None
        self.out_file = None
        self.clients = []
        self.lock = threading.Lock()
        self.rotation_timer = None
        self.current_log_path = None

    def handle_client(self, client_socket, addr):
        """Handle a single client connection."""
        if not self.quiet:
            print(f"{Colors.GREEN}Client connected: {addr[0]}:{addr[1]}{Colors.RESET}")

        buffer = ""
        try:
            while self.running:
                try:
                    data = client_socket.recv(4096)
                    if not data:
                        break

                    buffer += data.decode('utf-8', errors='replace')

                    # Process complete lines
                    while '\n' in buffer:
                        line, buffer = buffer.split('\n', 1)
                        line = line.strip()

                        if not line:
                            continue

                        # Format the log
                        log_line, level = format_unified_log(line)

                        # Write to file (plain text)
                        if self.out_file:
                            with self.lock:
                                self.out_file.write(log_line + '\n')
                                self.out_file.flush()

                        # Print to terminal (with colors)
                        if not self.quiet:
                            print(colorize_log(log_line, level))

                except socket.timeout:
                    continue
                except Exception as e:
                    if self.running and not self.quiet:
                        print(f"{Colors.RED}Error receiving from {addr}: {e}{Colors.RESET}")
                    break

        finally:
            client_socket.close()
            with self.lock:
                if client_socket in self.clients:
                    self.clients.remove(client_socket)
            if not self.quiet:
                print(f"{Colors.YELLOW}Client disconnected: {addr[0]}:{addr[1]}{Colors.RESET}")

    def _make_rotated_path(self):
        """Generate a log file path with timestamp for rotation."""
        base = self.output_file
        ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
        # e.g. /tmp/app_logs.txt -> /tmp/app_logs_20260205_195300.txt
        root, ext = os.path.splitext(base)
        return f"{root}_{ts}{ext}"

    def _open_log_file(self):
        """Open the log output file, with timestamped name if rotation is enabled."""
        if not self.output_file:
            return

        if self.rotate_minutes > 0:
            rotated_path = self._make_rotated_path()
            self.current_log_path = rotated_path
        else:
            self.current_log_path = self.output_file

        self.out_file = open(self.current_log_path, 'a', buffering=1)

        # If rotating, also maintain a symlink at the base path for easy access
        if self.rotate_minutes > 0:
            try:
                if os.path.islink(self.output_file) or os.path.exists(self.output_file):
                    os.remove(self.output_file)
                os.symlink(self.current_log_path, self.output_file)
            except OSError:
                pass  # Symlink may fail on some systems, that's fine

        print(f"{Colors.CYAN}Writing logs to: {self.current_log_path}{Colors.RESET}")

    def _rotate_log(self):
        """Rotate the log file: close current, open new with fresh timestamp."""
        if not self.running or not self.output_file:
            return

        with self.lock:
            old_path = self.current_log_path
            if self.out_file:
                self.out_file.close()
            self._open_log_file()

        if not self.quiet:
            print(f"{Colors.CYAN}Log rotated: {old_path} -> {self.current_log_path}{Colors.RESET}")

        self._schedule_rotation()

    def _schedule_rotation(self):
        """Schedule the next log rotation."""
        if self.rotate_minutes > 0 and self.running:
            self.rotation_timer = threading.Timer(self.rotate_minutes * 60, self._rotate_log)
            self.rotation_timer.daemon = True
            self.rotation_timer.start()

    def run(self):
        """Run the TCP log server."""
        local_ip = get_local_ip()

        # Create TCP socket
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

        try:
            self.server_socket.bind(('0.0.0.0', self.port))
            self.server_socket.listen(5)
            self.server_socket.settimeout(1.0)  # Allow checking for shutdown
        except OSError as e:
            print(f"{Colors.RED}Error: Could not bind to port {self.port}: {e}{Colors.RESET}")
            sys.exit(1)

        self.running = True

        # Open output file if specified
        self._open_log_file()

        # Start rotation timer if enabled
        self._schedule_rotation()

        # Main accept loop
        while self.running:
            try:
                client_socket, addr = self.server_socket.accept()
                client_socket.settimeout(1.0)
                with self.lock:
                    self.clients.append(client_socket)

                # Handle client in a new thread
                thread = threading.Thread(target=self.handle_client, args=(client_socket, addr))
                thread.daemon = True
                thread.start()

            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    print(f"{Colors.RED}Error accepting connection: {e}{Colors.RESET}")

    def shutdown(self):
        """Gracefully shutdown the server."""
        print(f"\n{Colors.YELLOW}Shutting down...{Colors.RESET}")
        self.running = False

        # Cancel rotation timer
        if self.rotation_timer:
            self.rotation_timer.cancel()

        # Close all client connections
        with self.lock:
            for client in self.clients:
                try:
                    client.close()
                except:
                    pass
            self.clients.clear()

        # Close server socket
        if self.server_socket:
            try:
                self.server_socket.close()
            except:
                pass

        # Close output file
        if self.out_file:
            try:
                self.out_file.close()
            except:
                pass


def main():
    parser = argparse.ArgumentParser(
        description='V4MinimalApp Log Server - Receives logs and screenshots from iOS app over TCP',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                          # Listen on port 9999 (logs) and 9998 (screenshots)
  %(prog)s --port 8888              # Listen on port 8888 for logs
  %(prog)s -o /tmp/app_logs.txt     # Write logs to file (rotate every 15 min)
  %(prog)s -o /tmp/logs.txt -r 30   # Rotate every 30 minutes
  %(prog)s -o /tmp/logs.txt -r 0    # No rotation (single file)
  %(prog)s -o /tmp/logs.txt -q      # Write to file only (quiet mode)
        """
    )
    parser.add_argument('-p', '--port', type=int, default=9999,
                        help='TCP port for logs (default: 9999)')
    parser.add_argument('-s', '--screenshot-port', type=int, default=9998,
                        help='TCP port for screenshots (default: 9998)')
    parser.add_argument('-o', '--output', type=str, default=None,
                        help='Output file to write logs (for Claude Code to read)')
    parser.add_argument('--screenshot-dir', type=str, default='/tmp/app_screenshots',
                        help='Directory to save screenshots (default: /tmp/app_screenshots)')
    parser.add_argument('-q', '--quiet', action='store_true',
                        help='Quiet mode - only write to file, no terminal output')
    parser.add_argument('-r', '--rotate', type=int, default=15, metavar='MINUTES',
                        help='Rotate log file every N minutes (default: 15, 0 to disable)')

    args = parser.parse_args()

    if args.quiet and not args.output:
        print(f"{Colors.RED}Error: --quiet requires --output{Colors.RESET}")
        sys.exit(1)

    local_ip = get_local_ip()

    # Print startup banner
    print(f"\n{Colors.BOLD}{'='*60}{Colors.RESET}")
    print(f"{Colors.GREEN}V4MinimalApp Log Server Started (TCP){Colors.RESET}")
    print(f"{Colors.BOLD}{'='*60}{Colors.RESET}")
    print(f"  Log server:        {Colors.CYAN}{local_ip}:{args.port}{Colors.RESET}")
    print(f"  Screenshot server: {Colors.MAGENTA}{local_ip}:{args.screenshot_port}{Colors.RESET}")
    print(f"  Screenshot dir:    {Colors.MAGENTA}{args.screenshot_dir}{Colors.RESET}")
    if args.output:
        print(f"  Log file:          {Colors.CYAN}{args.output}{Colors.RESET}")
    if args.rotate > 0:
        print(f"  Log rotation:      {Colors.CYAN}every {args.rotate} minutes{Colors.RESET}")
    else:
        print(f"  Log rotation:      {Colors.GRAY}disabled{Colors.RESET}")
    print(f"\n  {Colors.YELLOW}Configure iOS app with:{Colors.RESET}")
    print(f"    Host: {Colors.BOLD}{local_ip}{Colors.RESET}")
    print(f"    Log Port: {Colors.BOLD}{args.port}{Colors.RESET}")
    print(f"    Screenshot Port: {Colors.BOLD}{args.screenshot_port}{Colors.RESET}")
    print(f"\n{Colors.GRAY}Waiting for connections... (Ctrl+C to stop){Colors.RESET}\n")

    # Create servers
    log_server = LogServer(args.port, args.output, args.quiet, args.rotate)
    screenshot_server = ScreenshotServer(args.screenshot_port, args.screenshot_dir, args.quiet)

    # Handle graceful shutdown
    def signal_handler(sig, frame):
        log_server.shutdown()
        screenshot_server.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Start screenshot server in a thread
    screenshot_thread = threading.Thread(target=screenshot_server.run)
    screenshot_thread.daemon = True
    screenshot_thread.start()

    # Run log server in main thread
    log_server.run()


if __name__ == '__main__':
    main()
