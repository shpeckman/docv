# src/docv/crystal_pages/model.cr

module Docv
  module CrystalPages
    # :nodoc:
    struct Location
      include JSON::Serializable

      getter filename : String?
    end

    # :nodoc:
    struct TypeRef
      include JSON::Serializable

      getter kind : String
      getter full_name : String
    end

    # :nodoc:
    # Only the external name matters, to recognize generated members.
    struct Arg
      include JSON::Serializable

      getter external_name : String?
    end

    # :nodoc:
    struct Definition
      include JSON::Serializable

      getter return_type : String?
      getter body : String?
    end

    # :nodoc:
    # Constant or enum member.
    struct Constant
      include JSON::Serializable

      # `crystal docs` leaves macro expressions unexpanded.
      MACRO_STARTS = {"{{", "{%"}

      getter name : String
      getter doc : String?
      @value : String?

      # As written in the source; `nil` when unknown or an unexpanded macro.
      def value : String?
        value = @value
        value unless value && MACRO_STARTS.any? { |start| value.starts_with?(start) }
      end
    end

    # :nodoc:
    # Constructor, method or macro.
    struct Member
      include JSON::Serializable

      # Defined in every type by the compiler or `record`; hidden unless documented.
      BOILERPLATE = {"clone", "copy_with", "finalize"}

      # Bodies of the `new` overloads `JSON::Serializable` and `YAML::Serializable` add.
      SERIALIZER_BODIES = {"new_from_json_pull_parser(pull)", "new_from_yaml_node(ctx, node)"}

      ID_SUFFIX = /-(?:instance-method|class-method|macro|function)\z/

      getter html_id : String
      getter name : String
      getter doc : String?
      @[JSON::Field(key: "abstract")]
      getter? abstract_def : Bool = false
      getter args : Array(Arg) = [] of Arg
      getter args_string : String?
      @[JSON::Field(key: "def")]
      getter definition : Definition?

      # Whether the compiler or the standard library generated this member.
      def generated? : Bool
        (doc.nil? && BOILERPLATE.includes?(name)) ||
          args.any? { |arg| arg.external_name.try(&.starts_with?("__")) } ||
          SERIALIZER_BODIES.includes?(definition.try(&.body))
      end

      # As declared, e.g. `(name : String) : Language`.
      def parameters : String
        CrystalPages.clean_type(args_string || return_type.try { |type| " : #{type}" } || "")
      end

      # `crystal docs` gives no parameter string for a member without
      # parameters; macro-generated getters carry their return type only in
      # the id (`name:Type-instance-method`).
      private def return_type : String?
        definition.try(&.return_type) || begin
          rest = HTML.unescape(html_id).lchop(name)
          rest.sub(ID_SUFFIX, "")[1..].presence if args.empty? && rest.starts_with?(':')
        end
      end
    end

    # :nodoc:
    # A documented type; the program (top level) is one too.
    class TypeDoc
      include JSON::Serializable

      getter kind : String
      getter full_name : String
      @[JSON::Field(key: "abstract")]
      getter? abstract_type : Bool = false
      getter superclass : TypeRef?
      getter ancestors : Array(TypeRef) = [] of TypeRef
      getter locations : Array(Location) = [] of Location
      getter? program : Bool = false
      @[JSON::Field(key: "enum")]
      getter? enum_type : Bool = false
      @[JSON::Field(key: "alias")]
      getter? alias_type : Bool = false
      getter aliased : String?
      getter constants : Array(Constant) = [] of Constant
      getter included_modules : Array(TypeRef) = [] of TypeRef
      getter extended_modules : Array(TypeRef) = [] of TypeRef
      getter subclasses : Array(TypeRef) = [] of TypeRef
      getter including_types : Array(TypeRef) = [] of TypeRef
      getter namespace : TypeRef?
      getter doc : String?
      getter constructors : Array(Member) = [] of Member
      getter class_methods : Array(Member) = [] of Member
      getter instance_methods : Array(Member) = [] of Member
      getter macros : Array(Member) = [] of Member
      getter types : Array(TypeDoc) = [] of TypeDoc

      # Drops generated members and the `Kind#member?` predicates of enums.
      protected def after_initialize : Nil
        {@constructors, @class_methods, @instance_methods, @macros}.each &.reject!(&.generated?)
        return unless enum_type?
        predicates = constants.map { |constant| "#{constant.name.underscore}?" }
        @instance_methods.reject! { |member| member.args.empty? && predicates.includes?(member.name) }
      end

      def base_name : String
        CrystalPages.base_name(full_name)
      end

      # Only types with constructors, methods or macros get a page of their own.
      def lib? : Bool
        kind == "lib"
      end

      # Subsection titles and related types, in page order.
      def relations : Array({String, Array(TypeRef)})
        [
          {"Included modules", included_modules},
          {"Extended modules", extended_modules},
          {"Direct known subclasses", subclasses},
          {"Direct including types", including_types},
        ]
      end

      # Whether the top level namespace declares anything worth a page.
      def toplevel_content? : Bool
        !(class_methods.empty? && macros.empty? && constants.empty?)
      end
    end

    # :nodoc:
    # Root of the `crystal docs --format json` output.
    class Project
      include JSON::Serializable

      getter repository_name : String
      getter body : String
      getter program : TypeDoc
    end

    # :nodoc:
    module DocTool
      COMMAND = "crystal"

      # Compiler diagnostics go to standard error.
      def self.load(root : String) : Project
        output = IO::Memory.new
        status = Process.run(COMMAND, {"docs", "--format", "json"}, chdir: root, output: output, error: Process::Redirect::Inherit)
        raise Error.new("`#{COMMAND} docs` failed with exit code #{status.exit_code}") unless status.success?
        Project.from_json(output.rewind)
      rescue ex : File::Error
        raise Error.new("cannot run `#{COMMAND}`: #{ex.message}")
      end
    end

    # A Crystal shard: its root directory, name and version.
    class Shard
      # :nodoc:
      MANIFEST = "shard.yml"
      # :nodoc:
      REQUIRE = /\A\s*require\s+"(\.\.?\/[^"]+)"/
      # :nodoc:
      VERSION_LINE = /\Aversion:\s*["']?([^\s"']+)/
      # :nodoc:
      TARGET_LINE = /\A\s+main:\s*["']?([^\s"']+)/

      getter root : String
      getter name : String
      # The version in `shard.yml`, if any.
      getter version : String?

      # Source file → {order of the entry file that reaches it, require path}.
      @entries = {} of String => {Int32, String}

      # The nearest directory at or above *dir* with a `shard.yml`; `nil` if none.
      def self.root(dir : String) : String?
        current = File.expand_path(dir)
        loop do
          return current if File.file?(File.join(current, MANIFEST))
          parent = File.dirname(current)
          return nil if parent == current
          current = parent
        end
      end

      # The shard in the directory *root*, named *name*.
      def initialize(@root : String, @name : String)
        manifest = File.join(root, MANIFEST)
        lines = File.file?(manifest) ? File.read_lines(manifest) : [] of String
        @version = lines.compact_map(&.match(VERSION_LINE).try(&.[1])).first?
        targets = lines.compact_map(&.match(TARGET_LINE).try { |md| File.expand_path(md[1], root) })
        src = File.join(root, "src")
        main = File.join(src, "#{name}.cr")
        entries = [main].select { |path| File.file?(path) }
        entries.concat(Dir.glob(File.join(src, name, "*.cr")).sort)
        entries.concat(Dir.glob(File.join(src, "*.cr")).sort.reject { |path| path == main || targets.includes?(path) })
        entries.each_with_index do |entry, order|
          visit(entry, {order, Path[entry].relative_to(src).to_s.rchop(".cr")})
        end
      end

      # :nodoc:
      # From the first entry file that reaches one of the type's source files.
      def require_path(type : TypeDoc) : String?
        found = type.locations.compact_map { |location| location.filename.try { |file| @entries[File.expand_path(file, root)]? } }
        found.min_by?(&.[0]).try(&.[1])
      end

      # :nodoc:
      # Makes the shard's absolute path relative, so pages are the same on any machine.
      def relative(text : String) : String
        text.gsub("#{root}/", "").gsub(root, ".")
      end

      private def visit(file : String, entry : {Int32, String}) : Nil
        return if @entries.has_key?(file)
        @entries[file] = entry
        File.each_line(file) do |line|
          next unless md = line.match(REQUIRE)
          targets(File.expand_path(md[1], File.dirname(file))).each { |target| visit(target, entry) }
        end
      end

      # Files a relative require loads, by the compiler's lookup rules.
      private def targets(path : String) : Array(String)
        return Dir.glob(File.join(path.rchop("/**"), "**", "*.cr")).sort if path.ends_with?("/**")
        return Dir.glob(File.join(path.rchop("/*"), "*.cr")).sort if path.ends_with?("/*")
        candidates = path.ends_with?(".cr") ? [path] : ["#{path}.cr", File.join(path, "#{File.basename(path)}.cr")]
        candidates.select { |candidate| File.file?(candidate) }.first(1)
      end
    end

    # :nodoc:
    # The documented types in nesting order, the top level first when it
    # declares anything.
    class Types
      getter project : Project
      getter types = [] of TypeDoc

      def initialize(@project : Project)
        program = project.program
        @types << program if program.toplevel_content?
        collect(program)
      end

      private def collect(type : TypeDoc) : Nil
        type.types.each do |nested|
          @types << nested
          collect(nested)
        end
      end
    end
  end
end
