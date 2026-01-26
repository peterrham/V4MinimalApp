#!/usr/bin/env python3
"""
Test Client for V4MinimalApp Log Server

Sends test log messages to verify the server is working.
Run this AFTER starting log_server.py.

Usage:
    python3 test_client.py [--host HOST] [--port PORT]

Example:
    python3 test_client.py                    # Test localhost:9999
    python3 test_client.py --host 192.168.1.5 # Test specific host
"""

import socket
import argparse
import time
import sys


class LogClient:
    """TCP client for sending logs to the server."""

    def __init__(self, host: str, port: int):
        self.host = host
        self.port = port
        self.sock = None

    def connect(self) -> bool:
        """Establish TCP connection to the server."""
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.settimeout(5.0)
            self.sock.connect((self.host, self.port))
            return True
        except socket.timeout:
            print(f"ERROR: Connection timed out to {self.host}:{self.port}")
            return False
        except socket.error as e:
            print(f"ERROR: Could not connect to {self.host}:{self.port} - {e}")
            return False

    def send(self, message: str) -> bool:
        """Send a log message. Returns True if successful."""
        if not self.sock:
            return False
        try:
            self.sock.sendall((message + '\n').encode('utf-8'))
            return True
        except Exception as e:
            print(f"Error sending: {e}")
            return False

    def close(self):
        """Close the connection."""
        if self.sock:
            try:
                self.sock.close()
            except:
                pass
            self.sock = None


def run_tests(host: str, port: int):
    """Run a series of test log messages."""
    print(f"\n{'='*50}")
    print(f"Testing Log Server at {host}:{port} (TCP)")
    print(f"{'='*50}\n")

    client = LogClient(host, port)

    print("Connecting to server...")
    if not client.connect():
        print("\nFailed to connect. Make sure the server is running:")
        print("  python3 log_server.py")
        return False

    print("Connected!\n")

    # Test messages in various formats
    test_messages = [
        # Simple messages
        ("Simple message", "Hello from test client!"),

        # With log levels
        ("Debug level", "[DEBUG] [TestClient] This is a debug message"),
        ("Info level", "[INFO] [TestClient] This is an info message"),
        ("Notice level", "[NOTICE] [TestClient] This is a notice message"),
        ("Warning level", "[WARNING] [TestClient] This is a warning message"),
        ("Error level", "[ERROR] [TestClient] This is an error message"),
        ("Fault level", "[FAULT] [TestClient] This is a fault message"),

        # Simulating app logs
        ("Camera log", "[INFO] [CameraManager] Camera session started"),
        ("Gemini log", "[DEBUG] [GeminiService] Analyzing frame..."),
        ("Detection", "[INFO] [GeminiService] Detected: MacBook Pro, Coffee mug, Desk lamp"),
        ("API Error", "[ERROR] [GeminiService] API error: 429 Too Many Requests"),
        ("Frame capture", "[DEBUG] [CameraManager] Frame captured: 1920x1080"),

        # App logs
        ("Start log", "[INFO] [App] Starting detection"),
        ("Success", "[INFO] [App] Detection complete"),
    ]

    print("Sending test messages...\n")

    success_count = 0
    for name, message in test_messages:
        print(f"  [{name}] ", end="")
        if client.send(message):
            print("sent")
            success_count += 1
        else:
            print("FAILED")
        time.sleep(0.1)  # Small delay between messages

    client.close()

    print(f"\n{'='*50}")
    print(f"Results: {success_count}/{len(test_messages)} messages sent")
    print(f"{'='*50}")

    if success_count == len(test_messages):
        print("\nAll messages sent successfully!")
        print("Check the server terminal to see the formatted logs.\n")
        return True
    else:
        print("\nSome messages failed to send.")
        print("Make sure the server is running: python3 log_server.py\n")
        return False


def interactive_mode(host: str, port: int):
    """Interactive mode - type messages to send."""
    print(f"\n{'='*50}")
    print(f"Interactive Mode - Connecting to {host}:{port}")
    print(f"{'='*50}")

    client = LogClient(host, port)

    if not client.connect():
        print("Failed to connect. Make sure the server is running.")
        return

    print("Connected!")
    print("Type messages and press Enter to send.")
    print("Use format: [LEVEL] [Category] message")
    print("Type 'quit' to exit.\n")

    while True:
        try:
            message = input("> ").strip()
            if message.lower() == 'quit':
                print("Goodbye!")
                break
            if message:
                if not client.send(message):
                    print("Failed to send - connection may be lost")
                    break
        except (KeyboardInterrupt, EOFError):
            print("\nGoodbye!")
            break

    client.close()


def connectivity_test(host: str, port: int) -> bool:
    """
    Test TCP connectivity to the server.
    """
    print(f"\nTesting TCP connectivity to {host}:{port}...")

    client = LogClient(host, port)

    if client.connect():
        print(f"  SUCCESS: Connected to {host}:{port}")

        # Send a test message
        test_msg = "[INFO] [ConnectivityTest] Ping"
        if client.send(test_msg):
            print(f"  SUCCESS: Test message delivered")
        else:
            print(f"  ERROR: Failed to send test message")
            client.close()
            return False

        client.close()
        print(f"  Connection closed cleanly")
        return True
    else:
        print(f"  FAILED: Could not establish TCP connection")
        print(f"\n  Troubleshooting:")
        print(f"    1. Is the server running? python3 log_server.py")
        print(f"    2. Check Mac firewall: System Preferences > Security > Firewall")
        print(f"    3. Verify the IP address is correct")
        return False


def main():
    parser = argparse.ArgumentParser(
        description='Test client for V4MinimalApp Log Server (TCP)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                          # Run test suite on localhost:9999
  %(prog)s --host 192.168.1.5       # Test specific host
  %(prog)s -i                       # Interactive mode
  %(prog)s --connectivity           # Just test connectivity
        """
    )
    parser.add_argument('--host', type=str, default='127.0.0.1',
                        help='Server host (default: 127.0.0.1)')
    parser.add_argument('-p', '--port', type=int, default=9999,
                        help='Server port (default: 9999)')
    parser.add_argument('-i', '--interactive', action='store_true',
                        help='Interactive mode - type messages to send')
    parser.add_argument('-c', '--connectivity', action='store_true',
                        help='Just test connectivity, then exit')

    args = parser.parse_args()

    if args.connectivity:
        success = connectivity_test(args.host, args.port)
        sys.exit(0 if success else 1)

    if args.interactive:
        interactive_mode(args.host, args.port)
    else:
        success = run_tests(args.host, args.port)
        sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
