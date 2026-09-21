//
//  receiver_name.c
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

#include "include/receiver_name.h"

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
