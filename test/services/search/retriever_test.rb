require "test_helper"

class Search::RetrieverTest < ActiveSupport::TestCase
  # Every document and query gets the same vector, so only the keyword half decides the order.
  class FlatEmbedder
    def query(_) = Array.new(Search::Embedder::DIMENSIONS, 0.1)
  end

  def doc(content, kind: "vote")
    rc = RollCall.create!(chamber: "senate", congress: 119, session: 1, number: RollCall.count + 1)
    SearchDocument.create!(record: rc, kind:, chamber: "senate", content:, content_digest: content.hash.to_s,
                           embedding: Array.new(Search::Embedder::DIMENSIONS, 0.1))
  end

  def search(query, **opts) = Search::Retriever.new(embedder: FlatEmbedder.new).call(query, kind: "vote", **opts).map(&:content)

  test "a rare word outweighs a common one repeated many times" do
    doc("On the Nomination: military officers for military posts in the military reserve, military academies")
    israel = doc("On the Motion to Discharge: disapproval of the proposed foreign military sale to Israel")
    10.times { |i| doc("On Passage: military construction bill #{i}") }
    # The keyword half alone: with every embedding equal, the semantic half's order is arbitrary.
    ids = Search::Retriever.new(embedder: FlatEmbedder.new).send(:keyword_ids, SearchDocument.all, "military Israel")
    assert_equal israel.id, ids.first
  end

  test "House rule votes are left out, and identical texts collapse to one result" do
    doc("House roll call 230 on 2026-06-30: On Ordering the Previous Question. H.Res. 1398: Providing for consideration of the bill (H.R. 8800) Israel")
    doc("House roll call 265 on 2026-07-22: On Agreeing to the Amendment. H.R. 8800: Israel defense")
    doc("House roll call 266 on 2026-07-22: On Agreeing to the Amendment. H.R. 8800: Israel defense")
    assert_equal [ "House roll call 265 on 2026-07-22: On Agreeing to the Amendment. H.R. 8800: Israel defense" ], search("Israel")
  end
end
