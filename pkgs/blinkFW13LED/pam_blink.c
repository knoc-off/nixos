#define _GNU_SOURCE
#include <dlfcn.h>
#include <security/pam_appl.h>
#include <security/pam_modules.h>
#include <stdlib.h>
#include <stdio.h>

#ifndef BLINK_SCRIPT
#define BLINK_SCRIPT "/etc/nixos/pkgs/blinkFW13LED/testing.sh"
#endif

typedef int (*pam_sm_authenticate_t)(pam_handle_t *, int, int, const char **);

int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    static pam_sm_authenticate_t real_pam_sm_authenticate = NULL;

    printf("pam_blink.so: pam_sm_authenticate called\n");

    if (!real_pam_sm_authenticate) {
        real_pam_sm_authenticate = (pam_sm_authenticate_t)dlsym(RTLD_NEXT, "pam_sm_authenticate");
        if (!real_pam_sm_authenticate) {
            fprintf(stderr, "pam_blink.so: Failed to find real pam_sm_authenticate\n");
            return PAM_SYSTEM_ERR;
        }
    }

    // Start the LED blinking script
    int ret = system(BLINK_SCRIPT);
    if (ret != 0) {
        fprintf(stderr, "pam_blink.so: Failed to execute blink script: %d\n", ret);
    } else {
        printf("pam_blink.so: Blink script executed successfully\n");
    }

    // Call the real pam_sm_authenticate function
    return real_pam_sm_authenticate(pamh, flags, argc, argv);
}

