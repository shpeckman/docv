# src/docv/roff/unsafe.cr
module Docv::Roff
  class Engine
    # Requests that run commands or access files. They run only with
    # `Options#unsafe`; otherwise they are accepted and ignored. `\V` is
    # gated the same way (see `interpolate`).
    UNSAFE = Set{"sy", "pso", "pi", "open", "opena", "write", "writec", "writem", "close", "cf", "trf", "rd"}

    @streams = Hash(String, File).new
    @pipes = [] of String

    # Runs an `UNSAFE` request.
    private def unsafe_request(name : String, raw : String) : Nil
      case name
      when "sy"            then system(interpolate(raw, true))
      when "pso"           then pipe_source(interpolate(raw, true))
      when "pi"            then pipe_output(interpolate(raw, true))
      when "open", "opena" then open_stream(raw, append: name == "opena")
      when "write"         then write_stream(raw, newline: true)
      when "writec"        then write_stream(raw, newline: false)
      when "writem"        then write_macro(raw)
      when "close"         then args(raw).first?.try { |stream| @streams.delete(stream).try &.close }
      when "cf", "trf"     then copy_file(args(raw).first?)
      when "rd"            then read_input(raw)
      end
    end

    # Runs *command* with `/bin/sh -c`; *input* feeds its standard input,
    # *output* receives its standard output (both default to the null
    # device, so commands never touch the viewer's terminal).
    private def shell(command : String, input : IO? = nil, output : IO? = nil) : Process::Status?
      null_in = File.open(File::NULL)
      null_out = File.open(File::NULL, "w")
      begin
        Process.run("/bin/sh", ["-c", command], input: input || null_in, output: output || null_out, error: null_out)
      ensure
        null_in.close
        null_out.close
      end
    rescue ex : IO::Error | File::Error
      @doc.messages << "cannot run #{command}: #{ex.message}"
      nil
    end

    # `.sy`: runs a command; the raw wait status goes to register `systat`.
    private def system(command : String) : Nil
      return if command.strip.empty?
      status = shell(command)
      @registers.set("systat", status ? status.system_exit_status.to_i64 : -1_i64)
    end

    # `.pso`: runs a command and reads its output as input.
    private def pipe_source(command : String) : Nil
      return if command.strip.empty?
      output = IO::Memory.new
      shell(command, output: output) || return
      run_frame(Frame.new(Frame::Kind::File, split_lines(Source.decode(output.to_slice)), "pso"))
    end

    # `.pi`: the formatted page is piped to the command after parsing.
    private def pipe_output(command : String) : Nil
      command = command.strip
      @pipes << command unless command.empty?
    end

    private def run_pipes : Nil
      return if @pipes.empty?
      text = String.build do |io|
        Layout.new(@doc).lines(@columns).each { |line| io << line.text.rstrip << '\n' }
      end
      @pipes.each { |command| shell(command, input: IO::Memory.new(text)) }
    end

    # `.open stream file` / `.opena stream file`.
    private def open_stream(raw : String, append : Bool) : Nil
      list = args(raw)
      return if list.size < 2
      stream, path = list[0], list[1]
      @streams.delete(stream).try &.close
      @streams[stream] = File.open(path, append ? "a" : "w")
    rescue ex : File::Error
      @doc.messages << "cannot open #{list.try(&.[1]?)}: #{ex.message}"
    end

    # `.write stream text` / `.writec stream text`: text in copy mode, a
    # leading quote removed.
    private def write_stream(raw : String, newline : Bool) : Nil
      stream, text = split_name(raw)
      file = @streams[stream]? || return
      text = text[1..] if text.starts_with?('"')
      file << interpolate(text, true)
      file << '\n' if newline
      file.flush
    end

    # `.writem stream macro`: writes the macro body without interpretation.
    private def write_macro(raw : String) : Nil
      list = args(raw)
      file = list[0]?.try { |stream| @streams[stream]? } || return
      body = list[1]?.try { |name| macro_body(name) } || return
      body.each { |line| file << line << '\n' }
      file.flush
    end

    # `.cf file` / `.trf file`: the file's lines set unprocessed as unfilled
    # text; control characters other than tab are dropped.
    private def copy_file(name : String?) : Nil
      return unless name
      path = File.file?(name) ? name : @source.resolve(name)
      unless path
        @doc.messages << "cannot open #{name}"
        return
      end
      text = Source.decode(File.open(path, &.getb_to_end))
      @builder.break_line
      fill = @env.fill?
      @env.fill = false
      split_lines(text).each do |line|
        line = line.gsub(/[\x00-\x08\x0B-\x1F\x7F]/, "")
        if line.empty?
          @builder.blank(1, hard: true)
        else
          @builder.text(line, 0_u16)
          @builder.break_line
        end
      end
      @env.fill = fill
    rescue ex : IO::Error | File::Error
      @doc.messages << "cannot read #{name}: #{ex.message}"
    end

    # `.rd [prompt]`: prints the prompt (or a bell) on standard error and
    # reads input lines from `Options#stdin` up to an empty line.
    private def read_input(raw : String) : Nil
      input = @options.stdin || return
      prompt = args(raw).first?
      STDERR << (prompt ? "#{prompt}:" : "\a")
      STDERR.flush
      lines = [] of String
      while line = input.gets
        break if line.empty?
        lines << line
      end
      run_frame(Frame.new(Frame::Kind::File, lines, "rd")) unless lines.empty?
    end

    private def close_streams : Nil
      @streams.each_value(&.close)
      @streams.clear
    end
  end
end
