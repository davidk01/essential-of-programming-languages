require 'pegrb'
require 'pp'

module LetRefsGrammar

  # For references we need a store so we are going to model it with an array.
  class Store
    def initialize; @store = []; end
    def [](key); @store[key]; end
    def []=(key, value); @store[key] = value; end
    def length; @store.length; end
  end

  # Environment class. Basically just chained hash maps modeling the usual
  # lexical scope structure we all know and love.
  class Env
    def initialize(inner, outer); @inner, @outer = inner, outer; end
    def [](val); @inner[val] || @outer[val]; end
    def []=(key, val); @inner[key] = val; end
    def increment; Env.new({}, self); end
  end

  # AST classes.
  class ConstExp < Struct.new(:value)
    def eval(_, _); self.value; end
  end

  class SymbolEval < Struct.new(:expressions)
    # Factor out the boilerplate for defining the delegation to eval.
    def self.define_symbol_eval(method_symbol)
      define_method(:eval) do |env, store|
        super(env, store, method_symbol)
      end
    end
  end

  # Common evaluation for arithmetic operations so we abstract it.
  class ArithmeticOp < SymbolEval
    # We use lazy enumerators to not evaluate all the expressions. There might be
    # a type error along the way so evaluating all the expressions and then hitting a type
    # error is wasted effort. Evaluate only when necessary and die as soon as we have a type error.
    def eval(env, store, op)
      accumulator = self.expressions[0].eval(env, store)
      self.expressions.lazy.drop(1).each {|x| accumulator = accumulator.send(op, x.eval(env, store))}
      accumulator
    end
  end

  # Delegate to +ArithmeticOp.eval+ with the proper operator symbol.
  class DiffExp < ArithmeticOp; define_symbol_eval(:-); end
  class AddExp < ArithmeticOp; define_symbol_eval(:+); end
  class MultExp < ArithmeticOp; define_symbol_eval(:*); end
  class DivExp < ArithmeticOp; define_symbol_eval(:/); end
  class ModExp < ArithmeticOp; define_symbol_eval(:%); end

  # Similar kind of abstraction as for +ArithmeticOp+.
  class OrderOp < SymbolEval
    # We use lazy enumerators for short circuiting the operations because we don't
    # need to evaluate all the expressions. We can bail as soon as we see a false result.
    def eval(env, store, op)
      lazy_exprs = self.expressions.lazy
      pairs = lazy_exprs.zip(lazy_exprs.drop(1)).take(self.expressions.length - 1)
      pairs.each {|x, y| return false unless x.eval(env, store).send(op, y.eval(env, store))}
      true
    end
  end

  # Delegate to +OrderOp.eval+ with the right operator symbol.
  class LessExp < OrderOp; define_symbol_eval(:<); end
  class LessEqExp < OrderOp; define_symbol_eval(:<=); end
  class EqExp < OrderOp; define_symbol_eval(:==); end
  class GreaterExp < OrderOp; define_symbol_eval(:>); end
  class GreaterEqExp < OrderOp; define_symbol_eval(:>=); end

  class ZeroCheck < Struct.new(:expressions)
    def eval(env, store); self.expressions.all? {|x| x.eval(env, store) == 0}; end
  end

  class IfExp < Struct.new(:test, :true_branch, :false_branch)
    def eval(env, store)
      self.test.eval(env, store) ? self.true_branch.eval(env, store) : self.false_branch.eval(env, store)
    end
  end

  class Identifier < Struct.new(:value)
    def eval(env, _); env[self.value]; end
  end

  class Assignment < Struct.new(:variable, :value)
    # This is a little tricky but I'm going to go with an eager evaluation strategy.
    # Might come back and re-think this in terms of lazy evaluation.
    def eval(env, store); env[self.variable.value] = self.value.eval(env, store); end
  end

  class LetExp < Struct.new(:assignments, :body)
    def eval(env, store)
      new_env = env.increment
      assignments.each {|assignment| assignment.eval(new_env, store)}
      self.body.eval(new_env, store)
    end
  end

  class ListExp < Struct.new(:list)
    def eval(env, store); self.list.map {|x| x.eval(env, store)}; end
  end

  class CarExp < Struct.new(:list)
    def eval(env, store); self.list.eval(env, store).first; end
  end

  class CdrExp < Struct.new(:list)
    def eval(env, store); self.list.eval(env, store)[1..-1]; end
  end

  class NullExp < Struct.new(:list)
    def eval(env, store); self.list.eval(env, store).empty?; end
  end

  class ConsExp < Struct.new(:head, :tail)
    def eval(env, store); [self.head.eval(env, store)] + self.tail.eval(env, store); end
  end

  class Condition < Struct.new(:left, :right)
    def eval(env, store); self.left.eval(env, store) ? self.right.eval(env, store) : false; end
  end

  class CondExp < Struct.new(:conditions)
    def eval(env, store); self.conditions.each {|x| if (val = x.eval(env, store)) then return val end}; end
  end

  class Procedure < Struct.new(:arguments, :body)
    def eval(env, store)
      lambda do |*args|
        procedure_env = env.increment
        self.arguments.zip(args).each {|arg, value| procedure_env[arg.value] = value}
        self.body.eval(procedure_env, store)
      end
    end
  end

  class ProcedureCall < Struct.new(:operator, :operands)
    def eval(env, store)
      self.operator.eval(env, store).call(*self.operands.map {|x| x.eval(env, store)})
    end
  end

  class NewRef < Struct.new(:expression)
    def eval(env, store)
      evaluated_expression = self.expression.eval(env, store)
      position = store.length
      store[position] = evaluated_expression
      position
    end
  end

  class DeRef < Struct.new(:location)
    def eval(env, store)
      evaluated_location = self.location.eval(env, store)
      if evaluated_location > store.length || evaluated_location < 0
        raise StandardError, "Reference location is out of bounds: #{evaluated_location}."
      end
      store[evaluated_location]
    end
  end

  class SetRef < Struct.new(:location, :value)
    def eval(env, store)
      evaluated_value = self.value.eval(env, store)
      evaluated_location = self.location.eval(env, store)
      if evaluated_location > store.length || evaluated_location < 0
        raise StandardError, "Reference location is out of bounds: #{evaluated_location}."
      end
      store[evaluated_location] = evaluated_value
    end
  end

  class BeginExpression < Struct.new(:expressions)
    def eval(env, store)
      result = nil
      self.expressions.each {|x| result = x.eval(env, store)}
      result
    end
  end

  @grammar = Grammar.rules do

    operator_class_mapping = {'-' => DiffExp, '+' => AddExp, '*' => MultExp, '/' => DivExp, '%' => ModExp,
     '<' => LessExp, '<=' => LessEqExp, '=' => EqExp, '>' => GreaterExp, '>=' => GreaterEqExp,
     'car' => CarExp, 'cdr' => CdrExp, 'null?' => NullExp, 'cons' => ConsExp
    }

    ws, sep = one_of(/\s/).many.any.ignore, one_of(/\s/).many.ignore

    # any sequence of digits, e.g. 123
    number = (one_of('-').any[:sign] > one_of(/\d/).many[:digits] > cut!) >> ->(s) {
      [ConstExp.new(s[:digits].map(&:text).join.to_i * (s[:sign][0] ? -1 : 1))]
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
    arithmetic_expression = (general_arithmetic_op[:operator] > one_of('(') > ws >
     cut! > r(:expression)[:first] > (ws > one_of(',').ignore > ws > cut! >
     r(:expression)).many[:rest] > ws > one_of(')') > cut!) >> ->(s) {
      [s[:operator][0].new(s[:first] + s[:rest])]
    }

    # list expressions: list(), list(expression {, expression}*)
    empty_list = (m('list()') > cut!)>> ->(s) {
      [ListExp.new([])]
    }

    non_empty_list = (m('list(') > ws > cut! > r(:expression)[:head] >
     (ws > one_of(',').ignore > ws > cut! > r(:expression)).many.any[:tail] >
     ws > one_of(')') > cut!) >> ->(s) {
      [ListExp.new(s[:head] + s[:tail])]
    }

    list_expression = empty_list | non_empty_list

    # unary list operators
    unary_list_op = ((m('car') | m('cdr') | m('null?')) > cut!)[:list_operator] >> ->(s) {
      [operator_class_mapping[s[:list_operator].map(&:text).join]]
    }

    unary_list_op_expression = (unary_list_op[:op] > one_of('(') > ws > cut! >
     r(:expression)[:list_expression] > ws > one_of(')') > cut!) >> ->(s) {
      [s[:op][0].new(s[:list_expression][0])]
    }

    # binary list operators
    binary_list_op = (m('cons') > cut!)[:list_operator] >> ->(s) {
      [operator_class_mapping[s[:list_operator].map(&:text).join]]
    }

    binary_list_op_expression = (binary_list_op[:op] > one_of('(') > ws >
     cut! > r(:expression)[:first] > ws > one_of(',') >
     ws > cut! > r(:expression)[:second] > ws > one_of(')') > cut!) >> ->(s) {
      [s[:op][0].new(s[:first][0], s[:second][0])]
    }

    # unary or binary list expressions
    list_op_expression = unary_list_op_expression | binary_list_op_expression

    # cond expression
    cond_expression = (m('cond') > cut! > (sep > r(:expression) > sep > m('==>').ignore >
     cut! > sep > r(:expression)).many.any[:conditions] > ws >
     m('end') > cut!) >> ->(s) {
      [CondExp.new(s[:conditions].each_slice(2).map {|l, r| Condition.new(l, r)})]
    }

    # zero?(expression {, expression}+)
    zero_check = (m('zero?(') > ws > cut! > r(:expression)[:first] >
     (ws > one_of(',').ignore > ws > cut! > r(:expression)).many.any[:rest] >
     ws > one_of(')') > cut!) >> ->(s) {
       [ZeroCheck.new(s[:first] + s[:rest])]
    }

    # if expression then expression else expression
    if_expression = (m('if') > sep > cut! > ws > r(:expression)[:test] > sep >
     m('then') > sep > cut! > r(:expression)[:true] > sep >
     m('else') > sep > cut! > r(:expression)[:false] > cut!) >> ->(s) {
      [IfExp.new(s[:test][0], s[:true][0], s[:false][0])]
    }

    # non-space, non-paren, non-comma characters all become identifiers
    identifier = one_of(/[^\s\(\),;]/).many[:chars] >> ->(s) {
      [Identifier.new(s[:chars].map(&:text).join)]
    }

    # variable = expression
    assignment = (identifier[:variable] > sep > one_of('=') > sep > cut! >
     r(:expression)[:value]) >> ->(s) {
       [Assignment.new(s[:variable][0], s[:value][0])]
    }

    # let identifier = expression {, identifier = expression }* in expression
    let_expression = (m('let') > sep > cut! > assignment[:first] >
     (ws > one_of(',').ignore > cut! > ws > assignment).many.any[:rest] >
     sep > cut! > m('in') > sep > cut! > r(:expression)[:body] > cut!) >> ->(s) {
      [LetExp.new(s[:first] + s[:rest], s[:body][0])]
    }

    # procedures, proc (var1 {, var}*) expression
    argument_list = (identifier[:first] > cut! > (ws > one_of(',').ignore >
     cut! > ws > identifier).many.any[:rest]).any

    proc_expression = (m('proc') > cut! > ws > one_of('(') > ws > argument_list[:args] > ws >
     one_of(')') > cut! > sep > r(:expression)[:body]) >> ->(s) {
      [Procedure.new(s[:args], s[:body][0])]
    }

    # procedure call, lisp style, (expression expression)
    proc_call_expression = (one_of('(') > cut! > ws > r(:expression)[:operator] >
     (sep > r(:expression) > cut!).many.any[:operands] > ws > one_of(')') > cut!) >> ->(s) {
      [ProcedureCall.new(s[:operator][0], s[:operands])]
    }

    # references
    unary_ref_expression = ((m('newref') | m('deref'))[:ref_type] > cut! > one_of('(') > ws >
     r(:expression)[:expression] > ws > one_of(')') > cut!) >> ->(s) {
      ref_type = s[:ref_type].map(&:text).join
      case ref_type
      when 'newref'
        ref_class = NewRef
      when 'deref'
        ref_class = DeRef
      end
      [ref_class.new(s[:expression][0])]
    }

    binary_ref_expression = (m('setref(') > cut! > ws > r(:expression)[:loc] > ws > one_of(',') > ws >
     r(:expression)[:val] > ws > one_of(')')) >> ->(s) {
      [SetRef.new(s[:loc][0], s[:val][0])]
    }

    ref_expression = unary_ref_expression | binary_ref_expression

    # begin expression {; expression}* end
    begin_expression = (m('begin') > cut! > sep > r(:expression)[:first] >
     (one_of(';').ignore > cut! > sep > r(:expression)).many.any[:rest] > sep >
     m('end') > cut!) >> ->(s) {
      [BeginExpression.new(s[:first] + s[:rest])]
    }

    # all the expressions together
    rule :expression, number | arithmetic_expression | zero_check |
     if_expression | let_expression | list_expression | list_op_expression |
     cond_expression | proc_expression | proc_call_expression |
     ref_expression | begin_expression | identifier

    rule :start, r(:expression)

  end

  def self.parse(indexable); @grammar.parse(indexable); end

  def self.eval(indexable); @grammar.parse(indexable)[0].eval(Env.new({}, {}), Store.new); end

end