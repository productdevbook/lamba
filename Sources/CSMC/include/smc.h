#ifndef LAMBA_SMC_H
#define LAMBA_SMC_H

#include <stdint.h>

typedef enum {
    LAMBA_SMC_OK = 0,
    LAMBA_SMC_OPEN_FAILED = 1,   // AppleSMC service not found or could not be opened
    LAMBA_SMC_KEY_MISSING = 2,   // This Mac has no MagSafe LED key
    LAMBA_SMC_IO_FAILED = 3,     // Read/write rejected (usually: not running as root)
} lamba_smc_status;

/// Reads the MagSafe LED key (ACLC).
lamba_smc_status lamba_smc_read_led(uint8_t *out_value);

/// Writes the MagSafe LED key (ACLC). Requires root.
lamba_smc_status lamba_smc_write_led(uint8_t value);

/// Reads any SMC key (4 characters). `bytes` gets up to 32 bytes; `size` and `type` (four-char
/// code) describe them. Works without root for most keys.
lamba_smc_status lamba_smc_read_key(const char *key, uint8_t *bytes, uint32_t *size, uint32_t *type);

/// Writes any SMC key with exactly its own size. Requires root.
lamba_smc_status lamba_smc_write_key(const char *key, const uint8_t *bytes, uint32_t size);

#endif
