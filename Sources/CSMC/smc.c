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
