module Congress
  # Client for https://api.congress.gov/v3. The key is sent as a header so it never lands in URLs or logs.
  class Client
    BASE_URL = "https://api.congress.gov/v3".freeze
    MAX_LIMIT = 250

    def initialize(api_key: ENV["CONGRESS_KEY"])
      raise ArgumentError, "CONGRESS_KEY is not set (add it to .env)" if api_key.blank?
      @api_key = api_key
    end

    def get(path, **params)
      query = URI.encode_www_form(params.merge(format: "json"))
      JSON.parse(Http.get("#{BASE_URL}#{path}?#{query}", headers: { "X-Api-Key" => @api_key }))
    end

    # Yields each page's items for `key`. Return :stop from the block to stop paging early.
    def each_page(path, key, limit: MAX_LIMIT, **params)
      offset = 0
      loop do
        data = get(path, **params, limit: limit, offset: offset)
        items = Array(data[key])
        break if items.empty?
        break if yield(items) == :stop
        break if data.dig("pagination", "next").blank?
        offset += items.size
      end
    end

    def self.current_congress(date = Date.current)
      ((date.year - 1789) / 2) + 1
    end
  end
end
