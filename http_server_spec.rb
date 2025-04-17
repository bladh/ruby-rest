require 'rspec'
require 'net/http'
require 'json'
require_relative 'http_server'

RSpec.describe HTTPServer do
  let(:port) { 8081 }  # Use different port than main server
  let(:server) { HTTPServer.new(port, Logger.new(nil)) }  # Suppress logging in tests
  let(:base_uri) { "http://localhost:#{port}" }

  before(:each) do
    # Start server in a separate thread
    @server_thread = Thread.new { server.start }
    # Wait for server to start
    sleep(0.1)
  end

  after(:each) do
    # Stop server thread
    @server_thread.kill
    @server_thread.join
  end

  describe 'Basic routing' do
    before do
      server.get '/' do
        { message: 'Welcome' }
      end

      server.get '/error' do
        [{ error: 'Test error' }, 500]
      end
    end

    it 'handles basic GET request' do
      response = Net::HTTP.get_response(URI("#{base_uri}/"))
      
      expect(response.code).to eq('200')
      expect(JSON.parse(response.body)).to eq({ 'message' => 'Welcome' })
    end

    it 'handles custom status codes' do
      response = Net::HTTP.get_response(URI("#{base_uri}/error"))
      
      expect(response.code).to eq('500')
      expect(JSON.parse(response.body)).to eq({ 'error' => 'Test error' })
    end

    it 'returns 404 for unknown routes' do
      response = Net::HTTP.get_response(URI("#{base_uri}/not-found"))
      
      expect(response.code).to eq('404')
      expect(JSON.parse(response.body)).to eq({ 'error' => 'Not Found' })
    end
  end

  describe 'Path parameters' do
    before do
      server.get '/users/:id' do |params|
        { user_id: params['id'] }
      end

      server.get '/posts/:post_id/comments/:comment_id' do |params|
        { post: params['post_id'], comment: params['comment_id'] }
      end
    end

    it 'handles single path parameter' do
      response = Net::HTTP.get_response(URI("#{base_uri}/users/123"))
      
      expect(response.code).to eq('200')
      expect(JSON.parse(response.body)).to eq({ 'user_id' => '123' })
    end

    it 'handles multiple path parameters' do
      response = Net::HTTP.get_response(URI("#{base_uri}/posts/456/comments/789"))
      
      expect(response.code).to eq('200')
      expect(JSON.parse(response.body)).to eq({
        'post' => '456',
        'comment' => '789'
      })
    end
  end

  describe 'POST requests' do
    before do
      server.post '/data' do |params|
        { received: params }
      end
    end

    it 'handles POST request with JSON body' do
      uri = URI("#{base_uri}/data")
      data = { name: 'test', value: 42 }
      
      response = Net::HTTP.post(uri, data.to_json, 'Content-Type' => 'application/json')
      
      expect(response.code).to eq('200')
      parsed_response = JSON.parse(response.body)
      expect(parsed_response['received']).to eq({
        'name' => 'test',
        'value' => 42
      })
    end

    it 'handles invalid JSON in POST request' do
      uri = URI("#{base_uri}/data")
      invalid_json = '{ invalid json }'
      
      response = Net::HTTP.post(uri, invalid_json, 'Content-Type' => 'application/json')
      
      expect(response.code).to eq('400')
      expect(JSON.parse(response.body)['error']).to eq('Invalid JSON')
    end
  end

  describe 'Edge cases' do
    before do
      server.get '/empty' do
        {}
      end

      server.post '/echo' do |params|
        params
      end
    end

    it 'handles empty response body' do
      response = Net::HTTP.get_response(URI("#{base_uri}/empty"))
      
      expect(response.code).to eq('200')
      expect(JSON.parse(response.body)).to eq({})
    end

    it 'handles POST request with empty body' do
      uri = URI("#{base_uri}/echo")
      response = Net::HTTP.post(uri, '', 'Content-Type' => 'application/json')
      
      expect(response.code).to eq('200')
      expect(JSON.parse(response.body)).to eq({})
    end

    it 'handles concurrent requests' do
      threads = 10.times.map do
        Thread.new do
          Net::HTTP.get_response(URI("#{base_uri}/empty"))
        end
      end

      responses = threads.map(&:value)
      expect(responses).to all(have_attributes(code: '200'))
    end
  end
end 
