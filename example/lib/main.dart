import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_webview_plugin/flutter_webview_plugin.dart';

const kAndroidUserAgent =
    'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/62.0.3202.94 Mobile Safari/537.36';

String selectedUrl = 'https://m.zfrontier.com/gamer';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  final flutterWebViewPlugin = FlutterWebviewPlugin();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter WebView Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      routes: {
        '/': (_) => const MyHomePage(title: 'Flutter WebView Demo'),
        '/widget': (_) {
          return WebviewScaffold(
            url: selectedUrl,
            appBar: AppBar(
              title: const Text('Widget WebView'),
            ),
            withZoom: true,
            withLocalStorage: true,
            hidden: true,
            initialChild: Container(
              color: Colors.redAccent,
              child: const Center(
                child: Text('Waiting.....'),
              ),
            ),
            bottomNavigationBar: BottomAppBar(
              child: Row(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: () {
                      flutterWebViewPlugin.goBack();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios),
                    onPressed: () {
                      flutterWebViewPlugin.goForward();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.autorenew),
                    onPressed: () {
                      flutterWebViewPlugin.reload();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // Instance of WebView plugin
  FlutterWebviewPlugin flutterWebViewPlugin;

  // On destroy stream
  StreamSubscription _onDestroy;

  // On urlChanged stream
  StreamSubscription<String> _onUrlChanged;

  // On urlChanged stream
  StreamSubscription<WebViewStateChanged> _onStateChanged;

  StreamSubscription<WebViewHttpError> _onHttpError;

  StreamSubscription<double> _onProgressChanged;

  StreamSubscription<String> _onUpdateHistory;

  StreamSubscription<double> _onScrollYChanged;

  StreamSubscription<double> _onScrollXChanged;

  final _urlCtrl = TextEditingController(text: selectedUrl);

  final _codeCtrl = TextEditingController(text: 'window.navigator.userAgent');

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  final _history = [];

  bool _canGoBack = false;

  @override
  void initState() {
    super.initState();

    _urlCtrl.addListener(() {
      selectedUrl = _urlCtrl.text;
    });

    _setupPlugin();
    if (flutterWebViewPlugin != null) {
      flutterWebViewPlugin.close();
    }
  }

  void _processJsMessage (JavascriptMessage message) {
    print("receive zFApp channel msg: ${message.message}");
    // todo
  }

  void _setupPlugin() {
    if (!mounted) return;
    print("setup plugin");
    final p = new FlutterWebviewPlugin();
    if (flutterWebViewPlugin == p) return;
    flutterWebViewPlugin = p;

    print("set nav & js channel");
    FlutterWebviewPlugin.navigationDelegate = (NavigationRequest r) {
      print("nav request: ${r.url}");
      if (r.url.startsWith('https://flutter.dev/docs/get-started/install')) {
        print("nav prevent");
        return NavigationDecision.prevent;
      }
      return NavigationDecision.navigate;
    };

    final List<JavascriptChannel> channels = <JavascriptChannel>[
      JavascriptChannel(name: 'zFApp', onMessageReceived: _processJsMessage)
    ];
    FlutterWebviewPlugin.javascriptChannel = channels.toSet();

    print("add listeners");
    // Add a listener to on destroy WebView, so you can make came actions.
    _onDestroy = flutterWebViewPlugin.onDestroy.listen((_) {
      if (mounted) {
        // Actions like show a info toast.
        _scaffoldKey.currentState.showSnackBar(const SnackBar(content: const Text('Webview Destroyed')));
      }
    });

    // Add a listener to on url changed
    _onUrlChanged = flutterWebViewPlugin.onUrlChanged.listen((String url) async {
      print("url change listened: $url");
      if (mounted) {
        setState(() {
          _history.add('onUrlChanged: $url');
        });
      }
    });

    // Add a listener to on url changed
    _onUpdateHistory = flutterWebViewPlugin.onUpdateHistory.listen((String url) async {
      print("history change listened: $url");
      if (mounted) {
        final canGoBack = await flutterWebViewPlugin.canGoBack();
        print("can go back: ${canGoBack}");
        setState(() {
          _canGoBack = canGoBack;
        });
      }
    });

    _onProgressChanged = flutterWebViewPlugin.onProgressChanged.listen((double progress) {
      if (mounted) {
        setState(() {
          _history.add("onProgressChanged: $progress");
        });
      }
    });

    _onScrollYChanged = flutterWebViewPlugin.onScrollYChanged.listen((double y) {
      print("scroll y listened: $y");
      if (mounted) {
        setState(() {
          _history.add('Scroll in Y Direction: $y');
        });
      }
    });

    _onScrollXChanged = flutterWebViewPlugin.onScrollXChanged.listen((double x) {
      if (mounted) {
        setState(() {
          _history.add('Scroll in X Direction: $x');
        });
      }
    });

    _onStateChanged = flutterWebViewPlugin.onStateChanged.listen((WebViewStateChanged state) {
      print("state change listened: ${state.type}");
      if (mounted) {
        print("send js msg");
        flutterWebViewPlugin.evalJavascript("zFApp.postMessage('test: onState ${state.type}');");
        setState(() {
          _history.add('onStateChanged: ${state.type} ${state.url}');
        });
      }
    }, onDone: () {
      _setupPlugin();
    });

    _onHttpError = flutterWebViewPlugin.onHttpError.listen((WebViewHttpError error) {
      if (mounted) {
        setState(() {
          _history.add('onHttpError: ${error.code} ${error.url}');
        });
      }
    });
  }

  @override
  void dispose() {
    print("dispose");
    // Every listener should be canceled, the same should be done with this stream.
    _onDestroy.cancel();
    _onUrlChanged.cancel();
    _onStateChanged.cancel();
    _onHttpError.cancel();
    _onProgressChanged.cancel();
    _onUpdateHistory.cancel();
    _onScrollXChanged.cancel();
    _onScrollYChanged.cancel();

    flutterWebViewPlugin.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Plugin example app'),
      ),
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24.0),
              child: TextField(controller: _urlCtrl),
            ),
            RaisedButton(
              onPressed: () {
                flutterWebViewPlugin.launch(
                  selectedUrl,
                  rect: Rect.fromLTWH(0.0, 0.0, MediaQuery.of(context).size.width, 300.0),
                  userAgent: kAndroidUserAgent,
                  invalidUrlRegex: r'^(https).+(twitter)', // prevent redirecting to twitter when user click on its icon in flutter website
                );
                flutterWebViewPlugin.evalJavascript("zFApp.postMessage('test channel');");
              },
              child: const Text('Open Webview (rect)'),
            ),
            RaisedButton(
              onPressed: () {
                flutterWebViewPlugin.launch(selectedUrl, hidden: true);
              },
              child: const Text('Open "hidden" Webview'),
            ),
            RaisedButton(
              onPressed: () {
                flutterWebViewPlugin.launch(selectedUrl);
              },
              child: const Text('Open Fullscreen Webview'),
            ),
            RaisedButton(
              onPressed: () {
                Navigator.of(context).pushNamed('/widget');
              },
              child: const Text('Open widget webview'),
            ),
            Container(
              padding: const EdgeInsets.all(24.0),
              child: TextField(controller: _codeCtrl),
            ),
            RaisedButton(
              onPressed: () {
                final future = flutterWebViewPlugin.evalJavascript(_codeCtrl.text);
                future.then((String result) {
                  setState(() {
                    _history.add('eval: $result');
                  });
                });
              },
              child: const Text('Eval some javascript'),
            ),
            RaisedButton(
              onPressed: () {
                setState(() {
                  _history.clear();
                });
                flutterWebViewPlugin.close();
              },
              child: const Text('Close'),
            ),
            RaisedButton(
              onPressed: _canGoBack ?  () {
                flutterWebViewPlugin.goBack();
              } : null,
              child: const Text('Back'),
            ),
            RaisedButton(
              onPressed: () {
                flutterWebViewPlugin.getCookies().then((m) {
                  setState(() {
                    _history.add('cookies: $m');
                  });
                });
              },
              child: const Text('Cookies'),
            ),
            Text(_history.join('\n'))
          ],
        ),
      ),
    );
  }
}
