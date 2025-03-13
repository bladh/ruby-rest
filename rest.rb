require 'socket'
require 'json'
require 'sqlite3'
require 'securerandom'

def log(message, level = :info)
  timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
  color = case level
    when :info then "\e[32m" # Green
    when :warn then "\e[33m" # Yellow 
    when :error then "\e[31m" # Red
    else "\e[0m" # Default
  end
  reset_color = "\e[0m"
  
  puts "#{color}[#{timestamp}] #{level.upcase}:\t#{message}#{reset_color}"

  File.open('server.log', 'a') do |file|
    file.puts "[#{timestamp}] #{level.upcase}:\t#{message}"
  end
end

class HTTPServer
  def initialize(port)
    log("Initializing server on port #{port}", :info)
    @db = SQLite3::Database.new('items.db')
    @db.execute("CREATE TABLE IF NOT EXISTS items (id INTEGER PRIMARY KEY, name TEXT)")
    @server = TCPServer.new(port)
    @routes = {}
  end

  def get(path, &handler)
    @routes["GET #{path}"] = handler
  end

  def post(path, &handler) 
    @routes["POST #{path}"] = handler
  end

  def db
    @db
  end

  def start
    log("Server started at http://localhost:#{@server.addr[1]}", :info)
    
    loop do        
      client = @server.accept
      Thread.new { handle_request(client) }
    end
  ensure
    log("Server stopped", :info)
    @server.close if @server
    @db.close if @db
  end

  private

  def handle_request(client)
    request_line = client.gets
    if request_line.nil?
        log("Received empty request from #{client.peeraddr[3]}", :warn)
        return
    end

    request_id = SecureRandom.hex(4) # 8 character hex string instead of full UUID
    method, path, _ = request_line.split
    headers = {}
    
    # Parse headers
    while (line = client.gets.chomp) != ''
      key, value = line.split(': ')
      headers[key.downcase] = value
    end
    log("\##{request_id} Received from #{client.peeraddr[3]}: #{method} #{path}", :info)

    # Read body if present
    body = ''
    if headers['content-length']
      body = client.read(headers['content-length'].to_i)
    end
    # Parse JSON body if present
    json_body = body.empty? ? {} : JSON.parse(body)

    # Find and execute route handler
    route_key = "#{method} #{path}"
    if @routes[route_key]
      response, status = @routes[route_key].call(json_body, request_id)
      send_response(client, response, status)
      log("\##{request_id} Sent response: #{status} #{route_key}", :info)
    else
      send_response(client, {error: 'Not Found'}, 404)
      log("\##{request_id} Route not found: #{route_key}", :warn)
    end

    client.close
  end

  def send_response(client, data, status = 200)
    body = JSON.generate(data)
    
    client.write("HTTP/1.1 #{status}\r\n")
    client.write("Content-Type: application/json\r\n")
    client.write("Content-Length: #{body.bytesize}\r\n")
    client.write("\r\n")
    client.write(body)
  end
end

# Create and configure server
server = HTTPServer.new(8000)

# Define routes
server.get '/' do |_, _|
  [{message: 'Welcome to the API'}, 200]
end

server.get '/items' do |_, request_id|
  begin
    items = server.db.execute("SELECT * FROM items").map do |row|
      {id: row[0], name: row[1]}
    end
    [{items: items}, 200]
  rescue SQLite3::Exception => e
    log("\##{request_id} Database error: #{e.message}", :error)
    [{error: 'Database error', details: e.message}, 500]
  end
end

server.post '/items' do |body, request_id|
  begin
    raise JSON::ParserError, "Missing required field: name" unless body.key?('name')
    server.db.execute("INSERT INTO items (name) VALUES (?)", [body['name']])
    body['id'] = server.db.last_insert_row_id
    [{status: 'created', item: body}, 201]
  rescue SQLite3::Exception => e
    log("\##{request_id} Database error: #{e.message}", :error)
    [{error: 'Database error', details: e.message}, 500]
  rescue JSON::ParserError => e
    log("\##{request_id} Invalid JSON: #{body}", :error)
    [{error: 'Invalid JSON', details: e.message}, 400]
  end
end

server.get '/favicon.ico' do |_, _|
  # Return empty response for favicon requests
  [{}, 204]
end

server.start