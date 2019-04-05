//
//  EmporterCodaPlugIn.m
//  EmporterCodaPlugIn
//
//  Created by Mikey on 23/03/2019.
//  Copyright © 2019 Young Dynasty. All rights reserved.
//

#import "CodaPlugInsController.h"
#import "Emporter.h"


@interface EmporterCodaPlugin : NSObject <CodaPlugIn>
@property (nonatomic, readonly) CodaPlugInsController *controller;
@property (nonatomic, readonly) Emporter *emporter;
@property (nonatomic, readonly) NSURL *siteURL;
@property (nonatomic, readonly) NSURL *tunnelURL;
@property (nonatomic, readonly) EmporterUserConsentType consentType;
@end

@interface EmporterCodaPlugin()
@property (nonatomic, setter=_setConsentType:) EmporterUserConsentType consentType;
@end

@implementation EmporterCodaPlugin {
    Emporter *_emporter;
}

- (instancetype)initWithPlugInController:(CodaPlugInsController *)aController plugInBundle:(id <CodaPlugInBundle>)plugInBundle {
    self = [super init];
    if (self == nil)
        return nil;
    
    _controller = aController;
    
    [_controller registerActionWithTitle:NSLocalizedString(@"Copy URL", @"") target:self selector:@selector(copyURL:)];
    [_controller registerActionWithTitle:NSLocalizedString(@"Configure...", @"") target:self selector:@selector(configure:)];
    
    return self;
}

- (NSString *)name {
    return @"Emporter";
}

- (void)didLoadSiteNamed:(NSString *)name {
    // Prompt for consent after a site loads
    if (name != nil) {
        [self determineUserConsentWithCompletionHandler:nil];
    }
}

- (void)textViewDidFocus:(CodaTextView *)textView {
    // Prompt for consent when a text view comes in focus for a project for the first time
    if (self.siteURL != nil) {
        [self determineUserConsentWithCompletionHandler:nil];
    }
}

#pragma mark - Menu

- (void)copyURL:(id)sender {
    NSURL *tunnelURL = self.tunnelURL;
    if (tunnelURL == nil) {
        return NSBeep();
    }
    
    [[NSPasteboard generalPasteboard] declareTypes:@[NSPasteboardTypeString] owner:nil];
    [[NSPasteboard generalPasteboard] setString:tunnelURL.absoluteString forType:NSPasteboardTypeString];
}

- (void)configure:(id)sender {
    Emporter *emporter = self.emporter;
    if (emporter == nil) {
        return [Emporter isInstalled] ? NSBeep() : [self showDownloadAlert];
    }
    
    NSURL *siteURL = [sender isKindOfClass:[NSURL class]] ? sender : self.siteURL;
    if (siteURL == nil) {
        return NSBeep();
    }
    
    // Launch Emporter and try again if needed
    if (![emporter isRunning]) {
        return [emporter launchInBackgroundWithCompletionHandler:^(NSError *error) {
            if (error != nil) {
                NSLog(@"Could not launch Emporter: %@", emporter);
                return NSBeep();
            }
            
            [self configure:siteURL];
        }];
    }
    
    // Determine user consent when configuring a tunnel as we need consent for our other menu actions. The other
    // actions depend on the project being configured, so it makes sense to do it here.
    [self determineUserConsentWithCompletionHandler:^{
        NSError *error = nil;
        
        if (self.consentType == EmporterUserConsentTypeGranted) {
            [emporter configureTunnelWithURL:siteURL error:&error];
            
            if (error == nil) {
                return;
            } else {
                error = nil; // fall through
            }
        }
        
        // If we don't have consent, fall-back to less-powerful API which doesn't need permissions
        [[NSWorkspace sharedWorkspace] openURLs:@[siteURL] withApplicationAtURL:emporter.bundleURL options:0 configuration:@{} error:&error];
        
        if (error != nil) {
            NSLog(@"Could not configure URL: %@", error);
            NSBeep();
        }
    }];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(copyURL:)) {
        return self.tunnelURL != nil;
    } else if (menuItem.action == @selector(configure:)) {
        return self.siteURL != nil;
    } else {
        return YES;
    }
}

#pragma mark - User Consent

- (void)determineUserConsentWithCompletionHandler:(void(^)(void))completionHandler {
    Emporter *emporter = self.emporter;
    
    if (emporter != nil && _consentType != EmporterUserConsentTypeGranted) {
        [emporter determineUserConsentWithPrompt:YES completionHandler:^(EmporterUserConsentType consentType) {
            self.consentType = consentType;
            
            if (completionHandler != nil) {
                completionHandler();
            }
        }];
    } else if (completionHandler != nil) {
        dispatch_async(dispatch_get_main_queue(), completionHandler);
    }
}

- (void)showConsentErrorAlert {
    NSBeep();
}

#pragma mark - Properties

- (NSURL *)siteURL {
    if (_controller == nil) {
        return nil;
    } else if ([_controller siteLocalURL] != nil) {
        return [NSURL URLWithString:[_controller siteLocalURL]];
    } else if ([_controller siteLocalPath] != nil) {
        return [[NSURL fileURLWithPath:[_controller siteLocalPath] isDirectory:YES] fileReferenceURL];
    } else {
        return nil;
    }
}

- (Emporter *)emporter {
    if (_emporter == nil) {
        _emporter = [[Emporter alloc] init];
    }
    
    return _emporter;
}

- (NSURL *)tunnelURL {
    NSURL *siteURL = self.siteURL;
    Emporter *emporter = self.emporter;
    NSString *urlString = nil;
    
    if (siteURL != nil && emporter != nil && [emporter isRunning] && self.consentType == EmporterUserConsentTypeGranted) {
        EmporterTunnel *tunnel = [emporter tunnelForURL:siteURL error:nil];
        if (tunnel != nil) {
            urlString = tunnel.remoteUrl;
        }
    }
    
    return urlString ? [NSURL URLWithString:urlString] : nil;
}

#pragma mark -

- (void)showDownloadAlert {
    NSAlert *alert = [[NSAlert alloc] init];
    
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"Emporter must be installed before continuing.";
    alert.informativeText = @"Emporter creates secure, public URLs to your Mac. It's free.";
    
    [alert addButtonWithTitle:@"View in Mac App Store"];
    [alert addButtonWithTitle:@"Cancel"];
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [[NSWorkspace sharedWorkspace] openURL:[Emporter appStoreURL]];
    }
}

@end
