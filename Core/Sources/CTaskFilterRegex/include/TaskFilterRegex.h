#ifndef TSK_FILTER_REGEX_H
#define TSK_FILTER_REGEX_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct TskFilterRegex TskFilterRegex;
TskFilterRegex *tsk_filter_regex_create(const char *pattern, size_t length, char **error);
int tsk_filter_regex_search(const TskFilterRegex *pattern, const char *text, size_t length);
void tsk_filter_regex_destroy(TskFilterRegex *pattern);
void tsk_filter_regex_error_free(char *error);
#ifdef __cplusplus
}
#endif
#endif
