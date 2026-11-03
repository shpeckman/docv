# src/docv/config.cr
require "ini"

module Docv
  # An XDG base directory: `$variable`, or `~/fallback` when the variable is
  # unset or not an absolute path.
  def self.base_directory(variable : String, fallback : String) : String
    base = ENV[variable]?
    base.nil? || base.empty? || !Path[base].absolute? ? Path.home.join(fallback).to_s : base
  end

  # This program's directory under an XDG base directory: `$variable/docv`,
  # or `~/fallback/docv` when the variable is unset or not an absolute
  # path.
  def self.user_directory(variable : String, fallback : String) : String
    File.join(base_directory(variable, fallback), "docv")
  end

  # Parsing options.
  #
  # *unsafe* enables the requests that run commands or touch files (see
  # `Roff::Engine::UNSAFE`) and the `\V` escape. *stdin* is where `.rd` reads
  # from; `nil` makes `.rd` read nothing. *highlight* colors code examples
  # with tree-sitter grammars (`Syntax`).
  record Options, unsafe : Bool = false, stdin : IO? = nil, highlight : Bool = false

  # The user configuration in `$XDG_CONFIG_HOME/docv/config.ini`
  # (`~/.config/docv/config.ini` when the variable is unset or not an
  # absolute path). `Config.load` writes a commented default file when none
  # exists.
  class Config
    # A configuration file that cannot be parsed or holds an invalid value.
    class Error < Exception
    end

    FILE = "config.ini"

    # Words accepted for boolean values.
    BOOLEANS = {
      "true" => true, "yes" => true, "on" => true, "1" => true,
      "false" => false, "no" => false, "off" => false, "0" => false,
    }

    # Known keys per section.
    KEYS = {"roff" => Set{"unsafe"}, "viewer" => Set{"start-wrapped", "syntax-highlighting"}, "colors" => Theme::KEYS.keys.to_set}

    # The `[colors]` explanation in `DEFAULT`, followed there by every role
    # with its default, commented out.
    COLORS = <<-INI
      [colors]
      ; Styles of the viewer, one per role. A style is attribute words (bold,
      ; italic, underline, reverse, dim), a foreground color, and "on" with a
      ; background color: "bold cyan", "black on yellow", "on background+12".
      ; Colors: default, foreground, background, black, red, green, yellow,
      ; blue, magenta, cyan, white (bright-black ... bright-white for 8-15), a
      ; palette number 0-255 or #rrggbb. Named and numbered colors are the
      ; terminal theme's own; +N or -N ramps a color N percent toward the
      ; theme's foreground or background. With NO_COLOR set, colors are off
      ; and these are ignored. Uncomment a line to change a role.

      INI

    # The file written when no configuration exists.
    DEFAULT = String.build do |io|
      io << ROFF << '\n' << VIEWER << '\n' << COLORS
      Theme::DEFAULT.each { |role, spec| io << "; " << Theme.key(role) << " = " << spec << '\n' }
    end

    private ROFF = <<-INI
      ; docv configuration

      [roff]
      ; Run the roff requests that execute commands or access files:
      ;   sy, pso, pi           run shell commands
      ;   open, opena, write,   write files
      ;   writec, writem, close
      ;   cf, trf               copy files into the page
      ;   rd                    read input from the terminal
      ; and the \\V escape (environment variables).
      ; When false these requests are accepted and ignored. Manual pages are
      ; input from third parties: enable this only if you trust every page
      ; you open.
      unsafe = false

      INI

    private VIEWER = <<-INI
      [viewer]
      ; Start in the wrapped layout, paragraphs filled to the width (w
      ; switches). When false, the viewer starts unwrapped: one line per
      ; paragraph, scrolled sideways. -u on the command line starts unwrapped
      ; either way.
      start-wrapped = true
      ; Color code examples by their syntax: Markdown code blocks labeled
      ; with a language (```crystal) and the examples of the pages docv
      ; gen-cr makes. It takes a tree-sitter grammar and its highlights.scm
      ; query, found in ~/.local/lib and $XDG_DATA_HOME/tree-sitter/queries,
      ; where nvim and helix install them, or in $XDG_DATA_HOME/docv/grammars
      ; and $XDG_DATA_HOME/docv/queries/<language>/.
      syntax-highlighting = true

      INI

    # The file this configuration was read from, if any.
    getter path : String?
    # Whether unsafe roff requests run.
    getter? unsafe : Bool
    # Whether the viewer starts in the wrapped layout.
    getter? start_wrapped : Bool
    # Whether code examples are syntax highlighted.
    getter? syntax_highlighting : Bool
    # Role styles from `[colors]`.
    getter colors : Hash(Theme::Role, Theme::Spec)

    def initialize(@path : String? = nil, @unsafe : Bool = false, @colors = {} of Theme::Role => Theme::Spec,
                   @start_wrapped : Bool = true, @syntax_highlighting : Bool = true)
    end

    # The configuration directory: `$XDG_CONFIG_HOME/docv`.
    def self.directory : String
      Docv.user_directory("XDG_CONFIG_HOME", ".config")
    end

    # The configuration file path.
    def self.path : String
      File.join(directory, FILE)
    end

    # Reads the configuration at *path*. When the file does not exist it is
    # created with `DEFAULT` if *create* is set, and the defaults apply.
    def self.load(path : String = self.path, create : Bool = true) : Config
      unless File.exists?(path)
        if create
          Dir.mkdir_p(File.dirname(path))
          File.write(path, DEFAULT)
        end
        return new(path)
      end
      parse(File.read(path), path)
    end

    # Parses configuration *text*.
    def self.parse(text : String, path : String? = nil) : Config
      data = begin
        INI.parse(text)
      rescue ex : INI::ParseException
        raise Error.new("#{path || "config"}: #{ex.message}")
      end
      data.each do |section, values|
        known = KEYS[section]? || raise Error.new("#{path || "config"}: unknown section [#{section}]")
        values.each_key do |key|
          raise Error.new("#{path || "config"}: unknown key #{key} in [#{section}]") unless known.includes?(key)
        end
      end
      roff = data["roff"]? || {} of String => String
      viewer = data["viewer"]? || {} of String => String
      colors = (data["colors"]? || {} of String => String).to_h do |key, text|
        spec = begin
          Theme.parse(text)
        rescue ex : Theme::Error
          raise Error.new("#{path || "config"}: #{key}: #{ex.message}")
        end
        {Theme::KEYS[key], spec}
      end
      new(path, boolean(roff, "unsafe", false, path), colors, boolean(viewer, "start-wrapped", true, path),
        boolean(viewer, "syntax-highlighting", true, path))
    end

    private def self.boolean(values : Hash(String, String), key : String, default : Bool, path : String?) : Bool
      text = values[key]? || return default
      value = BOOLEANS[text.strip.downcase]?
      raise Error.new("#{path || "config"}: #{key} must be true or false, not #{text}") if value.nil?
      value
    end

    # The viewer theme: the defaults with the `[colors]` overrides.
    def theme : Theme
      Theme.new(@colors)
    end

    # Parsing options from this configuration; *stdin* feeds `.rd`.
    def options(stdin : IO? = nil) : Options
      Options.new(@unsafe, stdin, @syntax_highlighting)
    end
  end
end
