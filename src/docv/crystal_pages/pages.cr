# src/docv/crystal_pages/pages.cr

module Docv
  module CrystalPages
    # :nodoc:
    # Lays out constant values.
    module Literal
      # Longest value shown inline in a constant's tag.
      LIMIT = 60

      PAIRS = {'{' => '}', '[' => ']'}

      def self.inline?(value : String) : Bool
        value.size <= LIMIT && !value.includes?('\n')
      end

      # Splits a one-line hash, array or tuple literal into one element per line.
      def self.layout(value : String) : String
        return value unless (open = value[0]?) && (close = PAIRS[open]?) && value.ends_with?(close) && !value.includes?('\n')
        parts = split(value[1...-1])
        return value if parts.size < 2
        String.build do |io|
          io << open << '\n'
          parts.each { |part| io << "  " << part << ",\n" }
          io << close
        end
      end

      # Splits at commas outside nested brackets and string or char literals.
      private def self.split(inner : String) : Array(String)
        parts = [] of String
        depth = 0
        quote = nil.as(Char?)
        escaped = false
        start = 0
        inner.each_char_with_index do |char, index|
          if quote
            if escaped
              escaped = false
            elsif char == '\\'
              escaped = true
            elsif char == quote
              quote = nil
            end
          else
            case char
            when '"', '\''     then quote = char
            when '{', '[', '(' then depth += 1
            when '}', ']', ')' then depth -= 1
            when ','
              next unless depth == 0
              parts << inner[start...index].strip
              start = index + 1
            end
          end
        end
        parts << inner[start..].strip
        parts.reject(&.empty?)
      end
    end

    # :nodoc:
    # The date is set when the page is written.
    record Page, path : String, name : String, section : String, body : String, tables : Bool, footer : String, display : String do
      def render(date : String) : String
        String.build do |io|
          io << "'\\\" t\n" if tables
          io << ".\\\" " << display << '\n'
          io << ".\\\" " << MARKER << ' ' << GENERATED << '\n'
          io << ".TH " << Roff.quote(name) << ' ' << Roff.quote(section) << " \"" << date << "\" " << footer << '\n'
          io << body
        end
      end
    end

    # :nodoc:
    # Builds the two pages of a shard: the overview and the API page, one
    # section per type.
    class Pages
      # Left out of declarations.
      IMPLICIT_SUPERCLASSES = {"Reference", "Struct"}

      # In section order: subsection title, declaration keyword, members.
      MEMBER_SECTIONS = {
        {"Constructors", "def self.", ->(type : TypeDoc) { type.constructors }},
        {"Class methods", "def self.", ->(type : TypeDoc) { type.class_methods }},
        {"Instance methods", "def ", ->(type : TypeDoc) { type.instance_methods }},
        {"Macros", "macro ", ->(type : TypeDoc) { type.macros }},
      }

      # Section title of the top level methods, macros and constants.
      TOP_LEVEL = "Top level"

      @footer : String

      # *output* is the output directory as shown in each page's path comment.
      def initialize(@shard : Shard, @types : Types, @output : String)
        source = [@shard.name, @shard.version].compact.join(' ')
        @footer = "#{Roff.quote(source)} #{Roff.quote("#{@shard.name} API Reference")}"
      end

      def all : Array(Page)
        [overview, api]
      end

      private def overview : Page
        blocks = CrystalPages.blocks(@types.project.body)
        blocks.shift if (first = blocks.first?) && first.type.heading? && first.data["level"]? == 1
        intro = blocks.take_while { |block| !(block.type.heading? && (block.data["level"]?.as?(Int32) || 1) <= 2) }
        summary = intro.find(&.type.paragraph?).try { |paragraph| CrystalPages.summary(CrystalPages.plain(paragraph)) } || ""

        io = IO::Memory.new
        renderer = Renderer.new(io, sections: true)
        section(io, "NAME")
        io << Roff.escape(@shard.name) << " \\- " << Roff.escape(summary.empty? ? "#{@shard.name} API reference" : summary) << '\n'
        unless intro.empty?
          section(io, "DESCRIPTION")
          renderer.render(intro)
        end
        renderer.render(blocks[intro.size..])

        section(io, "TYPES")
        @types.types.each do |type|
          summary = CrystalPages.summary(type.doc)
          io << ".TP\n" << Roff.bold(title(type)) << '\n'
          io << (summary.empty? ? "\\&" : Inline.markdown(summary)) << '\n'
        end
        see_also(io, TYPE_SECTION)
        page(OVERVIEW_SECTION, io, renderer)
      end

      private def api : Page
        io = IO::Memory.new
        renderer = Renderer.new(io)
        section(io, "NAME")
        io << Roff.escape(@shard.name) << " \\- " << Roff.escape("#{@shard.name} API reference") << '\n'
        @types.types.each { |type| type_section(io, renderer, type) }
        see_also(io, OVERVIEW_SECTION)
        page(TYPE_SECTION, io, renderer)
      end

      private def type_section(io : IO, renderer : Renderer, type : TypeDoc) : Nil
        section(io, title(type))
        unless type.program?
          io << ".nf\n"
          @shard.require_path(type).try { |path| io << Roff.bold(%(require "#{path}")) << "\n.sp\n" }
          io << Roff.bold(declaration(type)) << "\n.fi\n"
        end
        renderer.render(CrystalPages.blocks(type.doc))

        if explicit_superclass?(type)
          chain = [type.full_name] + type.ancestors.select(&.kind.in?("class", "struct")).map(&.full_name)
          subsection(io, "Inheritance")
          io << Roff.escape(chain.join(" < ")) << '\n'
        end

        type.relations.each do |name, refs|
          next if refs.empty?
          subsection(io, name)
          io << refs.join(",\n") { |ref| Roff.bold(ref.full_name) } << '\n'
        end

        constants(io, renderer, type)
        members(io, renderer, type)

        files = type.locations.compact_map(&.filename).uniq
        unless files.empty?
          subsection(io, "Defined in")
          io << files.join("\n.br\n") { |file| Roff.escape(file) } << '\n'
        end
      end

      private def constants(io : IO, renderer : Renderer, type : TypeDoc) : Nil
        return if type.constants.empty?
        subsection(io, type.enum_type? ? "Enum members" : "Constants")
        type.constants.each do |constant|
          value = constant.value.try { |text| @shard.relative(text) }
          blocks = CrystalPages.blocks(constant.doc)
          if value.nil? || Literal.inline?(value)
            tag = value ? "#{constant.name} = #{value}" : constant.name
          else
            tag = constant.name
            blocks.unshift(CrystalPages.code_block("#{constant.name} = #{Literal.layout(value)}"))
          end
          entry(io, renderer, tag, blocks)
        end
      end

      private def members(io : IO, renderer : Renderer, type : TypeDoc) : Nil
        MEMBER_SECTIONS.each do |name, keyword, list|
          members = list.call(type)
          next if members.empty?
          subsection(io, name)
          members.each do |member|
            entry(io, renderer, signature(type, keyword, member), CrystalPages.blocks(member.doc))
          end
        end
      end

      # A bold *tag* with its documentation indented below.
      private def entry(io : IO, renderer : Renderer, tag : String, blocks : Array(Markd::Node)) : Nil
        if blocks.empty?
          io << ".PP\n" << Roff.bold(tag) << '\n'
        else
          renderer.item(".TP #{Roff::INDENT}\n#{Roff.bold(tag)}", blocks)
        end
      end

      # The other page of the shard, in *section*.
      private def see_also(io : IO, section : String) : Nil
        section(io, "SEE ALSO")
        io << ".BR " << Roff.quote(@shard.name) << " (" << section << SUFFIX << ")\n"
      end

      private def title(type : TypeDoc) : String
        type.program? ? TOP_LEVEL : type.base_name
      end

      private def declaration(type : TypeDoc) : String
        if type.alias_type? && (aliased = type.aliased)
          return "alias #{type.full_name} = #{CrystalPages.clean_type(aliased)}"
        end
        head = "#{"abstract " if type.abstract_type?}#{type.kind} #{type.full_name}"
        superclass = type.superclass
        superclass && explicit_superclass?(type) ? "#{head} < #{superclass.full_name}" : head
      end

      private def explicit_superclass?(type : TypeDoc) : Bool
        !!type.superclass.try { |superclass| !IMPLICIT_SUPERCLASSES.includes?(superclass.full_name) }
      end

      private def signature(type : TypeDoc, keyword : String, member : Member) : String
        keyword = "fun " if type.lib? && keyword != "macro "
        keyword = "def " if type.program? && keyword == "def self."
        "#{"abstract " if member.abstract_def?}#{keyword}#{member.name}#{member.parameters}"
      end

      private def section(io : IO, title : String) : Nil
        io << ".SH " << Roff.quote(title) << '\n'
      end

      private def subsection(io : IO, title : String) : Nil
        io << ".SS " << Roff.quote(title) << '\n'
      end

      # The page of the shard in manual *section*, compressed.
      private def page(section : String, io : IO, renderer : Renderer) : Page
        path = "man#{section}/#{@shard.name}.#{section}#{SUFFIX}#{COMPRESSION}"
        Page.new(path, @shard.name, "#{section}#{SUFFIX}", io.to_s, renderer.tables?, @footer, File.join(@output, path))
      end
    end

    # :nodoc:
    # Writes pages gzipped. Unchanged pages keep their date; stale generated
    # pages are removed; other files are never touched.
    class Generator
      TH_DATE = /\A\.TH "[^"]*" "[^"]*" "([^"]*)"/

      # Today, or `SOURCE_DATE_EPOCH` for reproducible builds.
      def self.today : String
        epoch = ENV["SOURCE_DATE_EPOCH"]?
        time = epoch ? Time.unix(epoch.to_i64? || raise Error.new("invalid SOURCE_DATE_EPOCH `#{epoch}`")) : Time.local
        time.to_s("%Y-%m-%d")
      end

      def initialize(@output : String, @date : String)
      end

      # Returns the numbers of pages written, unchanged and removed.
      def run(pages : Array(Page)) : {Int32, Int32, Int32}
        written = unchanged = 0
        pages.each do |page|
          file = File.join(@output, page.path)
          existing = File.file?(file) ? read(file) : nil
          if File.file?(file) && !existing.try(&.includes?(GENERATED))
            raise Error.new("#{file} was not generated from doc comments; move it away first")
          end
          if existing && (date = date_of(existing)) && existing == page.render(date)
            unchanged += 1
          else
            Dir.mkdir_p(File.dirname(file))
            write(file, page.render(@date))
            written += 1
          end
        end
        {written, unchanged, remove_stale(pages.map { |page| File.join(@output, page.path) }.to_set)}
      end

      # The text of a page file, gzipped or not; `nil` when unreadable.
      private def read(file : String) : String?
        return File.read(file) unless file.ends_with?(COMPRESSION)
        Compress::Gzip::Reader.open(file, &.gets_to_end)
      rescue IO::Error | Compress::Gzip::Error
        nil
      end

      # Gzips *text* into *file*, with a fixed header time so equal pages give
      # equal files.
      private def write(file : String, text : String) : Nil
        File.open(file, "w") do |io|
          Compress::Gzip::Writer.open(io) do |gzip|
            gzip.header.modification_time = Time.unix(0)
            gzip << text
          end
        end
      end

      private def date_of(text : String) : String?
        text.each_line.find(&.starts_with?(".TH ")).try(&.match(TH_DATE)).try(&.[1])
      end

      private def remove_stale(keep : Set(String)) : Int32
        stale = Dir.glob(File.join(@output, "man*", "*")).select do |file|
          !keep.includes?(file) && File.file?(file) && read(file).try(&.includes?(GENERATED))
        end
        stale.each { |file| File.delete(file) }
        stale.size
      end
    end
  end
end
