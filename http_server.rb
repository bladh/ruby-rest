require 'socket'
require 'json'
require 'securerandom'
require 'logger'

# A simple HTTP server that handles GET and POST requests with JSON responses
class HTTPServer
  CONTENT_TYPE = 'application/json'
  HTTP_VERSION = 'HTTP/1.1'

  # Initialize a new HTTP server
  # @param port [Integer] The port to listen on
  # @param logger [Logger] Optional logger instance (defaults to STDOUT)
  def initialize(port, logger = Logger.new($stdout))
    @logger = configure_logger(logger)
    @server = TCPServer.new(port)
    @routes = Hash.new { |h, k| h[k] = [] }
    @logger.info("Server initialized on port #{port}")
  end

  # Register a GET route
  # @param path [String] The route path (can include parameters like :id)
  # @yield [Hash] Handler block receiving merged params and body
  def get(path, &handler)
    add_route('GET', path, handler)
  end

  # Register a POST route
  # @param path [String] The route path (can include parameters like :id)
  # @yield [Hash] Handler block receiving merged params and body
  def post(path, &handler)
    add_route('POST', path, handler)
  end

  # Start the server and begin accepting connections
  def start
    @logger.info("Server started at http://localhost:#{@server.addr[1]}")
    loop { Thread.new(@server.accept) { |client| handle_request(client) } }
  ensure
    shutdown_server
  end

  private

  def configure_logger(logger)
    logger.formatter = proc do |severity, time, _, msg|
      "[#{time.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}:\t#{msg}\n"
    end
    logger
  end

  def shutdown_server
    @logger.info('Server stopped.')
    @server&.close
  end

  def add_route(method, path, handler)
    pattern = path.split('/').map do |segment|
      segment.start_with?(':') ? [:param, segment[1..]] : [:static, segment]
    end
    @routes[method] << [pattern, handler]
  end

  def match_route(method, path)
    path_segments = path.split('/')
    @routes[method].each do |pattern, handler|
      next unless pattern.length == path_segments.length

      params = {}
      matches = pattern.each_with_index.all? do |(type, value), i|
        type == :static ? value == path_segments[i] : params[value] = path_segments[i]
      end

      return [handler, params] if matches
    end
    nil
  end

  def handle_request(client)
    request_line = client.gets&.split
    return unless request_line

    request_id = SecureRandom.hex(4)
    method, path = request_line
    process_request(client, method, path, request_id)
  ensure
    client.close
  end

  def process_request(client, method, path, request_id)
    headers = parse_headers(client)
    body = read_body(client, headers['content-length'])

    @logger.info("\##{request_id} #{method} #{path} from #{client.peeraddr[3]}")

    if (match = match_route(method, path))
      handle_matched_route(client, match, body, request_id)
    else
      handle_not_found(client, method, path, request_id)
    end
  end

  def handle_matched_route(client, match, body, request_id)
    handler, params = match
    json = parse_json_body(body).merge(params)
    result = handler.call(json)
    response, status = result.is_a?(Array) ? result : [result, 200]
    send_response(client, response, status)
    @logger.info("\##{request_id} Response: #{status}")
  rescue JSON::ParserError => error
    @logger.error("\##{request_id} JSON parse error: #{error.message}")
    send_response(client, { error: 'Invalid JSON', details: error.message }, 400)
  end

  def handle_not_found(client, method, path, request_id)
    send_response(client, { error: 'Not Found' }, 404)
    @logger.warn("\##{request_id} Route not found: #{method} #{path}")
  end

  def parse_headers(client)
    headers = {}
    while (line = client.gets.chomp) != ''
      key, value = line.split(': ', 2)
      headers[key.downcase] = value
    end
    headers
  end

  def read_body(client, content_length)
    content_length ? client.read(content_length.to_i) : ''
  end

  def parse_json_body(body)
    body.empty? ? {} : JSON.parse(body)
  end

  def send_response(client, data, status = 200)
    body = JSON.generate(data)
    client.write([
      "#{HTTP_VERSION} #{status}",
      "Content-Type: #{CONTENT_TYPE}",
      "Content-Length: #{body.bytesize}",
      '',
      body
    ].join("\r\n"))
  end
end
