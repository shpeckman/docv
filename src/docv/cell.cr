# src/docv/cell.cr
module Docv
  # Display width of characters and grapheme clusters, and interning of
  # multi-codepoint clusters so a `Cell` stays a plain value.
  module Unicode
    # Inclusive codepoint ranges displayed two columns wide.
    WIDE = [
      {0x1100, 0x115F}, {0x231A, 0x231B}, {0x2329, 0x232A}, {0x23E9, 0x23EC}, {0x23F0, 0x23F0},
      {0x23F3, 0x23F3}, {0x25FD, 0x25FE}, {0x2614, 0x2615}, {0x2648, 0x2653}, {0x267F, 0x267F},
      {0x2693, 0x2693}, {0x26A1, 0x26A1}, {0x26AA, 0x26AB}, {0x26BD, 0x26BE}, {0x26C4, 0x26C5},
      {0x26CE, 0x26CE}, {0x26D4, 0x26D4}, {0x26EA, 0x26EA}, {0x26F2, 0x26F3}, {0x26F5, 0x26F5},
      {0x26FA, 0x26FA}, {0x26FD, 0x26FD}, {0x2705, 0x2705}, {0x270A, 0x270B}, {0x2728, 0x2728},
      {0x274C, 0x274C}, {0x274E, 0x274E}, {0x2753, 0x2755}, {0x2757, 0x2757}, {0x2795, 0x2797},
      {0x27B0, 0x27B0}, {0x27BF, 0x27BF}, {0x2B1B, 0x2B1C}, {0x2B50, 0x2B50}, {0x2B55, 0x2B55},
      {0x2E80, 0x303E}, {0x3041, 0x33FF}, {0x3400, 0x4DBF}, {0x4E00, 0x9FFF}, {0xA000, 0xA4CF},
      {0xA960, 0xA97F}, {0xAC00, 0xD7A3}, {0xF900, 0xFAFF}, {0xFE10, 0xFE19}, {0xFE30, 0xFE6F},
      {0xFF00, 0xFF60}, {0xFFE0, 0xFFE6}, {0x16FE0, 0x16FE4}, {0x17000, 0x18CFF}, {0x1AFF0, 0x1B2FF},
      {0x1F004, 0x1F004}, {0x1F0CF, 0x1F0CF}, {0x1F18E, 0x1F18E}, {0x1F191, 0x1F19A}, {0x1F200, 0x1F251},
      {0x1F300, 0x1F320}, {0x1F32D, 0x1F335}, {0x1F337, 0x1F37C}, {0x1F37E, 0x1F393}, {0x1F3A0, 0x1F3CA},
      {0x1F3CF, 0x1F3D3}, {0x1F3E0, 0x1F3F0}, {0x1F3F4, 0x1F3F4}, {0x1F3F8, 0x1F43E}, {0x1F440, 0x1F440},
      {0x1F442, 0x1F4FC}, {0x1F4FF, 0x1F53D}, {0x1F54B, 0x1F54E}, {0x1F550, 0x1F567}, {0x1F57A, 0x1F57A},
      {0x1F595, 0x1F596}, {0x1F5A4, 0x1F5A4}, {0x1F5FB, 0x1F64F}, {0x1F680, 0x1F6C5}, {0x1F6CC, 0x1F6CC},
      {0x1F6D0, 0x1F6D2}, {0x1F6D5, 0x1F6D7}, {0x1F6DC, 0x1F6DF}, {0x1F6EB, 0x1F6EC}, {0x1F6F4, 0x1F6FC},
      {0x1F7E0, 0x1F7EB}, {0x1F7F0, 0x1F7F0}, {0x1F90C, 0x1F93A}, {0x1F93C, 0x1F945}, {0x1F947, 0x1F9FF},
      {0x1FA70, 0x1FAFF}, {0x20000, 0x2FFFD}, {0x30000, 0x3FFFD},
    ]

    @@clusters = [""]
    @@cluster_ids = Hash(String, Int32).new

    # Columns taken by a single codepoint: 0, 1 or 2.
    def self.width(char : Char) : Int32
      code = char.ord
      return 1 if 0x20 <= code < 0x7F
      return 0 if code < 0x20 || 0x7F <= code < 0xA0
      return 0 if code == 0xAD || 0x200B <= code <= 0x200F || 0x2028 <= code <= 0x202E || 0x2060 <= code <= 0x2064
      return 0 if 0xFE00 <= code <= 0xFE0F || 0xE0100 <= code <= 0xE01EF || code == 0xFEFF
      return 0 if char.mark?
      wide?(code) ? 2 : 1
    end

    # Columns taken by a grapheme cluster.
    def self.width(cluster : String) : Int32
      return 0 if cluster.empty?
      first = cluster[0]
      base = width(first)
      return base if cluster.size == 1
      return 2 if base == 1 && cluster.includes?('\u{FE0F}')
      base
    end

    # Columns taken by *text*, summed per grapheme cluster.
    def self.text_width(text : String) : Int32
      return text.bytesize if text.ascii_only? && text.each_byte.all? { |byte| 0x20 <= byte < 0x7F }
      total = 0
      text.each_grapheme { |grapheme| total += width(grapheme.to_s) }
      total
    end

    # The start of *text* that fits in *width* columns, ending in `…` when
    # cut.
    def self.truncate(text : String, width : Int32) : String
      return text if text_width(text) <= width
      return "" if width < 2
      used = 1
      String.build do |io|
        text.each_grapheme do |grapheme|
          cluster = grapheme.to_s
          used += width(cluster)
          break if used > width
          io << cluster
        end
        io << '…'
      end
    end

    # Returns the interning id of a multi-codepoint cluster (`0` is unused).
    def self.cluster_id(cluster : String) : Int32
      @@cluster_ids[cluster] ||= begin
        @@clusters << cluster
        @@clusters.size - 1
      end
    end

    # Returns the cluster interned as *id*.
    def self.cluster(id : Int32) : String
      @@clusters[id]
    end

    private def self.wide?(code : Int32) : Bool
      low = 0
      high = WIDE.size - 1
      while low <= high
        mid = (low + high) // 2
        first, last = WIDE[mid]
        if code < first
          high = mid - 1
        elsif code > last
          low = mid + 1
        else
          return true
        end
      end
      false
    end
  end

  # One grid cell: a grapheme with its rendition. A wide grapheme occupies a
  # cell of width 2 followed by a continuation cell of width 0. The struct has
  # no padding (12 bytes), so rows compare with `memcmp`.
  struct Cell
    getter ch : Char
    getter cluster : Int32
    getter style : UInt16
    getter width : UInt8
    @pad : UInt8 = 0_u8

    def initialize(@ch : Char, @style : UInt16 = 0_u16, @width : UInt8 = 1_u8, @cluster : Int32 = 0)
    end

    # A blank cell in the default style.
    BLANK = Cell.new(' ')

    # A blank cell in *style*.
    def self.blank(style : UInt16) : Cell
      Cell.new(' ', style)
    end

    # Builds the cell of a grapheme cluster.
    def self.from(cluster : String, style : UInt16) : Cell
      first = cluster[0]
      width = Unicode.width(cluster)
      id = cluster.size == 1 ? 0 : Unicode.cluster_id(cluster)
      Cell.new(first, style, Math.max(width, 1).to_u8, id)
    end

    # The continuation cell after a wide cell in *style*.
    def self.continuation(style : UInt16) : Cell
      Cell.new(' ', style, 0_u8)
    end

    # True for the second half of a wide grapheme.
    def continuation? : Bool
      @width == 0
    end

    # Returns this cell with another rendition.
    def with_style(style : UInt16) : Cell
      Cell.new(@ch, style, @width, @cluster)
    end

    # Writes the grapheme of this cell.
    def text(io : IO) : Nil
      @cluster == 0 ? (io << @ch) : (io << Unicode.cluster(@cluster))
    end
  end
end
