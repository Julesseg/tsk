#include "CTaskChampion.h"
#include <stdlib.h>
#include <string.h>
#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif
#if TARGET_OS_IPHONE
extern char *tsk_tc_request(const char *input);
extern void tsk_tc_free(char *output);
char *tsk_bridge_request(const char *library, const char *input) {
    char *rust_output = tsk_tc_request(input);
    if (!rust_output) return NULL;
    char *output = strdup(rust_output);
    tsk_tc_free(rust_output);
    return output;
}
#else
#include <dlfcn.h>
#include <pthread.h>
static pthread_mutex_t load_mutex = PTHREAD_MUTEX_INITIALIZER;
static void *loaded_library = NULL;
char *tsk_bridge_request(const char *library, const char *input) {
    pthread_mutex_lock(&load_mutex);
    if (!loaded_library) loaded_library = dlopen(library, RTLD_NOW | RTLD_LOCAL);
    void *handle = loaded_library;
    pthread_mutex_unlock(&load_mutex);
    if (!handle) return NULL;
    char *(*request)(const char *) = dlsym(handle, "tsk_tc_request");
    void (*release)(char *) = dlsym(handle, "tsk_tc_free");
    char *output = NULL;
    if (request && release) {
        char *rust_output = request(input);
        if (rust_output) { output = strdup(rust_output); release(rust_output); }
    }
    return output;
}
#endif
void tsk_bridge_free(char *output) { free(output); }
