require 'logger'
require 'timeout'
require 'ostruct'
require 'monitor'
require_relative 'util'
require_relative 'peercast'

class ProxyServer
  include Util

  SERVER_NAME = "proxy/0.0.1"

  def initialize(log = Logger.new(STDOUT), options = {})
    host = options[:host] || '0.0.0.0'
    port = options[:port] || 8888
    @socket = TCPServer.open(host, port)
    @log = log
    @options = options
    @threads = []
    @monitor = Monitor.new # @threadsのロック
    @pecast_ip = options[:pecast_ip] || 'localhost'
    @pecast_port = options[:pecast_port] || 7144
    log.info format('server is on %s', addr_format(@socket.addr))
    log.info format('PeerCastStation: %p', pecast.getVersionInfo)
  end

  def pecast
    Peercast.new(@pecast_ip, @pecast_port)
  end

  def run
    loop do
      client = @socket.accept
      @log.info "connection accepted #{addr_format(client.peeraddr)}"

      t = Thread.start do
        process_request(client)
        catch(:quit) do
          @monitor.synchronize do
            if @threads.include?(t)
              @threads.delete(t)
              throw :quit
            end
          end while true
        end
      end
      @monitor.synchronize { @threads << t }
    end
  rescue Interrupt
    @log.info 'interrupt from terminal'

    # 後処理
  end

  private

  def process_request(s)
    req = http_request(s)
    handle_request(req, s)
  ensure
    s.close
  end

  def http_request(s)
    if (line = s.gets) =~ /\A([A-Z]+) (\S+) (\S+)\r\n\z/
      meth, path, version = Regexp.last_match.to_a.slice(1..3)
    else
      fail "invalid request line: #{line.inspect}"
    end

    # read headers
    headers = {}
    while (line = s.gets) != "\r\n"
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

  def handle_stats_request(request, s)
    s.write "HTTP/1.0 200 OK\r\n"
    s.write "Content-Type: text/plain\r\n"
    s.write "\r\n"
    s.write "stats page under construction"
  end

  # 新しいリレーを開始できないように、既存のチャンネルだけを視聴させる
  def request_valid?(request)
    ids = pecast.getChannels.map { |h| h['channelId'] }
    if request.path =~ /^\/(stream|pls)\/([A-Z0-9]+)/
      return ids.include?($2)
    else
      return false
    end
  end

  BUF_SIZE = 1024

  require 'timeout'
  include Timeout

  def handle_proxy_request(request, s)
    if request_valid?(request)
      peer = TCPSocket.new(@pecast_ip, @pecast_port)
      peer.write "GET #{request.path} HTTP/1.0\r\n"
      request.headers.each do |fld, val|
        peer.write "#{fld}: #{val}\r\n"
      end
      peer.write "\r\n"
      loop do
        timeout 5 do
          @log.debug('reading')
          data = peer.read(BUF_SIZE)
          @log.debug("read #{data.bytesize} bytes; writing...")
          s.write(data)
          @log.debug("written")
        end
      end
    else
      bad_request(s)
    end
  rescue => e
    puts "exception in handle_proxy_request #{e}"
  ensure
    peer.close
  end

  def bad_request(s)
    s.write "HTTP/1.0 400 Bad Request\r\n"
    s.write "Server: #{SERVER_NAME}\r\n"
    s.write "\r\n"
  end

  def handle_request(request, s)
    case request.meth
    when 'GET'
      case request.path
      when "/stats"
        handle_stats_request(request, s)
      when /^\/(stream|pls)\//
        handle_proxy_request(request, s)
      else
        bad_request(s)
      end
    else
      bad_request(s)
    end
  end
end
