# src/docv/config.cr

require "ini"

module Docv
  # :nodoc:
  # `$variable`, or `~/fallback` when it is unset or not absolute.
  def self.base_directory(variable : String, fallback : String) : String
    base = ENV[variable]?
    base.nil? || base.empty? || !Path[base].absolute? ? Path.home.join(fallback).to_s : base
  end

  # :nodoc:
  # `base_directory` with `docv` appended.
  def self.user_directory(variable : String, fallback : String) : String
    File.join(base_directory(variable, fallback), "docv")
  end

  # Parsing options: *unsafe* runs the requests that execute commands or
  # touch files (and `\V`); *stdin* feeds `.rd` (`nil` reads nothing);
  # *highlight* syntax-highlights code examples (`Syntax`); *indent* sets the
  # body indent of manual pages in columns (`nil`: 7 for man(7), 5 for
  # mdoc(7)).
  record Options, unsafe : Bool = false, stdin : IO? = nil, highlight : Bool = false, indent : Int32? = nil

  # :nodoc:
  # A RAM-backed directory for files that must not reach the disk:
  # `$XDG_RUNTIME_DIR`, else `/dev/shm`, else the temporary directory, with
  # `docv` appended.
  def self.runtime_directory : String
    base = ENV["XDG_RUNTIME_DIR"]?
    base = Dir.exists?("/dev/shm") ? "/dev/shm" : Dir.tempdir if base.nil? || base.empty? || !Path[base].absolute?
    File.join(base, "docv")
  end

  # Where the viewer keeps the man pages it generates for a Crystal shard:
  # `Memory` in a RAM-backed directory removed when it quits, `Disk` in the
  # shard's man directory.
  enum PageStore
    Memory
    Disk
  end

  # Settings from `[crystal]`: whether the viewer generates the man pages of
  # the Crystal shard it starts in, and where it keeps them.
  record CrystalSettings, generate : Bool = true, store : PageStore = PageStore::Memory

  # Settings of the viewer's dock from `[picker]`: its width in columns,
  # whether it opens at start, the fewest pages that make a group in its tree
  # (*min_group*), and the number of search threads (0: one less than the
  # processor count).
  record PickerSettings, dock_width : Int32 = 20, dock_open : Bool = false, min_group : Int32 = 2,
    search_threads : Int32 = 0

  # The user configuration, `$XDG_CONFIG_HOME/docv/config.ini`.
  class Config
    # An unparsable configuration or an invalid value.
    class Error < Exception
    end

    # :nodoc:
    FILE = "config.ini"

    # :nodoc:
    BOOLEANS = {
      "true" => true, "yes" => true, "on" => true, "1" => true,
      "false" => false, "no" => false, "off" => false, "0" => false,
    }

    # :nodoc:
    KEYS = {
      "man"     => Set{"roff-unsafe", "indent"},
      "viewer"  => Set{"start-wrapped", "syntax-highlighting"},
      "picker"  => Set{"dock-width", "dock-open", "min-group", "search-threads"},
      "crystal" => Set{"generate", "store"},
      "colors"  => Theme::KEYS.keys.to_set,
    }

    # :nodoc:
    # Body indent of manual pages when `indent` is unset.
    INDENT = 2

    # :nodoc:
    RANGES = {"indent" => 0..40, "dock-width" => 16..400, "min-group" => 2..1000, "search-threads" => 0..1024}

    # :nodoc:
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

    # The commented default file `load` writes when none exists.
    DEFAULT = String.build do |io|
      io << MAN << '\n' << VIEWER << '\n' << PICKER << '\n' << CRYSTAL << '\n' << COLORS
      Theme::DEFAULT.each { |role, spec| io << "; " << Theme.key(role) << " = " << spec << '\n' }
    end

    private MAN = <<-INI
      ; docv configuration

      [man]
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
      roff-unsafe = false
      ; Body indent of manual pages in columns (groff indents man(7) pages
      ; 7 and mdoc(7) pages 5).
      indent = 2

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

    private PICKER = <<-INI
      [picker]
      ; The dock left of the page holds the search field and the tree of
      ; pages (p opens and closes it); the page narrows to make room.
      ; Width of the dock in columns; dragging its right edge changes it
      ; until the viewer quits.
      dock-width = 20
      ; Open the dock at start.
      dock-open = false
      ; Fewest pages sharing a name prefix (abrt-cli, abrt-dump ...) that
      ; make a group in the tree.
      min-group = 2
      ; Threads that read the text of every page and search it, for the
      ; hit counts in the tree while finding in the page. 0: one less than
      ; the number of processors.
      search-threads = 0

      INI

    private CRYSTAL = <<-INI
      [crystal]
      ; In a Crystal shard, generate its man pages when the viewer starts, as
      ; docv gen-cr does: an overview, name(7cr), and the API, name(3cr).
      generate = true
      ; Where the generated pages go. memory: a RAM-backed directory removed
      ; when the viewer quits (Ctrl-s saves them into the shard's man
      ; directory); disk: the shard's man directory.
      store = memory

      INI

    # The file this configuration was read from, if any.
    getter path : String?
    # Whether unsafe roff requests run.
    getter? unsafe : Bool
    # The body indent of manual pages in columns.
    getter indent : Int32
    # Whether the viewer starts in the wrapped layout.
    getter? start_wrapped : Bool
    # Whether code examples are syntax highlighted.
    getter? syntax_highlighting : Bool
    # Role specs from `[colors]`.
    getter colors : Hash(Theme::Role, Theme::Spec)
    # Dock and search settings.
    getter picker : PickerSettings
    # Man pages of Crystal shards.
    getter crystal : CrystalSettings

    def initialize(@path : String? = nil, @unsafe : Bool = false, @colors = {} of Theme::Role => Theme::Spec,
                   @start_wrapped : Bool = true, @syntax_highlighting : Bool = true,
                   @picker : PickerSettings = PickerSettings.new, @indent : Int32 = INDENT,
                   @crystal : CrystalSettings = CrystalSettings.new)
    end

    # The configuration directory, `$XDG_CONFIG_HOME/docv`.
    def self.directory : String
      Docv.user_directory("XDG_CONFIG_HOME", ".config")
    end

    # The configuration file path.
    def self.path : String
      File.join(directory, FILE)
    end

    # Reads the configuration at *path*. A missing file gives the defaults and,
    # with *create*, is written as `DEFAULT`.
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

    # Parses configuration *text* (*path* names it in errors); raises `Error`
    # when invalid.
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
      man = data["man"]? || {} of String => String
      viewer = data["viewer"]? || {} of String => String
      picker = data["picker"]? || {} of String => String
      crystal = data["crystal"]? || {} of String => String
      colors = (data["colors"]? || {} of String => String).to_h do |key, text|
        spec = begin
          Theme.parse(text)
        rescue ex : Theme::Error
          raise Error.new("#{path || "config"}: #{key}: #{ex.message}")
        end
        {Theme::KEYS[key], spec}
      end
      defaults = PickerSettings.new
      settings = PickerSettings.new(integer(picker, "dock-width", path) || defaults.dock_width,
        boolean(picker, "dock-open", defaults.dock_open, path),
        integer(picker, "min-group", path) || defaults.min_group,
        integer(picker, "search-threads", path) || defaults.search_threads)
      shard = CrystalSettings.new(boolean(crystal, "generate", true, path),
        choice(crystal, "store", PageStore::Memory, path))
      new(path, boolean(man, "roff-unsafe", false, path), colors, boolean(viewer, "start-wrapped", true, path),
        boolean(viewer, "syntax-highlighting", true, path), settings, integer(man, "indent", path) || INDENT, shard)
    end

    private def self.boolean(values : Hash(String, String), key : String, default : Bool, path : String?) : Bool
      text = values[key]? || return default
      value = BOOLEANS[text.strip.downcase]?
      raise Error.new("#{path || "config"}: #{key} must be true or false, not #{text}") if value.nil?
      value
    end

    # The value of integer *key*, `nil` when unset.
    private def self.integer(values : Hash(String, String), key : String, path : String?) : Int32?
      text = values[key]? || return nil
      range = RANGES[key]
      value = text.strip.to_i?
      unless value && range.includes?(value)
        raise Error.new("#{path || "config"}: #{key} must be a number from #{range.begin} to #{range.end}, not #{text}")
      end
      value
    end

    # The value of *key* named after a member of the enum *default* belongs to.
    private def self.choice(values : Hash(String, String), key : String, default : T, path : String?) : T forall T
      text = values[key]? || return default
      T.parse?(text.strip) ||
        raise Error.new("#{path || "config"}: #{key} must be #{T.names.map(&.downcase).join(" or ")}, not #{text}")
    end

    # The default theme with the `[colors]` overrides.
    def theme : Theme
      Theme.new(@colors)
    end

    # Parsing options from this configuration; *stdin* feeds `.rd`.
    def options(stdin : IO? = nil) : Options
      Options.new(@unsafe, stdin, @syntax_highlighting, @indent)
    end
  end
end
