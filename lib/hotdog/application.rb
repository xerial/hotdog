#!/usr/bin/env ruby

require "logger"
require "optparse"
require "yaml"
require "hotdog/commands"
require "hotdog/formatters"

module Hotdog
  class Application
    def initialize()
      @optparse = OptionParser.new
      @options = {
        api_key: ENV["DATADOG_API_KEY"],
        application_key: ENV["DATADOG_APPLICATION_KEY"],
        application: self,
        confdir: find_confdir(File.expand_path(".")),
        debug: false,
        expiry: 180,
        fixed_string: false,
        force: false,
        format: "plain",
        headers: false,
        listing: false,
        logger: Logger.new(STDERR).tap { |logger|
          logger.level = Logger::INFO
        },
        max_time: 5,
        print0: false,
        print1: true,
        tags: [],
        verbose: false,
      }
      define_options
    end
    attr_reader :options

    def main(argv=[])
      config = File.join(options[:confdir], "config.yml")
      if File.file?(config)
        loaded = YAML.load(File.read(config))
        if Hash === loaded
          @options = @options.merge(Hash[loaded.map { |key, value| [Symbol === key ? key : key.to_s.to_sym, value] }])
        end
      end
      args = @optparse.parse(argv)

      unless options[:api_key]
        raise("DATADOG_API_KEY is not set")
      end

      unless options[:application_key]
        raise("DATADOG_APPLICATION_KEY is not set")
      end

      options[:formatter] = get_formatter(options[:format]).new

      if options[:debug] or options[:verbose]
        options[:logger].level = Logger::DEBUG
      else
        options[:logger].level = Logger::INFO
      end

      begin
        command = ( args.shift || "help" )
        get_command(command).new(@options.dup).tap do |cmd|
          cmd.run(args)
        end
      rescue Errno::EPIPE
        # nop
      end
    end

    private
    def define_options
      @optparse.on("--api-key API_KEY", "Datadog API key") do |api_key|
        options[:api_key] = api_key
      end
      @optparse.on("--application-key APP_KEY", "Datadog application key") do |app_key|
        options[:application_key] = app_key
      end
      @optparse.on("-0", "--null", "Use null character as separator") do |v|
        options[:print0] = v
      end
      @optparse.on("-1", "Use newline as separator") do |v|
        options[:print1] = v
      end
      @optparse.on("-d", "--[no-]debug", "Enable debug mode") do |v|
        options[:debug] = v
      end
      @optparse.on("--fixed-string", "Interpret pattern as fixed string") do |v|
        options[:fixed_string] = v
      end
      @optparse.on("-f", "--[no-]force", "Enable force mode") do |v|
        options[:force] = v
      end
      @optparse.on("-F FORMAT", "--format FORMAT", "Specify output format") do |format|
        options[:format] = format
      end
      @optparse.on("-h", "--[no-]headers", "Display headeres for each columns") do |v|
        options[:headers] = v
      end
      @optparse.on("-l", "--[no-]listing", "Use listing format") do |v|
        options[:listing] = v
      end
      @optparse.on("-a TAG", "-t TAG", "--tag TAG", "Use specified tag name/value") do |tag|
        options[:tags] += [tag]
      end
      @optparse.on("-V", "--[no-]verbose", "Enable verbose mode") do |v|
        options[:verbose] = v
      end
    end

    def const_name(name)
      name.to_s.split(/[^\w]+/).map { |s| s.capitalize }.join
    end

    def get_formatter(name)
      begin
        Hotdog::Formatters.const_get(const_name(name))
      rescue NameError
        if library = find_library("hotdog/formatters", name)
          load library
          Hotdog::Formatters.const_get(const_name(File.basename(library, ".rb")))
        else
          raise(NameError.new("unknown format: #{name}"))
        end
      end
    end

    def get_command(name)
      begin
        Hotdog::Commands.const_get(const_name(name))
      rescue NameError
        if library = find_library("hotdog/commands", name)
          load library
          Hotdog::Commands.const_get(const_name(File.basename(library, ".rb")))
        else
          raise(NameError.new("unknown command: #{name}"))
        end
      end
    end

    def find_library(dirname, name)
      load_path = $LOAD_PATH.map { |path| File.join(path, dirname) }.select { |path| File.directory?(path) }
      libraries = load_path.map { |path| Dir.glob(File.join(path, "*.rb")) }.reduce(:+).select { |file| File.file?(file) }
      rbname = "#{name}.rb"
      if library = libraries.find { |file| File.basename(file) == rbname }
        library
      else
        candidates = libraries.map { |file| [file, File.basename(file).slice(0, name.length)] }.select { |file, s| s == name }
        if candidates.length == 1
          candidates.first.first
        else
          nil
        end
      end
    end

    def find_confdir(path)
      if path == "/"
        # default
        if ENV.has_key?("HOTDOG_CONFDIR")
          ENV["HOTDOG_CONFDIR"]
        else
          File.join(ENV["HOME"], ".hotdog")
        end
      else
        confdir = File.join(path, ".hotdog")
        if File.directory?(confdir)
          confdir
        else
          find_confdir(File.dirname(path))
        end
      end
    end
  end
end

# vim:set ft=ruby :
