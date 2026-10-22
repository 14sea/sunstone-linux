#pragma once
#include <stdint.h>

/* Boot the SWEETLNX payload at pl (behind _end); returns only on error. */
const char *linux_boot(uintptr_t pl);
