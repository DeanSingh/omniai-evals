# frozen_string_literal: true

require "date"

module OmniAI
  module Evals
    # Dates are compared PARSED, never as strings: "2019-03-14", "03/14/2019" and
    # "March 14, 2019" are the same day, and a string compare scores three different
    # transcriptions of one correct answer as two failures.
    module Dates
      # Numeric slash AND dash dates are read as US month-first (MM/DD/YYYY, MM-DD-YYYY),
      # NOT by Date.parse.
      #
      # This is not a style preference, it is a correctness fix. Ruby's Date.parse reads
      # a slash date as DD/MM/YYYY, so it returns nil for "03/14/2019" (there is no month
      # 14) and -- far worse -- silently returns February 4th for "04/02/2019". A judge
      # would then mark a correct April 2nd transcription as wrong, with no error anywhere
      # to notice. Wrong-but-plausible is the failure mode this whole gem exists to catch,
      # so it cannot live in the date comparison itself.
      #
      # STATED DEFAULT (docs/contract.md): every dataset this grades is US, so month-first
      # is the rule. A non-US dataset needs a per-dataset locale field in the contract --
      # it is not something to infer from the text, because "04/02/2019" is valid in both
      # readings and guessing reintroduces exactly the silent error above. An unambiguous
      # key should be written ISO in the criteria file regardless.
      US_NUMERIC = %r{\A(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\z}

      # ISO stays ISO: "2019-03-14" is unambiguous and must NOT hit the US rule.
      ISO = /\A\d{4}-\d{2}-\d{2}\z/
      # "2019/03/14" is year-first by shape, so it is unambiguous too.
      ISO_SLASH = %r{\A(\d{4})/(\d{1,2})/(\d{1,2})\z}

      MONTH = "January|February|March|April|May|June|July|August|September|October|November|December|" \
        "Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec"

      # Every date shape seen in the faxed medical records this grades. Order matters:
      # the alternation is tried left to right, so longer textual forms come before the
      # numeric ones that could match a prefix of them.
      TOKEN = Regexp.union(
        /(?:#{MONTH})\.?\s+\d{1,2},?\s+\d{4}/,     # March 14, 2019 / Mar. 14 2019 / Mar 14 2019
        /\d{1,2}\s+(?:#{MONTH})\.?,?\s+\d{4}/,     # 14 March 2019
        %r{\d{4}[-/]\d{1,2}[-/]\d{1,2}},           # 2019-03-14 / 2019/03/14
        %r{\d{1,2}[/-]\d{1,2}[/-]\d{2,4}}          # 03/14/2019 / 03-14-2019 / 3/14/19
      )

    module_function

      # @return [Date, nil] nil when the value is not a date
      def parse(value)
        return nil if value.nil?

        text = value.to_s.strip
        return iso(text) if ISO.match?(text)

        slash = ISO_SLASH.match(text)
        return ymd(slash[1], slash[2], slash[3]) if slash

        us = US_NUMERIC.match(text)
        return us_numeric(us) if us

        textual(text)
      end

      # @return [Array<Date>] every date-shaped token in a blob of text, parsed. Used by
      #   the presence assertion so a date key matches whatever format the model wrote.
      def scan(text)
        text.to_s.scan(TOKEN).filter_map { |token| parse(token) }
      end

      # A textual month ("Mar. 14, 2019", "14 March 2019") is unambiguous, so Date.parse
      # is safe here -- the day-first trap only applies to all-numeric forms.
      def textual(text)
        Date.parse(text)
      rescue Date::Error
        nil
      end

      def iso(text)
        Date.iso8601(text)
      rescue Date::Error
        nil
      end

      def us_numeric(match)
        month, day, year = match.captures
        year = expand_year(year)
        ymd(year, month, day)
      end

      # A two-digit year in a medical record is this century unless that would be absurd;
      # 70 is the conventional pivot and matches Ruby's own strptime behaviour.
      def expand_year(year)
        return year if year.length == 4

        year.to_i < 70 ? "20#{year}" : "19#{year}"
      end

      def ymd(year, month, day)
        Date.new(year.to_i, month.to_i, day.to_i)
      rescue Date::Error
        nil
      end
    end
  end
end
