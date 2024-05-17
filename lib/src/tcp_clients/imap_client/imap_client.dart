import 'dart:async';
import 'dart:io';

import 'package:wuchuheng_email_storage/src/config/config.dart';
import 'package:wuchuheng_email_storage/src/exceptions/imap_response_exception.dart';
import 'package:wuchuheng_email_storage/src/tcp_clients/imap_client/dto/current_execute_command.dart';
import 'package:wuchuheng_email_storage/src/tcp_clients/imap_client/dto/request.dart';
import 'package:wuchuheng_email_storage/src/tcp_clients/imap_client/dto/response/capability_response.dart';
import 'package:wuchuheng_email_storage/src/tcp_clients/imap_client/imap_client_abstract.dart';
import 'package:wuchuheng_email_storage/src/utilities/log.dart';

import './services/connect_service.dart' as connect_service;
import './services/capability_service.dart' as capability_service;

class ImapClient implements ImapClientAbstract {
  final String host;
  final String username;
  final String password;
  final Duration timeout;
  late SecureSocket _socket;

  ImapClient({
    required this.host,
    required this.username,
    required this.password,
    this.timeout = const Duration(seconds: 5),
  }) {
    assert(host.isNotEmpty, 'The host cannot be empty.');
    assert(username.isNotEmpty, 'The username cannot be empty.');
    assert(password.isNotEmpty, 'The password cannot be empty.');
    assert(timeout.inSeconds > 0, 'The timeout must be greater than 0.');
  }

  @override
  Future<void> connect() async {
    _socket = await connect_service.connect(
      host: host,
      timeout: timeout,
      onData: _onData,
    );
  }

  /// Store the response data into the flush;
  List<String> _flush = [];

  _onData(String data) {
    // 1. Get the tag for the current command.
    final String tag = _currentExecuteCommand!.request.tag;

    // 2. Parse the data from the server, and complete the completer.
    data.split(EOF).where((e) => e.isNotEmpty).forEach((line) {
      // 2.1 Add the line to the flush.
      _flush.add(line);

      // 2.2 Complete the completer if the line contains the tag.
      final isLastLine =
          line.contains('OK') || line.contains('NO') || line.contains('BAD');
      if (isLastLine) {
        final tagFromServer = line.split(' ').first;

        // 2.2.1 Check if the tag from the server is the same as the tag from the client.
        // And then complete the completer.
        if (tagFromServer == tag) {
          _currentExecuteCommand?.timer.cancel();
          _currentExecuteCommand?.completer.complete(_flush);
          _flush = [];
        }
      }
    });
  }

  /// Define the completer to wait the current command response from the server
  CurrentExecuteCommand? _currentExecuteCommand;

  /// handle the data write to the server by the socket.
  Future<List<String>> _write({required Request request}) async {
    // 1. Wait the previous command response from the server finished.
    if (_currentExecuteCommand?.completer.isCompleted == false) {
      await _currentExecuteCommand!.completer.future;
    }

    // 2. Create a completer to wait the current command response from the server.
    // 2.1 Create a timer to handle the timeout of the current command.
    final timer = Timer(commandTimeout, () {
      final command = request.command.toString().split(' ').last.toUpperCase();
      _currentExecuteCommand!.completer.completeError(
        ResponseException('The command $command timeout.'),
      );
    });
    _currentExecuteCommand = CurrentExecuteCommand(
      request: request,
      completer: Completer(),
      timer: timer,
    );

    // 3. write the request to the server.
    final message = request.toMessage();
    log(message.substring(0, message.length - 2), level: LogLevel.TCP_OUTGOING);
    _socket.write(message);

    // 4. Return the completer future.
    return _currentExecuteCommand!.completer.future;
  }

  @override
  Future<CapabilityResponse> capability() async {
    return capability_service.capability(writeCommand: _write);
  }
}
