#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#include <stdio.h>
#include <mach/mach_time.h>
#include "mactop_smc.h"

// Private Symbols
typedef struct IOReportSubscriptionRef *IOReportSubscriptionRef;
extern CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef group, CFStringRef subgroup, uint64_t u1, uint64_t u2, uint64_t u3);
extern IOReportSubscriptionRef IOReportCreateSubscription(void* u, CFDictionaryRef channels, CFMutableDictionaryRef* sub, uint64_t u2, void* u3);
extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef sub, CFDictionaryRef channels, void* u);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef a, CFDictionaryRef b, void* u);
extern int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef item, int32_t idx);
extern CFStringRef IOReportChannelGetChannelName(CFDictionaryRef item);
extern CFStringRef IOReportChannelGetGroup(CFDictionaryRef item);
extern CFStringRef IOReportChannelGetSubGroup(CFDictionaryRef item);
extern CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef item);

void scan_all_io_groups() {
    const char *groups[] = {
        "Energy Model", "CPU Stats", "GPU Stats", "AMC Stats", "PMP", "Thermal", 
        "DCS Stats", "AppleH6Counters", "PerfCounters", "CLPC Stats", "RealTime Energy"
    };
    
    printf("\n--- IOReport Group Scanner ---\n");
    for (int i = 0; i < sizeof(groups)/sizeof(char*); i++) {
        CFStringRef groupRef = CFStringCreateWithCString(kCFAllocatorDefault, groups[i], kCFStringEncodingUTF8);
        CFDictionaryRef channels = IOReportCopyChannelsInGroup(groupRef, NULL, 0, 0, 0);
        if (channels) {
            CFArrayRef chs = CFDictionaryGetValue(channels, CFSTR("IOReportChannels"));
            printf("Group: %-20s | Status: OK (%ld channels)\n", groups[i], (long)(chs ? CFArrayGetCount(chs) : 0));
            CFRelease(channels);
        } else {
            printf("Group: %-20s | Status: Not Found\n", groups[i]);
        }
        CFRelease(groupRef);
    }
}

void scan_all_smc_keys() {
    io_connect_t conn = SMCOpen();
    if (!conn) return;

    printf("\n--- SMC Key Scanner (Filtered for Sensors) ---\n");
    int total = SMCGetKeyCount(conn);
    for (int i = 0; i < total; i++) {
        char key[5] = {0};
        if (SMCGetKeyFromIndex(conn, i, key) == kIOReturnSuccess) {
            // Filter: Temperatures (T), Power (P), Voltage (V), Current (I)
            if (key[0] == 'T' || key[0] == 'P' || key[0] == 'V' || key[0] == 'I') {
                double val = SMCGetFloatValue(conn, key);
                // Filtering out junk values (very small or very large)
                if (val > 0.001 && val < 500.0) {
                    printf("Key: %s | Value: %7.2f\n", key, val);
                }
            }
        }
    }
    SMCClose(conn);
}

int main() {
    @autoreleasepool {
        printf("========================================\n");
        printf("    GRAND SYSTEM SENSOR SCANNER (M2)\n");
        printf("========================================\n");
        
        scan_all_io_groups();
        scan_all_smc_keys();
        
        printf("\nScan Complete.\n");
    }
    return 0;
}
