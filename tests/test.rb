# 不正な要求を送ってサーバを落とすテスト
require_relative '../proxy'

class MockPeercast
end

describe ProxyServer::Session do
  context "with invalid request line" do
    before do
      @pecast = MockPeercast.new
      @socket = StringIO.new("\0")
      @session = ProxyServer::Session.new(@socket, @pecast)
    end

    it "should raise error" do
      expect { @session.call }.to raise_error(StandardError)
    end

    it "'s socket should be closed" do
      expect { @session.call rescue nil }.to change { @socket.closed? }
    end
  end
end
