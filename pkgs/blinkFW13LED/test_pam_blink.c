#include <stdlib.h>
#include <stdio.h>
#include <security/pam_appl.h>
#include <security/pam_modules.h>
#include <security/pam_misc.h>

// Conversation function for PAM
int pam_conversation(int num_msg, const struct pam_message **msg,
                     struct pam_response **resp, void *appdata_ptr) {
    return PAM_SUCCESS;
}

int main() {

    // get and print the vaule in LD_PRELOAD
    char *ld_preload = getenv("LD_PRELOAD");
    printf("LD_PRELOAD: %s\n", ld_preload);



    // PAM conversation structure
    struct pam_conv conv = {
        .conv = pam_conversation,
        .appdata_ptr = NULL
    };

    // Load the PAM module
    pam_handle_t *pamh = NULL;
    int retval = pam_start("test", NULL, &conv, &pamh);
    if (retval != PAM_SUCCESS) {
        fprintf(stderr, "pam_start failed\n");
        return 1;
    }

    // Call the pam_authenticate function
    retval = pam_authenticate(pamh, 0);
    if (retval != PAM_SUCCESS) {
        fprintf(stderr, "pam_authenticate failed\n");
        pam_end(pamh, retval);
        return 1;
    }

    printf("pam_authenticate succeeded\n");

    // End the PAM transaction
    pam_end(pamh, retval);

    return 0;
}

