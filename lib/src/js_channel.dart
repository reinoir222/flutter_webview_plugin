import 'package:flutter/material.dart';

final RegExp _validChannelNames = RegExp('^[a-zA-Z_][a-zA-Z0-9]*\$');

/// Callback type for handling messages sent from Javascript running in a web view.
typedef void JavascriptMessageHandler(JavascriptMessage message);

/// A message that was sent by JavaScript code running in a [WebView].
class JavascriptMessage {
  /// Constructs a JavaScript message object.
  ///
  /// The `message` parameter must not be null.
  const JavascriptMessage(this.message) : assert(message != null);

  /// The contents of the message that was sent by the JavaScript code.
  final String message;
}

/// A named channel for receiving messaged from JavaScript code running inside a web view.
class JavascriptChannel {
  /// Constructs a Javascript channel.
  ///
  /// The parameters `name` and `onMessageReceived` must not be null.
  JavascriptChannel({
    @required this.name,
    @required this.onMessageReceived,
  })  : assert(name != null),
        assert(onMessageReceived != null),
        assert(_validChannelNames.hasMatch(name));

  /// The channel's name.
  ///
  /// Passing this channel object as part of a [WebView.javascriptChannels] adds a channel object to
  /// the Javascript window object's property named `name`.
  ///
  /// The name must start with a letter or underscore(_), followed by any combination of those
  /// characters plus digits.
  ///
  /// Note that any JavaScript existing `window` property with this name will be overriden.
  ///
  /// See also [WebView.javascriptChannels] for more details on the channel registration mechanism.
  final String name;

  /// A callback that's invoked when a message is received through the channel.
  final JavascriptMessageHandler onMessageReceived;
}