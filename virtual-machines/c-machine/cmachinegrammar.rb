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
      StringConst.new(s[:chars].map(&:text).join)
    }

    single_quote_string = (one_of("'") > one_of(/[^']/).many[:chars] > one_of("'")) >> ->(s) {
      StringConst.new(s[:chars].map(&:text).join)
    }

    string = double_quote_string | single_quote_string

    integer = one_of(/\d/).many[:digits] >> ->(s) {
      ConstExp.new(s[:digits].map(&:text).join.to_i)
    }

    boolean = (m('#t')[:true] | m('#f')[:false]) >> ->(s) {
      ConstExp.new(s[:true] ? true : false)
    }

    float = (one_of(/\d/).many[:integral] > one_of('.') > one_of(/\d/).many[:fractional]) >> ->(s) {
      ConstExp.new([s[:integral].map(&:text), '.', s[:fractional].map(&:text)].flatten.join.to_f)
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

  ##
  # We need to recursively figure out what the type of the variable is because compound type
  # constructors like ptr and array can be nested arbitrarily.

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

  ##
  # When we declare a variable we can supply a default value and the default value can be
  # an arbitrary expression which means we can't just plop down the node into the variable
  # value field and need to do some extra traversals over the s-expression to get it in the
  # form we want.

  def self.value_resolution(variable_value)
    case variable_value
    when Array
      to_ast(variable_value)
    else
      variable_value
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
      function_name = list[1]
      function_arguments = list[2].each_slice(2).map do |argument_name, argument_type|
        ArgumentDefinition.new(type_resolution(argument_type), argument_name)
      end
      return_type = list[3]
      function_body = list[4]
      FunctionDefinition.new(type_resolution(return_type), function_name,
       function_arguments, to_ast(function_body))
    when :do # sequence of statements
      Statements.new(list[1..-1].map {|e| to_ast(e)})
    when :declare # variable declaration
      variable_name = list[1]
      variable_type = type_resolution(list[2])
      variable_value = value_resolution(list[3])
      VariableDeclaration.new(variable_type, variable_name, variable_value)
    when :set # variable mutation
    when :if # if expression
    when :while # while loop
    when :for # for loop
    when :case # case statement
    when :return # return statement
    else
      raise StandardError, "Unknown node type."
    end
  end

  def self.parse(iterable)
    s_expressions = @grammar.parse(iterable)
    s_expressions.map {|l| to_ast(l)}
  end

end
