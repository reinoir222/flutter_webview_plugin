#import "FlutterWebviewPlugin.h"

static NSString *const CHANNEL_NAME = @"flutter_webview_plugin";

// UIWebViewDelegate
@interface FlutterWebviewPlugin() <WKNavigationDelegate, UIScrollViewDelegate, WKUIDelegate> {
    BOOL _enableAppScheme;
    BOOL _enableZoom;
    NSString* _invalidUrlRegex;
    BOOL _hasNavDelegate;
    // The set of registered JavaScript channel names.
    NSMutableSet* _javaScriptChannelNames;
}
@end

@implementation FlutterWebviewPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    channel = [FlutterMethodChannel
               methodChannelWithName:CHANNEL_NAME
               binaryMessenger:[registrar messenger]];

    UIViewController *viewController = [UIApplication sharedApplication].delegate.window.rootViewController;
    FlutterWebviewPlugin* instance = [[FlutterWebviewPlugin alloc] initWithViewController:viewController];

    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithViewController:(UIViewController *)viewController {
    self = [super init];
    if (self) {
        self.viewController = viewController;
        if (self.jsChannels == nil) {
            self.jsChannels = [NSMutableArray array];
        }
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"launch" isEqualToString:call.method]) {
        if (!self.webview)
            [self initWebview:call];
        else
            [self navigate:call];
        result(nil);
    } else if ([@"close" isEqualToString:call.method]) {
        [self closeWebView];
        result(nil);
    } else if ([@"eval" isEqualToString:call.method]) {
        [self evalJavascript:call completionHandler:^(NSString * response) {
            result(response);
        }];
    } else if ([@"resize" isEqualToString:call.method]) {
        [self resize:call];
        result(nil);
    } else if ([@"reloadUrl" isEqualToString:call.method]) {
        [self reloadUrl:call];
        result(nil);
    } else if ([@"show" isEqualToString:call.method]) {
        [self show];
        result(nil);
    } else if ([@"hide" isEqualToString:call.method]) {
        [self hide];
        result(nil);
    } else if ([@"stopLoading" isEqualToString:call.method]) {
        [self stopLoading];
        result(nil);
    } else if ([@"cleanCookies" isEqualToString:call.method]) {
        [self cleanCookies];
    } else if ([@"canGoBack" isEqualToString:call.method]) {
        [self onCanGoBack:call result:result];
    } else if ([@"back" isEqualToString:call.method]) {
        [self back];
        result(nil);
    } else if ([@"forward" isEqualToString:call.method]) {
        [self forward];
        result(nil);
    } else if ([@"reload" isEqualToString:call.method]) {
        [self reload];
        result(nil);
    } else if ([[call method] isEqualToString:@"addJavascriptChannels"]) {
        [self onAddJavaScriptChannels:call result:result];
        result(nil);
    } else if ([[call method] isEqualToString:@"removeJavascriptChannels"]) {
        [self onRemoveJavaScriptChannels:call result:result];
        result(nil);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)initWebview:(FlutterMethodCall*)call {
    NSNumber *clearCache = call.arguments[@"clearCache"];
    NSNumber *clearCookies = call.arguments[@"clearCookies"];
    NSNumber *hidden = call.arguments[@"hidden"];
    NSDictionary *rect = call.arguments[@"rect"];
    _enableAppScheme = call.arguments[@"enableAppScheme"];
    NSString *userAgent = call.arguments[@"userAgent"];
    NSNumber *withZoom = call.arguments[@"withZoom"];
    NSNumber *scrollBar = call.arguments[@"scrollBar"];
    NSNumber *withJavascript = call.arguments[@"withJavascript"];
    _invalidUrlRegex = call.arguments[@"invalidUrlRegex"];
    _hasNavDelegate = call.arguments[@"hasNavigationDelegate"];

    if (clearCache != (id)[NSNull null] && [clearCache boolValue]) {
        [[NSURLCache sharedURLCache] removeAllCachedResponses];
    }

    if (clearCookies != (id)[NSNull null] && [clearCookies boolValue]) {
        if (@available(iOS 9.0, *)) {
            NSSet *websiteDataTypes
            = [NSSet setWithArray:@[
                                    WKWebsiteDataTypeCookies,
                                    ]];
            NSDate *dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
            
            [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:websiteDataTypes modifiedSince:dateFrom completionHandler:^{
            }];
        } else {
            // Fallback on earlier versions
        }
    }

    if (userAgent != (id)[NSNull null]) {
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"UserAgent": userAgent}];
    }

    CGRect rc;
    if (rect != nil) {
        rc = [self parseRect:rect];
    } else {
        rc = self.viewController.view.bounds;
    }

    _javaScriptChannelNames = [[NSMutableSet alloc] init];

    WKUserContentController* userContentController = [[WKUserContentController alloc] init];
    if ([self.jsChannels count] > 0) {
        [userContentController removeAllUserScripts];
        [_javaScriptChannelNames addObjectsFromArray:self.jsChannels];
        [self registerJavaScriptChannels:_javaScriptChannelNames controller:userContentController];
    }
    WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
    configuration.userContentController = userContentController;

    self.webview = [[WKWebView alloc] initWithFrame:rc configuration:configuration];
    self.webview.UIDelegate = self;
    self.webview.navigationDelegate = self;
    self.webview.scrollView.delegate = self;
    self.webview.hidden = [hidden boolValue];
    self.webview.scrollView.showsHorizontalScrollIndicator = [scrollBar boolValue];
    self.webview.scrollView.showsVerticalScrollIndicator = [scrollBar boolValue];
    
    [self.webview addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:NULL];
    [self.webview addObserver:self forKeyPath:@"URL" options:NSKeyValueObservingOptionNew context:NULL];

    WKPreferences* preferences = [[self.webview configuration] preferences];
    if ([withJavascript boolValue]) {
        [preferences setJavaScriptEnabled:YES];
    } else {
        [preferences setJavaScriptEnabled:NO];
    }

    _enableZoom = [withZoom boolValue];

    UIViewController* presentedViewController = self.viewController.presentedViewController;
    UIViewController* currentViewController = presentedViewController != nil ? presentedViewController : self.viewController;
    [currentViewController.view addSubview:self.webview];

    [self navigate:call];
}

