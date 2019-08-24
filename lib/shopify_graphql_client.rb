require "shopify_graphql_client/version"
require "graphql/client"
require "shopify_api"

module ShopifyGraphQLClient
  class Error < StandardError; end
  class GraphQLError < Error; end
  class ThrottledError < Error; end

  class << self
    def parse(str, filename=nil, lineno=nil)
      if filename.nil? && lineno.nil?
        location = caller_locations(1, 1).first
        filename = location.path
        lineno = location.lineno
      end

      client.parse(str, filename=filename, lineno=lineno)
    end

    def client
      @client ||= GraphQL::Client.new(schema: schema, execute: Executor.new).tap do |client|
        client.allow_dynamic_queries = true
      end
    end

    def query(*args)
      result = client.query(*args)
      errors = result.errors

      process_errors(result.errors) if result.errors&.any?
        
      result
    end

    private

    def process_errors(errors)
      errors = errors.messages.map do |path, messages|
        message = "#{path}: #{messages.join(' -')}"
        error_type = messages.include?('Throttled') ? :throttled : :standard
        OpenStruct.new message: message, error_type: error_type
      end

      error_message = errors.map(&:message).join('\n')
      if errors.any? { |m| m.error_type == :throttled }
        raise ThrottledError, error_message
      else
        raise GraphQLError, error_message
      end
    end

    def schema
      @schema ||= load_schema
    end

    def load_schema
      unless File.exist?(schema_path)
        raise Error, "The schema file does not exist at #{schema_path}"
      end

      GraphQL::Client.load_schema(schema_path)
    end

    def schema_path
      File.join(__dir__, "../schema.json")
    end
  end

  class Executor < GraphQL::Client::HTTP
    # avoid initializing @uri
    def initialize; end

    def headers(_context)
      ShopifyAPI::Base.headers
    end

    def uri
      ShopifyAPI::Base.site.dup.tap do |uri|
        uri.path = "/admin/api/graphql.json"
      end
    end
  end
end
