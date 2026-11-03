# src/docv/syntax.cr

require "treesitter"

module Docv
  # Syntax highlighting through tree-sitter: a grammar from
  # `grammar_directories` and its `highlights.scm` from `query_directories`.
  # docv ships neither; a language without both stays plain.
  module Syntax
    # A directory of `<language>/highlights.scm` queries. Of two patterns on
    # one node the later wins (nvim), or the earlier with *first_wins* (helix).
    record QueryDirectory, path : String, first_wins : Bool = false

    # Code block labels that differ from their grammar's name.
    ALIASES = {
      "cr" => "crystal", "sh" => "bash", "shell" => "bash", "zsh" => "bash", "console" => "bash",
      "js" => "javascript", "mjs" => "javascript", "jsx" => "javascript", "ts" => "typescript",
      "py" => "python", "rb" => "ruby", "rs" => "rust", "yml" => "yaml", "md" => "markdown",
      "c++" => "cpp", "cxx" => "cpp", "hpp" => "cpp", "h" => "c", "cs" => "c_sharp", "csharp" => "c_sharp",
      "golang" => "go", "kt" => "kotlin", "ex" => "elixir", "exs" => "elixir", "hs" => "haskell",
      "ml" => "ocaml", "pl" => "perl", "ps1" => "powershell", "tf" => "hcl", "dockerfile" => "dockerfile",
      "html" => "html", "htm" => "html", "xml" => "xml", "scm" => "query",
    }

    # :nodoc:
    # Example language by page section suffix (`Foo.3cr`).
    SECTION_LANGUAGES = {"cr" => "crystal"}

    # Capture names to `Markup`, matched by longest dotted prefix; `None` and
    # unlisted names stay plain.
    CAPTURES = {
      "keyword" => Markup::SyntaxKeyword, "conditional" => Markup::SyntaxKeyword,
      "repeat" => Markup::SyntaxKeyword, "include" => Markup::SyntaxKeyword,
      "exception" => Markup::SyntaxKeyword, "storageclass" => Markup::SyntaxKeyword,
      "define" => Markup::SyntaxKeyword, "preproc" => Markup::SyntaxKeyword, "label" => Markup::SyntaxKeyword,
      "string" => Markup::SyntaxString, "character" => Markup::SyntaxString,
      "comment" => Markup::SyntaxComment,
      "function" => Markup::SyntaxFunction, "method" => Markup::SyntaxFunction,
      "constructor" => Markup::SyntaxFunction,
      "type" => Markup::SyntaxType, "namespace" => Markup::SyntaxType, "module" => Markup::SyntaxType,
      "constant" => Markup::SyntaxConstant, "number" => Markup::SyntaxConstant, "float" => Markup::SyntaxConstant,
      "boolean" => Markup::SyntaxConstant, "variable.builtin" => Markup::SyntaxConstant,
      "operator" => Markup::SyntaxOperator,
      "punctuation" => Markup::SyntaxPunctuation,
      "property" => Markup::SyntaxProperty, "field" => Markup::SyntaxProperty,
      "attribute" => Markup::SyntaxProperty, "variable.member" => Markup::SyntaxProperty,
      "variable.other.member" => Markup::SyntaxProperty,
      "tag" => Markup::SyntaxTag,
      "variable" => Markup::None, "spell" => Markup::None, "nospell" => Markup::None,
      "none" => Markup::None, "conceal" => Markup::None,
    }

    # :nodoc:
    QUERY_FILE = "highlights.scm"
    # :nodoc:
    # `; inherits: ecma,jsx` (nvim; a name in parentheses is optional).
    INHERITS = /\A;+\s*inherits\s*:?\s*(.+)/

    # Grammar directories searched after `TreeSitter::Language.directories`.
    class_property grammar_directories : Array(String) = [
      File.join(Docv.user_directory("XDG_DATA_HOME", ".local/share"), "grammars"),
      File.join(Docv.base_directory("XDG_DATA_HOME", ".local/share"), "nvim", "site", "parser"),
      File.join(Docv.base_directory("XDG_DATA_HOME", ".local/share"), "nvim", "lazy", "nvim-treesitter", "parser"),
      File.join(Docv.base_directory("XDG_CONFIG_HOME", ".config"), "helix", "runtime", "grammars"),
      "/usr/lib64/helix/runtime/grammars", "/usr/lib/helix/runtime/grammars", "/usr/share/helix/runtime/grammars",
    ]

    # Query directories, searched in order.
    class_property query_directories : Array(QueryDirectory) = [
      QueryDirectory.new(File.join(Docv.user_directory("XDG_DATA_HOME", ".local/share"), "queries")),
      QueryDirectory.new(File.join(Docv.base_directory("XDG_DATA_HOME", ".local/share"), "tree-sitter", "queries")),
      QueryDirectory.new(File.join(Docv.base_directory("XDG_DATA_HOME", ".local/share"), "nvim", "site", "queries")),
      QueryDirectory.new(File.join(Docv.base_directory("XDG_DATA_HOME", ".local/share"), "nvim", "lazy", "nvim-treesitter", "queries")),
      QueryDirectory.new("/usr/share/nvim/runtime/queries"),
      QueryDirectory.new(File.join(Docv.base_directory("XDG_CONFIG_HOME", ".config"), "helix", "runtime", "queries"), true),
      QueryDirectory.new("/usr/lib64/helix/runtime/queries", true),
      QueryDirectory.new("/usr/lib/helix/runtime/queries", true),
      QueryDirectory.new("/usr/share/helix/runtime/queries", true),
    ]

    private record Grammar, parser : TreeSitter::Parser, query : TreeSitter::Query, first_wins : Bool

    @@grammars = {} of String => Grammar?

    # The grammar name of code block *label* (its first word, lower case,
    # through `ALIASES`); `nil` when empty.
    def self.language(label : String) : String?
      name = label.split.first?.try(&.downcase) || return nil
      ALIASES[name]? || name
    end

    # :nodoc:
    def self.page_language(path : String?) : String?
      file = path.try { |current| File.basename(current) } || return nil
      _, section = Manpath.split(file) || return nil
      SECTION_LANGUAGES[section.lstrip("0123456789")]?
    end

    # The lines of *code* as runs of text and markup; `nil` when *language*
    # lacks a grammar or highlight query.
    def self.highlight(code : String, language : String) : Array(Array({String, Markup}))?
      grammar = grammar(language) || return nil
      marks = Array(Markup).new(code.bytesize, Markup::None)
      tree = grammar.parser.parse(code)
      last = {-1, -1}
      grammar.query.each_capture(tree.root, code) do |capture|
        markup = markup(capture.name) || next
        node = capture.node
        range = {node.start_byte, Math.min(node.end_byte, code.bytesize)}
        next if grammar.first_wins && range == last
        last = range
        (range[0]...range[1]).each { |byte| marks[byte] = markup }
      end
      runs(code, marks)
    rescue TreeSitter::Error
      nil
    end

    # Highlights *blocks*, the consecutive text and blank blocks of one code
    # example, by setting the markup on their spans.
    def self.apply(blocks : Array(Block), language : String) : Nil
      lines = [] of String
      owners = [] of Block?
      blocks.each do |block|
        case block.kind
        when .text?
          lines << block.text
          owners << block
        when .blank?
          block.lines.times do
            lines << ""
            owners << nil
          end
        else
          return
        end
      end
      runs = highlight(lines.join('\n'), language) || return
      runs.each_with_index do |line, index|
        block = owners[index]? || next
        base = block.spans.first?.try(&.style) || 0_u16
        block.spans = line.map do |text, markup|
          Span.new(text, markup.none? ? base : Styles.id(Styles[base].copy_with(markup: markup)))
        end
      end
    end

    # :nodoc:
    def self.markup(name : String) : Markup?
      return nil if name.starts_with?('_')
      loop do
        if markup = CAPTURES[name]?
          return markup.none? ? nil : markup
        end
        dot = name.rindex('.') || return nil
        name = name[0, dot]
      end
    end

    # Forgets loaded grammars, so changed directories take effect.
    def self.clear : Nil
      @@grammars.clear
    end

    private def self.grammar(name : String) : Grammar?
      return @@grammars[name] if @@grammars.has_key?(name)
      @@grammars[name] = load(name)
    end

    private def self.load(name : String) : Grammar?
      found = query(name, Set(String).new) || return nil
      source, first_wins = found
      grammar_directories.each do |dir|
        TreeSitter::Language.directories << dir unless TreeSitter::Language.directories.includes?(dir)
      end
      language = TreeSitter::Language.load(name)
      Grammar.new(TreeSitter::Parser.new(language), TreeSitter::Query.new(language, source), first_wins)
    rescue TreeSitter::Error | File::Error
      nil
    end

    # Inherited queries come first in the returned text.
    private def self.query(name : String, seen : Set(String)) : {String, Bool}?
      return nil unless seen.add?(name)
      directory = query_directories.find { |dir| File.file?(File.join(dir.path, name, QUERY_FILE)) } || return nil
      text = File.read(File.join(directory.path, name, QUERY_FILE))
      inherited = text.lines.take_while(&.starts_with?(';')).compact_map(&.match(INHERITS).try(&.[1])).flat_map(&.split(','))
      parts = [] of String
      inherited.each { |other| query(other.strip.strip("()"), seen).try { |found| parts << found[0] } }
      parts << text
      {parts.join('\n'), directory.first_wins}
    end

    # *marks* holds one `Markup` per byte of *code*.
    private def self.runs(code : String, marks : Array(Markup)) : Array(Array({String, Markup}))
      lines = [[] of {String, Markup}]
      buffer = String::Builder.new
      current = Markup::None
      byte = 0
      code.each_char do |char|
        if char == '\n'
          flush(lines, buffer, current)
          buffer = String::Builder.new
          lines << [] of {String, Markup}
          byte += 1
          next
        end
        markup = marks[byte]? || Markup::None
        if markup != current && buffer.bytesize > 0
          flush(lines, buffer, current)
          buffer = String::Builder.new
        end
        current = markup
        buffer << char
        byte += char.bytesize
      end
      flush(lines, buffer, current)
      lines
    end

    private def self.flush(lines : Array(Array({String, Markup})), buffer : String::Builder, markup : Markup) : Nil
      lines.last << {buffer.to_s, markup} if buffer.bytesize > 0
    end
  end
end
