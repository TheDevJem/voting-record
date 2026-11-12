require "net/http"

module Congress
  # Small HTTP helper with retries for the public data sources we sync from.
  module Http
    USER_AGENT = "voting-record/1.0 (Rails sync)".freeze
    RETRYABLE = [ Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET, SocketError, OpenSSL::SSL::SSLError ].freeze

    class Error < StandardError; end
    class NotFound < Error; end

    module_function

    def get(url, headers: {}, attempts: 5)
      uri = URI(url)
      attempt = 0
      begin
        attempt += 1
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                   open_timeout: 10, read_timeout: 60) do |http|
          request = Net::HTTP::Get.new(uri)
          request["User-Agent"] = USER_AGENT
          headers.each { |k, v| request[k] = v }
          http.request(request)
        end

        case response
        when Net::HTTPSuccess then response.body
        when Net::HTTPNotFound then raise NotFound, "404 #{redact(url)}"
        when Net::HTTPTooManyRequests, Net::HTTPServerError
          raise Error, "#{response.code} #{redact(url)}"
        else
          raise Error, "#{response.code} #{redact(url)}: #{response.body.to_s[0, 200]}"
        end
      rescue *RETRYABLE, Error => e
        raise if e.is_a?(NotFound) || attempt >= attempts
        # Back off harder on rate limiting (Congress.gov enforces an hourly per-key limit).
        sleep(e.message.start_with?("429") ? 60 : 2**attempt)
        retry
      end
    end

    def redact(url) = url.to_s.sub(/api_key=[^&]+/, "api_key=REDACTED")
  end
end
