require 'bundler/setup'
require 'pegrb'

module LetGrammar

  # Environment class. Basically just chained hashmaps modeling the usual
  # lexical scope structure we all know and love.
  class Env
    def initialize(inner, outer); @inner, @outer = inner, outer; end
    def [](val); @inner[val] || @outer[val]; end
    def []=(key, val); @inner[key] = val; end
    def increment; Scope.new({}, self); end
  end

  # AST classes.
  class ConstExp < Struct.new(:value); end
  class DiffExp < Struct.new(:expressions); end
  class AddExp < Struct.new(:expressions); end
  class MultExp < Struct.new(:expressions); end
  class DivExp < Struct.new(:expressions); end
  class LessExp < Struct.new(:expressions); end
  class LessEqExp < Struct.new(:expressions); end
  class EqExp < Struct.new(:expressions); end
  class GreaterExp < Struct.new(:expresssions); end
  class GreaterEqExp < Struct.new(:expressions); end
  class ZeroCheck < Struct.new(:expressions); end
  class IfExp < Struct.new(:test, :true, :false); end
  class Identifier < Struct.new(:value); end
  class Binding < Struct.new(:variable, :value); end
  class LetExp < Struct.new(:binding, :body); end
  class ListExp < Struct.new(:list); end
  class CarExp < Struct.new(:list); end
  class CdrExp < Struct.new(:list); end
  class NullExp < Struct.new(:list); end
  class ConsExp < Struct.new(:head, :tail); end
  class Condition < Struct.new(:left, :right); end
  class CondExp < Struct.new(:conditions); end

  @grammar = Grammar.rules do

    operator_class_mapping = {'-' => DiffExp, '+' => AddExp, '*' => MultExp, '/' => DivExp,
     '<' => LessExp, '<=' => LessEqExp, '=' => EqExp, '>' => GreaterExp, '>=' => GreaterEqExp,
     'car' => CarExp, 'cdr' => CdrExp, 'null?' => NullExp, 'cons' => ConsExp
    }

    whitespace = one_of(/\s/).many.any.ignore

    sep = one_of(/\s/).many.ignore

    # any sequence of digits, e.g. 123
    number = (one_of(/\d/).many[:digits] > cut!) >> ->(s) {
      [ConstExp.new(s[:digits].map(&:text).join.to_i)]
    }

    # All order operators have a similar structure as well
    order_operator = ((m('<=') | m('>=') | one_of('<', '=', '>'))[:operator] > cut!) >> ->(s) {
      [operator_class_mapping[s[:operator].map(&:text).join]]
    }

    # All the operator expressions have a common structure so abstract it
    arithmetic_operator = (one_of('-', '+', '*', '/')[:operator] > cut!) >> ->(s) {
      [operator_class_mapping[s[:operator].first.text]]
    }

    # Combine the operators into one
    general_arithmetic_operator = order_operator | arithmetic_operator

    # {-, +, *, /, <, <=, =, >, >=}(expression {, expression}+)
    arithmetic_expression = (general_arithmetic_operator[:operator] > one_of('(') > whitespace >
     cut! > r(:expression)[:first] > (whitespace > one_of(',').ignore > whitespace > cut! >
     r(:expression)).many[:rest] > whitespace > one_of(')') > cut!) >> ->(s) {
      [s[:operator][0].new(s[:first] + s[:rest])]
    }

    # list expressions: list(), list(expression {, expression}*)
    empty_list = (m('list()') > cut!)>> ->(s) {
      [ListExp.new([])] 
    }

    non_empty_list = (m('list(') > whitespace > cut! > r(:expression)[:head] >
     (whitespace > one_of(',').ignore > whitespace > cut! > r(:expression)).many.any[:tail] >
     whitespace > one_of(')') > cut!) >> ->(s) {
      [ListExp.new(s[:head] + s[:tail])]
    }

    list_expression = empty_list | non_empty_list

    # unary list operators
    unary_list_operator = ((m('car') | m('cdr') | m('null?')) > cut!)[:list_operator] >> ->(s) {
      [operator_class_mapping[s[:list_operator].map(&:text).join]]
    }

    unary_list_operator_expression = (unary_list_operator[:op] > one_of('(') > whitespace > cut! >
     r(:expression)[:list_expression] > whitespace > one_of(')') > cut!) >> ->(s) {
      [s[:op][0].new(s[:list_expression][0])]
    }

    # binary list operators
    binary_list_operator = (m('cons') > cut!)[:list_operator] >> ->(s) {
      [operator_class_mapping[s[:list_operator].map(&:text).join]]
    }

    binary_list_operator_expression = (binary_list_operator[:op] > one_of('(') > whitespace >
     cut! > r(:expression)[:first] > whitespace > one_of(',') >
     whitespace > cut! > r(:expression)[:second] > whitespace > one_of(')') > cut!) >> ->(s) {
      [s[:op][0].new(s[:first][0], s[:second][0])]
    }

    # unary or binary list expressions
    list_operator_expression = unary_list_operator_expression | binary_list_operator_expression

    # cond expression
    cond_expression = (m('cond') > cut! > (sep > r(:expression) > sep > m('==>').ignore >
     cut! > sep > r(:expression)).many.any[:conditions] > whitespace >
     m('end') > cut!) >> ->(s) {
      [CondExp.new(s[:conditions].each_slice(2).map {|l, r| Condition.new(l, r)})]
    }

    # zero?(expression {, expression}+)
    zero_check = (m('zero?(') > whitespace > cut! > r(:expression)[:first] >
     (whitespace > one_of(',').ignore > whitespace > cut! > r(:expression)).many.any[:rest] >
     whitespace > one_of(')') > cut!) >> ->(s) {
       [ZeroCheck.new(s[:first] + s[:rest])]
    }

    # if expression then expression else expression
    if_expression = (m('if') > sep > cut! > whitespace > r(:expression)[:test] > sep >
     m('then') > sep > cut! > r(:expression)[:true] > sep >
     m('else') > sep > cut! > r(:expression)[:false] > cut!) >> ->(s) {
      [IfExp.new(s[:test][0], s[:true][0], s[:false][0])]
    }

    # non-space, non-paren, non-comma characters all become identifiers
    identifier = one_of(/[^\s\(\)\,]/).many[:chars] >> ->(s) {
      [Identifier.new(s[:chars].map(&:text).join)]
    }

    # variable = expression
    binding = (identifier[:variable] > sep > one_of('=') > sep > cut! >
     r(:expression)[:value]) >> ->(s) {
       [Binding.new(s[:variable][0], s[:value][0])]
    }

    # let identifier = expression in expression
    # TODO: extend to allow for multiple bindings
    let_expression = (m('let') > sep > cut! > binding[:binding] > sep > cut! >
     m('in') > sep > cut! > r(:expression)[:body] > cut!) >> ->(s) {
      [LetExpression.new(s[:binding][0], s[:body][0])]
    }

    # all the expressions together
    rule :expression, number | arithmetic_expression | zero_check |
     if_expression | let_expression | list_expression | list_operator_expression |
     cond_expression | identifier

    rule :start, r(:expression)

  end

  def self.parse(indexable); @grammar.parse(indexable); end

end
