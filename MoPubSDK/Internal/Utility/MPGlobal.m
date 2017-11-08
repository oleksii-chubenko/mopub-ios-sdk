//
//  MPGlobal.m
//  MoPub
//
//  Copyright 2011 MoPub, Inc. All rights reserved.
//

#import "MPGlobal.h"
#import "MPConstants.h"
#import "MPLogging.h"
#import "NSURL+MPAdditions.h"
#import "MoPub.h"
#import <CommonCrypto/CommonDigest.h>

#import <sys/types.h>
#import <sys/sysctl.h>
#import <objc/message.h>

static UIWindow *_keyWindow = nil;

BOOL MPViewHasHiddenAncestor(UIView *view);
UIWindow *MPViewGetParentWindow(UIView *view);
BOOL MPViewIntersectsParentWindow(UIView *view);
NSString *MPSHA1Digest(NSString *string);

UIInterfaceOrientation MPInterfaceOrientation()
{
    return MPSharedApplication().statusBarOrientation;
}

void MPSetKeyWindow(UIWindow *window)
{
    _keyWindow = window;
}

UIWindow *MPKeyWindow()
{
    return _keyWindow ?: MPSharedApplication().keyWindow;
}

CGFloat MPStatusBarHeight() {
    if (MPSharedApplication().statusBarHidden) return 0.0f;

    CGFloat width = CGRectGetWidth(MPSharedApplication().statusBarFrame);
    CGFloat height = CGRectGetHeight(MPSharedApplication().statusBarFrame);

    return (width < height) ? width : height;
}

CGRect MPApplicationFrame()
{
    CGRect frame = MPScreenBounds();

    frame.origin.y += MPStatusBarHeight();
    frame.size.height -= MPStatusBarHeight();

    return frame;
}

CGRect MPScreenBounds()
{
    // Prior to iOS 8, window and screen coordinates were fixed and always specified relative to the
    // device’s screen in a portrait orientation. Starting with iOS8, the `fixedCoordinateSpace`
    // property was introduced which specifies bounds that always reflect the screen dimensions of
    // the device in a portrait-up orientation.
    CGRect bounds = [UIScreen mainScreen].bounds;
    if ([[UIScreen mainScreen] respondsToSelector:@selector(fixedCoordinateSpace)]) {
        bounds = [UIScreen mainScreen].fixedCoordinateSpace.bounds;
    }

    // Rotate the portrait-up bounds if the orientation of the device is in landscape.
    if (UIInterfaceOrientationIsLandscape(MPInterfaceOrientation())) {
        CGFloat width = bounds.size.width;
        bounds.size.width = bounds.size.height;
        bounds.size.height = width;
    }

    return bounds;
}

CGSize MPScreenResolution()
{
    CGRect bounds = MPScreenBounds();
    CGFloat scale = MPDeviceScaleFactor();

    return CGSizeMake(bounds.size.width*scale, bounds.size.height*scale);
}

CGFloat MPDeviceScaleFactor()
{
    if ([[UIScreen mainScreen] respondsToSelector:@selector(displayLinkWithTarget:selector:)] &&
        [[UIScreen mainScreen] respondsToSelector:@selector(scale)]) {
        return [[UIScreen mainScreen] scale];
    } else {
        return 1.0;
    }
}

NSDictionary *MPDictionaryFromQueryString(NSString *query) {
    NSMutableDictionary *queryDict = [NSMutableDictionary dictionary];
    NSArray *queryElements = [query componentsSeparatedByString:@"&"];
    for (NSString *element in queryElements) {
        NSArray *keyVal = [element componentsSeparatedByString:@"="];
        NSString *key = [keyVal objectAtIndex:0];
        NSString *value = [keyVal lastObject];
        [queryDict setObject:[value stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]
                      forKey:key];
    }
    return queryDict;
}

NSString *MPSHA1Digest(NSString *string)
{
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    NSData *data = [string dataUsingEncoding:NSASCIIStringEncoding];
    CC_SHA1([data bytes], (CC_LONG)[data length], digest);

    NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }

    return output;
}

BOOL MPViewIsVisible(UIView *view)
{
    // In order for a view to be visible, it:
    // 1) must not be hidden,
    // 2) must not have an ancestor that is hidden,
    // 3) must be within the frame of its parent window.
    //
    // Note: this function does not check whether any part of the view is obscured by another view.

    return (!view.hidden &&
            !MPViewHasHiddenAncestor(view) &&
            MPViewIntersectsParentWindow(view));
}

