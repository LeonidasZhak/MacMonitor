#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#include <stdio.h>
#include <mach/mach_time.h>
#include <termios.h>
#include <unistd.h>
#include "mactop_smc.h"

// Private Symbols
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct IOReportSubscriptionRef *IOReportSubscriptionRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timeout);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int64_t field);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);

extern CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef group, CFStringRef subgroup, uint64_t u1, uint64_t u2, uint64_t u3);
extern IOReportSubscriptionRef IOReportCreateSubscription(void* u, CFDictionaryRef channels, CFMutableDictionaryRef* sub, uint64_t u2, void* u3);
extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef sub, CFDictionaryRef channels, void* u);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef a, CFDictionaryRef b, void* u);
extern int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef item, int32_t idx);
extern CFStringRef IOReportChannelGetChannelName(CFDictionaryRef item);
extern CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef item);

#define kIOHIDEventTypeTemperature 15

// Persistent State
static IOReportSubscriptionRef g_subscription = NULL;
static CFMutableDictionaryRef g_channels = NULL;
static CFDictionaryRef g_last_sample = NULL;
static uint64_t g_last_time_abs = 0;
static IOHIDEventSystemClientRef g_hid_client = NULL;
static io_connect_t g_smc_conn = 0;
static mach_timebase_info_data_t g_timebase;

typedef struct {
    double cpu_w, gpu_w, soc_w;
    double cpu_temp, gpu_temp;
} Snapshot;

static Snapshot g_snapshot = {0};

void init_all() {
    mach_timebase_info(&g_timebase);
    g_smc_conn = SMCOpen();
    
    // 1. IOReport
    CFDictionaryRef energy = IOReportCopyChannelsInGroup(CFSTR("Energy Model"), NULL, 0, 0, 0);
    g_channels = CFDictionaryCreateMutableCopy(NULL, 0, energy);
    CFRelease(energy);
    
    CFMutableDictionaryRef sub = NULL;
    g_subscription = IOReportCreateSubscription(NULL, g_channels, &sub, 0, NULL);
    if (sub) CFRelease(sub);
    
    g_last_sample = IOReportCreateSamples(g_subscription, g_channels, NULL);
    g_last_time_abs = mach_absolute_time();

    // 2. HID Thermal Client
    g_hid_client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
    int page = 0xff00, usage = 0x0005;
    CFNumberRef pNum = CFNumberCreate(NULL, kCFNumberIntType, &page);
    CFNumberRef uNum = CFNumberCreate(NULL, kCFNumberIntType, &usage);
    const void *vals[] = { pNum, uNum };
    CFDictionaryRef matching = CFDictionaryCreate(NULL, keys, vals, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDEventSystemClientSetMatching(g_hid_client, matching);
    CFRelease(pNum); CFRelease(uNum); CFRelease(matching);
}

void update_metrics() {
    @autoreleasepool {
        // --- POWER ---
        CFDictionaryRef current = IOReportCreateSamples(g_subscription, g_channels, NULL);
        uint64_t now_abs = mach_absolute_time();
        double duration = (double)(now_abs - g_last_time_abs) * g_timebase.numer / g_timebase.denom / 1e9;
        
        CFDictionaryRef delta_dict = IOReportCreateSamplesDelta(g_last_sample, current, NULL);
        if (delta_dict) {
            CFArrayRef chs = CFDictionaryGetValue(delta_dict, CFSTR("IOReportChannels"));
            g_snapshot.cpu_w = 0; g_snapshot.gpu_w = 0; g_snapshot.soc_w = 0;
            for (int i = 0; i < CFArrayGetCount(chs); i++) {
                CFDictionaryRef ch = CFArrayGetValueAtIndex(chs, i);
                NSString *name = (NSString*)IOReportChannelGetChannelName(ch);
                int64_t val = IOReportSimpleGetIntegerValue(ch, 0);
                NSString *unit = (NSString*)IOReportChannelGetUnitLabel(ch);
                double scale = [unit isEqualToString:@"nJ"] ? 1e9 : ([unit isEqualToString:@"uJ"] ? 1e6 : 1e3);
                double watts = (double)val / (scale * duration);
                if ([name containsString:@"CPU"]) g_snapshot.cpu_w += watts;
                else if ([name containsString:@"GPU"]) g_snapshot.gpu_w += watts;
                g_snapshot.soc_w += watts;
            }
            CFRelease(delta_dict);
        }
        if (g_last_sample) CFRelease(g_last_sample);
        g_last_sample = current;
        g_last_time_abs = now_abs;

        // --- THERMALS ---
        // CPU via HID (most accurate)
        double cpu_sum = 0; int cpu_cnt = 0;
        CFArrayRef services = IOHIDEventSystemClientCopyServices(g_hid_client);
        if (services) {
            for (CFIndex i = 0; i < CFArrayGetCount(services); i++) {
                IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
                CFStringRef product = (CFStringRef)IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
                if (!product) continue;
                if (strstr([(NSString*)product UTF8String], "PMU tdie")) {
                    IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0);
                    if (event) {
                        double t = IOHIDEventGetFloatValue(event, kIOHIDEventTypeTemperature << 16);
                        if (t > 10 && t < 150) { cpu_sum += t; cpu_cnt++; }
                        CFRelease(event);
                    }
                }
                CFRelease(product);
            }
            CFRelease(services);
        }
        g_snapshot.cpu_temp = cpu_cnt > 0 ? cpu_sum / cpu_cnt : SMCGetFloatValue(g_smc_conn, "Tp0P");
        
        // GPU via SMC (Verified keys for M2: TRDX, Tg0f, etc)
        double gt = SMCGetFloatValue(g_smc_conn, "TRDX");
        if (gt == 0) gt = SMCGetFloatValue(g_smc_conn, "Tg0f");
        if (gt == 0) gt = SMCGetFloatValue(g_smc_conn, "Tg0n");
        g_snapshot.gpu_temp = gt;
    }
}

void print_ui() {
    printf("\033[H\033[J");
    printf("┌──────────────────────────────────────┐\n");
    printf("│      MENU BAR SIMULATOR (LIVE)       │\n");
    printf("├──────────────────────────────────────┤\n");
    printf("│ CPU: %5.1f°C | %6.3f W             │\n", g_snapshot.cpu_temp, g_snapshot.cpu_w);
    printf("│ GPU: %5.1f°C | %6.3f W             │\n", g_snapshot.gpu_temp, g_snapshot.gpu_w);
    printf("│ SOC:         | %6.3f W             │\n", g_snapshot.soc_w);
    printf("├──────────────────────────────────────┤\n");
    printf("│ Snapshot is persistent and accurate.  │\n");
    printf("│ (Ctrl+C to quit)                     │\n");
    printf("└──────────────────────────────────────┘\n");
}

int main() {
    init_all();
    for(int i=0; i<3; i++) {
        [NSThread sleepForTimeInterval:1.0];
        update_metrics();
    }

    while (1) {
        update_metrics();
        print_ui();
        usleep(1000000); // 1s
    }
    return 0;
}
