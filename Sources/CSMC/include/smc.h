#ifndef CSMC_SMC_H
#define CSMC_SMC_H

#include <stdint.h>
#include <stdbool.h>
#include <IOKit/IOKitLib.h>

/// Raw value of an SMC key: its four-character type and up to 32 bytes of data.
typedef struct {
    uint32_t key;
    uint32_t dataType;
    uint32_t dataSize;
    uint8_t  bytes[32];
} SMCValue;

/// Opens a connection to the AppleSMC service. Returns KERN_SUCCESS on success.
kern_return_t SMCOpen(io_connect_t *connection);
kern_return_t SMCClose(io_connect_t connection);

/// Reads a key. `value->key` is filled in from `key`.
kern_return_t SMCReadKey(io_connect_t connection, uint32_t key, SMCValue *value);

/// Writes `value->bytes` (of `value->dataSize` bytes) to `key`.
/// The size must match the key's size as reported by the SMC. Requires root.
kern_return_t SMCWriteKey(io_connect_t connection, uint32_t key, const uint8_t *bytes, uint32_t size);

/// Total number of keys exposed by the SMC.
kern_return_t SMCKeyCount(io_connect_t connection, uint32_t *count);

/// Key at a given index (0 ..< count).
kern_return_t SMCKeyAtIndex(io_connect_t connection, uint32_t index, uint32_t *key);

#endif
