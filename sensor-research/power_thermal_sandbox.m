#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#include <stdio.h>
#include "mactop_smc.h"

// IOReport Private Headers/Symbols
typedef struct IOReportSubscriptionRef *IOReportSubscriptionRef;
extern CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef group, CFStringRef subgroup, uint64_t unknown1, uint64_t unknown2, uint64_t unknown3);
extern IOReportSubscriptionRef IOReportCreateSubscription(void* unknown, CFDictionaryRef desiredChannels, CFMutableDictionaryRef* subSystem, uint64_t unknown2, void* unknown3);
extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef subscription, CFDictionaryRef subSystem, void* unknown);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef prev, CFDictionaryRef current, void* unknown);
extern int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef item, int32_t idx);
extern CFStringRef IOReportChannelGetChannelName(CFDictionaryRef item);

void print_power_and_thermals() {
    @autoreleasepool {
        // 1. Setup IOReport for Energy
        CFDictionaryRef channels = IOReportCopyChannelsInGroup(CFSTR("Energy Model"), NULL, 0, 0, 0);
        CFMutableDictionaryRef subSystem = NULL;
        IOReportSubscriptionRef subscription = IOReportCreateSubscription(NULL, (CFMutableDictionaryRef)channels, &subSystem, 0, NULL);
        
        if (!subscription) {
            printf("Error: Could not create IOReport subscription. Try running with sudo.\n");
            return;
        }

        // 2. Take two samples to calculate Delta (Power = Energy / Time)
        printf("Sampling Energy Model (1s)... \n");
        CFDictionaryRef sample1 = IOReportCreateSamples(subscription, subSystem, NULL);
        [NSThread sleepForTimeInterval:1.0];
        CFDictionaryRef sample2 = IOReportCreateSamples(subscription, subSystem, NULL);
        CFDictionaryRef delta = IOReportCreateSamplesDelta(sample1, sample2, NULL);

        printf("\n--- ACCURATE POWER (from Energy Model Delta) ---\n");
        if (delta) {
            CFArrayRef channelsArray = CFDictionaryGetValue(delta, CFSTR("IOReportChannels"));
            if (channelsArray) {
                for (int i = 0; i < CFArrayGetCount(channelsArray); i++) {
                    CFDictionaryRef channel = CFArrayGetValueAtIndex(channelsArray, i);
                    CFStringRef name = IOReportChannelGetChannelName(channel);
                    int64_t value = IOReportSimpleGetIntegerValue(channel, 0); 
                    
                    // Convert nanojoules delta per 1s to Watts
                    double watts = (double)value / 1e9;
                    if (watts > 0.001) {
                        printf("%-20s: %.3f W\n", [(NSString*)name UTF8String], watts);
                    }
                }
            }
        }

        // 3. Expanded SMC Sensor Scan (TG Pro Style)
        printf("\n--- EXPANDED SMC SENSORS (TG Pro Style) ---\n");
        io_connect_t conn = SMCOpen();
        if (conn) {
            const char *deep_keys[] = {
                "Tp0P", "Tp01", "Tp05", "Tp09", "Tp0D", 
                "Te0P", "Te01", "Te05",                 
                "Tg0P", "Tg0D", "Tg0j",                 
                "Tm0P", "Tm01", "Tm05",                 
                "Ta0P", "Ta01"                          
            };
            
            for (int i = 0; i < sizeof(deep_keys)/sizeof(char*); i++) {
                double temp = SMCGetFloatValue(conn, deep_keys[i]);
                if (temp > 0) {
                    printf("Sensor %s: %.2f °C\n", deep_keys[i], temp);
                }
            }
            SMCClose(conn);
        }

        if (channels) CFRelease(channels);
        if (sample1) CFRelease(sample1);
        if (sample2) CFRelease(sample2);
        if (delta) CFRelease(delta);
    }
}

int main() {
    print_power_and_thermals();
    return 0;
}
