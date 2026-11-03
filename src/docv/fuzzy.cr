# src/docv/fuzzy.cr

module Docv
  # :nodoc:
  # fzf-style subsequence scoring; reuses its buffers, so one per fiber.
  class Fuzzy
    SCORE_MATCH           = 16
    GAP_START             = -3
    GAP_EXTENSION         = -1
    BONUS_BOUNDARY        = SCORE_MATCH // 2
    BONUS_WHITE           = BONUS_BOUNDARY + 2
    BONUS_DELIMITER       = BONUS_BOUNDARY + 1
    BONUS_NON_WORD        = SCORE_MATCH // 2
    BONUS_CAMEL           = BONUS_BOUNDARY + GAP_EXTENSION
    BONUS_CONSECUTIVE     = -(GAP_START + GAP_EXTENSION)
    FIRST_CHAR_MULTIPLIER = 2

    # Characters after which a word starts with `BONUS_DELIMITER`.
    DELIMITERS = {'/', ',', ':', ';', '|'}

    # Score of an impossible alignment.
    NONE = Int32::MIN // 2

    # :nodoc:
    enum Kind : UInt8
      White
      NonWord
      Delimiter
      Lower
      Upper
      Letter
      Number

      # Letters and digits.
      def word? : Bool
        value >= Lower.value
      end
    end

    ASCII = StaticArray(Kind, 128).new { |code| Fuzzy.kind(code.unsafe_chr) }

    # `BONUS[previous][current]` by character class.
    BONUS = Kind.values.map { |previous| Kind.values.map { |current| Fuzzy.bonus(previous, current) } }

    getter query : String
    # True when the query has upper case and matches exactly.
    getter? exact : Bool

    @codes : Array(Int32)
    @bonus = [] of Int32
    @folded = [] of Int32
    @scores = [] of Int32
    @chunks = [] of Int32
    @consecutive = [] of Bool
    @ascii_folds : Array(Int32)? = nil

    def initialize(@query : String)
      @exact = query != query.downcase
      @codes = query.chars.map(&.ord)
    end

    def self.kind(char : Char) : Kind
      if char.lowercase?
        Kind::Lower
      elsif char.uppercase?
        Kind::Upper
      elsif char.number?
        Kind::Number
      elsif char.letter?
        Kind::Letter
      elsif char.whitespace?
        Kind::White
      elsif DELIMITERS.includes?(char)
        Kind::Delimiter
      else
        Kind::NonWord
      end
    end

    def self.bonus(previous : Kind, current : Kind) : Int32
      if current.word?
        return BONUS_WHITE if previous.white?
        return BONUS_DELIMITER if previous.delimiter?
        return BONUS_BOUNDARY if previous.non_word?
      end
      return BONUS_CAMEL if (previous.lower? && current.upper?) || (!previous.number? && current.number?)
      return BONUS_NON_WORD if current.non_word? || current.delimiter?
      return BONUS_WHITE if current.white?
      0
    end

    # An empty query matches everything with score 0.
    def empty? : Bool
      @codes.empty?
    end

    # Score of the best alignment in *text*; `nil` when the query is not a subsequence of it.
    def score(text : String) : Int32?
      return 0 if @codes.empty?
      text.ascii_only? ? run(text.to_slice, nil) : run(text.chars, nil)
    end

    # Whether `score` would match the UTF-8 *text*, without aligning.
    def match?(text : Bytes) : Bool
      count = @codes.size
      return true if count == 0
      index = 0
      if table = ascii_folds
        target = @codes.unsafe_fetch(0)
        bytes = text.to_unsafe
        text.size.times do |offset|
          byte = bytes[offset]
          next unless byte < 128 && table.unsafe_fetch(byte) == target
          index += 1
          return true if index == count
          target = @codes.unsafe_fetch(index)
        end
      else
        String.new(text).each_char do |char|
          next unless fold(char.ord) == @codes[index]
          index += 1
          return true if index == count
        end
      end
      false
    end

    # Folded code per ASCII byte; `nil` unless the query is ASCII.
    private def ascii_folds : Array(Int32)?
      return nil unless @codes.all? { |code| code < 128 }
      @ascii_folds ||= Array(Int32).new(128) { |code| fold(code) }
    end

    # Character indices of the best alignment in *text*; `nil` without a match.
    def positions(text : String) : Array(Int32)?
      return [] of Int32 if @codes.empty?
      positions = [] of Int32
      found = text.ascii_only? ? run(text.to_slice, positions) : run(text.chars, positions)
      found ? positions : nil
    end

    private def run(chars, positions : Array(Int32)?) : Int32?
      count = @codes.size
      size = chars.size
      return nil if size < count
      first = -1
      matched = 0
      index = 0
      while index < size && matched < count
        if fold(code(chars[index])) == @codes[matched]
          first = index if matched == 0
          matched += 1
        end
        index += 1
      end
      return nil if matched < count
      last = size - 1
      final = @codes[count - 1]
      while fold(code(chars[last])) != final
        last -= 1
      end
      width = last - first + 1
      prepare(count * width, width)
      previous = first > 0 ? kind(code(chars[first - 1])) : Kind::White
      width.times do |offset|
        value = code(chars[first + offset])
        current = kind(value)
        @bonus[offset] = BONUS[previous.value][current.value]
        @folded[offset] = fold(value)
        previous = current
      end
      score, column = align(count, width)
      return nil if score <= NONE
      trace(count, width, column, first, positions) if positions
      score
    end

    private def prepare(cells : Int32, width : Int32) : Nil
      if @scores.size < cells
        @scores = Array(Int32).new(cells, 0)
        @chunks = Array(Int32).new(cells, 0)
        @consecutive = Array(Bool).new(cells, false)
      end
      if @bonus.size < width
        @bonus = Array(Int32).new(width, 0)
        @folded = Array(Int32).new(width, 0)
      end
    end

    # Fills the score matrix, a row per query character; returns the best last-row score and column.
    private def align(count : Int32, width : Int32) : {Int32, Int32}
      scores = @scores.to_unsafe
      chunks = @chunks.to_unsafe
      consecutive = @consecutive.to_unsafe
      bonus = @bonus.to_unsafe
      folded = @folded.to_unsafe
      count.times do |row|
        target = @codes.unsafe_fetch(row)
        base = row * width
        above = base - width
        gap = NONE
        width.times do |col|
          if row > 0 && col >= 2
            gap += GAP_EXTENSION
            candidate = scores[above + col - 2] + GAP_START
            gap = candidate if candidate > gap
          end
          index = base + col
          if folded[col] != target
            scores[index] = NONE
            next
          end
          own = bonus[col]
          if row == 0
            scores[index] = SCORE_MATCH + own * FIRST_CHAR_MULTIPLIER
            chunks[index] = own
            consecutive[index] = false
            next
          end
          best = NONE
          chunk = own
          run = false
          if col >= 1 && (diagonal = scores[above + col - 1]) > NONE
            first_bonus = chunks[above + col - 1]
            first_bonus = own if own >= BONUS_BOUNDARY && own > first_bonus
            best = diagonal + SCORE_MATCH + Math.max(Math.max(own, first_bonus), BONUS_CONSECUTIVE)
            chunk = first_bonus
            run = true
          end
          if gap > NONE && (via_gap = gap + SCORE_MATCH + own) > best
            best = via_gap
            chunk = own
            run = false
          end
          scores[index] = best
          chunks[index] = chunk
          consecutive[index] = run
        end
      end
      base = (count - 1) * width
      score = NONE
      column = -1
      width.times do |col|
        value = scores[base + col]
        if value > score
          score = value
          column = col
        end
      end
      {score, column}
    end

    # Walks the matrix back from (*count* - 1, *column*) into *positions*.
    private def trace(count : Int32, width : Int32, column : Int32, first : Int32, positions : Array(Int32)) : Nil
      found = Array(Int32).new(count, 0)
      row = count - 1
      col = column
      loop do
        found[row] = first + col
        break if row == 0
        index = row * width + col
        if @consecutive[index]
          col -= 1
        else
          target = @scores[index] - SCORE_MATCH - @bonus[col]
          above = (row - 1) * width
          from = col - 2
          while from >= 0
            value = @scores[above + from]
            break if value > NONE && value + GAP_START + GAP_EXTENSION * (col - from - 2) == target
            from -= 1
          end
          return if from < 0
          col = from
        end
        row -= 1
      end
      positions.concat(found)
    end

    private def code(byte : UInt8) : Int32
      byte.to_i32
    end

    private def code(char : Char) : Int32
      char.ord
    end

    private def fold(code : Int32) : Int32
      return code if @exact
      if code < 128
        0x41 <= code <= 0x5A ? code + 32 : code
      else
        code.unsafe_chr.downcase.ord
      end
    end

    private def kind(code : Int32) : Kind
      code < 128 ? ASCII[code] : Fuzzy.kind(code.unsafe_chr)
    end
  end
end
