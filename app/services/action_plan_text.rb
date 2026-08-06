require "cgi"

# Source workbooks reach us with HTML-escaped text, sometimes escaped several
# times over ("Soil &amp;amp;amp; moisture conservation"), so labels have to be
# unescaped repeatedly before they can be displayed or grouped.
class ActionPlanText
  MAX_UNESCAPE_PASSES = 5
  NON_BREAKING_SPACES = [ "&#160;", "&nbsp;" ].freeze

  class << self
    def normalize(raw)
      text = raw.to_s

      MAX_UNESCAPE_PASSES.times do
        unescaped = CGI.unescapeHTML(NON_BREAKING_SPACES.reduce(text) { |value, entity| value.gsub(entity, " ") })
        break if unescaped == text

        text = unescaped
      end

      text.squish
    end

    def escaped?(raw)
      normalize(raw) != raw.to_s
    end

    # Variants that differ only by escaping, spacing or case describe the same
    # activity, so they need one shared key when rows are grouped.
    def group_key(raw)
      normalize(raw).downcase
    end
  end
end
