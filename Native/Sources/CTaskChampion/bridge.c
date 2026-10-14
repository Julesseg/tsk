#include "CTaskChampion.h"
#include <stdlib.h>
#include <string.h>
#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif
#if TARGET_OS_IPHONE
extern char *tsk_tc_request(const char *input);
extern void tsk_tc_free(char *output);
extern int tsk_tc_interrupt_sync(const char *path);
extern uint64_t tsk_tc_sync_generation(const char *path);
uint64_t tsk_bridge_sync_generation(const char *library, const char *path) {
    return tsk_tc_sync_generation(path);
}
int tsk_bridge_interrupt_sync(const char *library, const char *path) {
    return tsk_tc_interrupt_sync(path);
}
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
static void *load_library(const char *library) {
    pthread_mutex_lock(&load_mutex);
    if (!loaded_library) loaded_library = dlopen(library, RTLD_NOW | RTLD_LOCAL);
    void *handle = loaded_library;
    pthread_mutex_unlock(&load_mutex);
    return handle;
}
uint64_t tsk_bridge_sync_generation(const char *library, const char *path) {
    void *handle = load_library(library);
    if (!handle) return 0;
    uint64_t (*generation)(const char *) = dlsym(handle, "tsk_tc_sync_generation");
    return generation ? generation(path) : 0;
}
int tsk_bridge_interrupt_sync(const char *library, const char *path) {
    void *handle = load_library(library);
    if (!handle) return 0;
    int (*interrupt)(const char *) = dlsym(handle, "tsk_tc_interrupt_sync");
    return interrupt ? interrupt(path) : 0;
}
char *tsk_bridge_request(const char *library, const char *input) {
    void *handle = load_library(library);
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

#include <errno.h>
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>

int tsk_bridge_acquire_mutation(const char *path) {
    int descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0600);
    if (descriptor < 0) return -errno;
    while (flock(descriptor, LOCK_EX) != 0) {
        if (errno == EINTR) continue;
        int error = errno;
        close(descriptor);
        return -error;
    }
    return descriptor;
}

void tsk_bridge_release_mutation(int descriptor) {
    flock(descriptor, LOCK_UN);
    close(descriptor);
}