- (CGRect)parseRect:(NSDictionary *)rect {
    return CGRectMake([[rect valueForKey:@"left"] doubleValue],
                      [[rect valueForKey:@"top"] doubleValue],
                      [[rect valueForKey:@"width"] doubleValue],
                      [[rect valueForKey:@"height"] doubleValue]);
}

- (void) scrollViewDidScroll:(UIScrollView *)scrollView {
    id xDirection = @{@"xDirection": @(scrollView.contentOffset.x) };
    [channel invokeMethod:@"onScrollXChanged" arguments:xDirection];

    id yDirection = @{@"yDirection": @(scrollView.contentOffset.y) };
    [channel invokeMethod:@"onScrollYChanged" arguments:yDirection];
}

- (void)navigate:(FlutterMethodCall*)call {
    if (self.webview != nil) {
            NSString *url = call.arguments[@"url"];
            NSNumber *withLocalUrl = call.arguments[@"withLocalUrl"];
            if ( [withLocalUrl boolValue]) {
                NSURL *htmlUrl = [NSURL fileURLWithPath:url isDirectory:false];
                NSString *localUrlScope = call.arguments[@"localUrlScope"];
                if (@available(iOS 9.0, *)) {
                    if(localUrlScope == nil) {
                        [self.webview loadFileURL:htmlUrl allowingReadAccessToURL:htmlUrl];
                    }
                    else {
                        NSURL *scopeUrl = [NSURL fileURLWithPath:localUrlScope];
                        [self.webview loadFileURL:htmlUrl allowingReadAccessToURL:scopeUrl];
                    }
                } else {
                    @throw @"not available on version earlier than ios 9.0";
                }
            } else {
                NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
                NSDictionary *headers = call.arguments[@"headers"];

                if (headers != nil) {
                    [request setAllHTTPHeaderFields:headers];
                }

                [self.webview loadRequest:request];
            }
        }
}

- (void)onCanGoBack:(FlutterMethodCall*)call result:(FlutterResult)result {
    if (self.webview != nil) {
        BOOL canGoBack = [self.webview canGoBack];
        result([NSNumber numberWithBool:canGoBack]);
    } else {
        result(false);
    }

}

- (void)evalJavascript:(FlutterMethodCall*)call
     completionHandler:(void (^_Nullable)(NSString * response))completionHandler {
    if (self.webview != nil) {
        NSString *code = call.arguments[@"code"];
        [self.webview evaluateJavaScript:code
                       completionHandler:^(id _Nullable response, NSError * _Nullable error) {
            completionHandler([NSString stringWithFormat:@"%@", response]);
        }];
    } else {
        completionHandler(nil);
    }
}

