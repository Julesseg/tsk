#include "TaskFilterRegex.h"
#include <cstdlib>
#include <cstring>
#include <regex>
#include <string>

struct TskFilterRegex {
    std::regex expression;
    explicit TskFilterRegex(const std::string &pattern) : expression(pattern, std::regex_constants::ECMAScript) {}
};

extern "C" TskFilterRegex *tsk_filter_regex_create(const char *pattern, size_t length, char **error) {
    *error = nullptr;
    try {
        return new TskFilterRegex(std::string(pattern ? pattern : "", length));
    } catch (const std::exception &failure) {
        const auto message = std::string(failure.what());
        *error = static_cast<char *>(std::malloc(message.size() + 1));
        if (*error) std::memcpy(*error, message.c_str(), message.size() + 1);
        return nullptr;
    }
}

extern "C" int tsk_filter_regex_search(const TskFilterRegex *pattern, const char *text, size_t length) {
    try {
        const std::string value(text ? text : "", length);
        return std::regex_search(value, pattern->expression) ? 1 : 0;
    } catch (...) {
        return -1;
    }
}

extern "C" void tsk_filter_regex_destroy(TskFilterRegex *pattern) { delete pattern; }
extern "C" void tsk_filter_regex_error_free(char *error) { std::free(error); }
