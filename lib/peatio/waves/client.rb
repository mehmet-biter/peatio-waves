require 'memoist'
require 'faraday'
require 'better-faraday'

module Peatio
  module Waves
    class Client
      Error = Class.new(StandardError)
      class ConnectionError < Error; end

      class ResponseError < Error
        def initialize(code, msg)
          @code = code
          @msg = msg
        end

        def message
          "#{@msg} (#{@code})"
        end
      end

      extend Memoist

      def initialize(endpoint)
        @json_rpc_endpoint = URI.parse(endpoint)
        @json_rpc_api = @json_rpc_endpoint.user
        @json_rpc_e = "#{@json_rpc_endpoint.scheme}://#{@json_rpc_endpoint.host}:#{@json_rpc_endpoint.port}"
      end

      def client(method, path, para = nil)
        response = connection.public_send(method, path, para,{ 'Accept'       => 'application/json',
                                                               'Content-Type' => 'application/json' })
                       .assert_2xx!
        response = JSON.parse(response.body)
        response['error'].tap { |e| raise ResponseError.new(e['code'], e['message']) if e }
        response
      rescue => e
        if e.is_a?(Error)
          raise e
        elsif e.is_a?(Faraday::Error)
          raise ConnectionError, e
        else
          raise Error, e
        end
      end

      def json_rpc(method, params = [])
        response = connection.post \
          '/',
          { jsonrpc: '1.0', method: method, params: params }.to_json,
          { 'Accept'       => 'application/json',
            'Content-Type' => 'application/json' }
        response.assert_2xx!
        response = JSON.parse(response.body)
        response['error'].tap { |e| raise ResponseError.new(e['code'], e['message']) if e }
        response.fetch('result')
      rescue => e
        if e.is_a?(Error)
          raise e
        elsif e.is_a?(Faraday::Error)
          raise ConnectionError, e
        else
          raise Error, e
        end
      end

      private

      def connection
        @connection ||= Faraday.new(@json_rpc_e) do |f|
          f.adapter :net_http_persistent, pool_size: 5
        end.tap do |connection|
          unless @json_rpc_endpoint.user.blank?
          #   connection.headers['Authorization'] = nil
            connection.headers['X-API-Key'] = @json_rpc_endpoint.user
          end
        end
      end
    end
  end
end
