require "test_helper"

class AddressSuggestionsTest < ActiveSupport::TestCase
  # Photon's GeoJSON shape, trimmed to the properties AddressSuggestions reads.
  def feature(**props) = { "properties" => { "countrycode" => "US" }.merge(props.transform_keys(&:to_s)) }

  HOUSE = { type: "house", housenumber: "100", street: "State Street", city: "Montpelier", state: "Vermont", postcode: "05602" }.freeze

  # Skips the network: returns a canned Photon response and records the queries it was asked for.
  class Canned < AddressSuggestions
    attr_reader :queries

    def initialize(features) = (@features, @queries = features, [])

    private

    def fetch(query)
      @queries << query
      { "features" => @features }
    end
  end

  setup do
    Rails.cache.clear
    Member.create!(bioguide_id: "S000033", chamber: "senate", full_name: "Bernard Sanders", state: "Vermont", state_code: "VT")
  end

  test "formats house results USPS-style and drops duplicates from businesses at the same address" do
    features = [ feature(**HOUSE, name: "J. Morgan's Steakhouse"), feature(**HOUSE, name: "Hair Salon"), feature(**HOUSE) ]
    suggestions = Canned.new(features).call("100 State St Montp")
    assert_equal [ "100 State Street, Montpelier, VT 05602" ], suggestions.map(&:label)
    assert_equal "address", suggestions.first.kind
  end

  test "keeps states and US territories, drops other countries and results without a house number" do
    features = [ feature(type: "state", name: "Vermont"),
                 feature(**HOUSE, countrycode: "CA", state: "Ontario"),
                 feature(**HOUSE, countrycode: "PR", city: "San Juan", state: nil, country: "Puerto Rico", postcode: "00901"),
                 feature(**HOUSE, housenumber: nil) ]
    labels = Canned.new(features).call("vermo").map(&:label)
    assert_equal [ "Vermont", "100 State Street, San Juan, Puerto Rico 00901" ], labels
  end

  test "returns at most 5 suggestions" do
    features = (1..9).map { |n| feature(**HOUSE, housenumber: n.to_s) }
    assert_equal 5, Canned.new(features).call("State Street").size
  end

  test "short queries don't call Photon, and repeat queries come from the cache" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new # the test environment's null store caches nothing
    service = Canned.new([ feature(**HOUSE) ])
    assert_empty service.call("10")
    service.call("100 State")
    service.call("  100 STATE ")
    assert_equal [ "100 State" ], service.queries
  ensure
    Rails.cache = original
  end
end