- (void)resize:(FlutterMethodCall*)call {
    if (self.webview != nil) {
        NSDictionary *rect = call.arguments[@"rect"];
        CGRect rc = [self parseRect:rect];
        self.webview.frame = rc;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"estimatedProgress"] && object == self.webview) {
        [channel invokeMethod:@"onProgressChanged" arguments:@{@"progress": @(self.webview.estimatedProgress)}];
    } else if ([keyPath isEqualToString:@"URL"] && object == self.webview) {
        [channel invokeMethod:@"onUpdateHistory" arguments:@{@"url": self.webview.URL.absoluteString, @"isReload": @false}];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)closeWebView {
    if (self.webview != nil) {
        [self.webview stopLoading];
        [self.webview removeFromSuperview];
        self.webview.navigationDelegate = nil;
        [self.webview removeObserver:self forKeyPath:@"estimatedProgress"];
        [self.webview removeObserver:self forKeyPath:@"URL"];
        self.webview = nil;

        // manually trigger onDestroy
        [channel invokeMethod:@"onDestroy" arguments:nil];
    }
}

- (void)reloadUrl:(FlutterMethodCall*)call {
    if (self.webview != nil) {
		NSString *url = call.arguments[@"url"];
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
        NSDictionary *headers = call.arguments[@"headers"];
        
        if (headers != nil) {
            [request setAllHTTPHeaderFields:headers];
        }
        
        [self.webview loadRequest:request];
    }
}
- (void)show {
    if (self.webview != nil) {
        self.webview.hidden = false;
    }
}

- (void)hide {
    if (self.webview != nil) {
        self.webview.hidden = true;
    }
}
- (void)stopLoading {
    if (self.webview != nil) {
        [self.webview stopLoading];
    }
}
- (void)back {
    if (self.webview != nil) {
        [self.webview goBack];
    }
}
- (void)forward {
    if (self.webview != nil) {
        [self.webview goForward];
    }
}
- (void)reload {
    if (self.webview != nil) {
        [self.webview reload];
    }
}

- (void)cleanCookies {
    [[NSURLSession sharedSession] resetWithCompletionHandler:^{
        }];
}

- (bool)checkInvalidUrl:(NSString*)urlString {
  if (_invalidUrlRegex != [NSNull null] && urlString != nil) {
    NSError* error = NULL;
    NSRegularExpression* regex =
        [NSRegularExpression regularExpressionWithPattern:_invalidUrlRegex
                                                  options:NSRegularExpressionCaseInsensitive
                                                    error:&error];
    NSTextCheckingResult* match = [regex firstMatchInString:urlString
                                                    options:0
                                                      range:NSMakeRange(0, [urlString length])];
    return match != nil;
  } else {
    return false;
  }
}

- (void)sendState:(NSString*)url invalid:(BOOL*)invalid {
  id data = @{@"url": url,
    @"type": invalid ? @"abortLoad" : @"shouldStart",
    //@"navigationType": [NSNumber numberWithInt:navigationAction.navigationType]
  };
  [channel invokeMethod:@"onState" arguments:data];
}

