@TestOn('vm')
import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:test/test.dart';
import 'package:webdriver/io.dart';

void main() {
  HttpServer server;
  WebDriver webdriver;
  SseHandler handler;

  setUp(() async {
    handler = SseHandler(Uri.parse('/test'));

    var cascade = new shelf.Cascade()
        .add(handler.handler)
        .add(_faviconHandler)
        .add(createStaticHandler('test/web',
            listDirectories: true, defaultDocument: 'index.html'));

    server = await io.serve(cascade.handler, 'localhost', 0);
    webdriver = await createDriver();
  });

  tearDown(() async {
    await webdriver.quit();
    await server.close();
  });

  test('Can round trip messages', () async {
    await webdriver.get('http://localhost:${server.port}');
    var connection = await handler.connections.next;
    connection.sink.add('blah');
    expect(await connection.stream.first, 'blah');
  });

  test('Multiple clients can connect', () async {
    var connections = await handler.connections;
    await webdriver.get('http://localhost:${server.port}');
    await connections.next;
    await webdriver.get('http://localhost:${server.port}');
    await connections.next;
  });

  test('Routes data correctly', () async {
    var connections = await handler.connections;
    await webdriver.get('http://localhost:${server.port}');
    var connectionA = await connections.next;
    await webdriver.get('http://localhost:${server.port}');
    var connectionB = await connections.next;

    connectionA.sink.add('foo');
    connectionB.sink.add('bar');
    await connectionA.onClose;
    expect(await connectionB.stream.first, 'bar');
  });

  test('Can close from the server', () async {
    expect(handler.numberOfClients, 0);
    await webdriver.get('http://localhost:${server.port}');
    var connection = await handler.connections.next;
    expect(handler.numberOfClients, 1);
    connection.close();
    await connection.onClose;
    expect(handler.numberOfClients, 0);
  });

  test('Can close from the client-side', () async {
    expect(handler.numberOfClients, 0);
    await webdriver.get('http://localhost:${server.port}');
    var connection = await handler.connections.next;
    expect(handler.numberOfClients, 1);

    var closeButton = await webdriver.findElement(const By.tagName('button'));
    await closeButton.click();

    await connection.onClose;
    expect(handler.numberOfClients, 0);
  });

  test('Disconnects when navigating away', () async {
    await webdriver.get('http://localhost:${server.port}');
    expect(handler.numberOfClients, 1);

    await webdriver.get('chrome://version/');
    expect(handler.numberOfClients, 0);
  });
}

FutureOr<shelf.Response> _faviconHandler(shelf.Request request) {
  if (request.url.path.endsWith('favicon.ico')) {
    return new shelf.Response.ok('');
  }
  return new shelf.Response.notFound('');
}