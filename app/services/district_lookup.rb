# Finds the congressional district for a street address using the free US Census Geocoder
# (https://geocoding.geo.census.gov, no API key). Only the address the user typed is sent.
class DistrictLookup
  ENDPOINT = "https://geocoding.geo.census.gov/geocoder/geographies/onelineaddress".freeze
  # "Current_Current" switches to the next Congress's districts as soon as they're published, which can be
  # before those members are seated, so fall back to older vintages until we find the current Congress's map.
  VINTAGES = %w[Current_Current ACS2026_Current ACS2025_Current ACS2024_Current].freeze
  AT_LARGE_CODES = %w[00 98].freeze # 00 = at-large seat, 98 = non-voting delegate

  Result = Data.define(:matched_address, :state_code, :district)

  class NotFound < StandardError; end
  class Unavailable < StandardError; end

  def initialize(congress: Congress::Client.current_congress)
    @congress = congress
  end

  # Returns a Result, or raises NotFound / Unavailable.
  def call(address)
    VINTAGES.each do |vintage|
      match = geocode(address, vintage)
      raise NotFound, "We couldn't find that address." unless match

      geographies = match["geographies"] || {}
      district = geographies["#{@congress.ordinalize} Congressional Districts"]&.first
      next unless district # this vintage has a different Congress's map; try the next one

      state = geographies["States"]&.first
      code = district["CD#{@congress}"] || district["GEOID"].to_s[-2..]
      return Result.new(
        matched_address: match["matchedAddress"],
        state_code: state&.dig("STUSAB"),
        district: AT_LARGE_CODES.include?(code) ? nil : code.to_i
      )
    end
    raise Unavailable, "District maps for the #{@congress.ordinalize} Congress aren't available from the Census Geocoder."
  end

  private

  def geocode(address, vintage)
    query = URI.encode_www_form(address:, benchmark: "Public_AR_Current", vintage:, layers: "all", format: "json")
    data = JSON.parse(Congress::Http.get("#{ENDPOINT}?#{query}", attempts: 2))
    raise Unavailable, Array(data["errors"]).join(" ") if data["errors"].present?

    data.dig("result", "addressMatches", 0)
  rescue Congress::Http::Error, JSON::ParserError, *Congress::Http::RETRYABLE => e
    raise Unavailable, "The address lookup service is unavailable right now (#{e.class.name.demodulize})."
  end
end
