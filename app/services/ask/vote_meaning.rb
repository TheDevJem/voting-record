module Ask
  # What a Yea vote does, in plain words, worked out from the motion and the measure by fixed rules, so the model
  # only has to match a stance to a sentence like "A Yea vote supports blocking: the proposed foreign military sale
  # to Israel". Left to itself, the model read "Yea on the motion to discharge a disapproval resolution" as
  # supporting the sale, when it means moving the resolution that would block the sale.
  module VoteMeaning
    module_function

    # "A joint resolution providing for congressional disapproval of the proposed foreign military sale to ..."
    DISAPPROVAL = /\b(?:providing for congressional disapproval|disapproving|disapproval)(?: under [^,]+,)? of (.+)/i

    def for(roll_call, bill)
      title = (bill&.title || roll_call.topical_description).to_s.squish.delete_suffix(".")
      measure = measure_effect(title)
      motion = roll_call.question.to_s

      case motion
      when /motion to table/i
        "A Yea vote sets aside (kills) the measure or motion; a Nay vote keeps it alive. If passed, the measure would #{measure}."
      when /motion to recommit/i
        "A Yea vote sends the bill back to committee, usually to change or stall it; a Nay vote keeps it moving. The bill would #{measure}."
      when /motion to discharge/i
        "A Yea vote moves the measure out of committee toward a vote, i.e. supports it; a Nay vote keeps it stuck. The measure would #{measure}."
      when /cloture/i
        "A Yea vote ends debate so the measure can move forward, i.e. supports advancing it; a Nay vote holds it up. The measure would #{measure}."
      when /motion to proceed/i
        "A Yea vote brings the measure up for debate, i.e. supports considering it; a Nay vote blocks that. The measure would #{measure}."
      when /nomination/i
        "A Yea vote supports confirming the nominee: #{title.truncate(120)}."
      when /amendment/i
        what = roll_call.amendment_purpose.presence || title
        "A Yea vote supports adopting the amendment: #{what.delete_suffix('.').truncate(220)}."
      when /veto/i
        "A Yea vote overrides the President's veto, i.e. supports the measure. The measure would #{measure}."
      else # passage, agreeing to a resolution, concurring, and similar
        "A Yea vote supports the measure; a Nay vote opposes it. The measure would #{measure}."
      end
    end

    # "block: the proposed foreign military sale to Israel" for disapproval resolutions; otherwise the title itself.
    def measure_effect(title)
      return "do something not described in this data (no title or summary available)" if title.blank?

      if (target = title[DISAPPROVAL, 1])
        "BLOCK #{target.truncate(160)} (it is a disapproval resolution, so supporting it means opposing that)"
      else
        "do this: #{title.truncate(160)}"
      end
    end
  end
end
