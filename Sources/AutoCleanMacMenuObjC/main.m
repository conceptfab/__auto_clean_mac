#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <fcntl.h>
#import <sys/file.h>
#import <unistd.h>

static NSString * const ACMOpenSettingsNotification = @"com.micz.autocleanmac.openSettings";
static NSString * const ACMRunCleanupNotification = @"com.micz.autocleanmac.runCleanup";

@interface ACMMenuAppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic) EventHandlerRef eventHandler;
@property(nonatomic) EventHotKeyRef hotKeyRef;
@property(nonatomic) int lockFD;
@end

@implementation ACMMenuAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSString *mode = [self launchMode];
    if (![self acquireProcessLock]) {
        NSString *name = [mode isEqualToString:@"launch-agent"] ? ACMRunCleanupNotification : ACMOpenSettingsNotification;
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName:name object:nil];
        [NSApp terminate:nil];
        return;
    }

    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(handleOpenSettings:)
                                                            name:ACMOpenSettingsNotification
                                                          object:nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(handleRunCleanup:)
                                                            name:ACMRunCleanupNotification
                                                          object:nil];

    [self installMenu];
    if ([self globalShortcutEnabled]) {
        [self registerGlobalShortcut];
    }

    if ([mode isEqualToString:@"launch-agent"]) {
        [self launchUIWithArguments:@[@"--run-cleanup"]];
    } else if ([mode isEqualToString:@"manual"]) {
        [self launchUIWithArguments:@[@"--settings"]];
    }
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self launchUIWithArguments:@[@"--settings"]];
    return YES;
}

- (NSString *)launchMode {
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    if ([arguments containsObject:@"--menu-only"]) {
        return @"menu-only";
    }
    if ([arguments containsObject:@"--launch-agent"]) {
        return @"launch-agent";
    }
    return @"manual";
}

- (BOOL)acquireProcessLock {
    NSString *lockPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"com.micz.autocleanmac.menu.lock"];
    int fd = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
    if (fd == -1) {
        return YES;
    }
    if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
        close(fd);
        return NO;
    }
    self.lockFD = fd;
    return YES;
}

- (void)installMenu {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    NSStatusBarButton *button = self.statusItem.button;
    NSURL *iconURL = [NSBundle.mainBundle URLForResource:@"MenuBarIcon" withExtension:@"png"];
    NSImage *image = iconURL ? [[NSImage alloc] initWithContentsOfURL:iconURL] : nil;
    if (image != nil) {
        image.size = NSMakeSize(18, 18);
        button.image = image;
        button.imagePosition = NSImageOnly;
    } else {
        button.title = @"ACM";
        button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    }

    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *run = [menu addItemWithTitle:@"Uruchom cleanup" action:@selector(runNow:) keyEquivalent:@""];
    run.target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *settings = [menu addItemWithTitle:@"Preferencje..." action:@selector(openSettings:) keyEquivalent:@","];
    settings.target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [menu addItemWithTitle:@"Zakończ" action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    self.statusItem.menu = menu;
}

- (void)runNow:(id)sender {
    [self launchUIWithArguments:@[@"--run-cleanup"]];
}

- (void)openSettings:(id)sender {
    [self launchUIWithArguments:@[@"--settings"]];
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

- (void)handleOpenSettings:(NSNotification *)notification {
    [self launchUIWithArguments:@[@"--settings"]];
}

- (void)handleRunCleanup:(NSNotification *)notification {
    [self launchUIWithArguments:@[@"--run-cleanup"]];
}

- (NSURL *)uiExecutableURL {
    NSURL *dir = NSBundle.mainBundle.executableURL.URLByDeletingLastPathComponent;
    NSURL *bundledUI = [dir URLByAppendingPathComponent:@"AutoCleanMacUI"];
    if ([NSFileManager.defaultManager isExecutableFileAtPath:bundledUI.path]) {
        return bundledUI;
    }
    NSURL *developmentUI = [dir URLByAppendingPathComponent:@"AutoCleanMac"];
    if ([NSFileManager.defaultManager isExecutableFileAtPath:developmentUI.path]) {
        return developmentUI;
    }
    return nil;
}

- (void)launchUIWithArguments:(NSArray<NSString *> *)arguments {
    NSURL *url = [self uiExecutableURL];
    if (url == nil) {
        NSLog(@"AutoCleanMac: missing AutoCleanMacUI executable");
        return;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = url;
    task.arguments = arguments;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        NSLog(@"AutoCleanMac: failed to launch UI: %@", error);
    }
}

- (BOOL)globalShortcutEnabled {
    NSURL *configURL = [NSFileManager.defaultManager.homeDirectoryForCurrentUser
        URLByAppendingPathComponent:@".config/autoclean-mac/config.json"];
    NSData *data = [NSData dataWithContentsOfURL:configURL];
    if (data == nil) {
        return NO;
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSNumber *enabled = [json isKindOfClass:NSDictionary.class] ? json[@"global_shortcut_enabled"] : nil;
    return enabled.boolValue;
}

- (void)registerGlobalShortcut {
    if (self.hotKeyRef != NULL) {
        return;
    }

    EventHotKeyID hotKeyID;
    hotKeyID.signature = 'ACMC';
    hotKeyID.id = 1;

    EventTypeSpec eventType;
    eventType.eventClass = kEventClassKeyboard;
    eventType.eventKind = kEventHotKeyPressed;

    EventHandlerUPP handler = NewEventHandlerUPP(ACMHotKeyHandler);
    InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, (__bridge void *)self, &_eventHandler);
    RegisterEventHotKey(kVK_ANSI_C, cmdKey | shiftKey, hotKeyID, GetApplicationEventTarget(), 0, &_hotKeyRef);
}

static OSStatus ACMHotKeyHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:ACMOpenSettingsNotification object:nil];
    return noErr;
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        ACMMenuAppDelegate *delegate = [[ACMMenuAppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
