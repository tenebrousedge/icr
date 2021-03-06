require "../spec_helper"
require "file_utils"

describe "icr command" do
  context "passing flag arguments" do
    it "returns nothing for invalid option -c" do
      icr("", "-c").should eq ""
    end

    it "returns the version for option -v" do
      icr("", "-v").should contain(Icr::VERSION)
    end

    it "returns the help menu for option -h" do
      icr("", "-h").should contain("Usage: icr [options]")
    end

    describe "--prompt-mode option" do
      it "allows to change to simple prompt mode" do
        icr("1", "--prompt-mode", "simple", "--no-color").should match /> 1/
      end

      it "allows to change to none prompt mode" do
        icr("1", "--prompt-mode", "none", "--no-color").should match /1/
      end

      it "allows to change to default prompt mode" do
        icr("1", "--prompt-mode", "default", "--no-color").should match /> 1/
      end

      it "raises argument error if prompt mode is wrong" do
        expect_raises(ArgumentError) do
          Icr::Console.new(prompt_mode: "no-such-mode").start
        end
      end
    end

    describe "custom directory" do
      it "allows to run within a directory with spaces" do
        within_temp_folder do
          input = <<-CODE
            a = "baz"
            __
          CODE
          output = icr(input)
          output.should match /baz/
          output.should_not match /IndexError/
        end
      end
    end

    describe "using the -r option" do
      it "requires the colorize lib" do
        input = <<-CODE
          "hello".responds_to?(:colorize)
        CODE
        icr(input, "-r colorize").should match /true/
      end

      it "requires multiple libs colorize and http" do
        input = <<-CODE
          typeof(HTTP).name.responds_to?(:colorize)
        CODE
        icr(input, "-r http", "-r colorize").should match /true/
      end

      it "fails when colorize is not required first" do
        input = <<-CODE
          "hello".responds_to?(:colorize)
        CODE
        icr(input).should match /false/
      end
    end
  end

  it "returns the passed value" do
    icr("13").should match /\=> 13/
    icr("\"Saluton\"").should match /\=> "Saluton"/
  end

  it "does simple arithmetic" do
    icr("2 + 2").should match /\=> 4/
  end

  it "does boolean negation" do
    icr("false.!").should match /true/
  end

  it "allows to define variables" do
    input = <<-CRYSTAL
      a = 10
      b = 20
      c = a + b
    CRYSTAL
    icr(input).should match /\=> 10.*\=> 20.*\=> 30/m
  end

  it "does not repeat previous output" do
    input = <<-CRYSTAL
      puts "Saluton"
      puts "mondo!"
    CRYSTAL
    icr(input).should match /Saluton.*=> nil.*mondo!.* => nil/m
  end

  it "allows to require files" do
    input = <<-CRYSTAL
      require "io/**"
      IO::Memory.new("abc").to_s
    CRYSTAL
    icr(input).should match /\=> ok.*\=> "abc"/m
  end

  it "allows to define multiple line methods method" do
    input = <<-CRYSTAL
      def sqr(x)
        x * x
      end
      sqr(13)
    CRYSTAL
    icr(input).should match /\=> 169/
  end

  it "allows to define modules" do
    input = <<-CRYSTAL
      module MathModule
        def self.sqr(x)
          x * x
        end
      end
      MathModule.sqr(13)
    CRYSTAL
    icr(input).should match /\=> 169/
  end

  it "allows to define classes" do
    input = <<-CRYSTAL
      class MathClass
        def sqr(x)
          x * x
        end
      end
      MathClass.new.sqr(13)
    CRYSTAL
    icr(input).should match /\=> 169/
  end

  it "allows to define enums" do
    input = <<-CRYSTAL
      enum Color
        Red
        Green
        Blue
      end
      Color::Blue.value
    CRYSTAL
    icr(input).should match /\=> 2/
  end

  it "allows to define records" do
    input = <<-CRYSTAL
      record Person, first_name : String, last_name : String do
        def full_name
          first_name + " " + last_name
        end
      end
      Person.new("Mike", "Nog").full_name
    CRYSTAL
    icr(input).should match /Mike Nog/
  end

  it "allows to define struct" do
    input = <<-CRYSTAL
      struct N
        property name : String
        @name : String
        def initialize
          @name = "Default"
        end
        def name : String
        end
        def name=(@name : String)
        end
      end
      N.new.name = "Struct"
    CRYSTAL
    icr(input).should match /Struct/
  end

  it "allows to define multi line hash" do
    input = <<-CRYSTAL
      module Screen
        TILES = {
          0 => {:white, nil},
          2 => {:black, :white}
        }
      end
      Screen::TILES[2]
    CRYSTAL
    icr(input).should match /{:black, :white}/
  end

  describe "errors" do
    it "prints syntax error without crashing" do
      input = <<-CRYSTAL
        >>
        13
      CRYSTAL
      icr(input).should match /unexpected token: >>.*=> 13/m
    end

    it "prints compilation error without crashing" do
      input = <<-CRYSTAL
        var
        13
      CRYSTAL
      output = icr(input)
      output.should match /undefined local variable or method 'var'/
      output.should match /13/
    end

    it "prints runtime error without crashing" do
      input = "\"5a\".to_i"
      output = icr(input)
      output.should match /invalid Int32: 5a \(ArgumentError\)/i
    end
  end

  describe "quiting" do
    it "allows to quit with 'exit' command" do
      input = <<-CRYSTAL
        exit
        1313
      CRYSTAL
      icr(input).should_not match /1313/
    end

    it "allows to quit with 'quit' command" do
      input = <<-CRYSTAL
        quit
        1313
      CRYSTAL
      icr(input).should_not match /1313/
    end

    it "do not exit if 'exit' or 'quit' is part of other code" do
      input = <<-CRYSTAL
        puts "I do not want to exit"
        puts "nor quit"
      CRYSTAL
      icr(input).should match /I do not want to exit/
      icr(input).should match /nor quit/
    end
  end

  describe "assignment with operator" do
    it "allows to execute *= operation" do
      input = <<-CRYSTAL
        a = 123
        a *= 2
      CRYSTAL
      icr(input).should match /246/
    end
  end

  describe "using an alias" do
    it "aliases Mod to M" do
      input = <<-CRYSTAL
      module Mod
        def self.exe
          1 + 1
        end
      end
      alias M = Mod
      M.exe
      CRYSTAL
      icr(input).should match /2/
    end
  end

  it "allows redefining a variable in a block" do
    input = <<-CRYSTAL
    i = 0
    10.times do |a|
      i = i + a
    end
    i
    CRYSTAL
    icr(input).should match /45/
  end

  it "fails for unterminated char literal" do
    input = <<-CRYSTAL
    puts 'aa'
    CRYSTAL
    icr(input).should match /\schar\s/
  end

  describe "using constants" do
    it "allows for constant assignment" do
      input = <<-CRYSTAL
      A = 0
      B=1
      HTTP_STATUS    =    404
      Constant = "cheese"
      ISO8859_1 = :latin
      A =~ /test/
      Abc_B = "123"
      Abc_B =~ /^[A-Z]+([a-z_0-9_\_]+)?\s*=[^=~]/
      CRYSTAL
      icr(input).should_not match /dynamic\sconstant/
    end

    it "still allows for checking constant equality" do
      input = <<-CRYSTAL
      A = 0
      B = 1
      A == B
      CRYSTAL
      icr(input).should match /false/
    end

    it "allows for regex checking with constant" do
      input = <<-CRYSTAL
      Abc_B = "123"
      Abc_B =~ /^\d+/
      CRYSTAL
      icr(input).should match /0/
    end

    it "does not catch constant equality with constants with lower case letters" do
      input = <<-CRYSTAL
      Aa = 0
      Bb = 1
      Aa == Bb
      CRYSTAL
      icr(input).should match /false/
    end

    it "doesnt catch object comparison by .new" do
      icr("Reference.new == Reference.new").should match /false/
      icr("Reference.new != Reference.new").should match /true/
    end

    it "still throws dynamic constant assignment errors when needed" do
      input = <<-CRYSTAL
      def test
        A = 1
      CRYSTAL
      icr(input).should match /dynamic\sconstant\sassignment/
    end
  end

  it "allows for macros" do
    input = <<-CRYSTAL
    macro a_macro
      42
    end
    a_macro
    CRYSTAL
    icr(input).should match /42/
  end

  context "__" do
    it "returns last value" do
      icr("a = 42\n__").should match /42/
    end

    it "returns nil if there is no last value" do
      icr("__").should match /nil/
    end

    context "in expressions" do
      it "works with unary operators" do
        icr("true\n!__").should match /false/
      end

      it "works with binary operators" do
        icr("42\n__ + 1").should match /43/
        icr("42\n1 + __").should match /43/
      end

      it "allows method calls" do
        input = <<-CRYSTAL
          "aabbcc"
          __.count('a')
        CRYSTAL
        icr(input).should match /2/
      end

      it "works in methods/blocks" do
        input = <<-CRYSTAL
          38
          def add(v)
            __ + v
          end

          add(3)

          -> { __ + 1 }.call
        CRYSTAL

        icr(input).should match /42/
      end
    end

    it "is not interpreted as the last value if is a part of var name or literal" do
      icr("__v = 0").should match /0/
      icr("v__ = 0").should match /0/
      icr("v__1 = 0").should match /0/
      icr("filename = \"spec__helper.cr\"").should match /spec__helper.cr/
      icr("require \"random/secure\"").should match /ok/
    end

    it "highlights input code" do
      icr("1 + 2").should contain("\e[0;34m1\e[0;m \e[0;37m+\e[0;m \e[0;34m2\e[0;m")
    end
  end

  describe "configuration directory" do
    it "creates update_check.yml" do
      path = Path[Dir.tempdir].join("xdg_spec").to_s
      icr("", {"XDG_CONFIG_HOME" => path})
      File.exists?(Path[path].join("icr/update_check.yml").to_s).should be_true
      FileUtils.rm_r path if Dir.exists?(path)
    end

    it "expands tilde to $HOME" do
      path = "~/.tmp/xdg_spec"
      abs_path = path.gsub("~", Path.home.to_s)
      icr("", {"XDG_CONFIG_HOME" => path})
      Dir.exists?(abs_path).should be_true
      FileUtils.rm_r abs_path if Dir.exists?(abs_path)
    end
  end
end
