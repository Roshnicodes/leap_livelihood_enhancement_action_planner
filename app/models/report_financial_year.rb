class ReportFinancialYear
  FIRST_YEAR = 2015
  MIN_LAST_YEAR = 2028

  def self.options(date = Date.current)
    current_start = financial_year_start(date)
    last_start = [ MIN_LAST_YEAR, current_start + 1 ].max

    (FIRST_YEAR..last_start).map { |year| value_for(year) }.reverse
  end

  def self.value_for(start_year)
    "#{start_year}-#{start_year + 1}"
  end

  def self.short_label(value)
    start_year, end_year = value.to_s.split("-")
    return value.to_s if start_year.blank? || end_year.blank?

    "#{start_year}-#{end_year.last(2)}"
  end

  def self.normalize(value)
    text = value.to_s.squish.tr("–—", "-")
    return nil if text.blank?

    if (match = text.match(/\A(20\d{2})-(\d{2})\z/))
      start_year = match[1].to_i
      end_suffix = match[2].to_i
      end_year = (start_year / 100) * 100 + end_suffix
      end_year += 100 if end_year < start_year

      return "#{start_year}-#{end_year}"
    end

    if (match = text.match(/\A(20\d{2})-(20\d{2})\z/))
      return "#{match[1]}-#{match[2]}"
    end

    nil
  end

  def self.financial_year_start(date = Date.current)
    date = date.to_date
    date.month >= 4 ? date.year : date.year - 1
  end
end
