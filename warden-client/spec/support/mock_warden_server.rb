require "socket"
require "tempfile"
require "warden/protocol"

class Session

  def initialize(sock, handler = nil)
    @sock = sock
    @handler = handler

    # Post-initialization
    handle(nil)
  end

  def handle(request)
    @handler.call(self, request) if @handler
  end

  def close
    @sock.close
  ensure
    @sock = nil
  end

  def respond(response)
    data = response.wrap.encode.to_s
    @sock.write data.length.to_s + "\r\n"
    @sock.write data + "\r\n"
  end

  def run!
    while @sock && length = @sock.gets
      data = @sock.read(length.to_i)

      # Discard \r\n
      @sock.read(2)

      wrapped_request = Warden::Protocol::WrappedRequest.decode(data)
      handle(wrapped_request.request)
    end
  end
end

shared_context :mock_warden_server do

  SERVER_PATH = File.expand_path("../../../tmp/mock_server.sock", __FILE__)

  def new_client
    Warden::Client.new(SERVER_PATH)
  end

  def start_server(&blk)
    # Make sure the path to the unix socket is not used
    FileUtils.rm_rf(SERVER_PATH)

    # Create unix socket server
    server = UNIXServer.new(SERVER_PATH)

    # Accept new connections from a thread
    @server = Thread.new do
      begin
        loop do
          session = Session.new(server.accept, blk)
          session.run!
        end
      rescue => ex
        STDERR.puts ex.message
        STDERR.puts ex.backtrace
        raise
      end
    end
  end

  after(:each) do
    @server.kill if @server
  end
end
