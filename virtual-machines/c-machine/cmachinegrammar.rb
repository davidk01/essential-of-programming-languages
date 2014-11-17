require 'pegrb'
require_relative './ast'

# The grammar that describes the subset of C we are going to work with.
# I have taken some liberties with how arithmetic operations are defined
# because I don't want to worry about precedence. So all arithmetic operations
# are written prefix/function style, e.g. {+, -, *}(x, y, z, -(1, 2, 3)).
module CMachineGrammar

  @grammar = Grammar.rules do

    ws = one_of(/\s/).many.any.ignore

    lpar, rpar = one_of('(').ignore, one_of(')').ignore

    comment = (m(';;') > one_of(/[^\r\n]/).many.any > one_of(/[\r\n]/).many).ignore

    symbol = (one_of(/[^\(\)\;]/)[:first] > one_of(/[^\s\(\)]/).many.any[:rest]) >> ->(s) {
      [s[:first], s[:rest]].flatten.map(&:text).join.to_sym
    }

    double_quote_string = (one_of('"') > one_of(/[^"]/).many[:chars] > one_of('"')) >> ->(s) {
      s[:chars].map(&:text).join
    }

    single_quote_string = (one_of("'") > one_of(/[^']/).many[:chars] > one_of("'")) >> ->(s) {
      s[:chars].map(&:text).join
    }

    string = double_quote_string | single_quote_string

    integer = one_of(/\d/).many[:digits] >> ->(s) {
      s[:digits].map(&:text).join.to_i
    }

    boolean = (m('#t')[:true] | m('#f')[:false]) >> ->(s) {
      s[:true] ? true : false
    }

    float = (one_of(/\d/).many[:integral] > one_of('.') > one_of(/\d/).many[:fractional]) >> ->(s) {
      [s[:integral].map(&:text), '.', s[:fractional].map(&:text)].flatten.join.to_f
    }

    atomic = float | integer | boolean | string | symbol

    empty_list = lpar > ws > rpar

    non_empty_list = (lpar > (ws > (atomic | r(:list))).many[:elements] > ws > rpar) >> ->(s) {
      s[:elements].map(&:first)
    }

    rule :list, non_empty_list | empty_list

    program = (ws > (comment | r(:list)) > ws).many

    rule :start, program[:p] >> ->(s) { s[:p].reject(&:empty?).map(&:first) }
  end

  def self.type_resolution(type_specification)
    case type_specification
    when :int
      IntType
    when :bool
      BoolType
    when :float
      FloatType
    when Array
      compound_type_wrapper = type_specification[0]
      wrapped_type = type_specification[1]
      wrapped_type_length = type_specification[2]
      case compound_type_wrapper
      when :ptr
        PtrType.new(type_resolution(wrapped_type))
      when :array
        ArrayType.new(type_resolution(wrapped_type), wrapped_type_length)
      else
        raise StandardError, "Unknown compound type specification."
      end
    else # non-basic type and not an array so must be a derived/declared type
      DerivedType.new(type_specification)
    end
  end

  def self.to_ast(list)
    case list.first
    when :struct # struct definition
      struct_name = list[1]
      struct_members = list[2..-1].each_slice(2).map do |member_name, member_type|
        StructMember.new(type_resolution(member_type), member_name)
      end
      StructDeclaration.new(struct_name, struct_members)
    when :def # function definition
    when :do # sequence of statements
    when :declare # variable declaration
      # TODO: continue here
      require 'pry'; binding.pry
    when :set # variable mutation
    when :if # if expression
    when :while # while loop
    when :for # for loop
    when :case # case statement
    else
      raise StandardError, "Unknown node type."
    end
  end

  def self.parse(iterable)
    s_expressions = @grammar.parse(iterable)
    s_expressions.map {|l| to_ast(l)}
  end

end
