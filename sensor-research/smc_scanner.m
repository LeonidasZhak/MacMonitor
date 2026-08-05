#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#include <stdio.h>
#include "mactop_smc.h"

int main() {
    @autoreleasepool {
        io_connect_t conn = SMCOpen();
        if (!conn) {
            printf("Failed to open SMC\n");
            return 1;
        }

        int totalKeys = SMCGetKeyCount(conn);
        printf("SMC Keys: %d\n", totalKeys);
        printf("--- POTENTIAL GPU SENSORS ---\n");

        for (int i = 0; i < totalKeys; i++) {
            char key[5] = {0};
            if (SMCGetKeyFromIndex(conn, i, key) == kIOReturnSuccess) {
                // Look for common GPU prefixes from mactop
                // Tg, TR, Tg0P, Tg0L, TRd, etc.
                if (key[0] == 'T' && (key[1] == 'g' || key[1] == 'R')) {
                    double val = SMCGetFloatValue(conn, key);
                    if (val > 10 && val < 150) {
                        printf("Key: %s | Value: %.2f °C\n", key, val);
                    }
                }
            }
        }
        SMCClose(conn);
    }
    return 0;
}
