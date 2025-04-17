require_relative 'http_server'
require 'sqlite3'

server = HTTPServer.new(8000)

db = SQLite3::Database.new('items.db')
db.execute("CREATE TABLE IF NOT EXISTS items (id INTEGER PRIMARY KEY, name TEXT)")

server.get '/' do
  {message: 'Welcome to the API'}
end

server.get '/items' do
  begin
    items = db.execute("SELECT * FROM items").map do |row|
      {id: row[0], name: row[1]}
    end
    {items: items}
  rescue SQLite3::Exception => e
    [{error: 'Database error', details: e.message}, 500]
  end
end

server.get '/items/:id' do |params|
  begin
    id = params['id']
    item = db.execute("SELECT * FROM items WHERE id = ?", [id]).first
    if item
      {id: item[0], name: item[1]}
    else
      [{error: 'Item not found', id: id}, 404]
    end
  rescue SQLite3::Exception => e
    [{error: 'Database error', details: e.message}, 500]
  end
end

server.post '/items' do |params|
  begin
    raise JSON::ParserError, "Missing required field: name" unless params.key?('name')
    db.execute("INSERT INTO items (name) VALUES (?)", [params['name']])
    params['id'] = server.db.last_insert_row_id
    [{status: 'created', item: params}, 201]
  rescue SQLite3::Exception => e
    [{error: 'Database error', details: e.message}, 500]
  rescue JSON::ParserError => e
    [{error: 'Invalid JSON', details: e.message}, 400]
  end
end

server.post '/items/:id' do |params|
  begin
    id = params['id']
    name = params['name']
    raise JSON::ParserError, "Missing required field: name" unless name

    db.execute("UPDATE items SET name = ? WHERE id = ?", [name, id])
    if db.changes > 0
      {status: 'updated', item: {id: id, name: name}}
    else
      [{error: 'Item not found'}, 404]
    end
  rescue SQLite3::Exception => e
    [{error: 'Database error', details: e.message}, 500]
  end
end

server.get('/favicon.ico') { [{}, 204] }

server.start
