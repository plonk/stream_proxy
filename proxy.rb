require 'logger'
require 'timeout'
require 'ostruct'
require 'monitor'
require_relative 'util'

class ProxyServer
  include Util

  SERVER_NAME = "proxy/0.0.1"

  def initialize(log = Logger.new(STDOUT), options = {})
    host = options[:host] || '0.0.0.0'
    port = options[:port] || 8888
    @socket = TCPServer.open(host, port)
    @log = log
    @options = options
    @pecast_ip = options[:pecast_ip] || 'localhost'
    @pecast_port = options[:pecast_port] || 7144
    log.info format('server is on %s', addr_format(@socket.addr))
    log.info format('PeerCastStation: %p', pecast.getVersionInfo)
  end

  def run
    loop do
      client = @socket.accept
      @log.info "connection accepted #{addr_format(client.peeraddr)}"

      t = Thread.start do
        begin
          session = Session.new(client, pecast)
          session.call

        rescue => e
          @log.info "exception occured: #{e.inspect}"
        end
      end
    end
  rescue Interrupt
    @log.info 'interrupt from terminal'

    # 後処理
  end

  def pecast
    Peercast.new(@pecast_ip, @pecast_port)
  end

  require 'timeout'
  require_relative 'peercast'

  class Session
    include Timeout

    BUF_SIZE = 64 * 1024

    def initialize(client, pecast)
      @client = client
      @pecast = pecast
    end

    def call
      req = http_request
      handle_request(req)
    ensure
      @client.close
    end

    private

    def http_request
      if (line = @client.gets) =~ /\A([A-Z]+) (\S+) (\S+)\r\n\z/
        meth, path, version = Regexp.last_match.to_a.slice(1..3)
      else
        fail "invalid request line: #{line.inspect}"
      end

      # read headers
      headers = {}
      while (line = @client.gets) != "\r\n"
        if line =~ /\A([^:]+):\s*(.+)\r\n\z/
          key, value = Regexp.last_match.to_a.slice(1..2)
          headers[key] = value
        else
          fail "invalid header line: #{line.inspect}"
        end
      end
      OpenStruct.new(meth: meth, path: path, version: version,
                     headers: headers)
    end

    def handle_stats_request(request)
      @client.write "HTTP/1.0 200 OK\r\n"
      @client.write "Content-Type: text/plain\r\n"
      @client.write "\r\n"
      @client.write "stats page under construction"
    end

    # 新しいリレーを開始できないように、既存のチャンネルだけを視聴させる
    def request_valid?(request)
      ids = @pecast.getChannels.map { |h| h['channelId'] }
      if request.path =~ /^\/(stream|pls)\/([A-Z0-9]+)/
        return ids.include?($2)
      else
        return false
      end
    end

    def handle_proxy_request(request)
      if request_valid?(request)
        peer = @pecast.open
        peer.write "GET #{request.path} HTTP/1.0\r\n"
        request.headers.each do |fld, val|
          peer.write "#{fld}: #{val}\r\n"
        end
        peer.write "\r\n"
        loop do
          timeout 5 do
            data = peer.read(BUF_SIZE)
            @client.write(data)
          end
        end
      else
        bad_request
      end
    rescue => e
      puts "exception in handle_proxy_request #{e}"
    ensure
      peer.close
    end

    def bad_request
      @client.write "HTTP/1.0 400 Bad Request\r\n"
      @client.write "Server: #{SERVER_NAME}\r\n"
      @client.write "\r\n"
    end

    def handle_request(request)
      case request.meth
      when 'GET'
        case request.path
        when "/stats"
          handle_stats_request(request)
        when /^\/(stream|pls)\//
          handle_proxy_request(request)
        else
          bad_request
        end
      else
        bad_request
      end
    end
  end
end
