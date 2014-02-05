require 'pegrb'

module LetGrammar

  # Environment class. Basically just chained hash maps modeling the usual
  # lexical scope structure we all know and love. Not optimized at all for any
  # kind of special access patterns.
  class Env
    def initialize(inner, outer); @inner, @outer = inner, outer; end
    def [](val); @inner[val] || @outer[val]; end
    def []=(key, val); @inner[key] = val; end
    def increment; Env.new({}, self); end
  end

  # AST classes.
  class ConstExp < Struct.new(:value)
    def eval(_); self.value; end
  end

  # Common evaluation strategy so we abstract it.
  class ArithmeticOp < Struct.new(:expressions)
    # We again use lazy enumerators to not evaluate all the expressions. There might be
    # a type error along the way so evaluating all the expressions and then hitting a type
    # error is wasted effort. Evaluate only when necessary and die as soon as we have a type error.
    def eval(env, op)
      accumulator = self.expressions[0].eval(env)
      self.expressions.lazy.drop(1).each {|x| accumulator = accumulator.send(op, x.eval(env))}
      accumulator
    end
  end

  # Just need the right symbol to evaluate.
  class DiffExp < ArithmeticOp
    def eval(env); super(env, :-); end
  end
  class AddExp < ArithmeticOp
    def eval(env); super(env, :+); end
  end
  class MultExp < ArithmeticOp
    def eval(env); super(env, :*); end
  end
  class DivExp < ArithmeticOp
    def eval(env); super(env, :/); end
  end
  class ModExp < ArithmeticOp
    def eval(env); super(env, :%); end
  end

  # Similar kind of abstraction as for +ArithmeticOp+.
  class OrderOp < Struct.new(:expressions)
    # We use lazy enumerators for short circuiting the operations because we don't
    # need to evaluate all the expressions. We can bail as soon as we see a false result.
    # We are assuming a finite collection of expressions and in the absence of macros this
    # assumption holds.
    def eval(env, op)
      lazy_exprs = self.expressions.lazy
      pairs = lazy_exprs.zip(lazy_exprs.drop(1)).take(self.expression.length - 1)
      pairs.each {|x, y| return false unless x.eval(env).send(op, y.eval(env))}
      true
    end
  end

  # Just need the right symbol to evaluate.
  class LessExp < OrderOp
    def eval(env); super(env, :<); end
  end
  class LessEqExp < OrderOp
    def eval(env); super(env, :<=); end
  end
  class EqExp < OrderOp
    def eval(env); super(env, :==); end
  end
  class GreaterExp < OrderOp
    def eval(env); super(env, :>); end
  end
  class GreaterEqExp < OrderOp
    def eval(env); super(env, :>=); end
  end

  class ZeroCheck < Struct.new(:expressions)
    def eval(env); self.expressions.all? {|x| x.eval(env) == 0}; end
  end

  class IfExp < Struct.new(:test, :true_branch, :false_branch)
    def eval(env)
      self.test.eval(env) ? self.true_branch.eval(env) : self.false_branch.eval(env)
    end
  end

  class Identifier < Struct.new(:value)
    def eval(env); env[self.value]; end
  end

  class Assignment < Struct.new(:variable, :value)
    # This is a little tricky but I'm going to go with an eager evaluation strategy.
    # Might come back and re-think this in terms of lazy evaluation.
    def eval(env); env[self.variable.value] = self.value.eval(env); end
  end

  class LetExp < Struct.new(:assignments, :body)
    def eval(env)
      new_env = env.increment
      assignments.each {|assignment| assignment.eval(new_env)}
      self.body.eval(new_env)
    end
  end

  class ListExp < Struct.new(:list)
    def eval(env); self.list.map {|x| x.eval(env)}; end
  end

  class CarExp < Struct.new(:list)
    def eval(env); self.list.eval(env).first; end
  end

  class CdrExp < Struct.new(:list)
    def eval(env); self.list.eval(env)[1..-1]; end
  end

  class NullExp < Struct.new(:list)
    def eval(env); self.list.eval(env).empty?; end
  end

  class ConsExp < Struct.new(:head, :tail)
    def eval(env); [self.head.eval(env)] + self.tail.eval(env); end
  end

  class Condition < Struct.new(:left, :right)
    def eval(env); self.left.eval(env) ? self.right.eval(env) : false; end
  end

  class CondExp < Struct.new(:conditions)
    def eval(env); self.conditions.each {|x| if (val = x.eval(env)) then return val end}; end
  end

  class Procedure < Struct.new(:arguments, :body)
  end

  class ProcedureCall < Struct.new(:operator, :operands)
  end

  @grammar = Grammar.rules do

    operator_class_mapping = {'-' => DiffExp, '+' => AddExp, '*' => MultExp, '/' => DivExp, '%' => ModExp,
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
    order_op = ((m('<=') | m('>=') | one_of('<', '=', '>'))[:operator] > cut!) >> ->(s) {
      [operator_class_mapping[s[:operator].map(&:text).join]]
    }

    # All the operator expressions have a common structure so abstract it
    arithmetic_op = (one_of('-', '+', '*', '/')[:operator] > cut!) >> ->(s) {
      [operator_class_mapping[s[:operator].first.text]]
    }

    # Combine the operators into one
    general_arithmetic_op = order_op | arithmetic_op

    # {-, +, *, /, <, <=, =, >, >=}(expression {, expression}+)
    arithmetic_expression = (general_arithmetic_op[:operator] > one_of('(') > whitespace >
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
    unary_list_op = ((m('car') | m('cdr') | m('null?')) > cut!)[:list_operator] >> ->(s) {
      [operator_class_mapping[s[:list_operator].map(&:text).join]]
    }

    unary_list_op_expression = (unary_list_op[:op] > one_of('(') > whitespace > cut! >
     r(:expression)[:list_expression] > whitespace > one_of(')') > cut!) >> ->(s) {
      [s[:op][0].new(s[:list_expression][0])]
    }

    # binary list operators
    binary_list_op = (m('cons') > cut!)[:list_operator] >> ->(s) {
      [operator_class_mapping[s[:list_operator].map(&:text).join]]
    }

    binary_list_op_expression = (binary_list_op[:op] > one_of('(') > whitespace >
     cut! > r(:expression)[:first] > whitespace > one_of(',') >
     whitespace > cut! > r(:expression)[:second] > whitespace > one_of(')') > cut!) >> ->(s) {
      [s[:op][0].new(s[:first][0], s[:second][0])]
    }

    # unary or binary list expressions
    list_op_expression = unary_list_op_expression | binary_list_op_expression

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
    identifier = one_of(/[^\s\(\),]/).many[:chars] >> ->(s) {
      [Identifier.new(s[:chars].map(&:text).join)]
    }

    # variable = expression
    assignment = (identifier[:variable] > sep > one_of('=') > sep > cut! >
     r(:expression)[:value]) >> ->(s) {
       [Assignment.new(s[:variable][0], s[:value][0])]
    }

    # let identifier = expression {, identifier = expression }* in expression
    let_expression = (m('let') > sep > cut! > assignment[:first] >
     (whitespace > one_of(',').ignore > cut! > whitespace > assignment).many.any[:rest] >
     sep > cut! > m('in') > sep > cut! > r(:expression)[:body] > cut!) >> ->(s) {
      [LetExp.new(s[:first] + s[:rest], s[:body][0])]
    }

    # procedures, proc (var1 {, var}*) expression
    proc_expression = (m('proc') > cut! > whitespace > one_of('(') > identifier[:first] > cut! >
     (whitespace > one_of(',') > whitespace > identifier).many.any[:rest] > one_of(')') > cut! > sep >
     r(:expression)[:body]) >> ->(s) {
      [Procedure.new(s[:first] + s[:rest], s[:body][0])]
    }

    # procedure call, lisp style, (expression expression)
    proc_call_expression = (one_of('(') > cut! > whitespace > r(:expression)[:operator] >
     (sep > r(:expression)).many[:operands] > whitespace > one_of(')') > cut!) >> ->(s) {
      [ProcedureCall.new(s[:operator][0], s[:operands])]
    }

    # all the expressions together
    rule :expression, number | arithmetic_expression | zero_check |
     if_expression | let_expression | list_expression | list_op_expression |
     cond_expression | proc_expression | proc_call_expression | identifier

    rule :start, r(:expression)

  end

  def self.parse(indexable); @grammar.parse(indexable); end

end
