# src/docv/roff/registers.cr

# :nodoc:
module Docv::Roff
  # User number registers (`.nr`, `.af`, `.rr`, `.rnn`, `.aln`).
  class Registers
    class Register
      property value : Int64
      property increment : Int64
      property format : String

      def initialize(@value = 0_i64, @increment = 0_i64, @format = "0")
      end
    end

    @registers = Hash(String, Register).new

    def []?(name : String) : Register?
      @registers[name]?
    end

    def set(name : String, value : Int64, increment : Int64? = nil) : Nil
      register = @registers[name] ||= Register.new
      register.value = value
      increment.try { |step| register.increment = step }
    end

    # Auto-increments *name* in the direction of *sign* (`\n+x`, `\n-x`); returns the new value.
    def step(name : String, sign : Int32) : Int64
      register = @registers[name] ||= Register.new
      register.value = register.value &+ (register.increment &* sign)
      register.value
    end

    def format(name : String, format : String) : Nil
      (@registers[name] ||= Register.new).format = format
    end

    def delete(name : String) : Nil
      @registers.delete(name)
    end

    def rename(from : String, to : String) : Nil
      @registers.delete(from).try { |register| @registers[to] = register }
    end

    def alias(name : String, target : String) : Nil
      @registers[target]?.try { |register| @registers[name] = register }
    end

    def has_key?(name : String) : Bool
      @registers.has_key?(name)
    end

    # `.af` formats: `0`/`001` decimal (digits set the width), `i`/`I` roman, `a`/`A` letters.
    def self.render(value : Int64, format : String) : String
      case format
      when "i" then roman(value).downcase
      when "I" then roman(value)
      when "a" then alpha(value).downcase
      when "A" then alpha(value)
      else
        digits = value.abs.to_s
        width = format.size
        digits = digits.rjust(width, '0') if width > 1
        value < 0 ? "-#{digits}" : digits
      end
    end

    private ROMAN = [{1000, "M"}, {900, "CM"}, {500, "D"}, {400, "CD"}, {100, "C"}, {90, "XC"},
                     {50, "L"}, {40, "XL"}, {10, "X"}, {9, "IX"}, {5, "V"}, {4, "IV"}, {1, "I"}]

    private def self.roman(value : Int64) : String
      return "0" if value == 0
      rest = value.abs
      text = String.build do |io|
        ROMAN.each do |amount, numeral|
          while rest >= amount
            io << numeral
            rest -= amount
          end
        end
      end
      value < 0 ? "-#{text}" : text
    end

    private def self.alpha(value : Int64) : String
      return "0" if value == 0
      rest = value.abs
      text = String.build do |io|
        letters = [] of Char
        while rest > 0
          rest -= 1
          letters << ('A' + (rest % 26))
          rest //= 26
        end
        letters.reverse_each { |letter| io << letter }
      end
      value < 0 ? "-#{text}" : text
    end
  end
end
