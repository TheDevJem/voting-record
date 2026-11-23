require "net/http"

# Address autocomplete for the "Find your representatives" box, from Photon (https://photon.komoot.io), a free
# OpenStreetMap geocoder run by komoot. The public demo server is for light, fair use: no key, but requests are
# throttled if overused, so callers debounce and results are cached. Only the partial text the user typed is sent.
#
# Suggestions are just cleaner input: the chosen address still goes through DistrictLookup (Census Geocoder) to
# find the district. Only full addresses and states are suggested, since those are what that search can resolve.
# OpenStreetMap is missing many house numbers, and Photon then answers with a *different* house on a nearby street.
# Picking one of those would search someone else's address, so when the user has typed a house number, only
# addresses with that house number are suggested; otherwise the list stays empty and the typed text is searched as is.
class AddressSuggestions
  ENDPOINT = "https://photon.komoot.io/api/".freeze
  USER_AGENT = "voting-record/1.0 (address autocomplete)".freeze
  MIN_LENGTH = 3
  LIMIT = 5
  # Fetch extra: several businesses at one address come back as separate results, and non-US ones are dropped.
  FETCH = 20
  # The US plus territories that send a delegate to the House (OSM gives these their own country codes).
  COUNTRY_CODES = %w[US PR GU VI AS MP].freeze
  # Bias toward the middle of the contiguous US so "Springfield" doesn't start in Europe.
  BIAS = { lat: 39.8, lon: -98.6 }.freeze
  CACHE_FOR = 1.day

  Suggestion = Data.define(:label, :kind)

  class Unavailable < StandardError; end

  def call(query)
    query = query.to_s.squish
    return [] if query.length < MIN_LENGTH

    Rails.cache.fetch([ "address_suggestions/v2", query.downcase ], expires_in: CACHE_FOR) do
      parse(fetch(query), house_number_in(query)).map(&:to_h)
    end.map { |h| Suggestion.new(**h) }
  end

  private

  def fetch(query)
    params = [ [ "q", query ], [ "limit", FETCH ], [ "lang", "en" ], [ "lat", BIAS[:lat] ], [ "lon", BIAS[:lon] ],
               [ "layer", "house" ], [ "layer", "state" ] ]
    uri = URI("#{ENDPOINT}?#{URI.encode_www_form(params)}")
    # Short timeouts and no retries: a suggestion that arrives late is useless, and the box works without one.
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 2, read_timeout: 3) do |http|
      http.request(Net::HTTP::Get.new(uri, "User-Agent" => USER_AGENT, "Accept" => "application/json"))
    end
    raise Unavailable, "Photon returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
    raise Unavailable, "Photon request failed (#{e.class.name.demodulize})"
  end

  def parse(data, house_number)
    Array(data["features"]).filter_map { |f| suggestion(f["properties"] || {}, house_number) }.uniq(&:label).first(LIMIT)
  end

  # "2300 Main St" => "2300"; "Main St" => nil. Matched as a prefix, so "23" still suggests 2300 while typing.
  def house_number_in(query)
    query[/\A(\d+[a-z]?)\b/i, 1]&.downcase
  end

  def suggestion(p, house_number)
    return unless COUNTRY_CODES.include?(p["countrycode"].to_s.upcase)

    case p["type"]
    when "house"
      return if p["housenumber"].blank? || p["street"].blank?
      return if house_number && !p["housenumber"].to_s.downcase.start_with?(house_number)

      # "100 State Street, Montpelier, VT 05602": USPS style, the form the Census Geocoder documents.
      place = p["city"] || p["town"] || p["village"] || p["locality"] || p["county"]
      state = p["state"] || p["country"] # territories are countries in OSM ("Puerto Rico")
      region = [ state_codes[state.to_s.downcase] || state, p["postcode"] ].compact.join(" ")
      Suggestion.new(label: [ "#{p['housenumber']} #{p['street']}", place, region.presence ].compact.join(", "), kind: "address")
    when "state"
      Suggestion.new(label: p["name"], kind: "state") if p["name"].present?
    end
  end

  # "vermont" => "VT", from the synced members (the same source the state search uses).
  def state_codes
    @state_codes ||= Member.distinct.pluck(:state, :state_code).to_h { |name, code| [ name.to_s.downcase, code ] }
  end
end
