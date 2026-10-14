#ifndef TSK_TASKCHAMPION_H
#define TSK_TASKCHAMPION_H
#include <stdint.h>
char *tsk_bridge_request(const char *library, const char *input);
uint64_t tsk_bridge_sync_generation(const char *library, const char *path);
int tsk_bridge_interrupt_sync(const char *library, const char *path);
void tsk_bridge_free(char *output);
#endif
