# Simple Ruby REST Server

A lightweight, thread-safe HTTP server implementation in Ruby that supports
JSON responses, path parameters, and concurrent request handling.

Perhaps most useful to extend your scripts with simple REST functionality, and
you don't want to involve any gems.

## Features

- GET and POST request handling
- JSON request/response support
- Path parameters (e.g., `/users/:id`)
- Concurrent request handling

## Basic Usage

Either copy `http_server.rb` to your project directory, or write your
script directly in the same file.

```ruby
require_relative 'http_server'

# Initialize server on port 8000
server = HTTPServer.new(8000)

# Define a simple GET route
server.get '/' do
  { message: 'Welcome to the API' }
end

# Route with path parameter
server.get '/users/:id' do |params|
  { user_id: params['id'] }
end

# POST route with JSON body
server.post '/items' do |params|
  # params contains both path parameters and JSON body
  [{ status: 'created', item: params }, 201]
end

# Start the server
server.start
```

## Route Handlers

### Basic Response
```ruby
server.get '/hello' do
  { message: 'Hello, World!' }  # Returns 200 OK by default
end
```

### Custom Status Codes
```ruby
server.post '/create' do |params|
  [{ id: 123, status: 'created' }, 201]
end
```

### Path Parameters
```ruby
server.get '/users/:id/posts/:post_id' do |params|
  {
    user_id: params['id'],
    post_id: params['post_id']
  }
end
```

### Handling POST Data
```ruby
server.post '/data' do |params|
  # params contains path parameters and JSON body
  { received: params }
end
```

## Custom Logging

The server uses standard Ruby `Logger`

```ruby
# Log to file
logger = Logger.new('server.log')

# Initialize server with custom logger
server = HTTPServer.new(8000, logger)
```

## Testing

### Requirements

Install RSpec for running tests:
```bash
gem install rspec
```

### Running Tests

```bash
rspec http_server_spec.rb
```

## Limitations

This server is only meant for quick-and-dirty internal stuff, so keep in mind:

- JSON-only response format
- GET and POST methods only
- No built-in SSL/TLS support
- No query parameter parsing
- No middleware support

If you need any of that, then you'd need to extend it yourself. If you need
something to actually use in production, check
[Sinatra](https://sinatrarb.com/).
