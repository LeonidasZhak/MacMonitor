#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#include <stdio.h>
#include <mach/mach_time.h>
#include "mactop_smc.h"

// --- Private Symbols for Global Discovery ---
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

#define kIOHIDEventTypeTemperature 15

// --- Global Discovery Logic ---

void discover_io_report_sensors() {
    printf("\n[1/3] DISCOVERING IOREPORT CHANNELS (Dynamic)...\n");
    const char *groups[] = {
        "Energy Model", "CPU Stats", "GPU Stats", "AMC Stats", "PMP", "Thermal", 
        "DCS Stats", "AppleH6Counters", "PerfCounters", "CLPC Stats", "RealTime Energy"
    };
    
    for (int i = 0; i < sizeof(groups)/sizeof(char*); i++) {
        CFStringRef groupRef = CFStringCreateWithCString(NULL, groups[i], kCFStringEncodingUTF8);
        CFDictionaryRef channels = IOReportCopyChannelsInGroup(groupRef, NULL, 0, 0, 0);
        if (channels) {
            CFArrayRef chs = CFDictionaryGetValue(channels, CFSTR("IOReportChannels"));
            CFIndex count = chs ? CFArrayGetCount(chs) : 0;
            printf("Group: %-20s | Status: OK | Channels: %ld\n", groups[i], (long)count);
            
            // Print sample of first 5 channel names
            for (int j = 0; j < (count > 5 ? 5 : count); j++) {
                CFDictionaryRef ch = CFArrayGetValueAtIndex(chs, j);
                CFStringRef name = IOReportChannelGetChannelName(ch);
                printf("  - Sample: %s\n", [(NSString*)name UTF8String]);
            }
            CFRelease(channels);
        }
        CFRelease(groupRef);
    }
}

void discover_smc_sensors() {
    printf("\n[2/3] DISCOVERING SMC SENSORS (Global Scan)...\n");
    io_connect_t conn = SMCOpen();
    if (!conn) {
        printf("Error: Could not connect to SMC. Run as sudo.\n");
        return;
    }

    int total = SMCGetKeyCount(conn);
    printf("Total SMC Keys found on this Mac: %d\n", total);
    printf("%-6s | %-10s | %s\n", "Key", "Value", "Probable Type");
    printf("-------|------------|---------------\n");

    for (int i = 0; i < total; i++) {
        char key[5] = {0};
        if (SMCGetKeyFromIndex(conn, i, key) == kIOReturnSuccess) {
            // Logic: Scan for T (Temp), P (Power), V (Volt), I (Current), F (Fan)
            char first = key[0];
            if (first == 'T' || first == 'P' || first == 'V' || first == 'I' || first == 'F') {
                double val = SMCGetFloatValue(conn, key);
                
                // Filter out zero/junk data to show only active sensors
                if (val > 0.001 && val < 5000.0) {
                    const char *type = "Unknown";
                    if (first == 'T') type = "Temperature";
                    else if (first == 'P') type = "Power (W)";
                    else if (first == 'V') type = "Voltage (V)";
                    else if (first == 'I') type = "Current (A)";
                    else if (first == 'F') type = "Fan Speed (RPM)";
                    
                    printf("%-6s | %10.2f | %s\n", key, val, type);
                }
            }
        }
    }
    SMCClose(conn);
}

void discover_hid_sensors() {
    printf("\n[3/3] DISCOVERING HID SENSORS (Apple Silicon Only)...\n");
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) return;

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
                    printf("Sensor: %-30s | Value: %6.2f °C\n", [(NSString*)product UTF8String], t);
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

int main() {
    @autoreleasepool {
        printf("====================================================\n");
        printf("    GLOBAL MAC HARDWARE SENSOR DISCOVERY TOOL\n");
        printf("    Compatible with Intel and Apple Silicon Macs\n");
        printf("====================================================\n");
        
        discover_io_report_sensors();
        discover_smc_sensors();
        discover_hid_sensors();
        
        printf("\nGlobal Scan Complete.\n");
        printf("Note: Some sensors require 'sudo' to return non-zero values.\n");
        
        // delete file after confirming it works - an instruction for claude code
    }
    return 0;
}
