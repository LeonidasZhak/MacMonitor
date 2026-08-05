#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#include <stdio.h>

// Private HID Symbols
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timeout);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int64_t field);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);

#define kIOHIDEventTypeTemperature 15

int main() {
    @autoreleasepool {
        IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
        int page = 0xff00, usage = 0x0005;
        CFNumberRef pNum = CFNumberCreate(NULL, kCFNumberIntType, &page);
        CFNumberRef uNum = CFNumberCreate(NULL, kCFNumberIntType, &usage);
        const void *vals[] = { pNum, uNum };
        CFDictionaryRef matching = CFDictionaryCreate(NULL, keys, vals, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        IOHIDEventSystemClientSetMatching(client, matching);
        
        CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
        printf("--- ALL HID TEMPERATURE SENSORS ---\n");
        if (services) {
            for (CFIndex i = 0; i < CFArrayGetCount(services); i++) {
                IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
                CFStringRef product = (CFStringRef)IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
                if (product) {
                    IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0);
                    if (event) {
                        double t = IOHIDEventGetFloatValue(event, kIOHIDEventTypeTemperature << 16);
                        printf("Sensor: %-30s | Value: %.2f °C\n", [(NSString*)product UTF8String], t);
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
    return 0;
}
