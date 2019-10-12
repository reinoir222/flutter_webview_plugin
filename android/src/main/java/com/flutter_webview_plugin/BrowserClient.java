package com.flutter_webview_plugin;

import android.annotation.TargetApi;
import android.graphics.Bitmap;
import android.os.Build;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import io.flutter.plugin.common.MethodChannel;

import java.util.HashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Created by lejard_h on 20/12/2017.
 */

public class BrowserClient extends WebViewClient {
    private Pattern invalidUrlPattern = null;
    private boolean hasNavigationDelegate = false;

    public BrowserClient() {
        this(null);
    }

    public BrowserClient(String invalidUrlRegex) {
        super();
        if (invalidUrlRegex != null) {
            invalidUrlPattern = Pattern.compile(invalidUrlRegex);
        }
    }

    public void updateInvalidUrlRegex(String invalidUrlRegex) {
        if (invalidUrlRegex != null) {
            invalidUrlPattern = Pattern.compile(invalidUrlRegex);
        } else {
            invalidUrlPattern = null;
        }
    }

    public void updateHasNav(boolean hasNav) {
        hasNavigationDelegate = hasNav;
    }

    @Override
    public void doUpdateVisitedHistory(WebView view, String url, boolean isReload) {
        super.doUpdateVisitedHistory(view, url, isReload);
        Map<String, Object> data = new HashMap<>();
        data.put("url", url);
        data.put("isReload", isReload);
        FlutterWebviewPlugin.channel.invokeMethod("onUpdateHistory", data);
    }

    @Override
    public void onPageStarted(WebView view, String url, Bitmap favicon) {
        super.onPageStarted(view, url, favicon);
        Map<String, Object> data = new HashMap<>();
        data.put("url", url);
        data.put("type", "startLoad");
        FlutterWebviewPlugin.channel.invokeMethod("onState", data);
    }

    @Override
    public void onPageFinished(WebView view, String url) {
        super.onPageFinished(view, url);
        Map<String, Object> data = new HashMap<>();
        data.put("url", url);

        FlutterWebviewPlugin.channel.invokeMethod("onUrlChanged", data);

        data.put("type", "finishLoad");
        FlutterWebviewPlugin.channel.invokeMethod("onState", data);

    }

    @TargetApi(Build.VERSION_CODES.LOLLIPOP)
    @Override
    public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
        // returning true causes the current WebView to abort loading the URL,
        // while returning false causes the WebView to continue loading the URL as usual.
        String url = request.getUrl().toString();
        boolean isForMainFrame = request.isForMainFrame();
        boolean isInvalid = checkInvalidUrl(url);
        if (isInvalid) {
            sendState(url, isInvalid);
            return true;
        }

        if (!this.hasNavigationDelegate) return false;
        HashMap<String, Object> args = new HashMap<>();
        args.put("url", url);
        args.put("isForMainFrame", isForMainFrame);
        if (isForMainFrame) {
            Map<String, String> headers = new HashMap();
            Map rhs = request.getRequestHeaders();
            if (rhs != null) {
                headers.putAll(rhs);
            }
            if (FlutterWebviewPlugin.customHeader != null) {
                headers.putAll(FlutterWebviewPlugin.customHeader);
            }
            FlutterWebviewPlugin.channel.invokeMethod(
                    "onNavRequest",
                    args,
                    new OnNavigationRequestResult(url, headers, view)
            );
        } else {
            FlutterWebviewPlugin.channel.invokeMethod("onNavRequest", args);
        }
        // We must make a synchronous decision here whether to allow the navigation or not,
        // if the Dart code has set a navigation delegate we want that delegate to decide whether
        // to navigate or not, and as we cannot get a response from the Dart delegate synchronously we
        // return true here to block the navigation, if the Dart delegate decides to allow the
        // navigation the plugin will later make an addition loadUrl call for this url.
        //
        // Since we cannot call loadUrl for a subframe, we currently only allow the delegate to stop
        // navigations that target the main frame, if the request is not for the main frame
        // we just return false to allow the navigation.
        //
        // For more details see: https://github.com/flutter/flutter/issues/25329#issuecomment-464863209
        return isForMainFrame;
    }

    @TargetApi(Build.VERSION_CODES.LOLLIPOP)
    @Override
    public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse errorResponse) {
        super.onReceivedHttpError(view, request, errorResponse);
        Map<String, Object> data = new HashMap<>();
        data.put("url", request.getUrl().toString());
        data.put("code", Integer.toString(errorResponse.getStatusCode()));
        FlutterWebviewPlugin.channel.invokeMethod("onHttpError", data);
    }

    @Override
    public void onReceivedError(WebView view, int errorCode, String description, String failingUrl) {
        super.onReceivedError(view, errorCode, description, failingUrl);
        Map<String, Object> data = new HashMap<>();
        data.put("url", failingUrl);
        data.put("code", Integer.toString(errorCode));
        FlutterWebviewPlugin.channel.invokeMethod("onHttpError", data);
    }

    private boolean checkInvalidUrl(String url) {
        if (invalidUrlPattern == null) {
            return false;
        } else {
            Matcher matcher = invalidUrlPattern.matcher(url);
            return matcher.lookingAt();
        }
    }

    public static void sendState(String url, boolean isInvalid) {
        Map<String, Object> data = new HashMap<>();
        data.put("url", url);
        data.put("type", isInvalid ? "abortLoad" : "shouldStart");
        FlutterWebviewPlugin.channel.invokeMethod("onState", data);
    }

    private static class OnNavigationRequestResult implements MethodChannel.Result {
        private final String url;
        private final Map<String, String> headers;
        private final WebView webView;

        private OnNavigationRequestResult(String url, Map<String, String> headers, WebView webView) {
            this.url = url;
            this.headers = headers;
            this.webView = webView;
        }

        @Override
        public void success(Object shouldLoad) {
            Boolean typedShouldLoad = (Boolean) shouldLoad;
            sendState(url, !typedShouldLoad);
            if (typedShouldLoad) {
                loadUrl();
            }
        }

        @Override
        public void error(String errorCode, String s1, Object o) {
            throw new IllegalStateException("onNavRequest calls must succeed: " + s1);
        }

        @Override
        public void notImplemented() {
            throw new IllegalStateException(
                    "onNavRequest must be implemented by the webview method channel");
        }

        private void loadUrl() {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                webView.loadUrl(url, headers);
            } else {
                webView.loadUrl(url);
            }
        }
    }
}