//
//  KYAStatusItemImageProvider.m
//  KYAStatusItemUI
//
//  Created by Marcel Dierkes on 17.08.15.
//  Copyright © 2015 Marcel Dierkes. All rights reserved.
//

#import "KYAStatusItemImageProvider+Private.h"
#import <KYACommon/KYACommon.h>
#import "NSURL+KYAStatusItemImage.h"
#import "NSImage+KYAStatusItemImage.h"

// Draws a bolt to the right of the active icon, vertically centered.
static NSImage *KYACreateClosedLidIconImage(NSImage *activeIcon)
{
    Auto configuration = [NSImageSymbolConfiguration configurationWithPointSize:11.0 weight:NSFontWeightBlack];
    Auto bolt = [[NSImage imageWithSystemSymbolName:@"bolt.fill" accessibilityDescription:nil]
                 imageWithSymbolConfiguration:configuration];
    NSSize iconSize = activeIcon.size;
    NSSize boltSize = bolt.size;
    NSSize size = NSMakeSize(iconSize.width + boltSize.width, iconSize.height);

    Auto image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [activeIcon drawInRect:NSMakeRect(0.0, 0.0, iconSize.width, iconSize.height)];
        NSRect boltRect = NSMakeRect(NSMaxX(rect) - boltSize.width,
                                     round((NSHeight(rect) - boltSize.height) / 2.0),
                                     boltSize.width,
                                     boltSize.height);
        [bolt drawInRect:boltRect];
        return YES;
    }];
    image.template = YES;
    return image;
}

@implementation KYAStatusItemImageProvider

+ (KYAStatusItemImageProvider *)currentProvider
{
    static KYAStatusItemImageProvider *provider;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        provider = self.customProvider ?: self.standardProvider;
    });
    
    return provider;
}

+ (KYAStatusItemImageProvider *)standardProvider
{
    static KYAStatusItemImageProvider *provider;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        provider = [[self alloc] initWithActiveIconName:NSImage.kya_defaultActiveIconImage
                                       inactiveIconName:NSImage.kya_defaultInactiveIconImage];
    });
    
    return provider;
}

+ (KYAStatusItemImageProvider *)customProvider
{
    static KYAStatusItemImageProvider *provider;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        if(KYACustomIconImageFilesExist() == NO)
        {
            provider = nil;
            return;
        }
        
        provider = [[self alloc] initWithActiveIconName:NSImage.kya_customActiveIconImage
                                       inactiveIconName:NSImage.kya_customInactiveIconImage];
    });
    
    return provider;
}

#pragma mark -

- (instancetype)initWithActiveIconName:(NSImage *)activeIcon inactiveIconName:(NSImage *)inactiveIcon
{
    NSParameterAssert(activeIcon);
    NSParameterAssert(inactiveIcon);
    
    self = [super init];
    if(self)
    {
        self.activeIconImage = activeIcon;
        self.inactiveIconImage = inactiveIcon;
        self.closedLidIconImage = KYACreateClosedLidIconImage(activeIcon);
    }
    return self;
}

@end