BOOL MPViewHasHiddenAncestor(UIView *view)
{
    UIView *ancestor = view.superview;
    while (ancestor) {
        if (ancestor.hidden) return YES;
        ancestor = ancestor.superview;
    }
    return NO;
}

UIWindow *MPViewGetParentWindow(UIView *view)
{
    UIView *ancestor = view.superview;
    while (ancestor) {
        if ([ancestor isKindOfClass:[UIWindow class]]) {
            return (UIWindow *)ancestor;
        }
        ancestor = ancestor.superview;
    }
    return nil;
}

BOOL MPViewIntersectsParentWindow(UIView *view)
{
    UIWindow *parentWindow = MPViewGetParentWindow(view);

    if (parentWindow == nil) {
        return NO;
    }

    // We need to call convertRect:toView: on this view's superview rather than on this view itself.
    CGRect viewFrameInWindowCoordinates = [view.superview convertRect:view.frame toView:parentWindow];

    return CGRectIntersectsRect(viewFrameInWindowCoordinates, parentWindow.frame);
}

BOOL MPViewIntersectsParentWindowWithPercent(UIView *view, CGFloat percentVisible)
{
    UIWindow *parentWindow = MPViewGetParentWindow(view);

    if (parentWindow == nil) {
        return NO;
    }

    // We need to call convertRect:toView: on this view's superview rather than on this view itself.
    CGRect viewFrameInWindowCoordinates = [view.superview convertRect:view.frame toView:parentWindow];
    CGRect intersection = CGRectIntersection(viewFrameInWindowCoordinates, parentWindow.frame);

    CGFloat intersectionArea = CGRectGetWidth(intersection) * CGRectGetHeight(intersection);
    CGFloat originalArea = CGRectGetWidth(view.bounds) * CGRectGetHeight(view.bounds);

    return intersectionArea >= (originalArea * percentVisible);
}

NSString *MPResourcePathForResource(NSString *resourceName)
{
    if ([[NSBundle mainBundle] pathForResource:@"MoPub" ofType:@"bundle"] != nil) {
        return [@"MoPub.bundle" stringByAppendingPathComponent:resourceName];
    }
    else if ([[UIDevice currentDevice].systemVersion compare:@"8.0" options:NSNumericSearch] != NSOrderedAscending) {
        // When using open source or cocoapods (on ios 8 and above), we can rely on the MoPub class
        // living in the same bundle/framework as the assets.
        // We can use pathForResource on ios 8 and above to succesfully load resources.
        NSBundle *resourceBundle = [NSBundle bundleForClass:[MoPub class]];
        NSString *resourcePath = [resourceBundle pathForResource:resourceName ofType:nil];
        return resourcePath;
    }
    else {
        // We can just return the resource name because:
        // 1. This is being used as an open source release so the resource will be
        // in the main bundle.
        // 2. This is cocoapods but CAN'T be using frameworks since that is only allowed
        // on ios 8 and above.
        return resourceName;
    }
}

NSArray *MPConvertStringArrayToURLArray(NSArray *strArray)
{
    NSMutableArray *urls = [NSMutableArray array];

    for (NSObject *str in strArray) {
        if ([str isKindOfClass:[NSString class]]) {
            NSURL *url = [NSURL URLWithString:(NSString *)str];
            if (url) {
                [urls addObject:url];
            }
        }
    }

    return urls;
}

UIApplication *MPSharedApplication()
{
    static SEL selector = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        selector = sel_getUid("sharedApplication");
    });
    
    static UIApplication *application = nil;

    if (application) {
        return application;
    }

    if (!_keyWindow) {
        return ((id(*)(id, SEL))objc_msgSend)([UIApplication class], selector);
    }
    
    for (id responder = _keyWindow; responder; responder = [responder nextResponder]) {
        if ([responder isKindOfClass:[UIApplication class]]) {
            application = responder;
            break;
        }
    }
    
    return application;
}

BOOL MPOpenURL(NSURL *url)
{
    static SEL selector = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        selector = sel_getUid("openURL:");
    });
    
    return ((BOOL(*)(id, SEL, NSURL *))objc_msgSend)(MPSharedApplication(), selector, url);
}

////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation UIDevice (MPAdditions)

