#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <os/log.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include <dlfcn.h>
#include <CoreFoundation/CoreFoundation.h>

// Send a log message directly to the TCP log server
static void send_early_log(const char *message) {
    // Read server settings from UserDefaults
    // Keys: "logServerHost" and "logServerPort"

    CFStringRef hostKey = CFStringCreateWithCString(NULL, "logServerHost", kCFStringEncodingUTF8);
    CFStringRef portKey = CFStringCreateWithCString(NULL, "logServerPort", kCFStringEncodingUTF8);

    CFPropertyListRef hostValue = CFPreferencesCopyAppValue(hostKey, kCFPreferencesCurrentApplication);
    CFPropertyListRef portValue = CFPreferencesCopyAppValue(portKey, kCFPreferencesCurrentApplication);

    CFRelease(hostKey);
    CFRelease(portKey);

    if (!hostValue) {
        // No server configured
        return;
    }

    char host[256] = {0};
    int port = 9999;

    if (CFGetTypeID(hostValue) == CFStringGetTypeID()) {
        CFStringGetCString((CFStringRef)hostValue, host, sizeof(host), kCFStringEncodingUTF8);
    }
    CFRelease(hostValue);

    if (portValue) {
        if (CFGetTypeID(portValue) == CFStringGetTypeID()) {
            char portStr[16];
            CFStringGetCString((CFStringRef)portValue, portStr, sizeof(portStr), kCFStringEncodingUTF8);
            port = atoi(portStr);
        }
        CFRelease(portValue);
    }

    if (strlen(host) == 0) {
        return;
    }

    // Create TCP socket and connect
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        return;
    }

    // Set short timeout for early boot (don't block app startup)
    struct timeval timeout;
    timeout.tv_sec = 1;
    timeout.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    struct sockaddr_in server_addr;
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(port);

    if (inet_pton(AF_INET, host, &server_addr.sin_addr) <= 0) {
        close(sock);
        return;
    }

    if (connect(sock, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        close(sock);
        return;
    }

    // Send the message with newline
    char buffer[1024];
    snprintf(buffer, sizeof(buffer), "%s\n", message);
    send(sock, buffer, strlen(buffer), 0);

    close(sock);
}

__attribute__((constructor))
static void early_init_constructor(void) {
    // This runs when the app's image is loaded by dyld, before Swift @main or AppDelegate

    // Get precise timestamp
    struct timeval tv;
    gettimeofday(&tv, NULL);
    struct tm *tm_info = localtime(&tv.tv_sec);
    char timestamp[64];
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", tm_info);

    // Format with milliseconds
    char full_timestamp[128];
    snprintf(full_timestamp, sizeof(full_timestamp), "%s.%03d", timestamp, (int)(tv.tv_usec / 1000));

    // Build log message
    char log_message[512];
    snprintf(log_message, sizeof(log_message),
             "[INFO] [EarlyBoot] [EarlyInit.c:0] [%s] C constructor ran - FIRST possible log point (before Swift) early_init_constructor",
             full_timestamp);

    // Log to stderr
    fprintf(stderr, "%s\n", log_message);

    // Log to os_log (unified logging)
    os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "[EARLY_BOOT] C constructor ran - first possible log point (before Swift)");

    // Send directly to TCP log server
    send_early_log(log_message);
}
