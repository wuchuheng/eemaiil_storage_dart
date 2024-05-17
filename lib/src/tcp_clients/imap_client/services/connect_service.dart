import 'dart:async';
import 'dart:io';

import '../../../config/config.dart';
import '../../../utilities/log.dart';

/// Connect to the IMAP server over a secure socket.
///
/// The [host] is the hostname of the IMAP server.
/// The [timeout] is the duration to wait for the connection to be established.
///
Future<SecureSocket> connect({
  required String host,
  required Duration timeout,
  required Function(String) onData,
}) async {
  // 1. Create a result completer to return the result of the connection.
  final Completer<SecureSocket> result = Completer();

  // 2. Create a timer to wait for the initial greeting from the server.
  // 2.1 If the initial greeting is not received within the timeout, complete the result completer with an error.
  final timer = Timer(timeout, () {
    result.completeError(
        'The IMAP server did not respond with an initial greeting.');
  });

  // 3. Connect to the IMAP server over a secure socket using the host and port 993. and set the timeout.
  final socket = await SecureSocket.connect(host, 993, timeout: timeout);

  // 4. Listen for response from the server.
  socket.listen((List<int> data) {
    final String response = String.fromCharCodes(data);

    // 4.1 Check if the initial greeting is received.
    if (response.isNotEmpty) {
      // 4.1.1 If the initial greeting is received, complete the result completer with the secure socket.
      result.complete(socket);

      // 4.1.2 Cancel the timer.
      timer.cancel();

      // 4.1.3 Bind the onData callback of the socket to the `onData` callback.
      response.split(EOF).where((line) => line.isNotEmpty).forEach((line) {
        log(line, level: LogLevel.TCP_COMING);

        onData(line);
      });
    }
  });

  // 5. Wait for the first response from the server.
  return result.future;
}
