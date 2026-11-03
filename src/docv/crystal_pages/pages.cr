# src/docv/crystal_pages/pages.cr
module Docv
  module CrystalPages
    # Lays out constant values for display.
    module Literal
      # Longest value shown in the constant's tag; longer ones get a display
      # of their own.
      LIMIT = 60

      PAIRS = {'{' => '}', '[' => ']'}

      def self.inline?(value : String) : Bool
        value.size <= LIMIT && !value.includes?('\n')
      end

      # *value* with a long one-line hash, array or tuple literal split into
      # one element per line.
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

      # Elements separated by top-level commas, outside nested brackets and
      # string or char literals.
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

    # One generated page; the date is set when it is written.
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

    # Builds every page of a shard: the overview and one page per documented
    # type.
    class Pages
      # Superclasses every class or struct has, left out of declarations.
      IMPLICIT_SUPERCLASSES = {"Reference", "Struct"}

      # Member sections in page order: title, declaration keyword, members.
      MEMBER_SECTIONS = {
        {"CONSTRUCTORS", "def self.", ->(type : TypeDoc) { type.constructors }},
        {"CLASS METHODS", "def self.", ->(type : TypeDoc) { type.class_methods }},
        {"INSTANCE METHODS", "def ", ->(type : TypeDoc) { type.instance_methods }},
        {"MACROS", "macro ", ->(type : TypeDoc) { type.macros }},
      }

      @footer : String

      # *output* is the output directory as it appears in each page's path
      # comment.
      def initialize(@shard : Shard, @types : Types, @output : String)
        source = [@shard.name, @shard.version].compact.join(' ')
        @footer = "#{Roff.quote(source)} #{Roff.quote("#{@shard.name} API Reference")}"
      end

      def all : Array(Page)
        [overview] + @types.types.map { |type| type_page(type) }
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
          io << ".TP\n.BR " << Roff.quote(page_name(type)) << " (" << TYPE_SECTION << SUFFIX << ")\n"
          io << (summary.empty? ? "\\&" : Inline.markdown(summary)) << '\n'
        end
        page("man#{OVERVIEW_SECTION}/#{@shard.name}.#{OVERVIEW_SECTION}#{SUFFIX}", @shard.name, OVERVIEW_SECTION, io, renderer)
      end

      private def type_page(type : TypeDoc) : Page
        io = IO::Memory.new
        renderer = Renderer.new(io)
        name = page_name(type)

        section(io, "NAME")
        summary = CrystalPages.summary(type.doc)
        io << Roff.escape(name) << " \\- "
        fallback = type.program? ? "top level methods, macros and constants of #{@shard.name}" : "#{type.kind} in #{@shard.name}"
        io << (summary.empty? ? Roff.escape(fallback) : Inline.markdown(summary, urls: false)) << '\n'

        unless type.program?
          section(io, "SYNOPSIS")
          io << ".nf\n"
          @shard.require_path(type).try { |path| io << Roff.bold(%(require "#{path}")) << "\n.sp\n" }
          io << Roff.bold(declaration(type)) << "\n.fi\n"
        end

        unless (description = CrystalPages.blocks(type.doc)).empty?
          section(io, "DESCRIPTION")
          renderer.render(description)
        end

        if explicit_superclass?(type)
          chain = [type.full_name] + type.ancestors.select(&.kind.in?("class", "struct")).map(&.full_name)
          section(io, "INHERITANCE")
          io << Roff.escape(chain.join(" < ")) << '\n'
        end

        type.relations.each do |title, refs|
          next if refs.empty?
          section(io, title)
          io << refs.join(",\n") { |ref| Roff.bold(ref.full_name) } << '\n'
        end

        constants(io, renderer, type)
        members(io, renderer, type)

        files = type.locations.compact_map(&.filename).uniq
        unless files.empty?
          section(io, "DEFINED IN")
          io << files.join("\n.br\n") { |file| Roff.escape(file) } << '\n'
        end

        see_also(io, type)
        page("man#{TYPE_SECTION}/#{name}.#{TYPE_SECTION}#{SUFFIX}", name, TYPE_SECTION, io, renderer)
      end

      private def constants(io : IO, renderer : Renderer, type : TypeDoc) : Nil
        return if type.constants.empty?
        section(io, type.enum_type? ? "ENUM MEMBERS" : "CONSTANTS")
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
        MEMBER_SECTIONS.each do |title, keyword, list|
          members = list.call(type)
          next if members.empty?
          section(io, title)
          members.each do |member|
            entry(io, renderer, signature(type, keyword, member), CrystalPages.blocks(member.doc))
          end
        end
      end

      # A bold *tag* with its documentation indented below it.
      private def entry(io : IO, renderer : Renderer, tag : String, blocks : Array(Markd::Node)) : Nil
        if blocks.empty?
          io << ".PP\n" << Roff.bold(tag) << '\n'
        else
          renderer.item(".TP #{Roff::INDENT}\n#{Roff.bold(tag)}", blocks)
        end
      end

      # Every related type with a page of its own, then the overview.
      private def see_also(io : IO, type : TypeDoc) : Nil
        related = [type.namespace, type.superclass].compact
        type.relations.each { |_, refs| related.concat(refs) }
        types = related.compact_map { |ref| @types[ref.full_name]? } + type.types + @types.referenced(type)
        names = types.map { |other| page_name(other) }.uniq.reject(page_name(type)).sort
        section(io, "SEE ALSO")
        names.each { |name| io << ".BR " << Roff.quote(name) << " (" << TYPE_SECTION << SUFFIX << "),\n" }
        io << ".BR " << Roff.quote(@shard.name) << " (" << OVERVIEW_SECTION << SUFFIX << ")\n"
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

      private def page_name(type : TypeDoc) : String
        type.program? ? "#{@shard.name}-toplevel" : type.base_name
      end

      private def section(io : IO, title : String) : Nil
        io << ".SH " << Roff.quote(title) << '\n'
      end

      private def page(path : String, name : String, section : String, io : IO, renderer : Renderer) : Page
        Page.new(path, name, "#{section}#{SUFFIX}", io.to_s, renderer.tables?, @footer, File.join(@output, path))
      end
    end

    # Writes pages into an output directory. A page whose content is
    # unchanged keeps its file and date; generated pages no longer produced
    # are removed. A file there that was not generated is never touched.
    class Generator
      TH_DATE = /\A\.TH "[^"]*" "[^"]*" "([^"]*)"/

      # Today, or the date of `SOURCE_DATE_EPOCH` for reproducible builds.
      def self.today : String
        epoch = ENV["SOURCE_DATE_EPOCH"]?
        time = epoch ? Time.unix(epoch.to_i64? || raise Error.new("invalid SOURCE_DATE_EPOCH `#{epoch}`")) : Time.local
        time.to_s("%Y-%m-%d")
      end

      def initialize(@output : String, @date : String)
      end

      # Writes *pages*; returns the numbers of pages written, unchanged and
      # removed.
      def run(pages : Array(Page)) : {Int32, Int32, Int32}
        written = unchanged = 0
        pages.each do |page|
          file = File.join(@output, page.path)
          existing = File.file?(file) ? File.read(file) : nil
          if existing && !existing.includes?(GENERATED)
            raise Error.new("#{file} was not generated from doc comments; move it away first")
          end
          if existing && (date = date_of(existing)) && existing == page.render(date)
            unchanged += 1
          else
            Dir.mkdir_p(File.dirname(file))
            File.write(file, page.render(@date))
            written += 1
          end
        end
        {written, unchanged, remove_stale(pages.map { |page| File.join(@output, page.path) }.to_set)}
      end

      private def date_of(text : String) : String?
        text.each_line.find(&.starts_with?(".TH ")).try(&.match(TH_DATE)).try(&.[1])
      end

      private def remove_stale(keep : Set(String)) : Int32
        stale = Dir.glob(File.join(@output, "man*", "*")).select do |file|
          !keep.includes?(file) && File.file?(file) && File.read(file).includes?(GENERATED)
        end
        stale.each { |file| File.delete(file) }
        stale.size
      end
    end
  end
end
