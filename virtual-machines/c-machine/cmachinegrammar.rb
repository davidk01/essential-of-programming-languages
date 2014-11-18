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
  # In certain places we need to make sure that things are symbols instead of other general
  # structures so this is a convenient way to do it. Makes me wish I had some static types here.

  class ::Symbol
    def symbol!
      self
    end
  end

  ##
  # We need to recursively figure out what the type of the variable is because compound type
  # constructors like ptr and array can be nested arbitrarily.

  def self.type_resolution(type_specification)
    case type_specification
    when :void
      VoidType
    when :int
      IntType
    when :bool
      BoolType
    when :float
      FloatType
    when Array
      compound_type_wrapper = type_specification[0].symbol!
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
      DerivedType.new(type_specification.symbol!)
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

  @operator_map = {
   :'=' => EqExp, :< => LessExp
  }

  ##
  # Do some sanity checking and post-processing required to convert s-expression based syntax
  # to an actual tree of ast classes.

  def self.to_ast(s_expr)
    case s_expr
    when Symbol
      return s_expr
    when ConstExp
      return s_expr
    when StringConst
      return s_expr
    when Array
    else
      raise StandardError, "This should never happen: #{s_expr}."
    end

    # If we got to this point then we must be dealing with an array

    case (h = s_expr.first)
    when :struct # struct definition
      struct_name = s_expr[1].symbol!
      struct_members = s_expr[2..-1].each_slice(2).map do |member_name, member_type|
        StructMember.new(type_resolution(member_type.symbol!), member_name.symbol!)
      end
      StructDeclaration.new(struct_name, struct_members)
    when :def # function definition
      function_name = s_expr[1].symbol!
      function_arguments = s_expr[2].each_slice(2).map do |argument_name, argument_type|
        ArgumentDefinition.new(type_resolution(argument_type), argument_name.symbol!)
      end
      return_type = type_resolution(s_expr[3])
      function_body = to_ast(s_expr[4])
      FunctionDefinition.new(return_type, function_name, function_arguments, function_body)
    when :do # sequence of statements
      Statements.new(s_expr[1..-1].map {|e| to_ast(e)})
    when :declare # variable declaration
      variable_name = s_expr[1].symbol!
      variable_type = type_resolution(s_expr[2])
      variable_value = value_resolution(s_expr[3])
      VariableDeclaration.new(variable_type, variable_name, variable_value)
    when :set # variable mutation
      variable_name = s_expr[1].symbol!
      variable_value = value_resolution(s_expr[2])
      Assignment.new(variable_name, variable_value)
    when :if # if expression. else branch is optional so we need to fill it in with empty statement
      test = to_ast(s_expr[1])
      true_branch = to_ast(s_expr[2])
      false_branch = (false_code = s_expr[3]).nil? ? Statements.new([]) : to_ast(false_code)
      If.new(test, true_branch, false_branch)
    when :while # while loop
    when :for # for loop
    when :case # case statement
    when :return # return statement
      return_expression = to_ast(s_expr[1])
      ReturnStatement.new(return_expression)
    when :'=', :<, :>, :<=, :>= # tests
      comparison_elements = s_expr[1..-1].map {|e| to_ast(e)}
      @operator_map[h].new(comparison_elements)
    else
      raise StandardError, "Unknown node type: #{s_expr}."
    end
  end

  def self.parse(iterable)
    s_expressions = @grammar.parse(iterable)
    s_expressions.map {|l| to_ast(l)}
  end

end
