#include "smc.h"

#include <IOKit/IOKitLib.h>
#include <string.h>

// Layout of the AppleSMC user client structure (stable since Intel Macs, also used on Apple silicon).
typedef struct { char major, minor, build, reserved; UInt16 release; } smc_vers_t;
typedef struct { UInt16 version, length; UInt32 cpu_limit, gpu_limit, mem_limit; } smc_plimit_t;
typedef struct { UInt32 data_size, data_type; char data_attributes; } smc_keyinfo_t;
typedef struct {
    UInt32 key;
    smc_vers_t vers;
    smc_plimit_t plimit;
    smc_keyinfo_t key_info;
    char result, status, command;
    UInt32 data32;
    unsigned char bytes[32];
} smc_param_t;

enum {
    SMC_KERNEL_INDEX = 2,
    SMC_CMD_READ_BYTES = 5,
    SMC_CMD_WRITE_BYTES = 6,
    SMC_CMD_READ_KEYINFO = 9,
};

static const UInt32 LED_KEY = ('A' << 24) | ('C' << 16) | ('L' << 8) | 'C';

static kern_return_t smc_call(io_connect_t conn, smc_param_t *in, smc_param_t *out) {
    size_t out_size = sizeof(smc_param_t);
    return IOConnectCallStructMethod(conn, SMC_KERNEL_INDEX, in, sizeof(smc_param_t), out, &out_size);
}

static lamba_smc_status smc_open(io_connect_t *conn) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return LAMBA_SMC_OPEN_FAILED;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, conn);
    IOObjectRelease(service);
    return kr == KERN_SUCCESS ? LAMBA_SMC_OK : LAMBA_SMC_OPEN_FAILED;
}

static lamba_smc_status led_key_size(io_connect_t conn, UInt32 *size) {
    smc_param_t in = {0}, out = {0};
    in.key = LED_KEY;
    in.command = SMC_CMD_READ_KEYINFO;
    if (smc_call(conn, &in, &out) != KERN_SUCCESS || out.result != 0 || out.key_info.data_size == 0) {
        return LAMBA_SMC_KEY_MISSING;
    }
    *size = out.key_info.data_size;
    return LAMBA_SMC_OK;
}

static lamba_smc_status led_transfer(int command, uint8_t *value) {
    io_connect_t conn;
    lamba_smc_status status = smc_open(&conn);
    if (status != LAMBA_SMC_OK) return status;

    UInt32 size = 0;
    status = led_key_size(conn, &size);
    if (status == LAMBA_SMC_OK) {
        smc_param_t in = {0}, out = {0};
        in.key = LED_KEY;
        in.command = (char)command;
        in.key_info.data_size = size;
        if (command == SMC_CMD_WRITE_BYTES) in.bytes[0] = *value;

        if (smc_call(conn, &in, &out) != KERN_SUCCESS || out.result != 0) {
            status = LAMBA_SMC_IO_FAILED;
        } else if (command == SMC_CMD_READ_BYTES) {
            *value = out.bytes[0];
        }
    }
    IOServiceClose(conn);
    return status;
}

lamba_smc_status lamba_smc_read_led(uint8_t *out_value) {
    return led_transfer(SMC_CMD_READ_BYTES, out_value);
}

lamba_smc_status lamba_smc_write_led(uint8_t value) {
    return led_transfer(SMC_CMD_WRITE_BYTES, &value);
}

// MARK: - Any key (fans, temperatures)

static UInt32 four_cc(const char *key) {
    return ((UInt32)(unsigned char)key[0] << 24) | ((UInt32)(unsigned char)key[1] << 16)
         | ((UInt32)(unsigned char)key[2] << 8) | (UInt32)(unsigned char)key[3];
}

/// Kept open: fans are read every couple of seconds.
static io_connect_t shared_conn = 0;

static lamba_smc_status shared_open(void) {
    if (shared_conn) return LAMBA_SMC_OK;
    return smc_open(&shared_conn);
}

static lamba_smc_status key_info(const char *key, UInt32 *size, UInt32 *type) {
    smc_param_t in = {0}, out = {0};
    in.key = four_cc(key);
    in.command = SMC_CMD_READ_KEYINFO;
    if (smc_call(shared_conn, &in, &out) != KERN_SUCCESS || out.result != 0 || out.key_info.data_size == 0) {
        return LAMBA_SMC_KEY_MISSING;
    }
    *size = out.key_info.data_size;
    if (type) *type = out.key_info.data_type;
    return LAMBA_SMC_OK;
}

lamba_smc_status lamba_smc_read_key(const char *key, uint8_t *bytes, uint32_t *size, uint32_t *type) {
    lamba_smc_status status = shared_open();
    if (status != LAMBA_SMC_OK) return status;
    UInt32 key_size = 0, key_type = 0;
    status = key_info(key, &key_size, &key_type);
    if (status != LAMBA_SMC_OK) return status;
    if (key_size > 32) return LAMBA_SMC_IO_FAILED;

    smc_param_t in = {0}, out = {0};
    in.key = four_cc(key);
    in.command = SMC_CMD_READ_BYTES;
    in.key_info.data_size = key_size;
    if (smc_call(shared_conn, &in, &out) != KERN_SUCCESS || out.result != 0) return LAMBA_SMC_IO_FAILED;
    memcpy(bytes, out.bytes, key_size);
    *size = key_size;
    if (type) *type = key_type;
    return LAMBA_SMC_OK;
}

lamba_smc_status lamba_smc_write_key(const char *key, const uint8_t *bytes, uint32_t size) {
    lamba_smc_status status = shared_open();
    if (status != LAMBA_SMC_OK) return status;
    UInt32 key_size = 0;
    status = key_info(key, &key_size, NULL);
    if (status != LAMBA_SMC_OK) return status;
    if (key_size != size || size > 32) return LAMBA_SMC_IO_FAILED;

    smc_param_t in = {0}, out = {0};
    in.key = four_cc(key);
    in.command = SMC_CMD_WRITE_BYTES;
    in.key_info.data_size = size;
    memcpy(in.bytes, bytes, size);
    if (smc_call(shared_conn, &in, &out) != KERN_SUCCESS || out.result != 0) return LAMBA_SMC_IO_FAILED;
    return LAMBA_SMC_OK;
}
