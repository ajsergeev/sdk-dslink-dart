part of dslink.http_server;

class DsHttpServer {
  /// to open a secure server, SecureSocket.initialize() need to be called before start()
  DsHttpServer.start(dynamic address, {int httpPort: 80, int httpsPort: 443, String certificateName, this.nodeProvider}) {
    if (httpPort > 0) {
      HttpServer.bind(address, httpPort).then((server) {
        print('listen on $httpPort');
        server.listen(_handleRqeuest);
      }).catchError((Object err) {
        print(err);
      });
    }
    
    if (httpsPort > 0 && certificateName != null) {
      HttpServer.bindSecure(address, httpsPort, certificateName: certificateName).then((server) {
        print('listen on $httpsPort');
        server.listen(_handleRqeuest);
      }).catchError((Object err) {
        print(err);
      });
    }
  }
  
  final NodeProvider nodeProvider;
  final Map<String, HttpServerLink> _sessions = new Map<String, HttpServerLink>();

  void _handleRqeuest(HttpRequest request) {
    try {
      String dsId = request.uri.queryParameters['dsId'];
      
      if (dsId == null || dsId.length < 64) {
        request.response.close();
        return;
      }
      
      switch (request.requestedUri.path) {
        case '/conn':
          _handleConn(request, dsId);
          break;
        case '/http':
          _handleHttpUpdate(request, dsId);
          break;
        case '/ws':
          _handleWsUpdate(request, dsId);
          break;
        default:
          request.response.close();
      }
    } catch (err) {
      if (err is int) {
        // TODO need protection because changing statusCode itself can throw
        request.response.statusCode = err;
      }
      request.response.close();
    }
  }

  void _handleConn(HttpRequest request, String dsId) {
    request.fold([], foldList).then((List<int> merged) {
      try {
        if (merged.length > 1024) {
          // invalid connection request
          request.response.close();
          return;
        }
        String str = UTF8.decode(merged);
        Map m = JSON.decode(str);
        HttpServerLink session = _sessions[dsId];
        if (session == null) {
          String modulus = m['publicKey'];
          var bytes = Base64.decode(modulus);
          if (bytes == null) {
            // public key is invalid
            throw HttpStatus.BAD_REQUEST;
          }
          session = new HttpServerLink(dsId, new BigInteger.fromBytes(1, bytes), nodeProvider: nodeProvider);
          if (!session.valid) {
            // dsId doesn't match public key
            throw HttpStatus.BAD_REQUEST;
          }
          _sessions[dsId] = session;
        }
        session.initSession(request);
      } catch (err) {
        if (err is int) {
          // TODO need protection because changing statusCode itself can throw
          request.response.statusCode = err;
        }
        request.response.close();
      }
    });

  }
  void _handleHttpUpdate(HttpRequest request, String dsId) {
    HttpServerLink session = _sessions[dsId];
    if (session != null) {
      session._handleHttpUpdate(request);
    } else {
      throw HttpStatus.UNAUTHORIZED;
    }
  }

  void _handleWsUpdate(HttpRequest request, String dsId) {
    HttpServerLink session = _sessions[dsId];
    if (session != null) {
      session._handleWsUpdate(request);
    } else {
      throw HttpStatus.UNAUTHORIZED;
    }
  }
}