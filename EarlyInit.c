#include <stdio.h>
#include <os/log.h>

__attribute__((constructor))
static void early_init_constructor(void) {
    // This runs when the app's image is loaded by dyld, before Swift @main or AppDelegate
    fprintf(stderr, "[INTENTIONAL] first possible place to log to stderr, constructor ran\n");
    os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "[INTENTIONAL] first possible place to log to stderr, constructor ran");
}
