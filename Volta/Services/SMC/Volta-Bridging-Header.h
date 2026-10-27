//
//  Volta-Bridging-Header.h
//  Volta
//
//  C layouts for talking to the AppleSMC kernel user client.
//  These mirror the structures used by Apple's own SMC tools and by open-source
//  projects such as "smcFanControl" and "battery" (actuallymentor). Declaring them
//  in C guarantees the 80-byte layout the kernel expects, padding included.
//

#ifndef Volta_Bridging_Header_h
#define Volta_Bridging_Header_h

#include <stdint.h>
#include <libproc.h>
#include <sys/resource.h>

/// Selector passed to IOConnectCallStructMethod. The SMC user client multiplexes every
/// operation through this single entry point and reads `data8` to decide what to do.
#define VOLTA_KERNEL_INDEX_SMC 2

/// Values for `data8`.
#define VOLTA_SMC_CMD_READ_BYTES 5
#define VOLTA_SMC_CMD_WRITE_BYTES 6
#define VOLTA_SMC_CMD_READ_INDEX 8
#define VOLTA_SMC_CMD_READ_KEYINFO 9

/// `result` value the SMC returns for an unknown key.
#define VOLTA_SMC_RESULT_KEY_NOT_FOUND 132

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    uint16_t release;
} VoltaSMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} VoltaSMCPLimitData;

typedef struct {
    /// Number of bytes the key's value occupies.
    uint32_t dataSize;
    /// Four-character type code, e.g. 'ui8 ', 'hex_', 'flag'.
    uint32_t dataType;
    char dataAttributes;
} VoltaSMCKeyInfo;

/// The single in/out structure for every SMC call (80 bytes).
typedef struct {
    /// Four-character key such as 'BCLM', packed big-endian into 32 bits.
    uint32_t key;
    VoltaSMCVersion vers;
    VoltaSMCPLimitData pLimitData;
    VoltaSMCKeyInfo keyInfo;
    /// SMC status code for the request (0 = success).
    char result;
    char status;
    /// The command (VOLTA_SMC_CMD_*).
    char data8;
    uint32_t data32;
    /// Value payload for reads and writes.
    unsigned char bytes[32];
} VoltaSMCParamStruct;

#endif /* Volta_Bridging_Header_h */
