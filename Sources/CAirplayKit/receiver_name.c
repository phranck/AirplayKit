//
//  receiver_name.c
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

#include "include/receiver_name.h"

#include <ctype.h>
#include <string.h>

void pa_split_instance_name(const char *instance, char *identifier, size_t identifierSize,
                            char *name, size_t nameSize) {
    if (!instance || !identifier || !name || identifierSize == 0 || nameSize == 0) return;

    identifier[0] = '\0';
    name[0] = '\0';

    const char *separator = strchr(instance, '@');

    if (!separator) {
        strncpy(identifier, instance, identifierSize - 1);
        identifier[identifierSize - 1] = '\0';
        strncpy(name, instance, nameSize - 1);
        name[nameSize - 1] = '\0';
        return;
    }

    const size_t addressLength = (size_t)(separator - instance);
    const size_t copied = addressLength < identifierSize - 1 ? addressLength : identifierSize - 1;
    memcpy(identifier, instance, copied);
    identifier[copied] = '\0';

    strncpy(name, separator + 1, nameSize - 1);
    name[nameSize - 1] = '\0';
}

void pa_unescape_instance_name(const char *escaped, char *plain, size_t plainSize) {
    if (!plain || plainSize == 0) return;

    plain[0] = '\0';
    if (!escaped) return;

    size_t written = 0;
    const char *cursor = escaped;

    while (*cursor && written + 1 < plainSize) {
        if (*cursor != '\\') {
            plain[written++] = *cursor++;
            continue;
        }

        cursor++;
        if (*cursor == '\0') break;

        // Three decimal digits stand for one byte. Anything else after the
        // backslash is that character itself, which is how a dot inside a label
        // and a backslash are carried.
        if (isdigit((unsigned char)cursor[0]) && isdigit((unsigned char)cursor[1])
            && isdigit((unsigned char)cursor[2])) {
            const int value = (cursor[0] - '0') * 100 + (cursor[1] - '0') * 10 + (cursor[2] - '0');
            plain[written++] = (char)value;
            cursor += 3;
            continue;
        }

        plain[written++] = *cursor++;
    }

    plain[written] = '\0';
}

void pa_identity_from_device_id(const char *deviceID, char *identifier, size_t identifierSize) {
    if (!identifier || identifierSize == 0) return;

    identifier[0] = '\0';
    if (!deviceID) return;

    size_t written = 0;
    for (const char *cursor = deviceID; *cursor && written + 1 < identifierSize; cursor++) {
        // Cast through unsigned char, because these take an int that has to be
        // representable as one, and a char is signed on most machines.
        const unsigned char character = (unsigned char)*cursor;
        if (!isxdigit(character)) continue;

        identifier[written++] = (char)toupper(character);
    }

    identifier[written] = '\0';
}