#pragma mark -- WkWebView Delegate
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {

    if (navigationAction.navigationType == WKNavigationTypeBackForward) {
        [channel invokeMethod:@"onBackPressed" arguments:nil];
    }
    if (!_enableAppScheme &&
            !([webView.URL.scheme isEqualToString:@"http"] ||
             [webView.URL.scheme isEqualToString:@"https"] ||
             [webView.URL.scheme isEqualToString:@"about"] ||
             [webView.URL.scheme isEqualToString:@"file"])
    ) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    NSString* url = navigationAction.request.URL.absoluteString;
    BOOL isInvalid = [self checkInvalidUrl: url];

    if (isInvalid) {
      [self sendState: url invalid: isInvalid];
      decisionHandler(WKNavigationActionPolicyCancel);
      return;
    }



    if (!_hasNavDelegate) {
        id data = @{@"url": url};
        [channel invokeMethod:@"onUrlChanged" arguments:data];
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }
    NSDictionary* arguments = @{
        @"url" : url,
        @"isForMainFrame" : @(navigationAction.targetFrame.isMainFrame)
    };
    [channel invokeMethod:@"onNavRequest"
        arguments:arguments
        result:^(id _Nullable result) {
            if ([result isKindOfClass:[FlutterError class]]) {
                NSLog(@"onNavRequest has unexpectedly completed with an error, "
                      @"allowing navigation.");
                decisionHandler(WKNavigationActionPolicyAllow);
                return;
            }
            if (result == FlutterMethodNotImplemented) {
                 NSLog(@"onNavRequest was unexepectedly not implemented: %@, "
                       @"allowing navigation.",
                       result);
                 decisionHandler(WKNavigationActionPolicyAllow);
                 return;
            }
            if (![result isKindOfClass:[NSNumber class]]) {
                 NSLog(@"onNavRequest unexpectedly returned a non boolean value: "
                       @"%@, allowing navigation.",
                       result);
                 decisionHandler(WKNavigationActionPolicyAllow);
                 return;
            }
            NSNumber* typedResult = result;
            BOOL allow = [typedResult boolValue];
            [self sendState: url invalid: !allow];
            if (allow) {
                id data = @{@"url": url};
                [channel invokeMethod:@"onUrlChanged" arguments:data];
                decisionHandler(WKNavigationActionPolicyAllow);
            } else {
                decisionHandler(WKNavigationActionPolicyCancel);
            }
        }
    ];
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
    forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {

    if (!navigationAction.targetFrame.isMainFrame) {
        [webView loadRequest:navigationAction.request];
    }

    return nil;
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [channel invokeMethod:@"onState" arguments:@{@"type": @"startLoad", @"url": webView.URL.absoluteString}];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [channel invokeMethod:@"onState" arguments:@{@"type": @"finishLoad", @"url": webView.URL.absoluteString}];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [channel invokeMethod:@"onError" arguments:@{@"code": [NSString stringWithFormat:@"%ld", error.code], @"error": error.localizedDescription}];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if ([navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse * response = (NSHTTPURLResponse *)navigationResponse.response;

        [channel invokeMethod:@"onHttpError" arguments:@{@"code": [NSString stringWithFormat:@"%ld", response.statusCode], @"url": webView.URL.absoluteString}];
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)registerJavaScriptChannels:(NSSet*)channelNames
                        controller:(WKUserContentController*)controller {
  for (NSString* channelName in channelNames) {
    FLTJavaScriptChannel* c =
        [[FLTJavaScriptChannel alloc] initWithMethodChannel:channel
                                      javaScriptChannelName:channelName];
    [controller addScriptMessageHandler:c name:channelName];
    NSString* wrapperSource = [NSString
        stringWithFormat:@"window.%@ = webkit.messageHandlers.%@;", channelName, channelName];
    WKUserScript* wrapperScript =
        [[WKUserScript alloc] initWithSource:wrapperSource
                               injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                            forMainFrameOnly:NO];
    [controller addUserScript:wrapperScript];
  }
}

- (void)onAddJavaScriptChannels:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSArray* channelNames = [call arguments];
  NSSet* channelNamesSet = [[NSSet alloc] initWithArray:channelNames];
  [self.jsChannels addObjectsFromArray:channelNames];
  NSLog(@"added. channels: %@", self.jsChannels);
  if (self.webview != nil) {
    [_javaScriptChannelNames addObjectsFromArray:channelNames];
    [self registerJavaScriptChannels:channelNamesSet
          controller:self.webview.configuration.userContentController];
  }
  result(nil);
}

- (void)onRemoveJavaScriptChannels:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSArray* channelNamesToRemove = [call arguments];
  [self.jsChannels removeObjectsInArray:channelNamesToRemove];
  NSLog(@"removed. channels: %@", self.jsChannels);
  if (self.webview != nil) {
    // WkWebView does not support removing a single user script, so instead we remove all
    // user scripts, all message handlers. And re-register channels that shouldn't be removed.
    [self.webview.configuration.userContentController removeAllUserScripts];
    for (NSString* channelName in _javaScriptChannelNames) {
      [self.webview.configuration.userContentController removeScriptMessageHandlerForName:channelName];
    }

    for (NSString* channelName in channelNamesToRemove) {
      [_javaScriptChannelNames removeObject:channelName];
    }

    [self registerJavaScriptChannels:_javaScriptChannelNames
                          controller:self.webview.configuration.userContentController];
  }

  result(nil);
}

#pragma mark -- UIScrollViewDelegate
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView.pinchGestureRecognizer.isEnabled != _enableZoom) {
        scrollView.pinchGestureRecognizer.enabled = _enableZoom;
    }
}

@end


@implementation FLTJavaScriptChannel {
  FlutterMethodChannel* _methodChannel;
  NSString* _javaScriptChannelName;
}

- (instancetype)initWithMethodChannel:(FlutterMethodChannel*)methodChannel
                javaScriptChannelName:(NSString*)javaScriptChannelName {
  self = [super init];
  NSAssert(methodChannel != nil, @"methodChannel must not be null.");
  NSAssert(javaScriptChannelName != nil, @"javaScriptChannelName must not be null.");
  if (self) {
    _methodChannel = methodChannel;
    _javaScriptChannelName = javaScriptChannelName;
  }
  return self;
}

- (void)userContentController:(WKUserContentController*)userContentController
      didReceiveScriptMessage:(WKScriptMessage*)message {
  NSAssert(_methodChannel != nil, @"Can't send a message to an unitialized JavaScript channel.");
  NSAssert(_javaScriptChannelName != nil,
           @"Can't send a message to an unitialized JavaScript channel.");
  NSDictionary* arguments = @{
    @"channel" : _javaScriptChannelName,
    @"message" : [NSString stringWithFormat:@"%@", message.body]
  };
  [_methodChannel invokeMethod:@"javascriptChannelMessage" arguments:arguments];
}

@end