module Search
  # Hybrid search over SearchDocuments: embedding similarity (finds paraphrases: "military aid" ~ "arms sale") plus
  # Postgres full-text search (finds exact terms: "Israel", "H.R. 2102"), merged with reciprocal rank fusion.
  class Retriever
    POOL = 40   # candidates taken from each method before merging
    # House "rule" votes ("H.Res. 1398: Providing for consideration of the bill (H.R. 8800)...") only set floor
    # procedure, and their long titles list several bills, so they match almost any topic and crowd out the real
    # votes. The vote on the bill itself is indexed separately.
    RRF_K = 60  # standard reciprocal-rank-fusion constant: a document ranked r scores 1 / (RRF_K + r)

    def initialize(embedder: Embedder.new)
      @embedder = embedder
    end

    # Returns up to `limit` SearchDocuments (with their records loaded), best first.
    def call(query, kind:, keywords: [], chamber: nil, limit: 10)
      scope = SearchDocument.where(kind:)
      scope = scope.where(chamber:) if chamber
      scope = scope.where.not("content LIKE ?", "%: Providing for consideration of %") if kind == "vote"
      text = [ query, *keywords ].join(" ")

      scores = Hash.new(0.0)
      [ semantic_ids(scope, query), keyword_ids(scope, text) ].each do |ids|
        ids.each_with_index { |id, rank| scores[id] += 1.0 / (RRF_K + rank + 1) }
      end
      ranked = scores.sort_by { |_, s| -s }.map(&:first)
      docs = SearchDocument.where(id: ranked).includes(:record).index_by(&:id).values_at(*ranked).compact
      docs.uniq { |d| same_text_key(d) }.first(limit)
    end

    private

    # House amendment votes carry no amendment text, so the 30 amendment votes on one NDAA read identically apart
    # from their roll-call number and date. Keep only the best-ranked of each so they don't fill every slot.
    def same_text_key(doc) = doc.content.sub(/\A(?:Senate|House) roll call \d+ on [\d-]+: /, "")

    def semantic_ids(scope, query)
      scope.where.not(embedding: nil).nearest_neighbors(:embedding, @embedder.query(query), distance: "cosine").limit(POOL).pluck(:id)
    end

    # Documents with any of the words, ranked by which words they contain, each weighted by how rare it is (IDF):
    # "Israel" is in a handful of votes, "military" and "security" in hundreds. Postgres's ts_rank/ts_rank_cd only
    # reward repetition, so a bulk nomination listing dozens of "Assistant Secretary" posts outranked "disapproval of
    # the proposed foreign military sale to ... Israel". Ties go to Postgres's length-normalized rank.
    def keyword_ids(scope, text)
      terms = text.downcase.scan(/[a-z0-9]+/).uniq.reject { |t| t.length < 2 }.first(12)
      total = scope.count
      weights = terms.filter_map do |t|
        df = scope.where("searchable @@ to_tsquery('english', ?)", t).count # 0 for stopwords ("to") and unknown words
        [ t, Math.log((total + 1.0) / (df + 0.5)) ] if df.positive?
      end
      return [] if weights.empty?

      tsquery = weights.map(&:first).join(" | ")
      score = weights.map { |t, w| SearchDocument.sanitize_sql_array([ "(searchable @@ to_tsquery('english', ?))::int * ?", t, w.round(4) ]) }.join(" + ")
      rank = SearchDocument.sanitize_sql_array([ "ts_rank(searchable, to_tsquery('english', ?), 1 | 32)", tsquery ])
      scope.where("searchable @@ to_tsquery('english', ?)", tsquery)
           .order(Arel.sql("(#{score}) DESC, #{rank} DESC")).limit(POOL).pluck(:id)
    end
  end
end
