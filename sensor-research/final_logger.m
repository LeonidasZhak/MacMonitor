#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#include <stdio.h>
#include "mactop_smc.h"

// --- Private Symbols ---
typedef struct IOReportSubscriptionRef *IOReportSubscriptionRef;
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timeout);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int64_t field);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);

extern CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef group, CFStringRef subgroup, uint64_t u1, uint64_t u2, uint64_t u3);
extern int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef item, int32_t idx);
extern CFStringRef IOReportChannelGetChannelName(CFDictionaryRef item);
extern CFStringRef IOReportChannelGetGroup(CFDictionaryRef item);
extern CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef item);

#define kIOHIDEventTypeTemperature 15

int main() {
    @autoreleasepool {
        printf("Starting exhaustive hardware sensor dump...\n");
        
        FILE *log = fopen("FULL_SYSTEM_SENSOR_LOG.txt", "w");
        if (!log) {
            printf("Error: Could not create log file.\n");
            return 1;
        }

        fprintf(log, "================================================================================\n");
        fprintf(log, "    EXHAUSTIVE SYSTEM SENSOR LOG (GLOBAL DISCOVERY)\n");
        fprintf(log, "    Date: Sunday 5 April, 2026\n");
        fprintf(log, "================================================================================\n\n");

        // --- 1. IOREPORT DUMP ---
        fprintf(log, "SECTION 1: IOREPORT CHANNELS (Power, Frequency, Residency)\n");
        fprintf(log, "--------------------------------------------------------------------------------\n");
        const char *groups[] = {
            "Energy Model", "CPU Stats", "GPU Stats", "AMC Stats", "PMP", "Thermal"
        };
        for (int i = 0; i < sizeof(groups)/sizeof(char*); i++) {
            CFStringRef grpRef = CFStringCreateWithCString(NULL, groups[i], kCFStringEncodingUTF8);
            CFDictionaryRef channels = IOReportCopyChannelsInGroup(grpRef, NULL, 0, 0, 0);
            if (channels) {
                CFArrayRef chs = CFDictionaryGetValue(channels, CFSTR("IOReportChannels"));
                if (chs) {
                    for (CFIndex j = 0; j < CFArrayGetCount(chs); j++) {
                        CFDictionaryRef ch = CFArrayGetValueAtIndex(chs, j);
                        CFStringRef name = IOReportChannelGetChannelName(ch);
                        CFStringRef unit = IOReportChannelGetUnitLabel(ch);
                        int64_t val = IOReportSimpleGetIntegerValue(ch, 0);
                        fprintf(log, "Group: %-15s | Channel: %-30s | Value: %12lld %s\n", 
                                groups[i], [(NSString*)name UTF8String], val, unit ? [(NSString*)unit UTF8String] : "");
                    }
                }
                CFRelease(channels);
            }
            CFRelease(grpRef);
        }

        // --- 2. SMC DUMP ---
        fprintf(log, "\nSECTION 2: SMC HARDWARE KEYS (Exhaustive Scan)\n");
        fprintf(log, "--------------------------------------------------------------------------------\n");
        io_connect_t conn = SMCOpen();
        if (conn) {
            int total = SMCGetKeyCount(conn);
            for (int i = 0; i < total; i++) {
                char key[5] = {0};
                if (SMCGetKeyFromIndex(conn, i, key) == kIOReturnSuccess) {
                    double val = SMCGetFloatValue(conn, key);
                    // Filter out non-numeric/inactive keys
                    if (val != 0 && val < 1000000) {
                        fprintf(log, "SMC Key: %-5s | Value: %10.3f\n", key, val);
                    }
                }
            }
            SMCClose(conn);
        }

        // --- 3. HID DUMP ---
        fprintf(log, "\nSECTION 3: HID THERMAL SERVICES (Internal PMU Mesh)\n");
        fprintf(log, "--------------------------------------------------------------------------------\n");
        IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (client) {
            const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
            int page = 0xff00, usage = 0x0005;
            CFNumberRef pNum = CFNumberCreate(NULL, kCFNumberIntType, &page);
            CFNumberRef uNum = CFNumberCreate(NULL, kCFNumberIntType, &usage);
            const void *vals[] = { pNum, uNum };
            CFDictionaryRef matching = CFDictionaryCreate(NULL, keys, vals, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            IOHIDEventSystemClientSetMatching(client, matching);
            
            CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
            if (services) {
                for (CFIndex i = 0; i < CFArrayGetCount(services); i++) {
                    IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
                    CFStringRef product = (CFStringRef)IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
                    if (product) {
                        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0);
                        if (event) {
                            double t = IOHIDEventGetFloatValue(event, kIOHIDEventTypeTemperature << 16);
                            fprintf(log, "HID Sensor: %-30s | Value: %7.2f °C\n", [(NSString*)product UTF8String], t);
                            CFRelease(event);
                        }
                        CFRelease(product);
                    }
                }
                CFRelease(services);
            }
            CFRelease(client);
            CFRelease(pNum); CFRelease(uNum); CFRelease(matching);
        }

        fprintf(log, "\n--- END OF LOG ---\n");
        fclose(log);
        printf("Exhaustive log saved to: FULL_SYSTEM_SENSOR_LOG.txt\n");
    }
    return 0;
}
