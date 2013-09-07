require_relative './values'

module LetGrammar

  ##
  # All the binary operator classes have a very generic structure
  # when it comes to evaluation. So abstract the class creation
  # and evaluation method definition.

  def self.binary_operator_class(ast_class, operator, eval_result_class)
    klass = const_set(ast_class, Class.new(Struct.new(:first, :second)))
    klass.class_eval do
      define_method(:eval) do |env|
        first_result = first.eval(env).value
        second_result = second.eval(env).value
        eval_result_class.new(first_result.send(operator, second_result))
      end
    end
  end

  ##
  # Numeric binary operator definitions

  [[:Diff, :-], [:Add, :+], [:Mult, :*], [:Div, :/]].each do |op_def|
    binary_operator_class(*op_def, NumVal)
  end

  ##
  # Boolean binary operator definitions

  [[:EqualTo, :==], [:GreaterThan, :>], [:LessThan, :<]].each do |op_def|
    binary_operator_class(*op_def, BoolVal)
  end

  ##
  # Currently only one type of constant exists, i.e. a number

  class Const < Struct.new(:value)
    def eval(env)
      NumVal.new(value)
    end
  end

  ##
  # Variable

  class Var < Struct.new(:value)
    def eval(env)
      env[value]
    end
  end

  ##
  # Unary minus

  class Minus < Struct.new(:value)
    def eval(env)
      NumVal.new(value.eval(env).value)
    end
  end

  ##
  # Zero test

  class Zero < Struct.new(:value)
    def eval(env)
      value.eval(env).value.zero? ? BoolVal.new(true) : BoolVal.new(false)
    end
  end

  ##
  # Usual if expression

  class If < Struct.new(:test, :then, :else)
    def eval(env)
      test.eval(env).value == true ?
       self.then.eval(env) : self.else.eval(env)
    end
  end

  ##
  # Single variable to expression binding that is used
  # in let expressions
  
  class LetBinding < Struct.new(:var, :value)
    def eval(env)
      env[var.value] = value.eval(env)
    end
  end

  ##
  # Bind variables to expressions

  class Let < Struct.new(:bindings, :body)
    def eval(env)
      bindings.each {|binder| binder.eval(env)}; body.eval(env)
    end
  end

  ##
  # List of conditional expressions. When evaluating we just
  # return the first value for which the test expression evaluates
  # to true.
  
  class Conds < Struct.new(:values)
    def eval(env)
      values.each do |cond|
        return cond[:value].eval(env) if cond[:test].eval(env).value
      end
    end
  end

  ##
  # Cons(head, tail)

  class Cons < Struct.new(:head, :tail)
    def flatten
      head + tail.flatten
    end
  end

  ##
  # List expressions

  class List < Struct.new(:value)
    def eval(env)
      ListVal.new(value.map {|x| x.eval(env)})
    end
  end

  ##
  # Unpacker

  class Unpack < Struct.new(:identifiers, :packed_expression, :body)
    def eval(env)
      evaluated_list = packed_expression.eval(env).value
      if identifiers.length != evaluated_list.length
        raise StandardError, "Malformed unpack expression."
      end
      identifiers.zip(evaluated_list).each {|var, value|
        env[var.value] = value
      }
      body.eval(env)
    end
  end

  ##
  # car, cdr, null?

  class Car < Struct.new(:value)
    def eval(env)
      value.eval(env).value.first
    end
  end

  class Cdr < Struct.new(:value)
    def eval(env)
      ListVal.new(value.eval(env).value[1..-1])
    end
  end

  class Null < Struct.new(:value)
    def eval(env)
      BoolVal.new(value.eval(env).value.empty?)
    end
  end

end
