# frozen_string_literal: true

module OmniAI
  module Evals
    module Assertions
      # Which option on a form was circled -- the `structure` type's `{"circled": ...}` target.
      #
      # It lives apart from the rest of Structure because it is the only assertion whose job is
      # to decide who a MARK belongs to, rather than to compare a value. Every rule here exists
      # to stop a mark being credited to an option that did not carry it, in either direction:
      # a correct answer scoring false, or an unmarked page scoring true.
      module Circled
        # A transcription marks a circled option one of two ways, and both count.
        #
        # LEXICAL: it says so -- "(circled)", "[x]", "circled", "selected".
        MARKED = /\(circled\)|\[x\]|\bcircled\b|\bselected\b/i
        # EMPHATIC: it renders the pen circle as emphasis, because production prompts tell it
        # to "match any formatting as closely as possible" and a circle IS emphasis. Measured
        # on a physician-completed exam form: four separate configs all transcribed the
        # circled option in bold and not one of them used the word "circled".
        #
        # The single-delimiter forms require non-word boundaries. Without that, `_(.+?)_`
        # matches the middle of a snake_case token and invents an emphasised span that was
        # never emphasis -- "field_Normal_name" would mark "Normal" as circled.
        EMPHASIS = /
          \*\*(.+?)\*\*
          | __(.+?)__
          | (?<![\w*])\*(?!\*)([^*]+?)\*(?![\w*])
          | (?<![\w_])_(?!_)([^_]+?)_(?![\w_])
        /x
        # A model transcribing a pen circle often leaves its ink as stray punctuation --
        # "(2) Normal)" with an unbalanced paren appeared in three of those four configs --
        # so text is compared with its punctuation edges trimmed.
        EDGE_NOISE = /\A[^[:alnum:]]+|[^[:alnum:]]+\z/
        # A leading option enumerator. Models bold the option text without it ("**Normal**"
        # for "2) Normal"), so the enumerator is stripped from both sides before comparing.
        ENUMERATOR = /\A(?:\(\d+\)|\d+[).]|[a-z][).])\s*/

      module_function

        def call(output:, criterion:)
          target = criterion.target
          option = target.fetch("circled")
          siblings = Array(target["among"]).reject { |s| same?(s, option) }
          field = field_text(Normalize.text(output), option, target)
          return failure(criterion, "option not found in output") if field.nil?

          rivals = siblings.select { |sibling| marked?(field, sibling, target) }
          unless rivals.empty?
            return failure(criterion,
              "#{rivals.size + 1} of the options are marked; the mark is not discriminating")
          end

          return pass(criterion, "marked circled") if lexical?(field, option, target)
          return pass(criterion, "marked by emphasis") if emphasised?(field, option)

          failure(criterion, "option present but not marked")
        end

        # The lines that carry this field's options -- every line mentioning the target or any
        # sibling -- rather than the whole page.
        #
        # Page scope is wrong in BOTH directions and a form makes both happen. Option strings
        # repeat: Yes/No, Normal, None, Left/Right. A bolded "No" in an unrelated field three
        # sections down refuses a correct mark (false negative), and a bolded target in some
        # other field would accept an unmarked one (false positive). The enumeration is one
        # line or a short run of adjacent ones, so that is the unit.
        #
        # @return [String, nil] nil when the option is not mentioned at all
        def field_text(text, option, target)
          lines = text.lines
          index = lines.index { |line| mentions?(line, option) }
          return nil if index.nil?

          siblings = Array(target["among"]).reject { |sibling| same?(sibling, option) }
          first = index
          first -= 1 while first.positive? && mentions_any?(lines[first - 1], siblings)
          last = index
          last += 1 while last < lines.size - 1 && mentions_any?(lines[last + 1], siblings)
          lines[first..last].join
        end

        # The run must be CONTIGUOUS, not every line mentioning a sibling. Option words repeat
        # across a form -- a Yes/No field elsewhere on the page also mentions "No" -- so
        # collecting every such line drags an unrelated field back in and its emphasis becomes
        # a phantom rival.
        def mentions_any?(line, options)
          options.any? { |option| mentions?(line, option) }
        end

        # Emphasis is checked across the field; a lexical marker must be ADJACENT to the
        # option, so it is checked in that option's own window.
        def marked?(field, option, target)
          lexical?(field, option, target) || emphasised?(field, option)
        end

        # A lexical marker counts only for the option it belongs to.
        #
        # Anywhere-on-the-line is not discriminating: "1) Slim (circled) 2) Normal 3) Muscular"
        # would score "2) Normal" as circled, the same hole the emphasis branch already closed.
        # Nor is a window bounded by the neighbours enough -- a marker sitting BETWEEN two
        # options falls inside both windows, marks both, and refuses a correct page as
        # "not discriminating".
        #
        # So each marker gets exactly one owner: the option it FOLLOWS, which is how these
        # transcriptions read ("2) Normal (circled)"). A marker with nothing before it -- a
        # checkbox opening the line -- belongs to the option it precedes instead.
        def lexical?(field, option, target)
          owners(field, target).any? { |owner| same?(owner, option) }
        end

        # @return [Array<String>] the options that own a lexical marker
        def owners(field, target)
          text = Normalize.phrase(field)
          options = [target.fetch("circled"), *Array(target["among"])].uniq
          placed = options.filter_map { |option| locate(text, option)&.then { |at| [option, at] } }

          marks(text, target).filter_map { |mark| owner_of(mark, placed) }
        end

        # @return [Array<Integer>] where each lexical marker starts
        def marks(text, target)
          text.enum_for(:scan, markers(target)).map { Regexp.last_match.begin(0) }
        end

        def owner_of(mark, placed)
          before = placed.select { |(_, at)| at.last <= mark }.max_by { |(_, at)| at.last }
          after = placed.select { |(_, at)| at.first >= mark }.min_by { |(_, at)| at.first }
          (before || after)&.first
        end

        # @return [Range, nil] where the option sits in the normalized text
        def locate(text, option)
          forms(option).filter_map do |form|
            index = text.index(form)
            index && (index..(index + form.length))
          end.min_by(&:first)
        end

        def mentions?(line, option)
          text = Normalize.phrase(line)
          forms(option).any? { |form| text.include?(form) }
        end

        # True when the option IS the emphasised span -- not merely when its field contains
        # emphasis somewhere. That distinction is the whole assertion: on a form where every
        # line carries a bold label, "this contains bold" passes vacuously for every option,
        # including the ones that were not circled.
        #
        # Equality after trimming, deliberately, rather than containment: a span wrapping
        # several options ("**1) Slim 2) Normal 3) Muscular**") contains the option but marks
        # none of them, and scoring that as circled is the same vacuous pass one level down.
        def emphasised?(field, option)
          wanted = forms(option)
          field.scan(EMPHASIS).flatten.compact.any? { |span| forms(span).intersect?(wanted) }
        end

        # The comparable spellings of one option: punctuation edges trimmed, and the same
        # again without a leading enumerator, because a model may bold "Normal" for "2) Normal".
        def forms(option)
          canonical = Normalize.phrase(option).gsub(EDGE_NOISE, "")
          [canonical, canonical.sub(ENUMERATOR, "").gsub(EDGE_NOISE, "")].uniq.reject(&:empty?)
        end

        def same?(left, right) = forms(left).intersect?(forms(right))

        # A criterion may supply its own lexical markers for a target with its own convention.
        def markers(target)
          custom = Array(target["markers"])
          return MARKED if custom.empty?

          Regexp.union(custom.map { |marker| Regexp.new(Regexp.escape(marker), Regexp::IGNORECASE) })
        end

        def pass(criterion, comment) = Result.new(key: criterion.id, score: true, comment:)
        def failure(criterion, comment) = Result.new(key: criterion.id, score: false, comment:)
      end
    end
  end
end
