require_relative './values'

module LetGrammar

  class ConstExpr < Struct.new(:value)
    def eval(env)
      NumVal.new(value)
    end
  end

  class VarExpr < Struct.new(:value)
    def eval(env)
      env[value]
    end
  end

  class DiffExpr < Struct.new(:first, :second)
    def eval(env)
      NumVal.new(first.eval(env).value - second.eval(env).value)
    end
  end

  class ZeroExpr < Struct.new(:value)
    def eval(env)
      value.eval(env).value.zero? ? BoolVal.new(true) : BoolVal.new(false)
    end
  end

  class IfExpr < Struct.new(:test, :then, :else)
    def eval(env)
      test.eval(env).value == true ?
       self.then.eval(env) : self.else.eval(env)
    end
  end

  class LetExpr < Struct.new(:var, :value, :body)
    def eval(env)
      env[var.value] = value.eval(env); body.eval(env)
    end
  end

end
