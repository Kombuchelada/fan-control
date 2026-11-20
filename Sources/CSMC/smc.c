#include "smc.h"
#include <string.h>

// Layout of the structure exchanged with AppleSMC's user client.
// Field order and sizes must match the kernel's definition exactly (80 bytes).

enum {
    kSMCUserClientHandleYPCEvent = 2,
    kSMCCmdReadBytes   = 5,
    kSMCCmdWriteBytes  = 6,
    kSMCCmdReadIndex   = 8,
    kSMCCmdReadKeyInfo = 9,
};

typedef struct {
    uint8_t  major;
    uint8_t  minor;
    uint8_t  build;
    uint8_t  reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t  dataAttributes;
} SMCKeyInfo;

typedef struct {
    uint32_t      key;
    SMCVersion    vers;
    SMCPLimitData pLimitData;
    SMCKeyInfo    keyInfo;
    uint8_t       result;
    uint8_t       status;
    uint8_t       data8;
    uint32_t      data32;
    uint8_t       bytes[32];
} SMCParamStruct;

_Static_assert(sizeof(SMCParamStruct) == 80, "SMCParamStruct must be 80 bytes");

static kern_return_t SMCCall(io_connect_t connection, SMCParamStruct *input, SMCParamStruct *output) {
    size_t outputSize = sizeof(SMCParamStruct);
    kern_return_t result = IOConnectCallStructMethod(connection,
                                                     kSMCUserClientHandleYPCEvent,
                                                     input, sizeof(SMCParamStruct),
                                                     output, &outputSize);
    if (result != KERN_SUCCESS) return result;
    // A non-zero result byte is an SMC-level error (e.g. 0x84 = key not found).
    if (output->result != 0) return kIOReturnError;
    return KERN_SUCCESS;
}

kern_return_t SMCOpen(io_connect_t *connection) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == IO_OBJECT_NULL) return kIOReturnNotFound;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, connection);
    IOObjectRelease(service);
    return result;
}

kern_return_t SMCClose(io_connect_t connection) {
    return IOServiceClose(connection);
}

static kern_return_t SMCGetKeyInfo(io_connect_t connection, uint32_t key, SMCKeyInfo *info) {
    SMCParamStruct input, output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.data8 = kSMCCmdReadKeyInfo;
    kern_return_t result = SMCCall(connection, &input, &output);
    if (result == KERN_SUCCESS) *info = output.keyInfo;
    return result;
}

kern_return_t SMCReadKey(io_connect_t connection, uint32_t key, SMCValue *value) {
    memset(value, 0, sizeof(*value));
    value->key = key;

    SMCKeyInfo info;
    kern_return_t result = SMCGetKeyInfo(connection, key, &info);
    if (result != KERN_SUCCESS) return result;

    SMCParamStruct input, output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.keyInfo.dataSize = info.dataSize;
    input.data8 = kSMCCmdReadBytes;
    result = SMCCall(connection, &input, &output);
    if (result != KERN_SUCCESS) return result;

    value->dataType = info.dataType;
    value->dataSize = info.dataSize > 32 ? 32 : info.dataSize;
    memcpy(value->bytes, output.bytes, value->dataSize);
    return KERN_SUCCESS;
}

kern_return_t SMCWriteKey(io_connect_t connection, uint32_t key, const uint8_t *bytes, uint32_t size) {
    SMCKeyInfo info;
    kern_return_t result = SMCGetKeyInfo(connection, key, &info);
    if (result != KERN_SUCCESS) return result;
    if (info.dataSize != size || size > 32) return kIOReturnBadArgument;

    SMCParamStruct input, output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.data8 = kSMCCmdWriteBytes;
    input.keyInfo.dataSize = size;
    memcpy(input.bytes, bytes, size);
    return SMCCall(connection, &input, &output);
}

kern_return_t SMCKeyCount(io_connect_t connection, uint32_t *count) {
    SMCValue value;
    // '#KEY' holds the number of keys as a big-endian ui32.
    kern_return_t result = SMCReadKey(connection, ('#' << 24) | ('K' << 16) | ('E' << 8) | 'Y', &value);
    if (result != KERN_SUCCESS) return result;
    *count = ((uint32_t)value.bytes[0] << 24) | ((uint32_t)value.bytes[1] << 16) |
             ((uint32_t)value.bytes[2] << 8) | (uint32_t)value.bytes[3];
    return KERN_SUCCESS;
}

kern_return_t SMCKeyAtIndex(io_connect_t connection, uint32_t index, uint32_t *key) {
    SMCParamStruct input, output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.data8 = kSMCCmdReadIndex;
    input.data32 = index;
    kern_return_t result = SMCCall(connection, &input, &output);
    if (result == KERN_SUCCESS) *key = output.key;
    return result;
}