- (NSString *)mp_hardwareDeviceName
{
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = malloc(size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *platform = [NSString stringWithCString:machine encoding:NSUTF8StringEncoding];
    free(machine);
    return platform;
}

@end

@implementation UIApplication (MPAdditions)

- (void)mp_preIOS7setApplicationStatusBarHidden:(BOOL)hidden
{
    // Hiding the status bar should use a fade effect.
    // Displaying the status bar should use no animation.
    UIStatusBarAnimation animation = hidden ?
    UIStatusBarAnimationFade : UIStatusBarAnimationNone;
    [MPSharedApplication() setStatusBarHidden:hidden withAnimation:animation];
}

- (BOOL)mp_supportsOrientationMask:(UIInterfaceOrientationMask)orientationMask
{
    NSArray *supportedOrientations = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"UISupportedInterfaceOrientations"];

    if (orientationMask & UIInterfaceOrientationMaskLandscapeLeft) {
        if ([supportedOrientations containsObject:@"UIInterfaceOrientationLandscapeLeft"]) {
            return YES;
        }
    }

    if (orientationMask & UIInterfaceOrientationMaskLandscapeRight) {
        if ([supportedOrientations containsObject:@"UIInterfaceOrientationLandscapeRight"]) {
            return YES;
        }
    }

    if (orientationMask & UIInterfaceOrientationMaskPortrait) {
        if ([supportedOrientations containsObject:@"UIInterfaceOrientationPortrait"]) {
            return YES;
        }
    }

    if (orientationMask & UIInterfaceOrientationMaskPortraitUpsideDown) {
        if ([supportedOrientations containsObject:@"UIInterfaceOrientationPortraitUpsideDown"]) {
            return YES;
        }
    }

    return NO;
}

- (BOOL)mp_doesOrientation:(UIInterfaceOrientation)orientation matchOrientationMask:(UIInterfaceOrientationMask)orientationMask
{
    BOOL supportsLandscapeLeft = (orientationMask & UIInterfaceOrientationMaskLandscapeLeft) > 0;
    BOOL supportsLandscapeRight = (orientationMask & UIInterfaceOrientationMaskLandscapeRight) > 0;
    BOOL supportsPortrait = (orientationMask & UIInterfaceOrientationMaskPortrait) > 0;
    BOOL supportsPortraitUpsideDown = (orientationMask & UIInterfaceOrientationMaskPortraitUpsideDown) > 0;

    if (supportsLandscapeLeft && orientation == UIInterfaceOrientationLandscapeLeft) {
        return YES;
    }

    if (supportsLandscapeRight && orientation == UIInterfaceOrientationLandscapeRight) {
        return YES;
    }

    if (supportsPortrait && orientation == UIInterfaceOrientationPortrait) {
        return YES;
    }

    if (supportsPortraitUpsideDown && orientation == UIInterfaceOrientationPortraitUpsideDown) {
        return YES;
    }

    return NO;
}

@end
////////////////////////////////////////////////////////////////////////////////////////////////////

@interface MPTelephoneConfirmationController ()

@property (nonatomic, strong) UIAlertController *alertView;

@end

@implementation MPTelephoneConfirmationController

- (id)initWithURL:(NSURL *)url clickHandler:(MPTelephoneConfirmationControllerClickHandler)clickHandler
{
    if (![url mp_hasTelephoneScheme] && ![url mp_hasTelephonePromptScheme]) {
        // Shouldn't be here as the url must have a tel or telPrompt scheme.
        MPLogError(@"Processing URL as a telephone URL when %@ doesn't follow the tel:// or telprompt:// schemes", url.absoluteString);
        return nil;
    }

    if (self = [super init]) {
        // If using tel://xxxxxxx, the host will be the number.  If using tel:xxxxxxx, we will try the resourceIdentifier.
        NSString *phoneNumber = [url host];

        if (!phoneNumber) {
            phoneNumber = [url resourceSpecifier];
            if ([phoneNumber length] == 0) {
                MPLogError(@"Invalid telelphone URL: %@.", url.absoluteString);
                return nil;
            }
        }

        NSURL *telephoneURL;
        if ([url mp_hasTelephonePromptScheme]) {
            telephoneURL = [NSURL URLWithString:[NSString stringWithFormat:@"tel://%@", phoneNumber]];
        } else {
            telephoneURL = url;
        }

        _alertView = [UIAlertController alertControllerWithTitle:@"Are you sure you want to call?" message:phoneNumber preferredStyle:UIAlertControllerStyleAlert];
        [self.alertView addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            clickHandler(telephoneURL, NO);
        }]];
        [self.alertView addAction:[UIAlertAction actionWithTitle:@"Call" style:0 handler:^(UIAlertAction * _Nonnull action) {
            clickHandler(telephoneURL, YES);
        }]];
    }

    return self;
}

- (void)dealloc
{
    [self.alertView dismissViewControllerAnimated:YES completion:nil];
}

- (void)showFromViewController:(UIViewController *)viewController
{
    [viewController presentViewController:self.alertView animated:YES completion:nil];
}

@end

