require 'socket'

module Util
  def addr_format(addr)
    _address_family, port, _hostname, numeric_address = addr
    "#{numeric_address}:#{port}"
  end
  module_function :addr_format

  def host_ip
    IPSocket.getaddress(Socket.gethostname)
  end
  module_function :host_ip
end

