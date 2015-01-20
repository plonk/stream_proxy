require 'optparse'
require 'logger'
require_relative 'proxy'

def parse_options
  options = {}
  OptionParser.new do |opt|
    opt.on('-d', 'デバッグ') do |v|
      $DEBUG = v
    end
    opt.on('--pecastation [HOSTNAME]', 'PeerCastStationのアドレス') do |v|
      options[:pecast_ip] = v
    end
    opt.on('--pecastation-port [HOSTNAME]', 'PeerCastStationのポート') do |v|
      options[:pecast_port] = v
    end
    opt.on('--host [HOSTNAME]', '待機するアドレス') do |v|
      options[:host] = v
    end
    opt.on('--port [NUM]', '待機するポート') do |v|
      options[:port] = v.to_i
    end
    opt.parse!(ARGV)
  end
  options
end

options = parse_options

if $DEBUG
  log = Logger.new(STDOUT)
  log.level = Logger::DEBUG
else
  log = Logger.new('proxy.log', 'daily')
  log.level = Logger::INFO
end

ProxyServer.new(log, options).run
