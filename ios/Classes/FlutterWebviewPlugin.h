#import <Flutter/Flutter.h>
#import <WebKit/WebKit.h>

static FlutterMethodChannel *channel;

@interface FlutterWebviewPlugin : NSObject<FlutterPlugin>
@property (nonatomic, retain) UIViewController *viewController;
@property (nonatomic, retain) WKWebView *webview;
@property (nonatomic, retain) NSMutableArray *jsChannels;
@end

@interface FLTJavaScriptChannel : NSObject <WKScriptMessageHandler>

- (instancetype)initWithMethodChannel:(FlutterMethodChannel*)methodChannel
                javaScriptChannelName:(NSString*)javaScriptChannelName;

@end